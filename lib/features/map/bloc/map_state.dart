import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';

part 'map_state.mapper.dart';

/// Map presentation state only. Everything about the in-progress recording
/// (activity, elapsed time, pause, tracking gap) lives in RecordingState.
@MappableClass()
class MapState with MapStateMappable {
  const MapState({
    this.styleUrl,
    this.userLocation,
    this.error,
    this.loadingStatus,
    this.isFollowingUser = false,
    this.selectedActivityType = ActivityTypeEntity.walk,
    this.recordingDetail = RecordingDetailEntity.balanced,
    this.mapControlsOnLeft = false,
    this.deviceHeading,
  });

  /// Resolved basemap style URL, or null for a tileless map (no PROTOMAPS_KEY
  /// compiled in, or the user opted out of tile fetches). A URL rather than a
  /// parsed style because MapLibre Native fetches and parses it itself.
  final String? styleUrl;
  final PositionEntity? userLocation;
  final AppError? error;
  final LoadingStatus? loadingStatus;

  /// Whether the camera follows the user's position.
  final bool isFollowingUser;

  /// What the next recording will be started as. Seeded from the last
  /// recorded type and changed from the record screen, so the common case
  /// (doing the same thing as last time) costs no interaction at all.
  final ActivityTypeEntity selectedActivityType;

  /// Sampling density preference, applied on top of the activity's profile.
  final RecordingDetailEntity recordingDetail;

  /// Whether the floating map controls sit on the left. Presentation only.
  final bool mapControlsOnLeft;

  /// Which way the device is pointing, degrees clockwise from true north, or
  /// null when no compass is available. Deliberately not the same thing as
  /// `userLocation.heading`, which is the direction of travel.
  final double? deviceHeading;
}
