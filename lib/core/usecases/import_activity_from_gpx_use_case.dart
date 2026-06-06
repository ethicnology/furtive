import 'dart:io';

import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

/// Parses GPX into an activity. Imports what ExportActivityToGpxUseCase emits
/// (`<trk>/<trkseg>/<trkpt lat lon><ele><time>`) plus the common variations:
/// multiple `<trk>`/`<trkseg>` blocks, `<rte>/<rtept>` route points, missing
/// `<ele>` (default 0), and missing `<time>` (synthesised from `now()` for the
/// first point + 1s increments — keeps duration math from blowing up but loses
/// real timestamps). Rejects points with non-finite or out-of-range coords via
/// the shared parseTrkpt validator.
///
/// Not a lossless round-trip: the exporter writes only the active segments of
/// an activity (pauses are deliberately excluded from the file), so a paused
/// stretch does not survive export→import. Each track segment is treated as a
/// discontinuity — the gap between segments is marked paused on import so it is
/// not counted as travelled distance (per GPX `<trkseg>` semantics).
class ImportActivityFromGpxUseCase {
  final activityRepository = ActivityRepository();

  ImportActivityFromGpxUseCase();

  /// Files larger than this are rejected before parsing. A typical 2-hour
  /// GPX with 1 Hz sampling is ~300-400 KB. 50 MB is a generous ceiling
  /// that still defends against billion-laughs / quadratic-blowup XML
  /// payloads (the xml package doesn't disable DTD entity expansion).
  static const _maxFileBytes = 50 * 1024 * 1024;

  Future<ActivityEntity> call(File file) async {
    final size = await file.length();
    if (size > _maxFileBytes) {
      throw GpxParseError(
        'File too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB)',
      );
    }
    final content = await file.readAsString();

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(content);
    } catch (e) {
      throw GpxParseError(e.toString());
    }

    final root = doc.rootElement;
    // Accept both gpx 1.0 and 1.1 — trkpt structure is identical between
    // them and we tolerate either xmlns.
    if (root.localName != 'gpx') {
      throw GpxParseError('Root element is <${root.localName}>, expected <gpx>');
    }

    // Collect points grouped by track segment. In GPX a new <trkseg> (or a
    // separate <trk>/<rte>) marks a discontinuity — the straight line between
    // the end of one segment and the start of the next must NOT be counted as
    // travelled distance. parseGpxSegments keeps the groups separate; we
    // stitch them with a paused boundary below so the stats math doesn't
    // bridge the gap.
    final groups = parseGpxSegments(root);

    final points = <ActivityPointEntity>[];
    // Track the last timestamp (real or synthesised) so points without a
    // `<time>` element get a +1s offset from whatever came before — keeps
    // ordering correct in mixed files (some trkpts have <time>, some don't)
    // and gives sane timestamps for GPX exports that strip time entirely
    // (lastTime stays null on entry → falls back to now()).
    DateTime? lastTime;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      // Between segments, insert a single paused boundary point duplicating
      // the previous segment's last point (1µs later so it sorts right after
      // it). Both legs touching the boundary cross an active↔paused status
      // change, so neither the straight-line gap NOR any real leg of the next
      // segment is counted as active distance. (Marking the next segment's
      // first real point paused instead would silently drop that segment's
      // first leg.)
      if (g > 0 && points.isNotEmpty) {
        final prev = points.last;
        points.add(
          ActivityPointEntity(
            position: prev.position,
            time: prev.time.add(const Duration(microseconds: 1)),
            status: ActivityPointStatusEntity.paused,
          ),
        );
      }
      for (final parsed in group) {
        final time =
            parsed.time ??
            (lastTime?.add(const Duration(seconds: 1)) ??
                DateTime.now().toUtc());
        lastTime = time;
        points.add(
          ActivityPointEntity(
            position: PositionEntity(
              latitude: parsed.latitude,
              longitude: parsed.longitude,
              elevation: parsed.elevation,
            ),
            time: time,
            status: ActivityPointStatusEntity.active,
          ),
        );
      }
    }

    if (points.isEmpty) throw const GpxNoPointsError();

    final metadataName = root
        .findElements('metadata')
        .firstOrNull
        ?.findElements('name')
        .firstOrNull
        ?.innerText;
    final fallbackName = file.uri.pathSegments.last.replaceAll(
      RegExp(r'\.gpx$', caseSensitive: false),
      '',
    );
    final name =
        (metadataName != null && metadataName.trim().isNotEmpty)
            ? metadataName.trim()
            : (fallbackName.isNotEmpty ? fallbackName : kDefaultActivityName);

    final startedAt = points.first.time.toUtc();
    final stoppedAt = points.last.time.toUtc();
    final createdAt = DateTime.now().toUtc();
    // Reuse the StartActivityUseCase id convention — millisecond-precise
    // ISO8601 from createdAt rather than startedAt so importing an old
    // GPX twice produces distinct ids.
    final id = createdAt.toIso8601String();

    final activity = ActivityEntity(
      id: id,
      name: name,
      description: '',
      createdAt: createdAt,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      points: points,
    );

    await activityRepository.store(activity);
    return activity;
  }
}

class GpxParseError extends AppError {
  GpxParseError(String details) : super('Invalid GPX: $details');
}

class GpxNoPointsError extends AppError {
  const GpxNoPointsError() : super('GPX contains no valid track points');
}
