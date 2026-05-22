import 'package:drift/drift.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/trace_model.dart';

class TraceLocalDataSource {
  final db = getIt.get<LocalDatabase>();

  TraceLocalDataSource();

  Future<void> store(TraceModel trace) async {
    await db.transaction(() async {
      final traceId = await db
          .into(db.traceMetadatas)
          .insert(
            TraceMetadatasCompanion(
              name: Value(trace.name),
              description: Value(trace.description),
              url: Value(trace.url),
            ),
          );

      if (trace.points.isEmpty) return;
      await db.batch((batch) {
        batch.insertAll(
          db.tracePoints,
          trace.points.map(
            (point) => TracePointsCompanion(
              latitude: Value(point.latitude),
              longitude: Value(point.longitude),
              elevation: Value(point.elevation),
              time: Value(point.time),
              traceId: Value(traceId),
            ),
          ),
        );
      });
    });
  }

  Future<List<TraceModel>> fetch() async {
    final query = db.select(db.traceMetadatas).join([
      leftOuterJoin(
        db.tracePoints,
        db.tracePoints.traceId.equalsExp(db.traceMetadatas.id),
      ),
    ]);

    final results = await query.get();
    final traceMap = <int, TraceModel>{};

    for (final row in results) {
      final trace = row.readTable(db.traceMetadatas);
      final point = row.readTableOrNull(db.tracePoints);

      traceMap.putIfAbsent(
        trace.id,
        () => TraceModel(
          name: trace.name,
          description: trace.description,
          url: trace.url,
          points: [],
        ),
      );

      if (point != null) {
        traceMap[trace.id]!.points.add(
          TracePointModel(
            latitude: point.latitude,
            longitude: point.longitude,
            elevation: point.elevation,
            time: point.time,
          ),
        );
      }
    }

    return traceMap.values.toList();
  }
}
