import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:furtive/core/models/trace_model.dart';

class TraceRemoteDataSource {
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
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final document = XmlDocument.parse(response.body);
      final tracks = document.findAllElements('trk');
      final traces = tracks.map(TraceModel.fromGpx).toList();
      return traces;
    } else {
      throw Exception('Failed to load traces: ${response.statusCode}');
    }
  }
}
