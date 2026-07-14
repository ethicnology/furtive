import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';

/// Ingestion-time quality gate for the continuous tracking stream. Rejects
/// fixes that are more likely GPS noise (multipath, urban canyon reflection,
/// momentary provider glitch) than real movement, before they ever reach the
/// recorded trace / distance and elevation-gain maths.
///
/// Deliberately conservative: every check only rejects when the platform
/// actually reported the relevant field. A provider that doesn't supply
/// accuracy is never penalised for it — the gate can only get stricter as
/// better metadata becomes available, never block a fix outright for lack of
/// data. See AUDIT-2026-07.md §4.2.
///
/// Stateful (tracks the last *accepted* fix), so use one instance per stream
/// subscription — `LocationRepository.getPositionStream()` creates a fresh
/// one on every call, matching one instance per stream (re)open.
class GpsQualityFilter {
  /// Fixes vaguer than this are more likely multipath/urban-canyon noise
  /// than a real GPS reading for a foot/bike activity. 25 m is the
  /// consensus starting point for running/cycling trackers (tighter than a
  /// phone's typical open-sky accuracy of 3-8 m, loose enough to tolerate
  /// normal jitter under light cover).
  final double maxHorizontalAccuracyMeters;

  /// A fix implying ground speed above this since the last *accepted* fix is
  /// treated as a teleport/jump artefact rather than real human-powered
  /// movement. One threshold for every activity type (the app has no
  /// per-activity sport selector to size this more tightly): 35 m/s
  /// (126 km/h) comfortably covers a fast bike descent while still catching
  /// the kind of multi-hundred-metre jump multipath reflections produce
  /// between two ~5s-apart fixes.
  final double maxSpeedMps;

  GpsQualityFilter({
    this.maxHorizontalAccuracyMeters = 25,
    this.maxSpeedMps = 35,
  });

  PositionEntity? _lastAccepted;

  /// Wraps [source], filtering out fixes that fail the quality gate.
  Stream<PositionEntity> apply(Stream<PositionEntity> source) =>
      source.where(_accept);

  bool _accept(PositionEntity position) {
    if (position.accuracy != null &&
        position.accuracy! > maxHorizontalAccuracyMeters) {
      return false;
    }

    final previous = _lastAccepted;
    if (previous != null && previous.time != null && position.time != null) {
      final dtSeconds =
          position.time!.difference(previous.time!).inMilliseconds / 1000;
      // dtSeconds <= 0: out-of-order/duplicate-timestamp fix. Not this
      // filter's job (LocationRepository already stamps fix time from the
      // platform and score_activity_use_case/activity_entity already guard
      // against non-positive deltas downstream) — accept and let those
      // guards handle it rather than rejecting on ambiguous data here.
      if (dtSeconds > 0) {
        final meters = Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
        if (meters.isFinite && (meters / dtSeconds) > maxSpeedMps) {
          // Reject without moving _lastAccepted: keep comparing subsequent
          // fixes against the last known-good anchor rather than chaining
          // off a fix we just decided not to trust.
          return false;
        }
      }
    }

    _lastAccepted = position;
    return true;
  }
}
