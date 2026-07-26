import 'dart:async';

import 'package:furtive/core/clock.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/location_repository.dart';

/// Owns the lifetime of the GPS position stream.
///
/// Extracted from MapBloc, which used to interleave four unrelated concerns.
/// This is the stream-lifecycle one: opening exactly once, recognising a stream
/// the OS silently suspended, and reopening it. Deliberately a plain class, not
/// a bloc — it has no UI state, and being plain makes it directly unit-testable
/// with a fake [LocationRepository] and a [FixedClock].
///
/// Two hazards it exists to contain:
///
///  * **Double-open.** [ensureOpen] memoises the in-flight open. A naive
///    `if (_subscription == null) await open()` is a check-then-act with an
///    await in the middle: two concurrent callers (MapPage.initState and the
///    onboarding finish both dispatch InitMap, and the default bloc transformer
///    runs differently-typed events concurrently) both see null, both call
///    `listen()`, and the app leaks a subscription while double-writing every
///    fix to the database.
///
///  * **Silent suspension.** geolocator can stop delivering fixes in deep Doze
///    without an error or `onDone` (Baseflow/flutter-geolocator#1023), so
///    liveness cannot be inferred from the subscription object. [isStale]
///    instead compares the last *raw* fix against [staleThreshold].
class PositionStreamController {
  PositionStreamController({LocationRepository? location, Clock? clock})
    : _location = location ?? LocationRepository(),
      _clock = clock ?? const SystemClock();

  final LocationRepository _location;
  final Clock _clock;

  /// If a recording is running and no fix has arrived for longer than this,
  /// assume the stream stalled and reopen. The Android stream is configured at
  /// 5 s intervals, so 20 s is ~4 missed fixes — past normal jitter, while a
  /// stationary device still emits at distanceFilter 0.
  static const staleThreshold = Duration(seconds: 20);

  StreamSubscription<PositionEntity>? _subscription;
  Future<void>? _opening;
  DateTime? _lastFixAt;

  /// Fires for every accepted fix.
  void Function(PositionEntity position)? onPosition;

  /// Fires when the underlying stream closes, which means the foreground
  /// service actually died — never a user gesture (the notification is ongoing
  /// and the service holds a wake lock). The owner should re-init; the activity
  /// row stays open and keeps recording.
  void Function()? onStreamClosed;

  bool get isOpen => _subscription != null;

  /// Wall-clock of the last fix received from the platform, or null if none has
  /// arrived since this controller was created.
  DateTime? get lastFixAt => _lastFixAt;

  /// Time since the last fix, or null when none has ever arrived.
  Duration? get sinceLastFix {
    final last = _lastFixAt;
    return last == null ? null : _clock.nowUtc().difference(last);
  }

  /// True when no fix has arrived for longer than [staleThreshold] — or when
  /// none ever arrived at all.
  bool get isStale {
    final gap = sinceLastFix;
    return gap == null || gap > staleThreshold;
  }

  /// Opens the stream if it is not already open, memoising the in-flight open so
  /// concurrent callers await the same one. Always use this rather than [_open].
  Future<void> ensureOpen() {
    if (_subscription != null) return Future.value();
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  /// Cancels and reopens. Used when [isStale] indicates the OS suspended the
  /// stream in the background.
  Future<void> reopen() async {
    await _subscription?.cancel();
    _subscription = null;
    await ensureOpen();
  }

  Future<void> _open() async {
    final stream = _location.getPositionStream(
      // Stamped for every raw platform fix, NOT only fixes that survive
      // GpsQualityFilter. Otherwise "every recent fix failed the quality gate"
      // (normal under tree cover / urban canyon / indoors) is indistinguishable
      // from "the foreground service died", and the watchdog tears down a
      // healthy service while showing a false tracking-gap banner.
      onRawFix: () => _lastFixAt = _clock.nowUtc(),
    );
    _subscription = stream
        .handleError(
          (Object error, StackTrace stack) =>
              logs.severe('position stream', error: error, trace: stack),
        )
        .listen(
          (position) => onPosition?.call(position),
          onDone: () {
            logs.warning('Position stream closed; reopening.');
            _subscription = null;
            onStreamClosed?.call();
          },
        );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    onPosition = null;
    onStreamClosed = null;
  }
}
