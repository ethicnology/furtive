import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:furtive/core/models/trace_model.dart';

class TraceRemoteDataSource {
  /// Stop waiting after this; the OSM endpoint occasionally hangs for a
  /// busy bbox and without a timeout the MapBloc handler would never
  /// complete (the user sees "loading traces…" forever).
  static const _requestTimeout = Duration(seconds: 30);

  /// Defensive cap on the response body. Symmetric with the GPX-import
  /// limit. A 10 MB GPX trace page is already pathological; anything
  /// bigger is almost certainly a misbehaving response we'd rather refuse
  /// than try to parse into memory.
  static const _maxResponseBytes = 10 * 1024 * 1024;

  Future<List<TraceModel>> getPublicTraces(
    double left,
    double bottom,
    double right,
    double top,
    int page,
  ) async {
    final uri = Uri.parse(
      'https://api.openstreetmap.org/api/0.6/trackpoints?bbox=$left,$bottom,$right,$top&page=$page',
    );
    final response = await http.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to load traces: ${response.statusCode}');
    }
    if (response.bodyBytes.length > _maxResponseBytes) {
      throw Exception(
        'OSM trace response too large (${response.bodyBytes.length} B)',
      );
    }
    final document = XmlDocument.parse(response.body);
    final traces = <TraceModel>[];
    for (final trk in document.findAllElements('trk')) {
      final segments = trk.findAllElements('trkseg').toList();
      if (segments.isEmpty) {
        // No segment wrapper — treat the whole track as one trace.
        traces.add(TraceModel.fromGpx(trk));
      } else {
        // One trace per <trkseg>: each segment is a continuous span, so the
        // map doesn't draw a straight line across reception gaps.
        for (final seg in segments) {
          traces.add(TraceModel.fromGpxSegment(trk, seg));
        }
      }
    }
    return traces;
  }
}
