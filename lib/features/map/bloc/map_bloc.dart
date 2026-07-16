import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/usecases/get_user_location_use_case.dart';
import 'package:furtive/core/usecases/start_track_position_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/core/usecases/start_activity_use_case.dart';
import 'package:furtive/core/usecases/cease_activity_use_case.dart';
import 'package:furtive/core/usecases/resume_ongoing_activity_use_case.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/get_traces_use_case.dart';
import 'package:furtive/core/utils/signal_gap_detector.dart';
import 'package:furtive/features/map/error.dart';

const double kSearchHalfSideDegrees = 0.01425;

// Localised display strings live in MapPage (_loadingMessage); this enum is
// just the state tag.
enum LoadingStatus { localizing, loadingMap, loadingTraces, startingActivity }

class MapBloc extends Bloc<MapEvent, MapState> with WidgetsBindingObserver {
  final _getMapConfigUseCase = GetMapConfigUseCase();
  final _getPublicGpsTracesUseCase = GetTracesUseCase();
  final _beginActivityUseCase = StartActivityUseCase();
  final _scoreActivityUseCase = ScoreActivityUseCase();
  final _ceaseActivityUsecase = CeaseActivityUseCase();
  final _startTrackPositionUsecase = StartTrackPositionUseCase();
  final _getUserLocationUseCase = GetUserLocationUseCase();
  final _resumeOngoingActivityUseCase = ResumeOngoingActivityUseCase();
  final _ensureBackgroundTrackingUseCase = EnsureBackgroundTrackingUseCase();

  StreamSubscription<PositionEntity>? _positionStream;

  // Guards concurrent callers of _openPositionStream(): InitMap can re-fire
  // (onboarding finish + MapPage.initState both dispatch it, and the
  // default bloc transformer runs different-typed events concurrently) and
  // races with EnsureTracking on app resume. _positionStream is only
  // assigned once _openPositionStream()'s internal await resolves, so a
  // naive "if (_positionStream == null)" check is a check-then-act with an
  // await in between — without this guard, two callers can both see null
  // and both call .listen(), leaking one subscription forever and
  // double-writing every GPS fix to the DB. All callers must go through
  // _ensurePositionStreamOpen() instead of _openPositionStream() directly.
  // See REVIEW-2026-07-FULL-APP.md H3.
  Future<void>? _openingPositionStream;

  Timer? _elapsedTimer;
  DateTime? _activityStartTime;
  DateTime? _pauseStartTime;
  Duration _totalPausedDuration = Duration.zero;

  // Wall-clock of the last GPS fix, used by EnsureTracking to detect a stream
  // the OS silently suspended in the background (no onDone, no error — a known
  // geolocator behaviour in deep Doze, see Baseflow/flutter-geolocator #1023).
  DateTime? _lastFixAt;

  // Detects GPS outages (indoors, tunnel, process kill) from the cadence of
  // recorded fixes — see _onScoreActivity. Reset on StartActivity so one
  // run's cadence history never leaks into the next; deliberately NOT reset
  // on resume-from-kill, where an empty window (fresh bloc) falls back to
  // the nominal threshold and still catches the kill-induced gap on the
  // first new fix.
  final _gapDetector = SignalGapDetector();

  // On foreground-resume, if a recording is running and no fix has arrived for
  // longer than this, assume the stream stalled and reopen it. The Android
  // intervalDuration is 5s, so 20s is ~4 missed fixes — comfortably past
  // normal jitter while a stationary device still emits at distanceFilter 0.
  static const _staleStreamThreshold = Duration(seconds: 20);

