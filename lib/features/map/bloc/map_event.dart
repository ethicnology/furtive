import 'package:latlong2/latlong.dart';
import 'package:furtive/core/entities/position_entity.dart';

sealed class MapEvent {
  const MapEvent();
}

class InitMap extends MapEvent {
  const InitMap();
}

/// Fired when the app returns to the foreground. Re-validates the position
/// stream so a recording resumes immediately if the OS suspended the stream
/// in deep background (Doze) without delivering onDone.
class EnsureTracking extends MapEvent {
  const EnsureTracking();
}

class StartActivity extends MapEvent {
  const StartActivity();
}

class CeaseActivity extends MapEvent {
  const CeaseActivity();
}

class ScoreActivity extends MapEvent {
  final PositionEntity position;
  ScoreActivity({required this.position});
}

class UpdateUserLocation extends MapEvent {
  final PositionEntity position;
  UpdateUserLocation({required this.position});
}

class PauseActivity extends MapEvent {
  const PauseActivity();
}

class FetchTraces extends MapEvent {
  const FetchTraces({required this.center});

  final LatLng center;
}

class ClearError extends MapEvent {
  const ClearError();
}

/// Dismisses the "tracking gap" banner (see MapState.trackingGap) after the
/// user has acknowledged that a segment of the trace was lost while the app
/// was suspended in the background.
class ClearTrackingGap extends MapEvent {
  const ClearTrackingGap();
}

class UpdateElapsedTime extends MapEvent {
  const UpdateElapsedTime();
}

class ToggleFollowUser extends MapEvent {
  const ToggleFollowUser();
}

class StopFollowingUser extends MapEvent {
  const StopFollowingUser();
}
