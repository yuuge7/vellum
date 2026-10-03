import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// An imported picture kept on the device so the piece can be reopened.
class RecentPiece {
  const RecentPiece({required this.id, required this.title, required this.file, required this.opened, this.origin});
  final String id;
  final String title;
  final File file;
  final DateTime opened;

  /// Fingerprint of the imported file, or null once the piece was cropped
  /// and no longer matches anything in the gallery.
  final String? origin;
}

/// Turns a picker or share file name into a title. Generated names (numeric
/// ids, long hex hashes as on saved pins, cache prefixes) fall back to a
/// generic one.
String pieceTitle(String fileName) {
  final name = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
  final generated = name.isEmpty ||
      RegExp(r'^[0-9_-]+$').hasMatch(name) ||
      RegExp(r'^[0-9a-f-]{16,}$', caseSensitive: false).hasMatch(name) ||
      name.startsWith('image_picker') ||
      name.startsWith('scaled_');
  return generated ? 'Your picture' : name;
}

/// Copies of imported pictures in the app's private storage, newest first.
/// A piece for the wall takes more than one sitting; this is how it is found
/// again without digging through the gallery.
class RecentsStore extends ChangeNotifier {
  RecentsStore({Directory? root, this.capacity = 12}) : _root = root; // ignore: prefer_initializing_formals

  static final RecentsStore instance = RecentsStore();

  final int capacity;
  Directory? _root;
  Future<void>? _loading;
  List<RecentPiece> _pieces = const <RecentPiece>[];

  List<RecentPiece> get pieces => _pieces;

  File get _index => File('${_root!.path}/index.json');

  /// Reads the index once; later calls return the same future.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    _root ??= Directory('${(await getApplicationDocumentsDirectory()).path}/pieces');
    await _root!.create(recursive: true);
    try {
      if (await _index.exists()) {
        final list = jsonDecode(await _index.readAsString()) as List<Object?>;
        _pieces = <RecentPiece>[
          for (final e in list.cast<Map<String, Object?>>())
            RecentPiece(
              id: e['id']! as String,
              title: e['title']! as String,
              file: File('${_root!.path}/${e['file']}'),
              opened: DateTime.fromMillisecondsSinceEpoch(e['opened']! as int),
              origin: e['origin'] as String?,
            ),
        ].where((p) => p.file.existsSync()).toList();
      }
    } catch (e) {
      debugPrint('recent pieces index unreadable: $e');
      _pieces = const <RecentPiece>[];
    }
    notifyListeners();
  }

  /// Keeps [bytes] (an encoded image) as a piece and moves it to the front.
  /// The same file imported twice stays one piece; a piece that was cropped
  /// since is left alone and the import becomes a new one.
  Future<RecentPiece> add(String title, Uint8List bytes) async {
    await load();
    final origin = _fingerprint(bytes);
    for (final p in _pieces) {
      if (p.origin == origin) return (await touch(p.id))!;
    }
    final now = DateTime.now();
    final piece = await _write(now.microsecondsSinceEpoch.toRadixString(36), title, bytes, now, origin);
    await _commit(<RecentPiece>[piece, ..._pieces]);
    return piece;
  }

  /// Marks a piece as just opened and returns it (null if it is gone).
  Future<RecentPiece?> touch(String id) async {
    await load();
    final p = _find(id);
    if (p == null) return null;
    final now = RecentPiece(id: p.id, title: p.title, file: p.file, opened: DateTime.now(), origin: p.origin);
    await _commit(<RecentPiece>[now, ..._pieces.where((e) => e.id != id)]);
    return now;
  }

  /// Swaps the stored picture of a piece (after cropping).
  Future<void> replaceImage(String id, Uint8List bytes) async {
    await load();
    final p = _find(id);
    if (p == null) return;
    final next = await _write(id, p.title, bytes, p.opened, null);
    await _commit(<RecentPiece>[for (final e in _pieces) e.id == id ? next : e], replaced: p);
  }

  Future<void> remove(String id) async {
    await load();
    await _commit(_pieces.where((p) => p.id != id).toList(), replaced: _find(id));
  }

  RecentPiece? _find(String id) {
    for (final p in _pieces) {
      if (p.id == id) return p;
    }
    return null;
  }

  // Every write gets a fresh file name, so cached thumbnails never go stale.
  Future<RecentPiece> _write(String id, String title, Uint8List bytes, DateTime opened, String? origin) async {
    final file = File('${_root!.path}/$id-${DateTime.now().microsecondsSinceEpoch}.img');
    await file.writeAsBytes(bytes, flush: true);
    return RecentPiece(id: id, title: title, file: file, opened: opened, origin: origin);
  }

  Future<void> _commit(List<RecentPiece> next, {RecentPiece? replaced}) async {
    final dropped = <RecentPiece>[?replaced, ...next.skip(capacity)];
    _pieces = next.take(capacity).toList();
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode(<Object?>[
      for (final p in _pieces)
        <String, Object?>{
          'id': p.id,
          'title': p.title,
          'file': p.file.uri.pathSegments.last,
          'opened': p.opened.millisecondsSinceEpoch,
          'origin': p.origin,
        },
    ]));
    await tmp.rename(_index.path);
    for (final p in dropped) {
      if (_pieces.any((e) => e.file.path == p.file.path)) continue;
      try {
        await p.file.delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// FNV-1a over the length and an even sample of the bytes: cheap, and
  /// stable for the same file.
  static String _fingerprint(Uint8List bytes) {
    var h = 0x811c9dc5 ^ bytes.length;
    final step = math.max(1, bytes.length ~/ 65536);
    for (var i = 0; i < bytes.length; i += step) {
      h = ((h ^ bytes[i]) * 0x01000193) & 0xffffffffffff;
    }
    return h.toRadixString(16).padLeft(12, '0');
  }
}
