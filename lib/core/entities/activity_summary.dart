import 'package:furtive/core/entities/activity_entity.dart' show formatPace;

/// Lightweight row for the activities list: the displayed stats only, with no
/// GPS points loaded. Distance/duration come from the denormalised columns on
/// the activities table (see ActivityLocalDataSource.fetchSummaries), so the
/// list scales without reading every point of every activity into memory.
class ActivitySummary {
  final String id;
  final String name;
  final DateTime startedAt;
  final double activeDistanceMeters;
  final Duration activeDuration;

  const ActivitySummary({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.activeDistanceMeters,
    required this.activeDuration,
  });

  double get activeDistanceInKm => activeDistanceMeters / 1000;

  double get activeSpeedKmh {
    final seconds = activeDuration.inSeconds;
    if (seconds <= 0) return 0;
    return (activeDistanceMeters / seconds) * 3.6;
  }

  String get activePaceMinPerKm =>
      activeSpeedKmh == 0 ? '--:--' : formatPace(60 / activeSpeedKmh);
}