  MapBloc() : super(const MapState()) {
    on<InitMap>(_onInitMap);
    on<EnsureTracking>(_onEnsureTracking);
    on<FetchTraces>(_onTracesSearchRequested);
    // droppable(): the default (concurrent) transformer let a fast
    // double-tap on Start enqueue two StartActivity events; both await the
    // multi-second one-shot GPS fix, both insert an activity row, and the
    // loser sits in the DB as a near-empty orphan "Track" until the next
    // cold start's fetchOngoing reconciliation auto-ceases it. Dropping any
    // StartActivity that arrives while one is already being handled closes
    // the race outright — a genuine second start (after the first
    // completed) is unaffected since droppable() only discards events that
    // arrive DURING an in-flight handler. See REVIEW-2026-07-FULL-APP.md M4.
    on<StartActivity>(_onStartActivity, transformer: droppable());
    on<CeaseActivity>(_onCeaseActivity);
    // sequential(): the default bloc transformer processes events of the
    // same type concurrently. At ~5s per GPS fix this has no throughput
    // cost, but concurrency here is actively harmful — two ScoreActivity
    // handlers in flight together (e.g. the OS delivering a backlog of
    // buffered fixes right after a resume) can both capture the same
    // `activity.points.last` for gap detection and each write their own
    // signalLost boundary pair, or clobber each other's in-memory point
    // append. See REVIEW-2026-07-FULL-APP.md M1.
    on<ScoreActivity>(_onScoreActivity, transformer: sequential());
    on<PauseActivity>(_onPauseActivity);
    on<ClearError>(_onClearError);
    on<ClearTrackingGap>(_onClearTrackingGap);
    on<UpdateElapsedTime>(_onUpdateElapsedTime);
    on<UpdateUserLocation>(_onUpdateUserLocation);
    on<ToggleFollowUser>(_onToggleFollowUser);
    on<StopFollowingUser>(_onStopFollowingUser);

    // Observe app lifecycle so we can re-check the position stream when the
    // user returns to the app (see _onEnsureTracking).
    WidgetsBinding.instance.addObserver(this);

    // InitMap is NOT auto-fired here — it triggers the OS location-permission
    // dialog, and the bloc is instantiated at app start (via the BlocProvider
    // in MyApp) which happens before the onboarding wizard's permissions
    // step. MapPage.initState and OnboardingPage._finish fire it explicitly
    // once the user is ready to see the map.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `state` here is the lifecycle arg, not the bloc state (unused below).
    if (state == AppLifecycleState.resumed) add(const EnsureTracking());
  }

