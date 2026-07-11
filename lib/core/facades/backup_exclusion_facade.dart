import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Excludes on-device files from the iOS iCloud/iTunes backup via
/// `NSURLIsExcludedFromBackupKey` (set natively in AppDelegate.swift).
///
/// Android already opts the whole app out of backups (`allowBackup="false"`
/// + `backup_rules.xml` / `data_extraction_rules.xml`); iOS has no manifest-
/// level equivalent — every file under Documents is backed up by default —
/// so without this, a "privacy-first, no cloud" tracker would still ship the
/// full SQLite GPS history and the log file to iCloud on iOS. See
/// AUDIT-2026-07.md §5.
///
/// A no-op (does nothing, never throws) on every non-iOS platform: Android
/// doesn't need it (manifest-level opt-out), and the desktop/web targets
/// don't have an OS-level backup story this matters for.
class BackupExclusionFacade {
  static const _channel = MethodChannel('app.furtive/backup_exclusion');

  /// Flags [paths] as excluded from backup. Paths that don't exist yet
  /// (e.g. sqlite -wal/-shm sidecars before the first write) are silently
  /// skipped by the native side. Best-effort: never throws, so a failure
  /// here can never block app startup.
  Future<void> excludeFromBackup(List<String> paths) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<List<Object?>>('excludeFromBackup', paths);
    } catch (_) {
      // Best-effort diagnostics-free failure — see class doc.
    }
  }
}
