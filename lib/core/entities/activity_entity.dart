import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';

part 'activity_entity.mapper.dart';

@MappableClass()
class ActivityEntity with ActivityEntityMappable {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final List<ActivityPointEntity> points;

  ActivityEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.startedAt,
    required this.stoppedAt,
    this.points = const [],
  });
}

enum ActivityPointStatusEntity { active, paused }

/// Format a pace in minutes-per-km as `m:ss`. Carries 60 rounded seconds into
/// the minute so a value like 5.999 min/km renders `6:00`, never `5:60`.
String formatPace(double paceMinutes) {
  var minutes = paceMinutes.floor();
  var seconds = ((paceMinutes - minutes) * 60).round();
  if (seconds >= 60) {
    minutes += 1;
    seconds = 0;
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Sentinel stored in `ActivityEntity.name` when the user hasn't picked a
/// custom name yet. Compared by reference in the activities list to decide
/// whether to fall back to the start timestamp. Localised display copy
/// lives under `AppLocalizations.activityDefaultName`.
const String kDefaultActivityName = 'Track';

@MappableClass()
class ActivityPointEntity with ActivityPointEntityMappable {
  final PositionEntity position;
  final DateTime time;
  final ActivityPointStatusEntity status;

  ActivityPointEntity({
    required this.position,
    required this.time,
    required this.status,
  });
}

class ActivitySegment {
  final List<ActivityPointEntity> points;
  final ActivityPointStatusEntity status;

  ActivitySegment({required this.points, required this.status});

  bool get isActive => status == ActivityPointStatusEntity.active;
  bool get isPaused => status == ActivityPointStatusEntity.paused;
}

// Per-instance cache of the segmented points. ActivityStatsWidget reads ~9
// stat getters per build (each derived from `segments`), and the map rebuilds
// it on every GPS fix and every 1s tick during a recording — without this,
// each build re-sorts and re-segments the entire points list ~9×, which grows
// to thousands of points on a long activity. Keyed on the entity instance:
// copyWith makes a new instance per fix, so the cache is naturally invalidated
// and the old entry is collected with its entity.
final Expando<List<ActivitySegment>> _segmentsCache = Expando('segments');

extension ActivityStatisticsExtension on ActivityEntity {
  double get activeDistanceInKm => activeDistanceMeters / 1000;

  double get pausedDistanceInKm => pausedDistanceMeters / 1000;

  double get activeSpeedMps =>
      activeDuration.inSeconds > 0
          ? (activeDistanceMeters / activeDuration.inSeconds)
          : 0.0;

  double get pausedSpeedMps =>
      pausedDuration.inSeconds > 0
          ? (pausedDistanceMeters / pausedDuration.inSeconds)
          : 0.0;

  double get activeSpeedKmh => activeSpeedMps * 3.6;

  double get pausedSpeedKmh => pausedSpeedMps * 3.6;

  String get activePaceMinPerKm =>
      activeSpeedKmh == 0 ? '--:--' : formatPace(60 / activeSpeedKmh);

  String get pausedPaceMinPerKm =>
      pausedSpeedKmh == 0 ? '--:--' : formatPace(60 / pausedSpeedKmh);

  List<ActivitySegment> get segments =>
      _segmentsCache[this] ??= _segmentPoints(points);

  List<ActivitySegment> get activeSegments =>
      segments.where((s) => s.isActive).toList();
  List<ActivitySegment> get pausedSegments =>
      segments.where((s) => s.isPaused).toList();

  Duration get activeDuration => _calculateSegmentsDuration(activeSegments);
  Duration get pausedDuration => _calculateSegmentsDuration(pausedSegments);

  double get activeDistanceMeters => _calculateSegmentsDistance(activeSegments);
  double get pausedDistanceMeters => _calculateSegmentsDistance(pausedSegments);

  // D+ only — sum of positive elevation deltas (matches Strava/Garmin
  // "Elevation Gain"). For a loop this is roughly half of total altitude
  // variation; for a one-way ascent it equals total climb.
  double get activeElevationGain => _calculateSegmentsElevationGain(activeSegments);
  double get pausedElevationGain => _calculateSegmentsElevationGain(pausedSegments);

  List<ActivitySegment> _segmentPoints(List<ActivityPointEntity> points) {
    if (points.isEmpty) return [];

    // Filter out any GPS fix with non-finite coordinates. flutter_map's
    // LatLng constructor crashes on NaN, and a single NaN point poisons
    // every downstream distance / interpolation calc.
    final valid =
        points
            .where(
              (p) =>
                  p.position.latitude.isFinite && p.position.longitude.isFinite,
            )
            .toList();
    if (valid.isEmpty) return [];

    // Copy + sort to avoid mutating the entity's points list.
    final sorted = valid..sort((a, b) => a.time.compareTo(b.time));

    final segments = <ActivitySegment>[];
    var currentSegmentPoints = <ActivityPointEntity>[sorted.first];
    var currentStatus = sorted.first.status;

    for (final point in sorted.skip(1)) {
      if (point.status == currentStatus) {
        currentSegmentPoints.add(point);
      } else {
        segments.add(
          ActivitySegment(
            points: List.unmodifiable(currentSegmentPoints),
            status: currentStatus,
          ),
        );
        currentSegmentPoints = [point];
        currentStatus = point.status;
      }
    }

    segments.add(
      ActivitySegment(
        points: List.unmodifiable(currentSegmentPoints),
        status: currentStatus,
      ),
    );

    return segments;
  }

  Duration _calculateSegmentsDuration(List<ActivitySegment> segments) {
    if (segments.isEmpty) return Duration.zero;

    var totalDuration = Duration.zero;
    for (final segment in segments) {
      if (segment.points.isEmpty) continue;

      final firstPoint = segment.points.first;
      final lastPoint = segment.points.last;
      final duration = lastPoint.time.difference(firstPoint.time);
      totalDuration += duration;
    }
    return totalDuration;
  }

  double _calculateSegmentsDistance(List<ActivitySegment> segments) {
    double totalDistance = 0.0;
    for (final segment in segments) {
      final points = segment.points;
      double segmentDistance = 0.0;
      for (int i = 0; i < points.length - 1; i++) {
        segmentDistance += Geolocator.distanceBetween(
          points[i].position.latitude,
          points[i].position.longitude,
          points[i + 1].position.latitude,
          points[i + 1].position.longitude,
        );
      }
      totalDistance += segmentDistance;
    }
    return totalDistance;
  }

  double _calculateSegmentsElevationGain(List<ActivitySegment> segments) {
    double totalGain = 0.0;
    for (final segment in segments) {
      final points = segment.points;
      for (int i = 0; i < points.length - 1; i++) {
        final delta =
            points[i + 1].position.elevation - points[i].position.elevation;
        if (delta > 0) totalGain += delta;
      }
    }
    return totalGain;
  }
}

/// One milestone marker per kilometre crossed during the active part of an
/// activity. Position is interpolated linearly on the segment that crossed
/// the threshold so the marker lands on the exact km, not on the next GPS
/// fix that happened to be past it.
class KmMilestone {
  final int km;
  final PositionEntity position;
  final DateTime time;
  const KmMilestone({
    required this.km,
    required this.position,
    required this.time,
  });
}

/// One per-kilometre split for the active portion. The last split may be
/// partial (e.g. 5.3 km final) — in that case `isPartial == true` and `km`
/// is fractional via `distanceMeters`.
class KmSplit {
  final int index;
  final double distanceMeters;
  final Duration duration;
  final bool isPartial;
  const KmSplit({
    required this.index,
    required this.distanceMeters,
    required this.duration,
    required this.isPartial,
  });

  double get speedKmh =>
      duration.inMicroseconds > 0
          ? (distanceMeters / 1000) /
              (duration.inMicroseconds / Duration.microsecondsPerHour)
          : 0;

  /// Minutes per kilometre (pace). Higher = slower.
  double get paceMinPerKm {
    if (distanceMeters <= 0 || duration.inMicroseconds <= 0) return 0;
    return (duration.inMicroseconds / Duration.microsecondsPerMinute) /
        (distanceMeters / 1000);
  }
}

extension ActivityKmExtension on ActivityEntity {
  /// Per-kilometre milestone markers, interpolated to the exact threshold.
  List<KmMilestone> get kmMilestones {
    final milestones = <KmMilestone>[];
    int nextKm = 1;
    double cumulativeMeters = 0;

    for (final segment in activeSegments) {
      final pts = segment.points;
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        final segMeters = Geolocator.distanceBetween(
          a.position.latitude,
          a.position.longitude,
          b.position.latitude,
          b.position.longitude,
        );
        // segMeters NaN check covers the case where Geolocator.distanceBetween
        // would return NaN on bad input; redundant with _segmentPoints
        // filtering but cheap.
        if (segMeters == 0 || !segMeters.isFinite) continue;

        // Walk through every km threshold this segment crosses (handles
        // gaps where one segment covers >1 km, e.g. after a brief loss
        // of signal).
        while (cumulativeMeters + segMeters >= nextKm * 1000) {
          final overshoot = nextKm * 1000 - cumulativeMeters;
          final t = overshoot / segMeters;
          final lat =
              a.position.latitude +
              (b.position.latitude - a.position.latitude) * t;
          final lon =
              a.position.longitude +
              (b.position.longitude - a.position.longitude) * t;
          final elev =
              a.position.elevation +
              (b.position.elevation - a.position.elevation) * t;
          final tMs = a.time.millisecondsSinceEpoch +
              ((b.time.millisecondsSinceEpoch -
                          a.time.millisecondsSinceEpoch) *
                      t)
                  .round();
          // Skip the milestone if any computed value is non-finite. The
          // segment filter already drops NaN inputs, but if a future code
          // path introduces another NaN source this prevents propagation
          // into PositionEntity → toLatLng → flutter_map crash.
          if (lat.isFinite && lon.isFinite) {
            milestones.add(
              KmMilestone(
                km: nextKm,
                position: PositionEntity(
                  latitude: lat,
                  longitude: lon,
                  elevation: elev.isFinite ? elev : 0,
                ),
                time: DateTime.fromMillisecondsSinceEpoch(tMs),
              ),
            );
          }
          nextKm++;
        }
        cumulativeMeters += segMeters;
      }
    }
    return milestones;
  }

  /// Per-kilometre splits over the active distance. Each split's duration
  /// counts only active time — gaps between paused/active segments are
  /// excluded so a 5 min coffee break between km 1 and km 2 doesn't tank
  /// the km 2 pace. The last entry may be a partial trailing fragment
  /// (isPartial: true).
  List<KmSplit> get kmSplits {
    final splits = <KmSplit>[];
    int nextKm = 1;
    double cumulativeMeters = 0;
    Duration cumulativeActive = Duration.zero;
    Duration prevSplitActive = Duration.zero;

    for (final segment in activeSegments) {
      final pts = segment.points;
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        final segMeters = Geolocator.distanceBetween(
          a.position.latitude,
          a.position.longitude,
          b.position.latitude,
          b.position.longitude,
        );
        final segActiveMs =
            b.time.millisecondsSinceEpoch - a.time.millisecondsSinceEpoch;
        // Guard against GPS clock skew / out-of-order points — a negative
        // delta would produce negative split durations and a negative bar.
        if (segActiveMs < 0) continue;

        // Only walk km thresholds for legs that actually cover ground, but
        // always accrue the elapsed time below — a stationary stretch (two
        // fixes at the same spot, common at distanceFilter=0) still consumes
        // active time the next split's pace must include. Skipping the time
        // here made the splits sum to less than activeDuration.
        if (segMeters.isFinite && segMeters > 0) {
          while (cumulativeMeters + segMeters >= nextKm * 1000) {
            final overshoot = nextKm * 1000 - cumulativeMeters;
            final t = overshoot / segMeters;
            final activeAtCrossing =
                cumulativeActive +
                Duration(milliseconds: (segActiveMs * t).round());
            splits.add(
              KmSplit(
                index: nextKm,
                distanceMeters: 1000,
                duration: activeAtCrossing - prevSplitActive,
                isPartial: false,
              ),
            );
            prevSplitActive = activeAtCrossing;
            nextKm++;
          }
          cumulativeMeters += segMeters;
        }
        cumulativeActive += Duration(milliseconds: segActiveMs);
      }
    }

    // Trailing partial kilometre.
    final partialMeters = cumulativeMeters - (nextKm - 1) * 1000;
    if (partialMeters > 50) {
      splits.add(
        KmSplit(
          index: nextKm,
          distanceMeters: partialMeters,
          duration: cumulativeActive - prevSplitActive,
          isPartial: true,
        ),
      );
    }
    return splits;
  }
}

extension ActivityPathExtension on ActivityEntity {
  Widget toPolylineLayer() {
    if (points.isEmpty) return PolylineLayer(polylines: <Polyline>[]);

    return PolylineLayer(
      polylines: segments.map(_polylineFromSegment).toList(),
    );
  }

  Polyline _polylineFromSegment(ActivitySegment segment) {
    return Polyline(
      points: segment.points.map((p) => p.position.toLatLng()).toList(),
      color:
          segment.isActive
              ? AppColors.primary.background
              : AppColors.secondary.background,
      strokeWidth: 4.0,
    );
  }
}
