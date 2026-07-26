import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/core/utils/signal_gap_detector.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';

/// The recording state machine: start, pause, stop, resume-after-kill, elapsed
/// time bookkeeping and GPS-outage bracketing.
///
/// Extracted from MapBloc, which mixed this with stream lifecycle and map
/// presentation. Keeping it separate matters beyond tidiness: the pause/elapsed
/// bookkeeping reconstructed in [_onResumeOngoing] after an OS kill is the
/// subtlest logic in the app, and it was previously reachable by exactly one
/// test because nothing in MapBloc was injectable.
class RecordingBloc extends Bloc<RecordingEvent, RecordingState> {
  RecordingBloc({
    ActivityRepository? activities,
    ScoreActivityUseCase? score,
    EnsureBackgroundTrackingUseCase? ensureBackgroundTracking,
    Clock? clock,
    SignalGapDetector? gapDetector,
  }) : _activities = activities ?? ActivityRepository(clock: clock),
       _score = score ?? ScoreActivityUseCase(),
       _ensureBackgroundTracking =
           ensureBackgroundTracking ?? EnsureBackgroundTrackingUseCase(),
       _clock = clock ?? const SystemClock(),
       _gapDetector = gapDetector ?? SignalGapDetector(),
       super(const RecordingState()) {
    // Start and cold-start resume must share ONE queue. Per-type transformers
    // do not coordinate with each other: both handlers could otherwise pass
    // `state.activity == null`, await storage/platform work, then each install a
    // different ongoing activity. Sequential also makes a fast second Start a
    // cheap no-op once the first handler has populated state.
    on<RecordingInitializationEvent>(_onInitialize, transformer: sequential());
    on<StopRecording>(_onStop);
    // sequential(): the default transformer processes same-typed events
    // concurrently. At ~5 s per fix there is no throughput cost, but concurrency
    // here is harmful — two handlers in flight (e.g. the OS delivering a backlog
    // of buffered fixes after a resume) can both capture the same
    // `activity.points.last` for gap detection and each write their own
    // signalLost boundary pair, or clobber each other's in-memory append.
    on<ScoreFix>(_onScoreFix, transformer: sequential());
    on<PauseRecording>(_onPause);
    on<TickElapsed>(_onTick);
    on<ClearRecordingError>((_, emit) => emit(state.copyWith(error: null)));
    on<ReportTrackingGap>(
      (event, emit) => emit(state.copyWith(trackingGap: event.gap)),
    );
    on<ClearTrackingGap>((_, emit) => emit(state.copyWith(trackingGap: null)));
  }

  final ActivityRepository _activities;
  final ScoreActivityUseCase _score;
  final EnsureBackgroundTrackingUseCase _ensureBackgroundTracking;
  final Clock _clock;

  /// Detects GPS outages from the cadence of recorded fixes. Reset on
  /// [StartRecording] so one run's cadence never leaks into the next;
  /// deliberately NOT reset on resume-from-kill, where an empty window falls
  /// back to the nominal threshold and still catches the kill-induced gap on
  /// the first new fix.
  final SignalGapDetector _gapDetector;

  Timer? _elapsedTimer;
  DateTime? _startedAt;
  DateTime? _pauseStartedAt;
  Duration _completedPauses = Duration.zero;

  @override
  Future<void> close() {
    _elapsedTimer?.cancel();
    return super.close();
  }

