# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-07-15

Remediation pass following a full audit of location tracking, permissions,
GPS accuracy and privacy — see `AUDIT-2026-07.md` and
`REVIEW-2026-07-FULL-APP.md` for the detailed findings and rationale behind
every item below. Ships as 1.3.0 rather than 1.2.0: the Android versionCode
had stayed at 1 across every prior release (1.0.0+1, 1.1.0+1, 1.2.0+1), which
F-Droid and Android both require to strictly increase between releases.

### Added
- **GPS outage detection ("signal lost")** — walking into a building or a
  tunnel (or the OS killing the app) stops GPS fixes without pausing the
  activity; previously the whole outage silently counted as active time
  (tanking the pace) and the map drew a solid straight line through the
  building. Detected outages are now recorded as a distinct "signal lost"
  span: elapsed time stays untouched, active duration/distance/pace exclude
  the gap, the map renders a discreet dashed line across the unknown
  stretch, the outage duration (with its straight-line distance) is shown in
  the activity detail, and GPX export/import represent the gap as separate
  track segments, as the GPX 1.1 spec prescribes for lost reception. The
  detection threshold adapts to the observed fix cadence (10× the rolling
  median interval between fixes, clamped to 30 s – 6 min) rather than using
  a fixed number or a speed cutoff — see `SignalGapDetector` for the design
  rationale and the OsmAnd/OpenTracks/academic prior art it draws on.
  Recordings made before this update are unaffected.
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
- **Package name changed to `com.ethicnology.furtive`** (was
  `com.example.furtive`). This is a one-way change made ahead of the app's
  first public F-Droid submission, while the installed base is still small
  — F-Droid rejects `com.example.*` application IDs, and an app ID cannot
  be changed after publication. If you already have an earlier build
  installed, export your activities to GPX before updating and re-import
  them after (the new package is a distinct app to Android; there is no
  in-place upgrade path across this change).
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
- GPX export now goes through the system share sheet instead of a folder
  picker — the folder picker never actually worked on iOS and failed for
  many folder choices on Android; sharing (Save to Files, another app, …)
  works reliably on both.
- The activities list now shows a retry button instead of a permanently
  spinning loader when it fails to load.
- Recording performance: the map no longer redraws its tiles, route line and
  kilometre markers every second — only the small stats overlay (timer,
  distance, pace) updates that often. On a long recording this noticeably
  reduces battery drain and jank.
- GPX import now parses the file off the main thread, so importing a large
  or long GPX no longer freezes the app briefly.

### Fixed
- A rare timing issue could open the GPS position stream twice at once
  (e.g. right after finishing the setup wizard), duplicating recorded points
  and leaking a stream subscription.
- Per-kilometre splits: switching the chart to the km/h view could label the
  slowest kilometre as the fastest and vice versa.
- A failed "Start" tap could still flash the "Activity started" success
  banner on top of the error message.
- Preference changes (map theme, language, lock-screen visibility) could
  silently fail to apply immediately if you closed Settings right after
  tapping Apply, without any indication that anything went wrong.
- GPX export/import edge cases: coordinates extremely close to the
  equator/prime meridian could produce an invalid file (scientific
  notation); illegal control characters in an activity name (possible via a
  previously-imported GPX) could also invalidate the file; files using an
  XML namespace prefix, or a `<trk>` with track points not wrapped in a
  `<trkseg>`, could be rejected entirely instead of importing; a `<time>`
  value without a timezone is now correctly read as UTC (previously
  interpreted in the device's local timezone, shifting the recorded time
  depending on where the file was imported).
- "New version available" notifications from the opt-out GitHub update
  check now actually appear — they were being silently dropped on
  essentially every launch due to a navigation timing issue.
- An abandoned recording that gets auto-closed after being found stale no
  longer reports its "stopped at" time as the moment it was discovered,
  keeping its duration accurate.
- Preference changes (map theme, map tiles, lock-screen visibility) now
  actually apply immediately instead of silently requiring an app restart —
  the "apply live" logic was comparing a value against itself and always
  concluding nothing had changed.
- A single intermittent GPS fix with no altitude reading no longer inflates
  elevation gain by hundreds of metres; it's now correctly excluded from the
  smoothing instead of being treated as a trusted 0 m sample.
- A fast double-tap on "Start" could create two concurrent recordings, one
  of which silently sat in the activities list as a near-empty orphan.
- The background tracking watchdog no longer mistakes "every fix currently
  fails the accuracy filter" (normal under tree cover, indoors, in an urban
  canyon) for "the tracking service died", which used to restart a perfectly
  healthy foreground service and show a false "tracking gap" banner.
- The live location dot no longer freezes indefinitely if the OS suspends
  the position stream while nothing is being recorded — the watchdog now
  reopens it regardless.
- GPX import: track segments/tracks that are not in chronological order in
  the file (e.g. a GPX concatenated from several separate recordings) no
  longer have their straight-line gap silently counted as active
  distance/duration.
- A backlogged/out-of-order GPS fix (delivered by the OS after the fact) can
  no longer move the internal "last known good" anchor backwards, which
  previously spliced a small spurious zig-zag into the recorded distance.
- A database schema upgrade interrupted mid-way (app killed, battery pulled)
  no longer permanently corrupts the local database; the upgrade is now a
  single atomic transaction that cleanly retries on the next launch instead.
  Sideloading an older build over a newer database is now refused outright
  instead of silently corrupting the schema version.

### Security & privacy
- iOS: the local database and log file are now excluded from iCloud/iTunes
  backups, matching the opt-out Android already had.
- Old shared activity-card images are cleaned up instead of accumulating in
  the app's temporary storage indefinitely.
- Removed the (already unused) local storage of third-party OSM traces
  fetched while panning the map; any residual data from before this fix is
  purged from the database on upgrade.
- Added a build-time switch (`DISABLE_UPDATE_CHECK`) to disable the
  opt-out GitHub update check entirely for distribution channels — such as
  F-Droid — that already manage updates themselves. See the README.
- Hardened error logging around the (currently unused) public-traces search
  so a future re-enable can't leak a precise map viewport into the log file.
- The opt-out GitHub update check no longer runs before the first-launch
  wizard — a fresh install used to phone home before you had any chance to
  see or decline the Preferences toggle that controls it.
- Exported GPX files and shared activity-card images no longer risk deleting
  each other out from under an in-flight share; each now purges only its own
  file type, and any leftover from a previous session is also cleaned up at
  the next app launch instead of only at the next share/export.

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

[1.3.0]: https://github.com/ethicnology/furtive/releases/tag/1.3.0
[1.2.0]: https://github.com/ethicnology/furtive/releases/tag/1.2.0
