import 'package:furtive/core/entities/trace_entity.dart';
import 'package:furtive/core/utils/gpx.dart';
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

  static TraceModel fromGpx(XmlElement track) =>
      _build(track, track.findAllElements('trkpt'));

  /// Build a trace from a single `<trkseg>`, reading metadata from its parent
  /// `<trk>`. Callers iterate segments so a track's discontinuities aren't
  /// joined into one bridged polyline on the map.
  static TraceModel fromGpxSegment(XmlElement track, XmlElement segment) =>
      _build(track, segment.findAllElements('trkpt'));

  static TraceModel _build(XmlElement track, Iterable<XmlElement> trkpts) {
    final name = track.findElements('name').firstOrNull?.innerText ?? 'Unknown';
    final description = track.findElements('desc').firstOrNull?.innerText ?? '';
    final url = track.findElements('url').firstOrNull?.innerText ?? '';
    final points = <TracePointModel>[];
    for (final point in trkpts) {
      final parsed = parseTrkpt(point);
      if (parsed == null) continue;
      points.add(
        TracePointModel(
          latitude: parsed.latitude,
          longitude: parsed.longitude,
          elevation: parsed.elevation,
          time: parsed.time,
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
}
