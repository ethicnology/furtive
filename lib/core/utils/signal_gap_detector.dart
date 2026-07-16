/// Detects GPS signal outages from the cadence of incoming fixes.
///
/// A gap can only be observed retroactively — when the fix that *ends* it
/// arrives. On each accepted fix, [check] compares the time since the
/// previous fix against an adaptive threshold; when exceeded, the caller
/// brackets the gap with `signalLost` boundary points (see
/// ActivityPointStatusEntity.signalLost).
///
/// Threshold design (researched 2026-07, see CHANGELOG for the summary):
/// - A *time*-based criterion, not a speed threshold: speed heuristics are
///   documented as too noisy for slow activities (OpenTracks issue #1187
///   moved away from one; Garmin's speed-based "moving time" notoriously
///   under-counts slow hikes).
/// - Calibrated *relative* to the observed fix cadence rather than a fixed
///   number: OsmAnd uses "gap > 10× the previous interval" alongside an
///   absolute bound; OpenTracks calibrates its idle timeout as a small
///   multiple of the configured GPS interval. Relative calibration matters
///   here because the Android stream is configured at 5 s intervals but iOS
///   has no interval knob, and GpsQualityFilter legitimately stretches the
///   accepted-fix cadence in urban canyons (rejected fixes leave holes).
/// - The rolling *median* (not mean) of recent intervals: a median is
///   insensitive to the occasional long interval — including the very gap
///   being detected.
/// - Clamped to [minThreshold, maxThreshold]: the floor absorbs brief
///   filter-induced dropouts (bridge, tree cover) without splitting the
///   trace; the ceiling (OsmAnd's read-side bound) guarantees a long outage
///   always splits even if the preceding cadence was degraded.
class SignalGapDetector {
  /// Fallback interval before enough samples accumulate — the Android
  /// stream's configured intervalDuration (location_gps_data_source.dart).
  static const nominalInterval = Duration(seconds: 5);

  /// Threshold = clamp(multiplier × median interval, min, max).
  static const multiplier = 10;
  static const minThreshold = Duration(seconds: 30);
  static const maxThreshold = Duration(minutes: 6);

  /// Rolling window size. At the nominal 5 s cadence this is ~100 s of
  /// recent history — long enough to smooth jitter, short enough to adapt
  /// when the cadence genuinely changes (e.g. moving into tree cover).
  static const windowSize = 20;

  final List<int> _intervalsMs = [];

  /// Current gap threshold given the recent fix cadence.
  Duration get threshold {
    final medianMs = _intervalsMs.isEmpty
        ? nominalInterval.inMilliseconds
        : _medianMs();
    final thresholdMs = medianMs * multiplier;
    if (thresholdMs < minThreshold.inMilliseconds) return minThreshold;
    if (thresholdMs > maxThreshold.inMilliseconds) return maxThreshold;
    return Duration(milliseconds: thresholdMs);
  }

  /// Feeds the interval between the previous and the current fix. Returns
  /// the gap duration when it exceeds [threshold] (a signal outage), null
  /// otherwise. Gap intervals are NOT added to the rolling window — the
  /// outage itself must not inflate the cadence estimate; a non-positive
  /// interval (clock skew, out-of-order fixes) is ignored entirely.
  Duration? check(DateTime previousFix, DateTime currentFix) {
    final gap = currentFix.difference(previousFix);
    if (gap <= Duration.zero) return null;
    if (gap > threshold) return gap;
    _intervalsMs.add(gap.inMilliseconds);
    if (_intervalsMs.length > windowSize) _intervalsMs.removeAt(0);
    return null;
  }

  /// Clears the cadence history (new recording).
  void reset() => _intervalsMs.clear();

  int _medianMs() {
    final sorted = List<int>.from(_intervalsMs)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) ~/ 2;
  }
}
