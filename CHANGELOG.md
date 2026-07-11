# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Remediation pass following a full audit of location tracking, permissions,
GPS accuracy and privacy — see `AUDIT-2026-07.md` for the detailed findings
and rationale behind every item below.

### Added
- **Notifications permission** — optionally grant it so the "Recording
  activity" notification is actually visible in the notification drawer on
  Android 13+ (it still works without it, just less visibly).
- **GPS fix quality is now used, not discarded** — recorded points carry
  horizontal/vertical accuracy when the platform reports it. Noisy or
  teleporting fixes (multipath, urban canyon) are filtered out of the live
  trace, and elevation gain (D+) is smoothed with a noise dead-band instead
  of summing every raw altitude wiggle — recordings made before this update
  are unaffected and keep their original numbers.
- **Map tiles preference** — turn off map tile loading in Preferences for a
  functional, tileless map with zero network requests, even on a build with
  a map key configured.
- **Lock-screen visibility preference** (Android) — turn off showing the
  live map/position on top of a locked screen while recording.
- Diagnostic logging of why the app's previous process disappeared (OS/OEM
  kill vs. you stopping it) to help make sense of "my recording just
  stopped" reports.

### Changed
- Resuming an in-progress recording after the OS kills the app no longer
  depends on getting a fresh GPS fix first — a slow/cold GPS right after
  unlocking the phone could previously delay or skip the resume entirely,
  which is very likely what caused reports of an activity being
  unexpectedly "killed" after unlocking the screen.
- The one-shot "centre on me" GPS fix now times out instead of being able to
  hang indefinitely.
- `ACCESS_COARSE_LOCATION` is now requested alongside fine location, as
  Android 12+ expects — without it the precise-location permission dialog
  could silently fail to appear on some devices.

### Security & privacy
- iOS: the local database and log file are now excluded from iCloud/iTunes
  backups, matching the opt-out Android already had.
- Old shared activity-card images are cleaned up instead of accumulating in
  the app's temporary storage indefinitely.
- Hardened error logging around the (currently unused) public-traces search
  so a future re-enable can't leak a precise map viewport into the log file.

## [1.2.0] - 2026-06-06

### Added
- **Internationalization** — app interface in 26 languages, map labels in 41,
  and locale-aware date formats. Override the language in Settings or the
  first-launch wizard.
- **First-launch wizard** — pick your defaults (map theme, language) and grant
  location permissions in a single flow.
- **GPX import** — import activities from other apps (Garmin, Strava, …); both
  track points and route points are supported.
- **Share an activity** as a card with map and stats through the system share
  sheet.
- **Activity stats** — per-kilometre splits chart with a pace ⇄ speed toggle,
  and D+ elevation gain (matching the Strava/Garmin convention).
- **Five map themes** — Light, Dark, White, Grayscale, Black.
- **Update check (opt-out)** — a once-a-day check against GitHub releases that
  you can turn off in Preferences; nothing is sent when it's disabled.
- **Reproducible builds** — anyone can rebuild from source and verify the
  published APK is byte-for-byte identical.

### Changed
- Activity recording: animated location marker with pulse and accuracy circle,
  kilometre markers on the map, hold-Stop-for-3-seconds to end (no accidental
  taps), and auto-redirect to the stats screen.
- Background recording keeps running with the screen off (wake-locked
  foreground service) and resumes your in-progress activity automatically if
  the system stops the app to save battery — reopening shows the live run
  instead of a blank map.
- The keyless / FOSS build now shows a functional map (your track on a blank
  canvas) instead of failing to load when no map key is configured.
- The activities list loads faster and uses less memory, and opening an
  activity loads its full track on demand.
- Permission requests are handled in-app where possible and only send you to
  system settings when that's actually required.

### Fixed
- Recorded points are timestamped at the moment of the GPS fix, keeping pace and
  distance correct even when the OS delivers a backlog after the app resumes.
- iOS no longer auto-pauses location updates, which could silently end an
  activity when you stood still.
- GPX import no longer counts the straight-line jump between separate track
  segments as travelled distance.
- Exported GPX files are written as UTF-8, so accented and non-Latin activity
  names are preserved.
- Shared route images keep their true shape regardless of latitude.
- Per-kilometre split times account for time spent stationary, and pace is
  formatted correctly.
- In-progress activities show live stats in the list instead of zeros.

### Security & privacy
- Added the legally required OpenStreetMap / Protomaps map attribution.
- The device name is no longer written to diagnostic logs.
- Removed background storage of third-party (OSM) trace data that was never
  read back.

[1.2.0]: https://github.com/ethicnology/furtive/releases/tag/1.2.0
