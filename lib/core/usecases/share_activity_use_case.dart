import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/widgets/share_card.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Render ShareCard offscreen via an Overlay entry, capture as PNG via
/// RepaintBoundary.toImage, write to the temp dir, and invoke the system
/// share sheet through share_plus' modern instance API.
///
/// The Overlay-entry pattern keeps the ShareCard out of the visible tree
/// while still attached to the Overlay's render pipeline — the boundary
/// gets a real frame, so the captured image isn't black. We position the
/// card far below the viewport (top: 100000) instead of using `Visibility`
/// or `Offstage`, both of which would skip painting and yield a blank
/// capture.
class ShareActivityUseCase {
  ShareActivityUseCase();

  /// Prefix of every share-card PNG this use case ever writes to the temp
  /// dir — used both to build today's filename and to find yesterday's
  /// leftovers to purge. Deliberately distinct from
  /// FileSystemFacade's `furtive-export-` GPX prefix (rather than the
  /// previous bare `furtive-`, which IS a prefix of `furtive-export-`): that
  /// overlap meant sharing a card right after exporting a GPX purged the
  /// just-exported GPX out from under a share target that might still be
  /// asynchronously reading it (same iOS race this deferred-delete pattern
  /// exists to avoid in the first place). See docs/REVIEW-2026-07-FULL-APP.md M2.
  static const _filePrefix = 'furtive-share-';

  Future<void> call(BuildContext context, ActivityEntity activity) async {
    // Read everything needed from context before the first await below —
    // using a BuildContext across an async gap risks reading from a
    // since-disposed widget tree.
    final overlayState = Overlay.of(context, rootOverlay: true);
    final l10n = AppLocalizations.of(context);
    final textDirection = Directionality.of(context);
    final boundaryKey = GlobalKey();

    // Best-effort purge of PNGs from *previous* calls (see the "deliberately
    // NOT deleting" note below for why the just-shared file itself is never
    // touched here or immediately after sharing). By the time this runs
    // again, any earlier share has long since completed — the OS's own temp-
    // dir reaping is not on any particular schedule, so without this a
    // frequent sharer accumulates one ~1 MB PNG per share indefinitely.
    // Never blocks/fails the share on an error.
    try {
      final tmpDir = await getTemporaryDirectory();
      final entries = await tmpDir.list().toList();
      for (final entry in entries) {
        if (entry is File && p.basename(entry.path).startsWith(_filePrefix)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Non-fatal — worst case a stale PNG lingers until the next share.
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        // Pinning width/height is critical: without them the Positioned
        // child inherits the Overlay Stack's screen-size constraints, and
        // SizedBox(1080×1350) gets clamped to screenW×screenH on any
        // phone smaller than the card. The capture would then be at the
        // device's logical size, not the design size we want.
        top: 100000,
        left: 0,
        width: ShareCard.width,
        height: ShareCard.height,
        child: RepaintBoundary(
          key: boundaryKey,
          child: Directionality(
            textDirection: textDirection,
            child: ShareCard(activity: activity),
          ),
        ),
      ),
    );

    overlayState.insert(entry);

    try {
      // Two end-of-frame waits: one to flush the just-inserted overlay
      // entry's first build, a second to ensure the RepaintBoundary's
      // layer has actually painted (otherwise toImage on the first frame
      // can return a blank image — observed pre-existing issue
      // flutter/flutter#75316).
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const AppError('Share card not mounted');
      }
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }

      // pixelRatio 2.0 gives 2160x2700 PNG — sharp on retina, ~1MB file.
      // Higher ratios bloat the file with no visual gain on mobile.
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw const AppError('Failed to encode share image');
      }

      final tmpDir = await getTemporaryDirectory();
      final fileName =
          '$_filePrefix${activity.startedAt.millisecondsSinceEpoch}.png';
      final file = File(p.join(tmpDir.path, fileName));
      await file.writeAsBytes(byteData.buffer.asUint8List());

      // Modern API — Share.shareXFiles is deprecated as of share_plus v11.
      final summary = l10n.shareSummary(
        activity.activeDistanceInKm.fmt2,
        activity.activeDuration.toHHMMSS(),
      );
      await SharePlus.instance.share(
        ShareParams(text: summary, files: [XFile(file.path)]),
      );

      // Deliberately NOT deleting the file here. On iOS the share sheet's
      // copy of the file is async and an eager delete can race the
      // share-target reading it. It's cleaned up at the start of the next
      // call instead (see above) — not relying solely on the OS's own,
      // unscheduled temp-dir reaping to keep old activity-shape PNGs from
      // accumulating on disk. See docs/AUDIT-2026-07.md §5.
    } finally {
      entry.remove();
    }
  }
}
