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

  final eleStr = point.findElements('ele').firstOrNull?.innerText;
  final eleRaw = eleStr != null ? double.tryParse(eleStr) : null;
  final elevation = (eleRaw != null && eleRaw.isFinite) ? eleRaw : 0.0;

  final timeStr = point.findElements('time').firstOrNull?.innerText;
  final time = timeStr != null ? DateTime.tryParse(timeStr) : null;

  return GpxPoint(
    latitude: lat,
    longitude: lon,
    elevation: elevation,
    time: time,
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

  for (final trk in root.findAllElements('trk')) {
    for (final seg in trk.findAllElements('trkseg')) {
      collect(seg.findAllElements('trkpt'));
    }
  }
  for (final rte in root.findAllElements('rte')) {
    collect(rte.findAllElements('rtept'));
  }
  if (groups.isEmpty) {
    collect([
      ...root.findAllElements('trkpt'),
      ...root.findAllElements('rtept'),
    ]);
  }
  return groups;
}
