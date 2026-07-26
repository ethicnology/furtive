import 'package:furtive/core/entities/position_entity.dart';

sealed class RecordingEvent {
  const RecordingEvent();
}

/// Events that decide which activity owns the recording state.
///
/// They share one sequential handler in RecordingBloc so a cold-start resume
/// and a user tapping Start cannot both pass the empty-state guard around an
/// await and create competing ongoing activities.
sealed class RecordingInitializationEvent extends RecordingEvent {
  const RecordingInitializationEvent();
}

/// Restore an in-progress recording from storage after a cold start (the OS
/// killed the process mid-run). No-op when one is already live.
class ResumeOngoingRecording extends RecordingInitializationEvent {
  const ResumeOngoingRecording();
}

class StartRecording extends RecordingInitializationEvent {
  const StartRecording();
}

class StopRecording extends RecordingEvent {
  const StopRecording();
}

/// Toggles pause/resume.
class PauseRecording extends RecordingEvent {
  const PauseRecording();
}

/// A GPS fix to append to the running recording.
class ScoreFix extends RecordingEvent {
  const ScoreFix({required this.position});

  final PositionEntity position;
}

/// 1 Hz tick that refreshes the displayed elapsed time.
class TickElapsed extends RecordingEvent {
  const TickElapsed();
}

class ClearRecordingError extends RecordingEvent {
  const ClearRecordingError();
}

/// Report that the position stream went silent for [gap] while a recording was
/// running — the trace has a hole that cannot be backfilled.
class ReportTrackingGap extends RecordingEvent {
  const ReportTrackingGap(this.gap);

  final Duration gap;
}

/// Dismisses the tracking-gap banner.
class ClearTrackingGap extends RecordingEvent {
  const ClearTrackingGap();
}
