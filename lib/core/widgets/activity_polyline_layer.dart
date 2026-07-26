import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/theme.dart';

/// Renders an activity's track as flutter_map polylines.
///
/// Lives here rather than on [ActivityEntity] where it used to: an entity that
/// returns a `Widget` forces the domain layer to import `flutter/material.dart`,
/// `flutter_map` AND the app's design system (`AppColors`), inverting the
/// dependency direction and making the entity untestable without a Flutter
/// binding. Same API as before (`activity.toPolylineLayer()`), just as an
/// extension declared in the presentation layer.
extension ActivityPathExtension on ActivityEntity {
  Widget toPolylineLayer() {
    if (points.isEmpty) return PolylineLayer(polylines: const <Polyline>[]);
    return PolylineLayer(polylines: segments.map(_polylineFrom).toList());
  }

  Polyline _polylineFrom(ActivitySegment segment) {
    // signalLost segments render as a discreet dashed straight line: the path
    // through the gap is unknown, so a solid line (implying a recorded trace)
    // would lie — but a bare hole reads as a rendering bug. Dashes communicate
    // "we don't know what happened here".
    return Polyline(
      points: segment.points.map((p) => p.position.toLatLng()).toList(),
      color: segment.isActive
          ? AppColors.primary.background
          : AppColors.secondary.background,
      pattern: segment.isSignalLost
          ? StrokePattern.dashed(segments: const [8, 10])
          : const StrokePattern.solid(),
      strokeWidth: 4.0,
    );
  }
}
