import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import '../repositories/map_repository.dart';

class GetMapConfigUseCase {
  final mapRepository = MapRepository();
  final preferencesRepository = PreferencesRepository();

  GetMapConfigUseCase();

  Future<Style?> call() async {
    final preferences = await preferencesRepository.fetch();
    return await mapRepository.getMapConfig(preferences);
  }
}
