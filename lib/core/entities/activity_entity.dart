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

  ({double gain, double loss}) get activeElevation =>
      _calculateSegmentsElevation(activeSegments);
  ({double gain, double loss}) get pausedElevation =>
      _calculateSegmentsElevation(pausedSegments);

  List<ActivitySegment> _segmentPoints(List<ActivityPointEntity> points) {
    if (points.isEmpty) return [];

    // Ensure they are sorted by time earliest to latest
    points.sort((a, b) => a.time.compareTo(b.time));

    final segments = <ActivitySegment>[];
    var currentSegmentPoints = <ActivityPointEntity>[points.first];
    var currentStatus = points.first.status;

    for (final point in points) {
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

  ({double gain, double loss}) _calculateSegmentsElevation(
    List<ActivitySegment> segments,
  ) {
    double totalGain = 0.0;
    double totalLoss = 0.0;

    for (final segment in segments) {
      double segmentGain = 0.0;
      double segmentLoss = 0.0;
      final points = segment.points;

      for (int i = 0; i < points.length - 1; i++) {
        final currentPoint = points[i];
        final nextPoint = points[i + 1];
        final elevationGain =
            nextPoint.position.elevation - currentPoint.position.elevation;
        if (elevationGain > 0) segmentGain += elevationGain;
        if (elevationGain < 0) segmentLoss += elevationGain;
      }
      totalGain += segmentGain;
      totalLoss += segmentLoss;
    }
    return (gain: totalGain, loss: totalLoss);
  }
}

extension ActivityPathExtension on ActivityEntity {
  Widget toPolylineLayer() {
    if (points.isEmpty) return PolylineLayer(polylines: <Polyline>[]);

    final segments = <Polyline>[];
    var segmentPoints = <ActivityPointEntity>[];
    ActivityPointStatusEntity? previousStatus;

    for (final point in points) {
      final hasStatusChanged =
          previousStatus != null && point.status != previousStatus;

      if (hasStatusChanged) {
        segments.add(_createPathSegment(segmentPoints, previousStatus));
        segmentPoints = [];
      }

      segmentPoints.add(point);
      previousStatus = point.status;
    }

    if (segmentPoints.isNotEmpty && previousStatus != null) {
      segments.add(_createPathSegment(segmentPoints, previousStatus));
    }

    return PolylineLayer(polylines: segments);
  }

  Polyline _createPathSegment(
    List<ActivityPointEntity> points,
    ActivityPointStatusEntity status,
  ) {
    return Polyline(
      points: points.map((p) => p.position.toLatLng()).toList(),
      color:
          status == ActivityPointStatusEntity.active
              ? AppColors.primary.background
              : AppColors.secondary.background,
      strokeWidth: 4.0,
    );
  }
}
