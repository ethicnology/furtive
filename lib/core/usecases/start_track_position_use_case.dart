import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/repositories/location_repository.dart';

class StartTrackPositionUseCase {
  final locationRepository = LocationRepository();

  StartTrackPositionUseCase();

  Future<Stream<PositionEntity>> call({void Function()? onRawFix}) async {
    final hasPermission = await locationRepository.checkLocationPermission();
    if (!hasPermission) {
      final granted = await locationRepository.requestLocationPermission();
      if (!granted) throw AppError('Location permission not granted');
    }
    return locationRepository.getPositionStream(onRawFix: onRawFix);
  }
}