  void _startTicking() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) add(const TickElapsed());
    });
  }

  Future<void> _onInitialize(
    RecordingInitializationEvent event,
    Emitter<RecordingState> emit,
  ) async {
    switch (event) {
      case ResumeOngoingRecording():
        await _onResumeOngoing(event, emit);
      case StartRecording():
        await _onStart(event, emit);
    }
  }

  Future<void> _onResumeOngoing(
    ResumeOngoingRecording event,
    Emitter<RecordingState> emit,
  ) async {
    if (state.activity != null) return;
    try {
      final ongoing = await _activities.fetchOngoing();
      if (ongoing == null) return;

      // Rebuild the timing bookkeeping the in-memory bloc lost on the kill.
      // startedAt is authoritative; completed-pause time comes from the
      // persisted point statuses (the same calc the stats use).
      _startedAt = ongoing.startedAt;
      _completedPauses = ongoing.pausedDuration;
      _pauseStartedAt = null;

      // Resume in whatever state the activity was in when it died, read from the
      // last recorded point. Staying paused keeps the dead gap out of active
      // elapsed time; if it was active, the gap counts as elapsed (the run was
      // notionally still going, just with no GPS) which is the honest reading.
      final lastTime = ongoing.points.isEmpty
          ? null
          : ongoing.points
                .map((p) => p.time)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      final wasPaused =
          lastTime != null &&
          ongoing.points.firstWhere((p) => p.time == lastTime).status ==
              ActivityPointStatusEntity.paused;

      final Duration elapsed;
      if (wasPaused) {
        // Continue the ongoing pause from the last fix. _completedPauses already
        // covers up to that fix, so resuming adds (now - lastFix) without double
        // counting. Freeze elapsed at the pause moment; no timer while paused.
        _pauseStartedAt = lastTime;
        elapsed = lastTime.difference(_startedAt!) - _completedPauses;
      } else {
        _startTicking();
        elapsed = _clock.nowUtc().difference(_startedAt!) - _completedPauses;
      }

      logs.fine(
        'Resumed ongoing activity ${ongoing.id} from storage '
        '(paused: $wasPaused).',
      );
      emit(
        state.copyWith(
          activity: ongoing,
          isPaused: wasPaused,
          elapsedTime: elapsed.isNegative ? Duration.zero : elapsed,
        ),
      );
    } catch (e, s) {
      // A failed resume must not block the map from loading.
      logs.severe('resumeOngoingRecording', error: e, trace: s);
    }
  }

  Future<void> _onStart(
    StartRecording event,
    Emitter<RecordingState> emit,
  ) async {
    // Defence in depth alongside droppable(): a recording is already running,
    // so a Start here is a no-op rather than a second concurrent activity.
    if (state.activity != null) return;
    try {
      emit(state.copyWith(isStarting: true, error: null));

      // Ask for the battery-optimisation exemption before recording begins so
      // the foreground service survives a locked screen on aggressive OEMs.
      // Best-effort: a denial still starts the run (FGS + wake lock remain).
      if (!await _ensureBackgroundTracking()) {
        logs.warning(
          'Battery optimisation exemption not granted; tracking may stop '
          'while the phone is locked on aggressive OEMs.',
        );
      }

      _elapsedTimer?.cancel();
      _pauseStartedAt = null;
      _completedPauses = Duration.zero;
      _gapDetector.reset();

      final activity = await _activities.startNew();
      logs.info(
        'StartRecording: activity ${activity.id} started at '
        '${activity.startedAt}',
      );
      _startedAt = activity.startedAt;
      _startTicking();

      emit(state.copyWith(activity: activity));
    } catch (e, s) {
      logs.severe('$StartRecording', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(isStarting: false));
    }
  }

  Future<void> _onScoreFix(ScoreFix event, Emitter<RecordingState> emit) async {
    // A stop can be processed between the fix arriving and this handler running,
    // nulling state.activity. Return rather than throwing.
    final activity = state.activity;
    if (activity == null) return;
    final status = state.isPaused
        ? ActivityPointStatusEntity.paused
        : ActivityPointStatusEntity.active;

    // Outage detection runs only between two consecutive *active* fixes: a pause
    // already excludes its time from active stats, and the active<->paused
    // transition is an inter-segment gap that is never counted. The check uses
    // the fix's own timestamp (the same source the stored point gets) so a
    // queued/delayed handler cannot fabricate a gap.
    ActivityPointEntity? gapFrom;
    final previous = activity.points.isEmpty ? null : activity.points.last;
    if (previous != null &&
        previous.status == ActivityPointStatusEntity.active &&
        status == ActivityPointStatusEntity.active) {
      final fixTime = event.position.time ?? _clock.nowUtc();
      final gap = _gapDetector.check(previous.time, fixTime);
      if (gap != null) {
        gapFrom = previous;
        logs.warning(
          'ScoreFix: GPS outage of ${gap.inSeconds}s detected on activity '
          '${activity.id} (threshold ${_gapDetector.threshold.inSeconds}s) — '
          'bracketing with signalLost boundary points.',
        );
      }
    }

    try {
      final newPoints = await _score(
        activityId: activity.id,
        position: event.position,
        status: status,
        gapFrom: gapFrom,
      );
      // Append to the LATEST in-memory activity, not the pre-await capture:
      // concurrent handlers would otherwise each append to the same stale list
      // and clobber one another. If a stop landed during the await, skip.
      final current = state.activity;
      if (current == null || current.id != activity.id) return;
      final pointCount = current.points.length + newPoints.length;
      // Heartbeat, not one line per fix (every ~5 s would flood the log over a
      // long activity) — roughly one line a minute, so a walk's continuity (or
      // a silent gap) stays visible in the exported logs.
      if (pointCount % 12 == 0) {
        logs.fine(
          'ScoreFix: activity ${activity.id} has $pointCount points '
          '(status: ${status.name}).',
        );
      }
      emit(
        state.copyWith(
          activity: current.copyWith(points: [...current.points, ...newPoints]),
        ),
      );
    } catch (e, s) {
      logs.severe('$ScoreFix', error: e, trace: s);
      emit(state.copyWith(error: AppError('ScoreFix: $e')));
    }
  }

  void _onPause(PauseRecording event, Emitter<RecordingState> emit) {
    if (state.activity == null) return;

    final wasPaused = state.isPaused;
    logs.info(
      'PauseRecording: activity ${state.activity!.id} '
      '${wasPaused ? 'resumed' : 'paused'} at elapsed '
      '${state.elapsedTime.inSeconds}s.',
    );

    if (wasPaused) {
      if (_pauseStartedAt != null) {
        _completedPauses += _clock.nowUtc().difference(_pauseStartedAt!);
        _pauseStartedAt = null;
      }
      _startTicking();
    } else {
      _pauseStartedAt = _clock.nowUtc();
      _elapsedTimer?.cancel();
    }

    emit(state.copyWith(isPaused: !wasPaused));
  }

  Future<void> _onStop(
    StopRecording event,
    Emitter<RecordingState> emit,
  ) async {
    // Back-to-back Stop taps would hit a null activity on the second pass.
    final activity = state.activity;
    if (activity == null) return;
    try {
      await _activities.cease(activity.id);
      logs.info(
        'StopRecording: activity ${activity.id} stopped with '
        '${activity.points.length} points, elapsed '
        '${state.elapsedTime.inSeconds}s.',
      );
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _startedAt = null;
      _pauseStartedAt = null;
      _completedPauses = Duration.zero;

      emit(
        state.copyWith(
          activity: null,
          elapsedTime: Duration.zero,
          isPaused: false,
        ),
      );
    } catch (e, s) {
      logs.severe('$StopRecording', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  void _onTick(TickElapsed event, Emitter<RecordingState> emit) {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    final elapsed = _clock.nowUtc().difference(startedAt) - _completedPauses;
    emit(
      state.copyWith(elapsedTime: elapsed.isNegative ? Duration.zero : elapsed),
    );
  }
}
