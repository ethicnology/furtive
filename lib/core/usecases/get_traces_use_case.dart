import 'package:furtive/core/entities/trace_entity.dart';
import 'package:furtive/core/repositories/trace_repository.dart';

class GetTracesUseCase {
  final repository = TraceRepository();

  GetTracesUseCase();

  Future<List<TraceEntity>> call(
    double left,
    double bottom,
    double right,
    double top,
    int page,
  ) async {
    // Note: traces are rendered directly from this result (held in MapState);
    // they are deliberately NOT persisted. The DB store path had no reader and
    // re-inserted overlapping OSM traces on every pan, growing the tables
    // without bound and retaining third-party trace data on disk — at odds
    // with the app's privacy stance.
    return await repository.fetch(left, bottom, right, top, page);
  }
}
