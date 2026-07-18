import 'package:xml/xml.dart';

/// A single trkpt parsed and validated for finiteness + coordinate range.
class GpxPoint {
  final double latitude;
  final double longitude;
  final double elevation;
  final DateTime? time;

  const GpxPoint({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.time,
  });
}

/// Parse a `<trkpt>` element and return [GpxPoint] if it carries valid data,
/// or null if the lat/lon are missing, non-finite, or out of WGS84 range.
/// Used by both the OSM trace renderer (lib/core/models/trace_model.dart) and
/// the GPX activity importer — keeping a single validator avoids the bug
/// class where one entry point silently lets junk in and the other crashes
/// downstream LatLng construction.
GpxPoint? parseTrkpt(XmlElement point) {
  final lat = double.tryParse(point.getAttribute('lat') ?? '');
  final lon = double.tryParse(point.getAttribute('lon') ?? '');
  if (lat == null || !lat.isFinite || lat < -90 || lat > 90) return null;
  if (lon == null || !lon.isFinite || lon < -180 || lon > 180) return null;

  final eleStr = point
      .findElements('ele', namespaceUri: '*')
      .firstOrNull
      ?.innerText;
  final eleRaw = eleStr != null ? double.tryParse(eleStr) : null;
  final elevation = (eleRaw != null && eleRaw.isFinite) ? eleRaw : 0.0;

  final timeStr = point
      .findElements('time', namespaceUri: '*')
      .firstOrNull
      ?.innerText;
  final time = timeStr != null ? _parseGpxTime(timeStr) : null;

  return GpxPoint(
    latitude: lat,
    longitude: lon,
    elevation: elevation,
    time: time,
  );
}

/// Parses a GPX `<time>` value, treating an offset-less timestamp as UTC —
/// per the GPX schema (built on xsd:dateTime), a time with no explicit zone
/// is UTC. `DateTime.tryParse` instead assumes such a string is in the
/// device's LOCAL zone (`isUtc == false`), which would make the very same
/// GPX file resolve to a different absolute instant depending on where it's
/// imported. A string WITH an explicit zone/offset ("Z" or "+02:00") is
/// parsed correctly as-is (`isUtc == true` in both cases in Dart) and
/// returned unchanged.
DateTime? _parseGpxTime(String s) {
  final parsed = DateTime.tryParse(s);
  if (parsed == null || parsed.isUtc) return parsed;
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

/// Group a GPX document's points by track segment. Each `<trkseg>` (and each
/// separate `<trk>` / `<rte>`) becomes its own group, because in GPX a new
/// segment marks a discontinuity — GPS reception lost or the receiver turned
/// off — so callers must not connect the last point of one group to the first
/// of the next. Empty groups (no valid points) are dropped. Falls back to a
/// single group of any stray `<trkpt>`/`<rtept>` for malformed files that
/// don't wrap points in a segment/route.
List<List<GpxPoint>> parseGpxSegments(XmlElement root) {
  final groups = <List<GpxPoint>>[];
  void collect(Iterable<XmlElement> elements) {
    final parsed = elements.map(parseTrkpt).whereType<GpxPoint>().toList();
    if (parsed.isNotEmpty) groups.add(parsed);
  }

  // `namespaceUri: '*'` matches by LOCAL name regardless of any namespace
  // prefix (e.g. a file using `<x:trkpt>`) — without it, findAllElements
  // matches the fully-qualified name, so a namespaced file would silently
  // find zero points and fall through to GpxNoPointsError.
  for (final trk in root.findAllElements('trk', namespaceUri: '*')) {
    final segments = trk.findAllElements('trkseg', namespaceUri: '*').toList();
    if (segments.isNotEmpty) {
      for (final seg in segments) {
        collect(seg.findAllElements('trkpt', namespaceUri: '*'));
      }
    } else {
      // Malformed-but-real-world: a <trk> with <trkpt> children directly,
      // not wrapped in a <trkseg>. Previously silently dropped whenever
      // *any other* <trk> in the same file did use <trkseg> (the fallback
      // below only fires when groups is empty overall).
      collect(trk.findAllElements('trkpt', namespaceUri: '*'));
    }
  }
  for (final rte in root.findAllElements('rte', namespaceUri: '*')) {
    collect(rte.findAllElements('rtept', namespaceUri: '*'));
  }
  if (groups.isEmpty) {
    collect([
      ...root.findAllElements('trkpt', namespaceUri: '*'),
      ...root.findAllElements('rtept', namespaceUri: '*'),
    ]);
  }
  return groups;
}
