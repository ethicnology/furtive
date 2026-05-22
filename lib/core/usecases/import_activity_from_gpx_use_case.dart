import 'dart:io';

import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

/// Round-trip-compatible with ExportActivityToGpxUseCase: the GPX we emit
/// (`<trk>/<trkseg>/<trkpt lat lon><ele><time>`) parses back into an
/// equivalent activity. Accepts the common variations: multiple `<trk>`
/// blocks (concatenated into one activity), missing `<ele>` (default 0),
/// missing `<time>` (synthesised from `now()` for the first point + 1s
/// increments — keeps duration math from blowing up but loses real
/// timestamps). Rejects points with non-finite or out-of-range coords via
/// the shared parseTrkpt validator.
///
/// GPX has no pause semantics so every imported point is marked active.
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

    final points = <ActivityPointEntity>[];
    // Track the last timestamp (real or synthesised) so points without a
    // `<time>` element get a +1s offset from whatever came before — keeps
    // ordering correct in mixed files (some trkpts have <time>, some
    // don't) and gives sane timestamps for GPX exports that strip time
    // entirely (lastTime stays null on entry → falls back to now()).
    DateTime? lastTime;
    // Walk both <trkpt> (track points — the standard form) and <rtept>
    // (route points — Garmin Connect exports planned/imported workouts
    // this way). Both elements share the lat/lon/<ele>/<time> shape so
    // parseTrkpt handles either. If a file ships only <wpt> waypoints
    // with no track or route we fall through to GpxNoPointsError below.
    final pointElements = [
      ...root.findAllElements('trkpt'),
      ...root.findAllElements('rtept'),
    ];
    for (final element in pointElements) {
      final parsed = parseTrkpt(element);
      if (parsed == null) continue;
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
