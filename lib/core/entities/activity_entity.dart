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

  String get activePaceMinPerKm {
    if (activeSpeedKmh == 0) return '--:--';
    final paceMinutes = 60 / activeSpeedKmh;
    final minutes = paceMinutes.floor();
    final seconds = ((paceMinutes - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get pausedPaceMinPerKm {
    if (pausedSpeedKmh == 0) return '--:--';
    final paceMinutes = 60 / pausedSpeedKmh;
    final minutes = paceMinutes.floor();
    final seconds = ((paceMinutes - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  List<ActivitySegment> get segments => _segmentPoints(points);

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

    // Copy + sort to avoid mutating the entity's points list.
    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));

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
        if (segMeters == 0) continue;

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
          milestones.add(
            KmMilestone(
              km: nextKm,
              position: PositionEntity(
                latitude: lat,
                longitude: lon,
                elevation: elev,
              ),
              time: DateTime.fromMillisecondsSinceEpoch(tMs),
            ),
          );
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
        if (segMeters == 0) continue;
        final segActiveMs =
            b.time.millisecondsSinceEpoch - a.time.millisecondsSinceEpoch;
        // Guard against GPS clock skew / out-of-order points — a negative
        // delta would produce negative split durations and a negative bar.
        if (segActiveMs < 0) continue;

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
