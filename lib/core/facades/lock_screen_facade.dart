import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toggles whether MainActivity may be shown on top of the Android lock
/// screen (`Activity.setShowWhenLocked`, native side in MainActivity.kt).
///
/// The manifest's `android:showWhenLocked="true"` sets the default so a
/// cold start behaves as before this preference existed; this facade lets
/// the user turn that off (live position visible to anyone glancing at a
/// locked phone) — or back on — without a rebuild. See docs/AUDIT-2026-07.md §5.
///
/// No-op on every non-Android platform and on Android below API 27, where
/// the attribute can't be changed at runtime (never throws either way).
class LockScreenFacade {
  static const _channel = MethodChannel('app.furtive/lock_screen');

  Future<void> setShowWhenLocked(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setShowWhenLocked', enabled);
    } catch (_) {
      // Best-effort — a failed toggle must not block app startup/prefs save.
    }
  }
}
