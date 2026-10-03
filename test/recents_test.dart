import 'dart:io';
import 'dart:typed_data';

import 'package:ar_drawing/library/recents.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int seed, [int n = 64]) => Uint8List.fromList(List<int>.generate(n, (i) => (i * 7 + seed) & 0xff));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_pieces'));
  tearDown(() => dir.deleteSync(recursive: true));

  int imageFiles() => dir.listSync().where((f) => f.path.endsWith('.img')).length;

  test('newest first, the same picture stays one piece', () async {
    final store = RecentsStore(root: dir);
    final a = await store.add('Fox', _bytes(1));
    await store.add('Moth', _bytes(2));
    expect(store.pieces.map((p) => p.title), ['Moth', 'Fox']);

    final again = await store.add('Fox', _bytes(1));
    expect(again.id, a.id);
    expect(store.pieces.map((p) => p.title), ['Fox', 'Moth']);
    expect(imageFiles(), 2);
  });

  test('capacity drops the oldest piece and its file', () async {
    final store = RecentsStore(root: dir, capacity: 2);
    for (var i = 0; i < 3; i++) {
      await store.add('p$i', _bytes(i));
    }
    expect(store.pieces.map((p) => p.title), ['p2', 'p1']);
    expect(imageFiles(), 2);
  });

  test('survives a restart; touch reorders; remove deletes the copy', () async {
    final first = RecentsStore(root: dir);
    final fox = await first.add('Fox', _bytes(1));
    await first.add('Moth', _bytes(2));

    final store = RecentsStore(root: dir);
    await store.load();
    expect(store.pieces.map((p) => p.title), ['Moth', 'Fox']);
    expect(await store.pieces.last.file.readAsBytes(), _bytes(1));

    await store.touch(fox.id);
    expect(store.pieces.first.id, fox.id);

    await store.remove(fox.id);
    expect(store.pieces.map((p) => p.title), ['Moth']);
    expect(imageFiles(), 1);
  });

  test('replaceImage swaps the picture under a new file name', () async {
    final store = RecentsStore(root: dir);
    final fox = await store.add('Fox', _bytes(1));
    await store.replaceImage(fox.id, _bytes(9, 32));
    final now = store.pieces.single;
    expect(now.id, fox.id);
    expect(now.file.path, isNot(fox.file.path));
    expect(await now.file.readAsBytes(), _bytes(9, 32));
    expect(imageFiles(), 1);
  });

  test('importing the original again leaves a cropped piece alone', () async {
    final store = RecentsStore(root: dir);
    final fox = await store.add('Fox', _bytes(1));
    await store.replaceImage(fox.id, _bytes(9, 32));
    final again = await store.add('Fox', _bytes(1));
    expect(again.id, isNot(fox.id));
    expect(store.pieces, hasLength(2));
    expect(await store.pieces.last.file.readAsBytes(), _bytes(9, 32));

    final reloaded = RecentsStore(root: dir);
    await reloaded.load();
    expect(reloaded.pieces.map((p) => p.origin == null), [false, true]);
  });

  test('titles: real names are kept, generated ones are not', () {
    expect(pieceTitle('fox line art.png'), 'fox line art');
    expect(pieceTitle('1000012345.jpg'), 'Your picture');
    expect(pieceTitle('image_picker_8F2A.jpg'), 'Your picture');
    expect(pieceTitle('3f2a9c0e7b1d4a6f8e2c5b7d9f01a3c4.jpg'), 'Your picture');
    expect(pieceTitle('face.png'), 'face'); // hex letters only, but a real word
  });
}
