import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';

/// The "you are here" marker, drawn by us rather than by MapLibre's native
/// LocationComponent.
///
/// The native puck was fed by its own location engine — a second
/// `PRIORITY_HIGH_ACCURACY` request at 750 ms which additionally subscribed to
/// Android's `network` provider and bypassed [GpsQualityFilter] entirely. It
/// therefore drew a position the rest of the app had never seen and had
/// already rejected: the camera centred on the filtered fix while the dot
/// wandered off on a wifi-derived one, sometimes hundreds of metres away.
///
/// This one is a plain Flutter widget placed by `WidgetLayer`, fed from the
/// same `MapState.userLocation` that the Follow button uses. The two cannot
/// disagree, because there is only one position left.
///
/// Two distinct bearings can be shown, and conflating them is the mistake this
/// widget exists to avoid:
///  * [deviceHeading] — which way the phone is *pointing*, from the compass.
///    Drawn as a cone spreading from the dot, the convention every mapping app
///    uses, because it says "roughly this way" rather than claiming precision
///    the magnetometer does not have.
///  * [headingDegrees] — the direction of *travel*, from GPS. Drawn as a
///    chevron, and only once actually moving: a course derived from no
///    movement is meaningless.
///
/// A phone can point east while its owner walks north, so both can be true at
/// once and neither substitutes for the other.
class UserLocationPuck extends StatelessWidget {
  const UserLocationPuck({super.key, this.headingDegrees, this.deviceHeading});

  /// Course over ground in degrees clockwise from true north, or null to draw
  /// no chevron. Callers should pass `PositionEntity.trustedHeading`, which
  /// already refuses a bearing reported while standing still.
  final double? headingDegrees;

  /// Device orientation in degrees clockwise from true north, or null when no
  /// compass is available.
  final double? deviceHeading;

  /// Size of the marker box. `Marker.size` must be given the same value or the
  /// widget is positioned against the wrong centre. Sized for the cone, which
  /// is the widest thing drawn here.
  static const Size size = Size.square(72);

  static const double _dotDiameter = 18;
  static const double _ringWidth = 3;
  static const double _coneRadius = 34;
  static const double _coneSpreadDegrees = 60;

  @override
  Widget build(BuildContext context) {
    final travel = headingDegrees;
    final facing = deviceHeading;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (facing != null)
            CustomPaint(
              size: size,
              painter: _HeadingConePainter(
                headingDegrees: facing,
                radius: _coneRadius,
                spreadDegrees: _coneSpreadDegrees,
              ),
            ),
          if (travel == null)
            _buildDot()
          else
            Transform.rotate(
              angle: travel * math.pi / 180,
              child: _buildChevron(),
            ),
        ],
      ),
    );
  }

  Widget _buildDot() => Container(
    width: _dotDiameter,
    height: _dotDiameter,
    decoration: BoxDecoration(
      color: kLocationPuck,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: _ringWidth),
      // A white ring alone disappears over a pale basemap; the shadow keeps
      // the puck readable on snow, sand and the light map themes.
      boxShadow: const [
        BoxShadow(color: Color(0x59000000), blurRadius: 4, spreadRadius: 1),
      ],
    ),
  );

  /// A white glyph one size up sitting behind the coloured one, which outlines
  /// the chevron without needing a custom painter or a shipped asset.
  Widget _buildChevron() => const Stack(
    alignment: Alignment.center,
    children: [
      Icon(Icons.navigation_rounded, size: 30, color: Colors.white),
      Icon(Icons.navigation_rounded, size: 22, color: kLocationPuck),
    ],
  );
}

/// The "facing this way" cone: a wedge fading out from the dot.
///
/// A wedge rather than an arrow on purpose. A compass corrected for
/// declination is still only good to a handful of degrees, and worse near
/// metal or a magnetic phone mount; a crisp arrow would assert a precision the
/// sensor does not have, while a spreading cone reads as an approximation.
class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter({
    required this.headingDegrees,
    required this.radius,
    required this.spreadDegrees,
  });

  final double headingDegrees;
  final double radius;
  final double spreadDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    // Canvas angles run clockwise from the +x axis (east); a bearing runs
    // clockwise from north, hence the quarter-turn.
    final startRadians =
        (headingDegrees - 90 - spreadDegrees / 2) * math.pi / 180;
    final sweepRadians = spreadDegrees * math.pi / 180;

    final wedge = Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(
        Rect.fromCircle(center: centre, radius: radius),
        startRadians,
        sweepRadians,
        false,
      )
      ..close();

    canvas.drawPath(
      wedge,
      Paint()
        ..shader = RadialGradient(
          colors: [
            kLocationPuck.withValues(alpha: 0.45),
            kLocationPuck.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_HeadingConePainter oldDelegate) =>
      oldDelegate.headingDegrees != headingDegrees ||
      oldDelegate.radius != radius ||
      oldDelegate.spreadDegrees != spreadDegrees;
}
