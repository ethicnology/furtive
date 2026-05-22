import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/facades/file_system_facade.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

class ExportActivityToGpxUseCase {
  final activityRepository = ActivityRepository();

  ExportActivityToGpxUseCase();

  Future<void> call(String activityId) async {
    final activity = await activityRepository.fetchSingle(activityId);
    final gpx = _generateGpx(activity);

    final fileName =
        '${_sanitizeForFilename(activity.name)}-${activity.startedAt.millisecondsSinceEpoch}.gpx';

    await FileSystemFacade.save(
      content: gpx,
      filename: fileName,
      mimeType: 'application/gpx+xml',
    );
  }

  String _generateGpx(ActivityEntity activity) {
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
          '      <trkpt lat="${point.position.latitude}" lon="${point.position.longitude}">',
        );
        buffer.writeln('        <ele>${point.position.elevation}</ele>');
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
  /// usable chars.
  String _sanitizeForFilename(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    return trimmed.isEmpty ? 'activity' : trimmed;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
