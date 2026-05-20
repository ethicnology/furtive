import 'package:furtive/core/entities/trace_entity.dart';
import 'package:xml/xml.dart';

class TraceModel {
  final String name;
  final String description;
  final String url;
  final List<TracePointModel> points;

  TraceModel({
    required this.name,
    required this.description,
    required this.url,
    required this.points,
  });

  static TraceEntity toEntity(TraceModel model) {
    return TraceEntity(
      name: model.name,
      description: model.description,
      url: model.url,
      points: model.points.map(TracePointModel.toEntity).toList(),
    );
  }

  static TraceModel fromEntity(TraceEntity entity) {
    return TraceModel(
      name: entity.name,
      description: entity.description,
      url: entity.url,
      points: entity.points.map(TracePointModel.fromEntity).toList(),
    );
  }

  static TraceModel fromGpx(XmlElement track) {
    final name = track.findElements('name').firstOrNull?.innerText ?? 'Unknown';
    final description = track.findElements('desc').firstOrNull?.innerText ?? '';
    final url = track.findElements('url').firstOrNull?.innerText ?? '';
    final trackPoints = track.findAllElements('trkpt');
    final points = <TracePointModel>[];
    for (final point in trackPoints) {
      final lat = double.tryParse(point.getAttribute('lat') ?? '');
      final lon = double.tryParse(point.getAttribute('lon') ?? '');
      // Reject points with missing/garbage/out-of-range coords up front so
      // bad GPX (from OSM or imports) can't poison the renderer or the DB.
      if (lat == null || !lat.isFinite || lat < -90 || lat > 90) continue;
      if (lon == null || !lon.isFinite || lon < -180 || lon > 180) continue;
      final timeStr = point.findElements('time').firstOrNull?.innerText;
      final time = timeStr != null ? DateTime.tryParse(timeStr) : null;
      final eleStr = point.findElements('ele').firstOrNull?.innerText;
      final eleRaw = eleStr != null ? double.tryParse(eleStr) : null;
      final elevation = (eleRaw != null && eleRaw.isFinite) ? eleRaw : 0.0;
      points.add(
        TracePointModel(
          latitude: lat,
          longitude: lon,
          elevation: elevation,
          time: time,
        ),
      );
    }

    return TraceModel(
      name: name,
      description: description,
      url: url,
      points: points,
    );
  }
}

class TracePointModel {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? time;

  TracePointModel({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.time,
  });

  static TracePointEntity toEntity(TracePointModel model) {
    return TracePointEntity(
      latitude: model.latitude,
      longitude: model.longitude,
      elevation: model.elevation,
      time: model.time,
    );
  }

  static TracePointModel fromEntity(TracePointEntity entity) {
    return TracePointModel(
      latitude: entity.latitude,
      longitude: entity.longitude,
      elevation: entity.elevation,
      time: entity.time,
    );
  }
}
