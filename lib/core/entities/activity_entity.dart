import 'package:collection/collection.dart' show mergeSort;
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

/// Point status. `active`/`paused` follow the user's recording state.
/// `signalLost` marks a *detected GPS outage*: when a fix arrives after a
/// time gap far exceeding the recent fix cadence (see SignalGapDetector),
/// two boundary points bracketing the gap are stored with this status —
/// duplicates of the last point before and the first point after the gap.
/// The resulting signalLost segment carries the outage duration and the
/// straight-line distance across it, keeping both out of the active stats
/// (the 23-minutes-inside-a-store problem: without this, the gap inflates
/// activeDuration and the polyline draws a straight line through the
/// building). Mirrors GPX `<trkseg>` semantics: "To represent a single GPS
/// track where GPS reception was lost ... start a new Track Segment".
enum ActivityPointStatusEntity { active, paused, signalLost }

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
  bool get isSignalLost => status == ActivityPointStatusEntity.signalLost;
}

// Per-instance cache of the segmented points. ActivityStatsWidget reads ~9
// stat getters per build (each derived from `segments`), and the map rebuilds
// it on every GPS fix and every 1s tick during a recording — without this,
// each build re-sorts and re-segments the entire points list ~9×, which grows
// to thousands of points on a long activity. Keyed on the entity instance:
// copyWith makes a new instance per fix, so the cache is naturally invalidated
// and the old entry is collected with its entity.
final Expando<List<ActivitySegment>> _segmentsCache = Expando('segments');

/// Every segment-derived scalar stat, computed together and cached as one
/// unit per entity instance — see [ActivityStatisticsExtension._stats].
class _StatsBundle {
  final Duration activeDuration;
  final Duration pausedDuration;
  final Duration signalLostDuration;
  final double activeDistanceMeters;
  final double pausedDistanceMeters;
  final double signalLostDistanceMeters;
  final double activeElevationGain;
  final double pausedElevationGain;

  _StatsBundle({
    required this.activeDuration,
    required this.pausedDuration,
    required this.signalLostDuration,
    required this.activeDistanceMeters,
    required this.pausedDistanceMeters,
    required this.signalLostDistanceMeters,
    required this.activeElevationGain,
    required this.pausedElevationGain,
  });
}

final Expando<_StatsBundle> _statsCache = Expando('stats');

extension ActivityStatisticsExtension on ActivityEntity {
  double get activeDistanceInKm => activeDistanceMeters / 1000;

  double get pausedDistanceInKm => pausedDistanceMeters / 1000;

  double get activeSpeedMps => activeDuration.inSeconds > 0
      ? (activeDistanceMeters / activeDuration.inSeconds)
      : 0.0;

  double get pausedSpeedMps => pausedDuration.inSeconds > 0
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
  List<ActivitySegment> get signalLostSegments =>
      segments.where((s) => s.isSignalLost).toList();

  /// Cached bundle of every segment-derived stat (see [_StatsBundle]).
  /// ActivityStatsWidget reads ~8 of these getters per build, and the map
  /// rebuilds on every GPS fix during a recording — without this, each
  /// build re-walks every point of every segment ~8× over, which grows to
  /// thousands of points on a long activity. Same per-instance Expando
  /// pattern as [segments] above, computed once per entity instance.
  _StatsBundle get _stats => _statsCache[this] ??= _StatsBundle(
    activeDuration: _calculateSegmentsDuration(activeSegments),
    pausedDuration: _calculateSegmentsDuration(pausedSegments),
    signalLostDuration: _calculateSegmentsDuration(signalLostSegments),
    activeDistanceMeters: _calculateSegmentsDistance(activeSegments),
    pausedDistanceMeters: _calculateSegmentsDistance(pausedSegments),
    signalLostDistanceMeters: _calculateSegmentsDistance(signalLostSegments),
    activeElevationGain: _calculateSegmentsElevationGain(activeSegments),
    pausedElevationGain: _calculateSegmentsElevationGain(pausedSegments),
  );

  Duration get activeDuration => _stats.activeDuration;
  Duration get pausedDuration => _stats.pausedDuration;

