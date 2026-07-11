import Flutter
import UIKit

// Dart calls this once at startup (see lib/core/facades/backup_exclusion_facade.dart)
// to exclude the SQLite DB and the log file from the iCloud/iTunes backup —
// matching the Android side, which already opts out entirely via
// allowBackup=false + backup_rules.xml / data_extraction_rules.xml. Without
// this, Documents (where both files live) is backed up by default on iOS,
// so a "privacy-first, no cloud" tracker would otherwise still ship the full
// GPS history to iCloud. See AUDIT-2026-07.md §5.
private let backupExclusionChannel = "app.furtive/backup_exclusion"

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: backupExclusionChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "excludeFromBackup":
          guard let paths = call.arguments as? [String] else {
            result(FlutterError(code: "bad_args", message: "expected a list of paths", details: nil))
            return
          }
          result(AppDelegate.excludeFromBackup(paths))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Sets NSURLIsExcludedFromBackupKey on every path that exists. Missing
  // paths are skipped, not an error — e.g. a fresh install has no sqlite
  // -wal/-shm sidecar files yet. Returns the paths it actually flagged, for
  // diagnostics on the Dart side; never throws.
  private static func excludeFromBackup(_ paths: [String]) -> [String] {
    var flagged: [String] = []
    for path in paths {
      guard FileManager.default.fileExists(atPath: path) else { continue }
      var url = URL(fileURLWithPath: path)
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      do {
        try url.setResourceValues(resourceValues)
        flagged.append(path)
      } catch {
        // Best-effort — a failure here must not crash app startup.
      }
    }
    return flagged
  }
}
