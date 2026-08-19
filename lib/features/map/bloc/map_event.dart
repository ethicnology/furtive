import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/position_entity.dart';

sealed class MapEvent {
  const MapEvent();
}

/// Preselect the activity the next recording will use. Purely a selection —
/// the GPS stream is only reconfigured once a recording actually starts.
class SelectActivityType extends MapEvent {
  const SelectActivityType(this.activityType);

  final ActivityTypeEntity activityType;
}

/// Re-read the recording preferences (control side, sampling detail, last
/// activity) and apply them.
///
/// Separate from [InitMap] on purpose: InitMap also re-resolves the basemap
/// style and flashes the loading UI, which is the wrong price for flipping a
/// switch that only moves buttons.
class RefreshRecordingPreferences extends MapEvent {
  const RefreshRecordingPreferences();
}

/// A new device heading from the compass.
class UpdateDeviceHeading extends MapEvent {
  const UpdateDeviceHeading(this.degrees);

  final double degrees;
}

/// Point the position stream at [profile] (null = no recording in progress).
/// Dispatched by the bloc itself when the recorded activity changes, so a
/// start, a stop and a cold-start resume all take the same path.
class ApplyMovementProfile extends MapEvent {
  const ApplyMovementProfile(this.profile);

  final MovementProfileEntity? profile;
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