  void _onUpdateUserLocation(UpdateUserLocation event, Emitter<MapState> emit) {
    try {
      _lastFixAt = DateTime.now();
      if (state.activity != null) {
        add(ScoreActivity(position: event.position));
      }
      emit(state.copyWith(userLocation: event.position));
    } catch (e, s) {
      logs.severe('$UpdateUserLocation', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _positionStream?.cancel();
    _elapsedTimer?.cancel();
    return super.close();
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

    // B38/H1: InitMap can re-fire — from the onboarding finish and from
    // PreferencesBloc on every theme/locale apply. Open the position stream
    // only once: if it's already running, leave it untouched so a preference
    // change mid-activity doesn't tear down live tracking (dropping fixes) or
    // leak a second listener. A re-init then just refreshes the user
    // location and map style below. A failed first subscription leaves
    // _positionStream null, so a later InitMap retries. Isolated in its own
    // try/catch so a failure here can never prevent the resume or style load
    // below from running (see AUDIT-2026-07.md §1: a single unguarded await
    // used to be able to strand an ongoing activity until it got
    // auto-ceased). _ensurePositionStreamOpen() (not _openPositionStream()
    // directly) closes the race where two concurrent InitMap calls — the
    // default bloc transformer runs different events concurrently, and
    // onboarding + MapPage.initState commonly both dispatch InitMap in quick
    // succession — would otherwise both see _positionStream == null and both
    // open a subscription (see H3 in REVIEW-2026-07-FULL-APP.md).
    try {
      await _ensurePositionStreamOpen();
    } catch (e, s) {
      logs.severe('$InitMap openPositionStream', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }

    // Cold start may follow an OS process kill that happened mid-recording
    // (Doze / OEM battery killer while the phone was locked). The activity
    // and its points are still in the DB; rehydrate the run so the user sees
    // their ongoing activity instead of losing it to a later auto-cease.
    //
    // Runs BEFORE the one-shot fix below and is NOT gated on isColdOpen
    // anymore: the internal `state.activity != null` guard in
    // _resumeOngoingActivity already makes a repeat call a cheap no-op once
    // resumed, and decoupling from isColdOpen means a transient failure gets
    // retried on the next InitMap instead of permanently skipping the
    // resume. Previously this ran AFTER _getUserLocationUseCase(), whose
    // one-shot GPS fix has no timeout and can hang or throw right after an
    // unlock (GPS not warmed up yet); since _positionStream was already
    // non-null by then, isColdOpen stayed false forever and the resume was
    // never retried — the ongoing activity sat orphaned in the DB until an
    // auto-cease silently "killed" it. Doing the resume first, independent of
    // the fix outcome, closes that gap. The map's recenter listener is gated
    // to fire only on a fresh start (see MapPage), so resuming here does not
    // move the camera before the map mounts.
    await _resumeOngoingActivity(emit);

    try {
      final userPosition = await _getUserLocationUseCase();
      emit(state.copyWith(userLocation: userPosition));
    } catch (e, s) {
      // Non-fatal and deliberately silent (no error banner): right after a
      // cold start the GPS may simply not be warmed up yet. The already-open
      // position stream will deliver a fix and update userLocation as soon
      // as one arrives; blocking/erroring the whole init on this one-shot
      // fix is exactly what used to prevent the resume above from mattering.
      logs.severe('$InitMap getUserLocation', error: e, trace: s);
    }

    emit(state.copyWith(loadingStatus: LoadingStatus.loadingMap));
    try {
      final style = await _getMapConfigUseCase();
      logs.info(
        '$InitMap getMapConfig: style '
        '${style == null ? 'null (tileless)' : 'loaded'}',
      );
      emit(state.copyWith(style: style));
    } catch (e, s) {
      logs.severe('$InitMap getMapConfig', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  // Opens the position stream if it isn't already open, memoising the
  // in-flight Future so concurrent callers (InitMap re-firing, EnsureTracking
  // racing with it) all await the SAME open instead of each independently
  // seeing _positionStream == null and calling .listen() themselves — the
  // check-then-act race that used to leak a subscription and double-write
  // every GPS fix to the DB (see H3 in REVIEW-2026-07-FULL-APP.md). ALWAYS
  // go through this method rather than _openPositionStream() directly.
  Future<void> _ensurePositionStreamOpen() {
    if (_positionStream != null) return Future.value();
    return _openingPositionStream ??= _openPositionStream().whenComplete(() {
      _openingPositionStream = null;
    });
  }

  // Opens the geolocator position stream and wires it into the bloc. Sets
  // _positionStream. Only ever called through _ensurePositionStreamOpen().
  Future<void> _openPositionStream() async {
    final userPositionStream = await _startTrackPositionUsecase(
      // Stamp on every raw platform fix, not just ones that later survive
      // GpsQualityFilter — see the doc comment on
      // LocationRepository.getPositionStream(). Keeps EnsureTracking from
      // mistaking "every recent fix failed the quality gate" (normal under
      // tree cover/urban canyon/indoors) for "the stream/foreground service
      // actually died".
      onRawFix: () => _lastFixAt = DateTime.now(),
    );
    _positionStream = userPositionStream
        .handleError(
          (error, StackTrace stack) =>
              logs.severe('position stream', error: error, trace: stack),
        )
        .listen(
          (position) {
            if (!isClosed) add(UpdateUserLocation(position: position));
          },
          // The stream closing is NOT treated as "stop the activity". The
          // notification is ongoing (non-swipeable) and the service holds a
          // wake lock, so a close means the foreground service actually died
          // (rare) — not a user gesture. Ceasing would silently end a run the
          // user still wants; instead drop the dead subscription and re-init to
          // reopen it. The activity row stays open and keeps recording.
          onDone: () {
            logs.warning('Position stream closed; reopening.');
            _positionStream = null;
            if (!isClosed) add(const InitMap());
          },
        );
  }

  // App returned to the foreground. If the stream died or went silent in the
  // background (geolocator can suspend it in deep Doze without emitting
  // onDone), reopen it so tracking resumes at once — whether or not a
  // recording is running. Previously this returned immediately when nothing
  // was being recorded, which meant a stream the OS silently killed while
  // idle (not recording) never got reopened for the rest of the session: no
  // later event re-triggers it, so the live "blue dot" location would stay
  // frozen at its last position until the app restarted. See
  // REVIEW-2026-07-FULL-APP.md M3.
  Future<void> _onEnsureTracking(
    EnsureTracking event,
    Emitter<MapState> emit,
  ) async {
    final last = _lastFixAt;
    final gap = last == null ? null : DateTime.now().difference(last);
    final stale = gap == null || gap > _staleStreamThreshold;
    if (_positionStream != null && !stale) {
      // App came back to foreground and the stream is healthy — logged so
      // resume checks are still visible in the exported logs, distinct from
      // silence meaning "the app was never backgrounded".
      logs.fine('EnsureTracking: stream healthy, no reopen needed.');
      return;
    }

    // A stale stream while actively recording means the OS suspended/killed
    // the foreground service in the background and no fixes were recorded
    // for the gap — the trace has a hole the reopen below can't backfill.
    // Surface it so the user knows a segment is missing (and can grant the
    // battery exemption). Only flag genuinely significant gaps (not
    // first-open jitter), and only while there is a recording to lose data
    // from — a frozen blue dot with nothing recording is silently reopened
    // below with no user-facing banner.
    if (state.activity != null &&
        !state.isPaused &&
        gap != null &&
        gap > _staleStreamThreshold) {
      logs.warning(
        'EnsureTracking: tracking gap of ${gap.inSeconds}s detected '
        '(stream suspended/killed while backgrounded).',
      );
      emit(state.copyWith(trackingGap: gap));
    }

    logs.warning('EnsureTracking: position stream stale/dead, reopening.');
    await _positionStream?.cancel();
    _positionStream = null;
    try {
      // Goes through the same guard as InitMap: if an open is already in
      // flight (e.g. a concurrent InitMap), this piggybacks on it instead
      // of racing to open a second subscription.
      await _ensurePositionStreamOpen();
      logs.info('EnsureTracking: position stream reopened successfully.');
    } catch (e, s) {
      logs.severe('EnsureTracking reopen', error: e, trace: s);
    }
  }

  void _onClearTrackingGap(ClearTrackingGap event, Emitter<MapState> emit) {
    emit(state.copyWith(trackingGap: null));
  }

  // Restore an in-progress recording from the DB after a cold start. No-op if
  // an activity is already live (the bloc survived) or nothing is ongoing.
  Future<void> _resumeOngoingActivity(Emitter<MapState> emit) async {
    if (state.activity != null) return;
    try {
      final ongoing = await _resumeOngoingActivityUseCase();
      if (ongoing == null) return;

      // Rebuild the timing bookkeeping the in-memory bloc lost on the kill.
      // startedAt is authoritative; completed-pause time comes from the
      // persisted point statuses (same calc the stats use).
      _activityStartTime = ongoing.startedAt;
      _totalPausedDuration = ongoing.pausedDuration;
      _pauseStartTime = null;

      // Resume in whatever state the activity was in when it died, read from
      // the last recorded point. If it was paused, staying paused keeps the
      // dead gap out of the active elapsed time; if it was active, the gap
      // counts as elapsed (the run was notionally still going, just with no
      // GPS) which is the honest representation.
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
        // Continue the ongoing pause from the last fix. pausedDuration already
        // covers up to that fix, so PauseActivity's resume adds (now - lastFix)
        // without double counting. Freeze elapsed at the pause moment; no timer
        // while paused.
        _pauseStartTime = lastTime;
        elapsed =
            lastTime.difference(_activityStartTime!) - _totalPausedDuration;
      } else {
        _elapsedTimer?.cancel();
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!isClosed) add(const UpdateElapsedTime());
        });
        elapsed =
            DateTime.now().difference(_activityStartTime!) -
            _totalPausedDuration;
      }

      // Key signal that the process was killed mid-recording and the app
      // recovered the activity from storage instead of losing it.
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
      logs.severe('resumeOngoingActivity', error: e, trace: s);
    }
  }

  Future<void> _onStartActivity(
    StartActivity event,
    Emitter<MapState> emit,
  ) async {
    // Defence in depth alongside the droppable() transformer above: a
    // recording is already running, so a Start tap here is a no-op rather
    // than spawning a second concurrent activity.
    if (state.activity != null) return;
    try {
      emit(state.copyWith(loadingStatus: LoadingStatus.startingActivity));

      // Ask for the battery-optimisation exemption before recording begins so
      // the foreground service survives a locked screen on aggressive OEMs.
      // Best-effort and non-blocking to the recording: a denial still starts
      // the run (FGS + wake lock remain), we just surface it as a warning.
      final exempt = await _ensureBackgroundTrackingUseCase();
      if (!exempt) {
        logs.warning(
          'Battery optimisation exemption not granted; tracking may stop '
          'while the phone is locked on aggressive OEMs.',
        );
      }

      _elapsedTimer?.cancel();
      _pauseStartTime = null;
      _totalPausedDuration = Duration.zero;
      _gapDetector.reset();

      // First we wait for user location
      final userPosition = await _getUserLocationUseCase();
      // Then we start the activity
      final activity = await _beginActivityUseCase();
      logs.info(
        '$StartActivity: activity ${activity.id} started at '
        '${activity.startedAt}',
      );
      // Then add the current location to the activity
      add(UpdateUserLocation(position: userPosition));
      _activityStartTime = activity.startedAt;

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isClosed) add(const UpdateElapsedTime());
      });

      emit(state.copyWith(activity: activity));
    } catch (e, s) {
      logs.severe('$StartActivity', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  Future<void> _onScoreActivity(
    ScoreActivity event,
    Emitter<MapState> emit,
  ) async {
    // A CeaseActivity (manual stop) can be processed between
    // _onUpdateUserLocation dispatching this event and the handler running,
    // nulling state.activity. Return rather than throwing —
    // the old `throw ActivityNotStartedError()` was outside the try/catch and
    // leaked an unhandled error into the bloc zone.
    final activity = state.activity;
    if (activity == null) return;
    final position = event.position;
    final status = state.isPaused
        ? ActivityPointStatusEntity.paused
        : ActivityPointStatusEntity.active;

    // GPS-outage detection: only between two consecutive *active* fixes —
    // a pause already excludes its time from the active stats, and the
    // active↔paused transition is an inter-segment gap that is never
    // counted. The check runs on the fix's own timestamp (same source the
    // stored point gets) so a queued/delayed handler can't fake a gap.
    ActivityPointEntity? gapFrom;
    final previous = activity.points.isEmpty ? null : activity.points.last;
    if (previous != null &&
        previous.status == ActivityPointStatusEntity.active &&
        status == ActivityPointStatusEntity.active) {
      final fixTime = position.time ?? DateTime.now().toUtc();
      final gap = _gapDetector.check(previous.time, fixTime);
      if (gap != null) {
        gapFrom = previous;
        logs.warning(
          '$ScoreActivity: GPS outage of ${gap.inSeconds}s detected on '
          'activity ${activity.id} (threshold '
          '${_gapDetector.threshold.inSeconds}s) — bracketing with '
          'signalLost boundary points.',
        );
      }
    }

    try {
      final newPoints = await _scoreActivityUseCase(
        activityId: activity.id,
        position: position,
        status: status,
        gapFrom: gapFrom,
      );
      // Append to the LATEST in-memory activity, not the pre-await capture:
      // concurrent ScoreActivity handlers would otherwise each append to the
      // same stale points list and clobber one another (a point vanishes from
      // the live polyline). If a cease landed during the await, skip the emit.
      final current = state.activity;
      if (current == null || current.id != activity.id) return;
      final pointCount = current.points.length + newPoints.length;
      // Heartbeat, not one line per fix (every ~5s would flood the log over
      // a long activity) — roughly one line/minute so a walk's continuity
      // (or a silent gap) is still visible in the exported logs.
      if (pointCount % 12 == 0) {
        logs.fine(
          '$ScoreActivity: activity ${activity.id} has $pointCount points '
          '(status: ${status.name}).',
        );
      }
      emit(
        state.copyWith(
          activity: current.copyWith(points: [...current.points, ...newPoints]),
        ),
      );
    } catch (e, s) {
      logs.severe('$ScoreActivity', error: e, trace: s);
      emit(state.copyWith(error: AppError('ScoreActivity: $e')));
    }
  }

  void _onPauseActivity(PauseActivity event, Emitter<MapState> emit) {
    try {
      if (state.activity == null) throw ActivityNotStartedError();

      final wasPaused = state.isPaused;
      logs.info(
        '$PauseActivity: activity ${state.activity!.id} '
        '${wasPaused ? 'resumed' : 'paused'} at elapsed '
        '${state.elapsedTime.inSeconds}s.',
      );

      if (wasPaused) {
        if (_pauseStartTime != null) {
          _totalPausedDuration += DateTime.now().difference(_pauseStartTime!);
          _pauseStartTime = null;
        }
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!isClosed) add(const UpdateElapsedTime());
        });
      } else {
        _pauseStartTime = DateTime.now();
        _elapsedTimer?.cancel();
      }

      emit(state.copyWith(isPaused: !state.isPaused));
    } catch (e, s) {
      logs.severe('$PauseActivity', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  Future<void> _onCeaseActivity(
    CeaseActivity event,
    Emitter<MapState> emit,
  ) async {
    // Back-to-back Stop taps would hit a null state.activity on the second
    // pass. Treat a second cease as a no-op instead of logging a spurious
    // severe from the null-check crash.
    final activity = state.activity;
    if (activity == null) return;
    try {
      await _ceaseActivityUsecase(activity.id);
      logs.info(
        '$CeaseActivity: activity ${activity.id} stopped with '
        '${activity.points.length} points, elapsed '
        '${state.elapsedTime.inSeconds}s.',
      );
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _activityStartTime = null;
      _pauseStartTime = null;
      _totalPausedDuration = Duration.zero;

      emit(
        state.copyWith(
          activity: null,
          elapsedTime: Duration.zero,
          isPaused: false,
        ),
      );
    } catch (e, s) {
      logs.severe('$CeaseActivity', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  void _onClearError(ClearError event, Emitter<MapState> emit) {
    emit(state.copyWith(error: null));
  }

  void _onUpdateElapsedTime(UpdateElapsedTime event, Emitter<MapState> emit) {
    try {
      if (_activityStartTime == null) return;

      final elapsed =
          DateTime.now().difference(_activityStartTime!) - _totalPausedDuration;
      emit(state.copyWith(elapsedTime: elapsed));
    } catch (e, s) {
      logs.severe('$UpdateElapsedTime', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  Future<void> _onTracesSearchRequested(
    FetchTraces event,
    Emitter<MapState> emit,
  ) async {
    try {
      final center = event.center;
      final double lat = center.latitude;
      final double lon = center.longitude;
      final double halfBox = kSearchHalfSideDegrees;
      final double left = lon - halfBox;
      final double right = lon + halfBox;
      final double bottom = lat - halfBox;
      final double top = lat + halfBox;

      emit(
        state.copyWith(
          searchCenter: PositionEntity(
            latitude: lat,
            longitude: lon,
            elevation: 0,
          ),
          loadingStatus: LoadingStatus.loadingTraces,
        ),
      );
      final traces = await _getPublicGpsTracesUseCase(
        left,
        bottom,
        right,
        top,
        0,
      );
      emit(state.copyWith(traces: traces));
    } catch (e, s) {
      logs.severe('$FetchTraces', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  void _onToggleFollowUser(ToggleFollowUser event, Emitter<MapState> emit) {
    emit(state.copyWith(isFollowingUser: !state.isFollowingUser));
  }

  void _onStopFollowingUser(StopFollowingUser event, Emitter<MapState> emit) {
    emit(state.copyWith(isFollowingUser: false));
  }
}
