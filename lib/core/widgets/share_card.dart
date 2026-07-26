import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Fixed-size shareable card rendered offscreen, captured by
/// ShareActivityUseCase via RepaintBoundary.toImage(). Deliberately does
/// NOT show the live map: vector_map_tiles + RepaintBoundary is unreliable
/// for platform-adjacent tile rendering (flutter/flutter#102866) and the
/// tiles often aren't fully painted at capture time. Drawing the polyline
/// ourselves on a CustomPainter is deterministic and stable.
///
/// Sized 1080x1350 (4:5 Instagram-portrait) so the resulting PNG is sharp
/// when downscaled by social apps. The use case mounts this inside an
/// Overlay positioned offscreen, paints one frame, captures, and disposes.
class ShareCard extends StatelessWidget {
  static const double width = 1080;
  static const double height = 1350;

  final ActivityEntity activity;
  const ShareCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeSegments = activity.activeSegments;
    // Locale-aware date+time. Older versions used the ISO substring, which
    // showed a "T" separator and the user's hour:minute:second in a fixed
    // english-friendly form.
    final localeName = Localizations.localeOf(context).toString();
    final dateLabel = DateFormat.yMMMd(
      localeName,
    ).add_Hm().format(activity.startedAt.toLocal());
    final activityName =
        (activity.name.isNotEmpty && activity.name != kDefaultActivityName)
        ? activity.name
        : dateLabel;

    // TextScaler.noScaling is load-bearing, not cosmetic. This card is a FIXED
    // 1080x1350 canvas captured straight to a PNG, but it is mounted inside the
    // app's Overlay and therefore inherits the user's system font scale. With a
    // large accessibility font the hardcoded sizes below get multiplied, the text
    // overflows its fixed boxes, and the exported image is visibly broken — for a
    // user who never sees the card on screen before sharing it. Pinning the scale
    // makes the output byte-comparable for everyone; the sizes here are design
    // constants of the canvas, not scalable UI text.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Material(
        color: Colors.black,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: AppColors.tertiary.foreground,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      color: AppColors.quaternary.background,
                      child: CustomPaint(
                        painter: _RoutePainter(
                          segments: activeSegments,
                          strokeColor: AppColors.primary.background,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  flex: 3,
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2.6,
                    children: [
                      _StatTile(
                        label: l10n.statDistance,
                        value: '${activity.activeDistanceInKm.fmt2} km',
                      ),
                      _StatTile(
                        label: l10n.statDuration,
                        value: activity.activeDuration.toHHMMSS(),
                      ),
                      _StatTile(
                        label: l10n.statPace,
                        value: '${activity.activePaceMinPerKm} /km',
                      ),
                      _StatTile(
                        label: l10n.statElevation,
                        value:
                            '+${activity.activeElevationGain.toStringAsFixed(0)} m',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    l10n.appTitle,
                    style: TextStyle(
                      color: AppColors.primary.background,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.quaternary.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.tertiary.foreground,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a route's WGS84 bounding box onto a canvas. Equirectangular with a
/// longitude correction: one degree of longitude spans cos(latitude)× the
/// ground distance of one degree of latitude, so without the factor a track
/// renders stretched horizontally away from the equator (≈1.5× too wide at
/// 48°). Longitude is scaled by cos(midLat) into latitude-equivalent degrees,
/// then the box is fit by the tighter axis so the route keeps its real-world
/// aspect ratio and is centred. (Antipodal / pole-spanning routes don't occur
/// within a single activity.)
class RouteProjection {
  final double scale;
  final double lonCorrection;
  final double minLon;
  final double maxLat;
  final double offsetX;
  final double offsetY;

  const RouteProjection({
    required this.scale,
    required this.lonCorrection,
    required this.minLon,
    required this.maxLat,
    required this.offsetX,
    required this.offsetY,
  });

  Offset project(double lat, double lon) => Offset(
    offsetX + (lon - minLon) * lonCorrection * scale,
    // Latitude grows north (up), canvas y grows down, so flip.
    offsetY + (maxLat - lat) * scale,
  );
}

RouteProjection computeRouteProjection({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  required Size size,
  double padding = 0.05,
}) {
  // 5% interior padding so the route doesn't kiss the edge.
  final pad = size.shortestSide * padding;
  final drawW = size.width - pad * 2;
  final drawH = size.height - pad * 2;

  final latRange = (maxLat - minLat).abs();
  final lonRange = (maxLon - minLon).abs();
  final midLatRad = ((minLat + maxLat) / 2) * (math.pi / 180);
  final lonCorrection = math.cos(midLatRad).abs().clamp(1e-6, 1.0);
  final safeLat = latRange < 1e-9 ? 1e-9 : latRange;
  // Longitude extent expressed in latitude-equivalent degrees.
  final lonExtent = (lonRange < 1e-9 ? 1e-9 : lonRange) * lonCorrection;
  final scale = (drawW / lonExtent) < (drawH / safeLat)
      ? drawW / lonExtent
      : drawH / safeLat;

  // Centre the scaled bbox in the canvas.
  final scaledW = lonExtent * scale;
  final scaledH = safeLat * scale;
  return RouteProjection(
    scale: scale,
    lonCorrection: lonCorrection,
    minLon: minLon,
    maxLat: maxLat,
    offsetX: pad + (drawW - scaledW) / 2,
    offsetY: pad + (drawH - scaledH) / 2,
  );
}

class _RoutePainter extends CustomPainter {
  final List<ActivitySegment> segments;
  final Color strokeColor;

  _RoutePainter({required this.segments, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Collect all valid points (segments are already filtered for finite
    // coords by ActivityEntity._segmentPoints, but the segment list itself
    // can be empty if the activity recorded nothing useful).
    final allPoints = segments.expand((s) => s.points).toList();
    if (allPoints.length < 2) {
      // Draw a placeholder dot at the centre so the card isn't an empty
      // black panel.
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        8,
        Paint()..color = strokeColor,
      );
      return;
    }

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLon = double.infinity;
    double maxLon = -double.infinity;
    for (final p in allPoints) {
      final lat = p.position.latitude;
      final lon = p.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    final proj = computeRouteProjection(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      size: size,
    );
    Offset project(double lat, double lon) => proj.project(lat, lon);

    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final segment in segments) {
      if (segment.points.length < 2) continue;
      final path = Path();
      var started = false;
      for (final p in segment.points) {
        final pt = project(p.position.latitude, p.position.longitude);
        if (!started) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Start (green) + end (red) pins.
    final first = allPoints.first.position;
    final last = allPoints.last.position;
    canvas.drawCircle(
      project(first.latitude, first.longitude),
      16,
      Paint()..color = Colors.greenAccent,
    );
    canvas.drawCircle(
      project(last.latitude, last.longitude),
      16,
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.segments != segments || old.strokeColor != strokeColor;
}
