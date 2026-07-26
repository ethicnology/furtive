import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

/// Result of parsing GPX content off the main isolate — see [_parseGpxContent].
class _GpxParseResult {
  final List<ActivityPointEntity> points;
  final String? metadataName;
  _GpxParseResult(this.points, this.metadataName);
}

typedef _GpxParseRequest = ({String content, DateTime fallbackTime});

/// Parses raw GPX XML text into activity points + the metadata name. A
/// top-level function (required by `compute()`/`Isolate.run`) so the DOM
/// parse and point-building — O(file size), and a multi-hour high-frequency
/// GPX can be several MB of XML producing tens of thousands of points — run
/// on a background isolate instead of janking the UI thread on import. See
/// M2 in docs/REVIEW-2026-07-FULL-APP.md. `ActivityPointEntity`/`PositionEntity`
/// are plain data classes (no closures/handles), so they transfer across the
/// isolate boundary without issue; thrown `GpxParseError`/`GpxNoPointsError`
/// propagate back to the caller isolate the same way `compute` propagates
/// any other exception.
_GpxParseResult _parseGpxContent(_GpxParseRequest request) {
  final content = request.content;
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
  // separate <trk>/<rte>) marks a loss of GPS reception — the straight
  // line between the end of one segment and the start of the next must NOT
  // be counted as travelled distance or active time. parseGpxSegments
  // keeps the groups separate; we bracket the gaps with signalLost
  // boundaries below so the stats math doesn't bridge them.
  final groups = parseGpxSegments(root);

  // Build each group's points first (real-or-synthesised time), keeping
  // document order for the synthesis pass below — a foreign GPX missing
  // `<time>` on some points still gets sane, monotonically increasing
  // timestamps from wherever came before it in the file.
  final groupPointLists = <List<ActivityPointEntity>>[];
  // Track the last timestamp (real or synthesised) so points without a
  // `<time>` element get a +1s offset from whatever came before — keeps
  // ordering correct in mixed files (some trkpts have <time>, some don't)
  // and gives sane timestamps for GPX exports that strip time entirely
  // (lastTime stays null on entry → falls back to now()).
  DateTime? lastTime;
  for (final group in groups) {
    final groupPoints = <ActivityPointEntity>[];
    for (final parsed in group) {
      final time =
          parsed.time ??
          (lastTime?.add(const Duration(seconds: 1)) ?? request.fallbackTime);
      lastTime = time;
      groupPoints.add(
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
    if (groupPoints.isNotEmpty) groupPointLists.add(groupPoints);
  }

  // Order groups chronologically (by each group's first point) before
  // bracketing gaps between them. ActivityEntity re-sorts every point by
  // time regardless of the order we hand it (see _segmentPoints), so
  // document order carries no meaning to the stats math — but the gap
  // bracketing below only inserts a signalLost pair between what it
  // considers "adjacent" groups. Bracketing by DOCUMENT adjacency (the
  // previous behaviour) breaks down for a file whose <trk> blocks are not
  // in chronological order (e.g. concatenated from several separate
  // recordings, newest first): the entity's time-sort then interleaves both
  // groups' active points with only the stray boundary point in between,
  // silently counting the straight-line jump between them — and the wall
  // clock span across it — as active distance/time instead of excluding it.
  // Sorting groups by real time first makes bracketing-by-adjacency and
  // bracketing-by-chronology the same operation.
  groupPointLists.sort((a, b) => a.first.time.compareTo(b.first.time));

  final points = <ActivityPointEntity>[];
  for (var g = 0; g < groupPointLists.length; g++) {
    final groupPoints = groupPointLists[g];

    // Between segments, bracket the gap with two signalLost boundary
    // points: a duplicate of the previous segment's last point (1µs later
    // so it sorts right after it) and a duplicate of this segment's first
    // point (1µs earlier). The pair forms a signalLost segment spanning
    // the gap, carrying its duration and straight-line distance — the same
    // shape live recording produces (ScoreActivityUseCase.gapFrom). Every
    // leg touching a boundary crosses a status change, so neither the gap
    // NOR any real leg of the next segment is counted as active distance.
    // If the file's timestamps don't actually advance across the gap
    // (synthesised or broken times), fall back to a single boundary point:
    // the gap still splits into separate segments, it just carries no
    // measurable signalLost duration.
    if (g > 0 && points.isNotEmpty && groupPoints.isNotEmpty) {
      final prev = points.last;
      final next = groupPoints.first;
      points.add(
        ActivityPointEntity(
          position: prev.position,
          time: prev.time.add(const Duration(microseconds: 1)),
          status: ActivityPointStatusEntity.signalLost,
        ),
      );
      if (next.time.isAfter(prev.time.add(const Duration(microseconds: 2)))) {
        points.add(
          ActivityPointEntity(
            position: next.position,
            time: next.time.subtract(const Duration(microseconds: 1)),
            status: ActivityPointStatusEntity.signalLost,
          ),
        );
      }
    }
    points.addAll(groupPoints);
  }

  if (points.isEmpty) throw const GpxNoPointsError();

  final metadataName = root
      .findElements('metadata')
      .firstOrNull
      ?.findElements('name')
      .firstOrNull
      ?.innerText;

  return _GpxParseResult(points, metadataName);
}

/// Parses GPX into an activity. Imports what ExportActivityToGpxUseCase emits
/// (`<trk>/<trkseg>/<trkpt lat lon><ele><time>`) plus the common variations:
/// multiple `<trk>`/`<trkseg>` blocks, `<rte>/<rtept>` route points, missing
/// `<ele>` (default 0), and missing `<time>` (synthesised from `now()` for the
/// first point + 1s increments — keeps duration math from blowing up but loses
/// real timestamps). Rejects points with non-finite or out-of-range coords via
/// the shared parseTrkpt validator.
///
/// Not a lossless round-trip: the exporter writes only the active segments of
/// an activity (pauses and signal outages are deliberately excluded from the
/// file), so a paused stretch does not survive export→import. Each track
/// segment boundary is treated as a GPS outage — per the GPX 1.1 spec's
/// `<trkseg>` doc ("To represent a single GPS track where GPS reception was
/// lost ... start a new Track Segment"), the gap is bracketed with signalLost
/// boundary points on import so it is neither counted as travelled distance
/// nor as active time, and its duration is reported as signal lost. Same
/// mechanic as live recording's gap detection (SignalGapDetector).
class ImportActivityFromGpxUseCase {
  ImportActivityFromGpxUseCase({ActivityRepository? activities, Clock? clock})
    : _activities = activities ?? ActivityRepository(clock: clock),
      _clock = clock ?? const SystemClock();

  final ActivityRepository _activities;
  final Clock _clock;

  /// Files larger than this are rejected before parsing.
  ///
  /// This bounds PEAK MEMORY, nothing else. A previous version of this comment
  /// claimed the ceiling defended against billion-laughs / quadratic-blowup XML
  /// "because the xml package doesn't disable DTD entity expansion". Both halves
  /// were wrong, and the claim is now pinned by tests in gpx_xml_safety_test.dart:
  /// package:xml does NOT expand custom DTD entities (a billion-laughs payload
  /// parses to the literal `&d;`) and does NOT resolve external ones (no XXE) —
  /// and a size cap could never have stopped billion-laughs anyway, whose whole
  /// point is that ~1 KB of input expands to gigabytes.
  ///
  /// What the cap does buy: [call] reads the file into a String and `compute`
  /// then COPIES it to the parse isolate, so the real peak is roughly 2-3x the
  /// file size. 10 MB already covers a 24 h recording at 1 Hz (a typical 2 h GPX
  /// is ~300-400 KB), so the old 50 MB ceiling only bought a ~150 MB peak and an
  /// OOM risk on entry-level Android.
  static const _maxFileBytes = 10 * 1024 * 1024;

  Future<ActivityEntity> call(File file) async {
    final size = await file.length();
    if (size > _maxFileBytes) {
      throw GpxParseError(
        'File too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB)',
      );
    }
    final content = await file.readAsString();

    // Parse + build points on a background isolate — see _parseGpxContent's
    // doc for why. `compute` marshals the result back (or rethrows a parse
    // error) on this isolate.
    final parsed = await compute(_parseGpxContent, (
      content: content,
      fallbackTime: _clock.nowUtc(),
    ));
    final points = parsed.points;
    final metadataName = parsed.metadataName;

    final fallbackName = file.uri.pathSegments.last.replaceAll(
      RegExp(r'\.gpx$', caseSensitive: false),
      '',
    );
    final name = (metadataName != null && metadataName.trim().isNotEmpty)
        ? metadataName.trim()
        : (fallbackName.isNotEmpty ? fallbackName : kDefaultActivityName);

    // min/max over the REAL (active) fixes only — not first/last, and not
    // the synthetic signalLost boundary duplicates (whose ±1µs offsets are
    // an artifact of bracketing the gap, not an actual GPS fix). `points`
    // follows document order, which for a multi-<trk> file with segments
    // out of chronological order (e.g. concatenated from several
    // recordings) would otherwise report a stoppedAt before startedAt. The
    // per-segment stats themselves are unaffected (segments are re-sorted
    // internally by ActivityEntity), but this metadata — the detail page's
    // "started at" line and the export filename's timestamp — must reflect
    // the real span.
    final activeTimes = points
        .where((p) => p.status == ActivityPointStatusEntity.active)
        .map((p) => p.time);
    final startedAt = activeTimes
        .reduce((a, b) => a.isBefore(b) ? a : b)
        .toUtc();
    final stoppedAt = activeTimes
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .toUtc();
    final createdAt = _clock.nowUtc();
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

    await _activities.store(activity);
    return activity;
  }
}

class GpxParseError extends AppError {
  GpxParseError(String details) : super('Invalid GPX: $details');
}

class GpxNoPointsError extends AppError {
  const GpxNoPointsError() : super('GPX contains no valid track points');
}
