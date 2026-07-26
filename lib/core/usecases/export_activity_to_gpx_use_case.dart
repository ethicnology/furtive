import 'package:flutter/foundation.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/facades/file_system_facade.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

class ExportActivityToGpxUseCase {
  ExportActivityToGpxUseCase({ActivityRepository? activities})
    : _activities = activities ?? ActivityRepository();

  final ActivityRepository _activities;

  Future<void> call(String activityId) async {
    final activity = await _activities.fetchSingle(activityId);
    final gpx = generateGpx(activity);

    final fileName =
        '${_sanitizeForFilename(activity.name)}-${activity.startedAt.millisecondsSinceEpoch}.gpx';

    await FileSystemFacade.save(
      content: gpx,
      filename: fileName,
      mimeType: 'application/gpx+xml',
    );
  }

  /// Public (visibleForTesting) so the pure string-generation logic is
  /// directly unit-testable without going through FileSystemFacade's
  /// platform channels (share sheet / directory picker).
  @visibleForTesting
  String generateGpx(ActivityEntity activity) {
    // Active segments only: paused stretches and signalLost gap-brackets are
    // deliberately excluded. Consecutive active segments separated by a gap
    // therefore land in separate <trkseg>/<trk> blocks — exactly the GPX 1.1
    // semantics for lost reception ("To represent a single GPS track where
    // GPS reception was lost ... start a new Track Segment").
    final activeSegments = activity.activeSegments;

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<gpx version="1.1" creator="Furtive" xmlns="http://www.topografix.com/GPX/1/1">',
    );
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${_escapeXml(activity.name)}</name>');
    buffer.writeln('    <desc>${_escapeXml(activity.description)}</desc>');
    buffer.writeln(
      '    <time>${activity.startedAt.toUtc().toIso8601String()}</time>',
    );
    buffer.writeln('  </metadata>');

    for (final segment in activeSegments) {
      buffer.writeln('  <trk>');
      buffer.writeln('    <trkseg>');

      for (final point in segment.points) {
        buffer.writeln(
          '      <trkpt lat="${_decimal(point.position.latitude, 7)}" '
          'lon="${_decimal(point.position.longitude, 7)}">',
        );
        buffer.writeln(
          '        <ele>${_decimal(point.position.elevation, 2)}</ele>',
        );
        buffer.writeln(
          '        <time>${point.time.toUtc().toIso8601String()}</time>',
        );
        buffer.writeln('      </trkpt>');
      }

      buffer.writeln('    </trkseg>');
      buffer.writeln('  </trk>');
    }

    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  /// Whitelist filename chars so a user-supplied activity name can't escape
  /// the documents directory (`..`) or use platform-reserved chars (`/`,
  /// `\`, null, control bytes). Falls back to a default if the name has no
  /// usable chars. Truncated to a conservative length — a very long
  /// activity name would otherwise risk ENAMETOOLONG on some filesystems.
  String _sanitizeForFilename(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    final limited = trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
    return limited.isEmpty ? 'activity' : limited;
  }

  /// Fixed-point decimal formatting for GPX numeric fields. `double.toString`
  /// switches to scientific notation below 1e-6 (e.g. a coordinate within
  /// ~1cm of the equator/prime meridian, or a near-zero smoothed elevation),
  /// which is not valid for the GPX/xsd:decimal `lat`/`lon`/`<ele>` fields.
  String _decimal(double value, int fractionDigits) =>
      value.toStringAsFixed(fractionDigits);

  /// Escapes XML predefined entities AND strips C0 control characters
  /// (U+0000-U+001F other than tab/LF/CR) — these are illegal in XML 1.0
  /// even when entity-escaped, and can appear in `name`/`desc` when the
  /// activity was created from an imported GPX file whose metadata wasn't
  /// itself sanitised.
  String _escapeXml(String text) {
    final withoutControlChars = text.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
      '',
    );
    return withoutControlChars
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
