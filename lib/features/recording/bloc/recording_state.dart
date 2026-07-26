import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/errors.dart';

part 'recording_state.mapper.dart';

@MappableClass()
class RecordingState with RecordingStateMappable {
  const RecordingState({
    this.activity,
    this.elapsedTime = Duration.zero,
    this.isPaused = false,
    this.isStarting = false,
    this.error,
    this.trackingGap,
  });

  /// The in-progress activity, or null when nothing is being recorded.
  final ActivityEntity? activity;

  /// Wall-clock time since the recording started, minus completed pauses.
  /// Never rewritten by a GPS outage — elapsed time stays the immutable truth
  /// (see ActivityPointStatusEntity.signalLost).
  final Duration elapsedTime;

  final bool isPaused;

  /// True between the Start tap and the activity row existing — the one-shot
  /// GPS fix it waits for can take seconds.
  final bool isStarting;

  final AppError? error;

  /// Set when a recording was running but the position stream went silent while
  /// the app was backgrounded/locked for longer than the stale threshold — the
  /// OS suspended or killed the foreground service and fixes were lost for this
  /// long. The UI shows a one-off banner so the user knows a segment is missing
  /// and can consider the battery-optimisation exemption. Null when healthy.
  final Duration? trackingGap;

  bool get isRecording => activity != null;
}
