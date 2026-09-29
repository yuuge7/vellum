import 'package:flutter/foundation.dart';

enum LessonPhase { tracing, complete }

/// State machine for a step-by-step lesson.
///
///   tracing(0) --next--> tracing(1) --next--> ... tracing(n-1) --next--> complete
///   complete --previous--> tracing(n-1) --previous--> ... tracing(0)
///   any --restart--> tracing(0)
class LessonPlayer extends ChangeNotifier {
  LessonPlayer(this.stepCount) : assert(stepCount > 0);

  final int stepCount;
  int _index = 0;
  LessonPhase _phase = LessonPhase.tracing;

  /// +1 after moving forward, -1 after moving back, 0 after a jump/restart.
  int _lastDirection = 0;

  int get index => _index;
  LessonPhase get phase => _phase;
  int get lastDirection => _lastDirection;
  bool get isComplete => _phase == LessonPhase.complete;
  bool get isLastStep => _index == stepCount - 1;
  bool get canGoBack => isComplete || _index > 0;
  bool get canGoForward => !isComplete;

  /// Number of layers that should be visible right now.
  int get visibleSteps => _index + 1;

  void next() {
    if (isComplete) return;
    if (_index < stepCount - 1) {
      _index++;
    } else {
      _phase = LessonPhase.complete;
    }
    _lastDirection = 1;
    notifyListeners();
  }

  void previous() {
    if (isComplete) {
      _phase = LessonPhase.tracing;
    } else if (_index > 0) {
      _index--;
    } else {
      return;
    }
    _lastDirection = -1;
    notifyListeners();
  }

  void goTo(int step) {
    final s = step.clamp(0, stepCount - 1);
    if (s == _index && !isComplete) return;
    _index = s;
    _phase = LessonPhase.tracing;
    _lastDirection = 0;
    notifyListeners();
  }

  void restart() => goTo(0);
}
