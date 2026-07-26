/// Injectable source of "now".
///
/// Exists so the app's time-dependent behaviour is testable without waiting in
/// real time. Furtive has several windows that are otherwise unreachable from a
/// test: the 12 h after which an unfinished recording is treated as abandoned
/// rather than resumable (`ActivityLocalDataSource.ongoingStaleAfter`), the 20 s
/// of silence after which the position stream is assumed suspended
/// (`PositionStreamController.staleThreshold`), the 24 h update-check TTL, and
/// all of the elapsed/paused-duration bookkeeping during a recording.
///
/// Everything in the app that needs the wall clock takes a [Clock] rather than
/// calling `DateTime.now()` directly. Production code gets [SystemClock] by
/// default, so call sites stay unchanged; tests pass a [FixedClock] (or their
/// own implementation) and drive time explicitly.
abstract interface class Clock {
  /// Current wall-clock instant. Implementations MUST return UTC — every
  /// timestamp Furtive persists, compares or serialises is UTC, and mixing a
  /// local-flagged DateTime into that is the classic source of off-by-hours
  /// duration bugs.
  DateTime nowUtc();
}

/// Default [Clock]: the real system clock, in UTC.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// [Clock] whose time only moves when told to. For tests.
///
/// ```dart
/// final clock = FixedClock(DateTime.utc(2026, 1, 1));
/// clock.advance(const Duration(hours: 13)); // trip the stale-activity window
/// ```
final class FixedClock implements Clock {
  FixedClock(DateTime now) : _now = now.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  /// Moves time forward by [delta].
  void advance(Duration delta) => _now = _now.add(delta);

  /// Jumps to an absolute instant.
  void set(DateTime now) => _now = now.toUtc();
}