  /// Total time spent in detected GPS outages (see
  /// [ActivityPointStatusEntity.signalLost]). Deliberately excluded from
  /// [activeDuration]/[pausedDuration] — shown separately so elapsed time
  /// stays the immutable truth and the active pace isn't tanked by time the
  /// user demonstrably wasn't being tracked.
  Duration get signalLostDuration => _stats.signalLostDuration;

  double get activeDistanceMeters => _stats.activeDistanceMeters;
  double get pausedDistanceMeters => _stats.pausedDistanceMeters;

  /// Straight-line distance across detected GPS outages. Informative only —
  /// the real path through the gap is unknown, so this is never added to
  /// [activeDistanceMeters].
  double get signalLostDistanceMeters => _stats.signalLostDistanceMeters;

  // D+ only — sum of positive elevation deltas (matches Strava/Garmin
  // "Elevation Gain"). For a loop this is roughly half of total altitude
  // variation; for a one-way ascent it equals total climb.
  double get activeElevationGain => _stats.activeElevationGain;
  double get pausedElevationGain => _stats.pausedElevationGain;

  List<ActivitySegment> _segmentPoints(List<ActivityPointEntity> points) {
    if (points.isEmpty) return [];

    // Filter out any GPS fix with non-finite coordinates. flutter_map's
    // LatLng constructor crashes on NaN, and a single NaN point poisons
    // every downstream distance / interpolation calc.
    final valid = points
        .where(
          (p) => p.position.latitude.isFinite && p.position.longitude.isFinite,
        )
        .toList();
    if (valid.isEmpty) return [];

    // Copy + sort to avoid mutating the entity's points list. MUST be a
    // STABLE sort: SQLite truncates DateTime to whole seconds (no
    // build.yaml configuring otherwise), so the ±1µs boundary pairs that
    // bracket a signalLost gap (ScoreActivityUseCase.gapFrom / GPX import's
    // <trkseg> handling) become exact ties once reloaded from the DB.
    // List.sort is a dual-pivot quicksort and NOT guaranteed stable beyond
    // ~32 elements — on a multi-thousand-point activity it can reorder a
    // tied pair, splitting the signalLost segment into two single-point
    // segments (losing its duration/distance and its dashed-line render).
    // mergeSort preserves the input list's order for ties; the callers of
    // ActivityEntity (fetchSingle/cease/fetchSummaries backfill, all
    // ordered `id ASC`) already guarantee that order matches insertion
    // order, which is chronological.
    final sorted = List<ActivityPointEntity>.from(valid);
    mergeSort(sorted, compare: (a, b) => a.time.compareTo(b.time));

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

  // Reject an altitude sample for gain purposes when its reported vertical
  // accuracy is worse than this. GPS vertical noise is typically 1.5-2x the
  // horizontal figure, so this is looser than GpsQualityFilter's 25 m
  // horizontal threshold. See docs/AUDIT-2026-07.md §4.4.
  static const _maxElevationVerticalAccuracyMeters = 20.0;

  // Window (in samples) for the trailing moving-average smoothing applied
  // before the hysteresis gain calculation — roughly 25-35 s of trace at the
  // ~5 s fix interval this app records at.
  static const _elevationSmoothingWindow = 5;

  // A smoothed altitude must move away from its anchor by more than this
  // before it counts as real elevation gain. GPS-only altitude (no
  // barometer) is noisy enough that summing every raw delta wildly
  // overstates D+ on a perfectly flat route; this dead-band is the standard
  // fix (see e.g. Strava's own description of smoothing + a gain threshold
  // in "Elevation on Strava").
  static const _elevationHysteresisMeters = 10.0;

  double _calculateSegmentsElevationGain(List<ActivitySegment> segments) {
    // Only every point in every prior recording (and every point in tests
    // that don't set it) has verticalAccuracy == null — "no quality signal
    // at all for this data". Rather than invent a smoothing/hysteresis
    // behaviour those recordings were never measured against, fall back to
    // the original raw-sum-of-positive-deltas algorithm. A modern recording
    // — which will have verticalAccuracy on essentially every point — takes
    // the smoothed path below.
    final hasQualityData = segments.any(
      (s) => s.points.any((p) => p.position.verticalAccuracy != null),
    );
    return hasQualityData
        ? _smoothedElevationGain(segments)
        : _rawElevationGain(segments);
  }

  double _rawElevationGain(List<ActivitySegment> segments) {
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

  double _smoothedElevationGain(List<ActivitySegment> segments) {
    double totalGain = 0.0;
    for (final segment in segments) {
      // Drop samples whose reported vertical accuracy is too poor to trust,
      // keeping the rest in original order — a dropped sample is skipped
      // entirely (not zeroed), so the next trusted sample is compared
      // against the last trusted one, not against a synthetic gap.
      final trusted = segment.points
          .where(
            (p) =>
                p.position.verticalAccuracy == null ||
                p.position.verticalAccuracy! <=
                    _maxElevationVerticalAccuracyMeters,
          )
          .map((p) => p.position.elevation)
          .where((e) => e.isFinite)
          .toList();
      if (trusted.length < 2) continue;

      totalGain += _hysteresisGain(
        _movingAverage(trusted, _elevationSmoothingWindow),
        _elevationHysteresisMeters,
      );
    }
    return totalGain;
  }

  /// Trailing (causal) moving average with a window clamped to the samples
  /// available so far — usable on a live/in-progress trace, not just a
  /// finished one.
  List<double> _movingAverage(List<double> values, int window) {
    final out = List<double>.filled(values.length, 0);
    double sum = 0;
    for (int i = 0; i < values.length; i++) {
      sum += values[i];
      final start = i - window + 1;
      if (start > 0) sum -= values[start - 1];
      final count = i - (start < 0 ? 0 : start) + 1;
      out[i] = sum / count;
    }
    return out;
  }

  /// Dead-band elevation gain: only accumulate once the smoothed altitude
  /// has moved away from the last anchor by more than [threshold] (whether
  /// climbing or descending resets the anchor; only climbing accumulates).
  double _hysteresisGain(List<double> smoothed, double threshold) {
    if (smoothed.isEmpty) return 0;
    double gain = 0;
    double anchor = smoothed.first;
    for (final value in smoothed.skip(1)) {
      final diff = value - anchor;
      if (diff >= threshold) {
        gain += diff;
        anchor = value;
      } else if (diff <= -threshold) {
        anchor = value;
      }
    }
    return gain;
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

  double get speedKmh => duration.inMicroseconds > 0
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

final Expando<List<KmMilestone>> _kmMilestonesCache = Expando('kmMilestones');
final Expando<List<KmSplit>> _kmSplitsCache = Expando('kmSplits');

extension ActivityKmExtension on ActivityEntity {
  /// Per-kilometre milestone markers, interpolated to the exact threshold.
  /// Cached per entity instance — KmMilestonesLayer recomputes this on every
  /// build, which the map triggers on every GPS fix; without caching this
  /// re-walks every point of every active segment each time.
  List<KmMilestone> get kmMilestones =>
      _kmMilestonesCache[this] ??= _computeKmMilestones();

  List<KmMilestone> _computeKmMilestones() {
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
          final tMs =
              a.time.millisecondsSinceEpoch +
              ((b.time.millisecondsSinceEpoch - a.time.millisecondsSinceEpoch) *
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
  /// (isPartial: true). Cached per entity instance — see [kmMilestones].
  List<KmSplit> get kmSplits => _kmSplitsCache[this] ??= _computeKmSplits();

  List<KmSplit> _computeKmSplits() {
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
    // signalLost segments render as a discreet dashed straight line: the
    // path through the gap is unknown, so a solid line (implying a recorded
    // trace) would lie — but a bare hole reads as a rendering bug. Dashes
    // communicate "we don't know what happened here".
    return Polyline(
      points: segment.points.map((p) => p.position.toLatLng()).toList(),
      color: segment.isActive
          ? AppColors.primary.background
          : AppColors.secondary.background,
      pattern: segment.isSignalLost
          ? StrokePattern.dashed(segments: const [8, 10])
          : const StrokePattern.solid(),
      strokeWidth: 4.0,
    );
  }
}
