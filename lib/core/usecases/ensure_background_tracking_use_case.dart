import 'package:furtive/core/repositories/location_repository.dart';

/// Best-effort request for the battery-optimisation (Doze / App Standby)
/// exemption. A continuous GPS tracker must keep its foreground service alive
/// while the phone is locked; without the exemption, aggressive OEM battery
/// managers can still kill the process mid-recording and silently drop the
/// track. Fired when a recording starts. A denial is not fatal — tracking
/// still relies on the foreground service + wake lock — so this never throws.
class EnsureBackgroundTrackingUseCase {
  final locationRepository = LocationRepository();

  EnsureBackgroundTrackingUseCase();

  /// Returns true if the exemption is granted (or the platform doesn't need
  /// one), false if the user declined. Never throws.
  Future<bool> call() async {
    try {
      if (await locationRepository.isBatteryOptimizationDisabled()) return true;
      return await locationRepository.requestDisableBatteryOptimization();
    } catch (_) {
      return false;
    }
  }
}
