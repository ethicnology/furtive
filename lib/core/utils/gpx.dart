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
