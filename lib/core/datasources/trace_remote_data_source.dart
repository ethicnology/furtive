import 'dart:convert';
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
    final body = await _getCapped(uri);
    final document = XmlDocument.parse(body);
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

  /// GET [uri], enforcing [_maxResponseBytes] while the body streams in so the
  /// cap actually bounds peak memory. A plain http.get() buffers the whole
  /// response first, which defeats the point of the cap for a hostile/huge
  /// response. Aborts the connection as soon as the running total exceeds the
  /// cap. Returns the decoded UTF-8 body.
  ///
  /// Network-layer failures (timeout, connection reset, DNS, ...) are
  /// re-thrown without their original message: package:http/dart:io
  /// exceptions (ClientException, SocketException, TimeoutException, ...)
  /// interpolate the request URI into toString() — which here carries [uri]'s
  /// bbox query param, i.e. the user's map viewport. That would otherwise
  /// reach disk verbatim via MapBloc's `logs.severe('$FetchTraces: $e')`.
  /// The explicit `throw Exception(...)` calls below are our own bbox-free
  /// messages and are left as-is.
  Future<String> _getCapped(Uri uri) async {
    final client = http.Client();
    try {
      http.StreamedResponse response;
      try {
        final request = http.Request('GET', uri);
        response = await client.send(request).timeout(_requestTimeout);
      } catch (e) {
        throw Exception('Failed to reach the OSM trace endpoint (${e.runtimeType})');
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to load traces: ${response.statusCode}');
      }

      // If the server advertises an oversized body, reject before downloading.
      final declared = response.contentLength;
      if (declared != null && declared > _maxResponseBytes) {
        throw Exception('OSM trace response too large ($declared B)');
      }

      final chunks = <List<int>>[];
      var total = 0;
      try {
        await for (final chunk in response.stream.timeout(_requestTimeout)) {
          total += chunk.length;
          if (total > _maxResponseBytes) {
            throw Exception(
              'OSM trace response too large (> $_maxResponseBytes B)',
            );
          }
          chunks.add(chunk);
        }
      } on Exception catch (e) {
        // Re-throw our own oversized-response Exception as-is; wrap
        // anything else (stream timeout, connection drop) bbox-free.
        if (e.toString().contains('OSM trace response too large')) rethrow;
        throw Exception('Failed to read the OSM trace response (${e.runtimeType})');
      }
      return utf8.decode(chunks.expand((c) => c).toList());
    } finally {
      client.close();
    }
  }
}
