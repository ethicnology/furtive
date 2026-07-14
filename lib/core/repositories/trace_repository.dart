import 'package:furtive/core/datasources/trace_remote_data_source.dart';
import 'package:furtive/core/models/trace_model.dart';
import 'package:furtive/core/entities/trace_entity.dart';

// Traces are deliberately NOT persisted — see GetTracesUseCase for why (the
// local store path had no reader and grew the DB unbounded, retaining
// third-party OSM trace data at odds with the app's privacy stance). The
// local storage plumbing (TraceLocalDataSource, trace_points/trace_metadatas
// tables) has been removed entirely; see local_database.dart's v8 migration,
// which drops the tables for users upgrading from an earlier version.
class TraceRepository {
  final remoteTraces = TraceRemoteDataSource();

  TraceRepository();

  Future<List<TraceEntity>> fetch(
    double left,
    double bottom,
    double right,
    double top,
    int page,
  ) async {
    final traces = await remoteTraces.getPublicTraces(
      left,
      bottom,
      right,
      top,
      page,
    );

    return traces.map(TraceModel.toEntity).toList();
  }
}
