import 'package:furtive/core/entities/position_entity.dart';

sealed class MapEvent {
  const MapEvent();
}

/// Opens the position stream, resumes any ongoing recording, fetches a one-shot
/// fix and loads the tile style. Idempotent — safe to re-fire (MapPage.initState,
/// the onboarding finish and a preferences change all dispatch it).
class InitMap extends MapEvent {
  const InitMap();
}

/// Fired when the app returns to the foreground. Re-validates the position
/// stream so tracking resumes at once if the OS suspended it in deep background
/// (Doze) without delivering onDone.
class EnsureTracking extends MapEvent {
  const EnsureTracking();
}

class UpdateUserLocation extends MapEvent {
  const UpdateUserLocation({required this.position});

  final PositionEntity position;
}

class ClearError extends MapEvent {
  const ClearError();
}

class ToggleFollowUser extends MapEvent {
  const ToggleFollowUser();
}

class StopFollowingUser extends MapEvent {
  const StopFollowingUser();
}
