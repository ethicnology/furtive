import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:furtive/core/errors.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Thrown when the user backs out of saving a file without completing the
/// action — the desktop directory picker was dismissed, or the mobile share
/// sheet was dismissed without picking a target. Callers should treat this
/// as a silent no-op, not a failure to surface to the user.
class FileSaveCancelled extends AppError {
  const FileSaveCancelled() : super('Cancelled by the user');
}

class FileSystemFacade {
  /// Prefix of every temp file this facade writes for the share-sheet path
  /// — used to find and purge leftovers from previous calls (see the
  /// "deliberately not deleting immediately" note below).
  static const _tempFilePrefix = 'furtive-export-';

  /// Deletes any leftover share/export temp file (GPX exports, share-card
  /// PNGs — see ShareActivityUseCase's own `furtive-share-` prefix) from the
  /// OS temp directory. Both call sites already purge their own leftovers
  /// at the START of their next invocation, so a one-time sharer/exporter
  /// otherwise keeps a location-bearing file sitting in the (sandboxed, but
  /// not user-visible) cache dir indefinitely — until they happen to
  /// share/export again. Called once at app startup so that window is
  /// bounded to "until the next launch" instead of "until the next share".
  /// Best-effort: never throws.
  static Future<void> purgeStaleTempFiles() async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final entries = await tmpDir.list().toList();
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is File &&
            (name.startsWith(_tempFilePrefix) ||
                name.startsWith('furtive-share-'))) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Non-fatal — worst case a stale file lingers until the next
      // share/export, same as before this existed.
    }
  }

  static Future<void> save({
    required String content,
    required String filename,
    String? mimeType,
  }) async {
    try {
      // Mobile (Android/iOS): file_selector's getDirectoryPath() is NOT
      // implemented by either platform plugin (verified in
      // file_selector_android 0.5.1+17 / file_selector_ios 0.5.3+2 — only
      // openFile/openFiles exist there), so this used to throw
      // UnimplementedError on every iOS export. Even where Android grants a
      // SAF directory permission, converting it to a raw dart:io path and
      // writing to it fails under scoped storage (targetSdk 36) for any
      // volume other than primary or any folder outside the well-known
      // collections — the granted permission was never actually usable.
      // The share sheet sidesteps both: the OS itself performs the write
      // (Save to Files / Drive / AirDrop / another app), through machinery
      // that already handles scoped storage correctly. See H1 in
      // docs/REVIEW-2026-07-FULL-APP.md.
      if (Platform.isAndroid || Platform.isIOS) {
        await _saveViaShareSheet(
          content: content,
          filename: filename,
          mimeType: mimeType,
        );
        return;
      }
      // Desktop: file_selector's directory picker + a real filesystem path
      // works as intended (no scoped-storage equivalent), so keep it.
      await _saveViaDirectoryPicker(content: content, filename: filename);
    } on FileSaveCancelled {
      // Not an error — the user backed out. Let it propagate as-is so
      // callers can treat it as a silent no-op instead of a failure
      // snackbar (see L-G3 in docs/REVIEW-2026-07-FULL-APP.md).
      rethrow;
    } catch (e) {
      throw AppError('Failed to save file: $e');
    }
  }

  static Future<void> _saveViaShareSheet({
    required String content,
    required String filename,
    String? mimeType,
  }) async {
    final tmpDir = await getTemporaryDirectory();

    // Best-effort purge of temp files from *previous* calls — mirrors
    // ShareActivityUseCase's identical pattern. The file just about to be
    // written below is deliberately NOT deleted after sharing: on iOS the
    // share sheet reads the file asynchronously, and an eager delete can
    // race that read (see the identical rationale in
    // share_activity_use_case.dart). Cleanup happens on the next export
    // instead of relying on the OS's unscheduled temp-dir reaping.
    try {
      final entries = await tmpDir.list().toList();
      for (final entry in entries) {
        if (entry is File &&
            p.basename(entry.path).startsWith(_tempFilePrefix)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Non-fatal — worst case a stale export lingers until the next one.
    }

    final file = File(p.join(tmpDir.path, '$_tempFilePrefix$filename'));
    // utf8.encode — NOT content.codeUnits. codeUnits yields UTF-16 units
    // truncated to bytes, mangling any char above U+00FF (accented activity
    // names, Cyrillic, CJK, emoji) in the exported GPX.
    await file.writeAsBytes(utf8.encode(content));

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: filename)],
      ),
    );
    if (result.status == ShareResultStatus.dismissed) {
      throw const FileSaveCancelled();
    }
  }

  static Future<void> _saveViaDirectoryPicker({
    required String content,
    required String filename,
  }) async {
    final path = await getDirectoryPath();
    if (path == null) throw const FileSaveCancelled();

    final XFile textFile = XFile.fromData(utf8.encode(content), name: filename);
    await textFile.saveTo(p.join(path, filename));
  }
}
