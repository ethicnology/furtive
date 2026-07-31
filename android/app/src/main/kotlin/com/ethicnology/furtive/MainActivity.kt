package com.ethicnology.furtive

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Dart reads this once at startup (see lib/core/facades/process_exit_facade.dart)
// to find out why the previous process instance disappeared. Purely
// diagnostic: geolocator's foreground service dies with the app process (it
// has no independent survival mechanism — see AUDIT-2026-07.md §1/§2), so
// this cannot bring tracking back on its own. What it *does* do is tell
// apart, in the user-shareable log file, an OS/OEM battery-manager kill
// (LOW_MEMORY, SIGNALED, FREEZER) from the user deliberately stopping the
// app (USER_REQUESTED — Android 13+'s foreground-service Task Manager) —
// turning "my recording died for no reason" bug reports into something
// diagnosable instead of a shrug. See AUDIT-2026-07.md §1.2 [P2-e].
private const val DIAGNOSTICS_CHANNEL = "app.furtive/diagnostics"

// Dart calls this to toggle whether MainActivity may show on top of the lock
// screen (see lib/core/facades/lock_screen_facade.dart). The manifest's
// android:showWhenLocked="true" sets the default for a cold start; this lets
// a user who finds the live map/position visible on their lock screen
// undesirable turn it off without a rebuild, and re-enable it, at runtime.
// Purely a window-visibility flag — unrelated to the "activity killed on
// unlock" bug (see AUDIT-2026-07.md §1: that was a resume-ordering bug, not
// this attribute) and to process survival (§2).
private const val LOCK_SCREEN_CHANNEL = "app.furtive/lock_screen"

// Device heading (which way the phone points), streamed to Dart so the map's
// location puck can face the right way. An EventChannel rather than a
// MethodChannel because this is a continuous sensor feed, and the companion
// MethodChannel below carries the position the magnetic-to-true-north
// correction needs. See CompassStreamHandler for why this is not a package.
private const val COMPASS_EVENT_CHANNEL = "app.furtive/compass"
private const val COMPASS_METHOD_CHANNEL = "app.furtive/compass_control"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val compass = CompassStreamHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_EVENT_CHANNEL)
            .setStreamHandler(compass)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updatePosition" -> {
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        val altitude = call.argument<Double>("altitude") ?: 0.0
                        if (latitude == null || longitude == null) {
                            result.error("bad_args", "expected latitude/longitude", null)
                        } else {
                            compass.updatePosition(latitude, longitude, altitude)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DIAGNOSTICS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lastExitReason" -> result.success(lastExitReason())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCK_SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setShowWhenLocked" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("bad_args", "expected a bool", null)
                        } else {
                            setShowWhenLockedCompat(enabled)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Activity.setShowWhenLocked(Boolean) is API 27+. The deprecated window
    // flag remains the only runtime implementation on API 24-26; leaving those
    // versions as a no-op would make the privacy toggle lie while the manifest's
    // showWhenLocked=true continued exposing the map.
    @Suppress("DEPRECATION")
    private fun setShowWhenLockedCompat(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
        } else if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

    // The most recently recorded reason this app's process went away, or
    // null if unavailable (API < 30, or the system hasn't recorded one yet
    // — e.g. the very first launch after install). Returned as a plain map
    // since that's what crosses a platform channel; see
    // ProcessExitFacade.lastExitReason on the Dart side for the typed view.
    private fun lastExitReason(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val activityManager = getSystemService(ActivityManager::class.java) ?: return null
        val infos = activityManager.getHistoricalProcessExitReasons(
            /* packageName = */ null,
            /* pid = */ 0,
            /* maxNum = */ 1,
        )
        val info = infos.firstOrNull() ?: return null
        return mapOf(
            "reason" to info.reason,
            "description" to reasonName(info.reason),
            "timestampMillis" to info.timestamp,
            "importance" to info.importance,
        )
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_FREEZER -> "FREEZER"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        else -> "UNRECOGNISED($reason)"
    }
}
