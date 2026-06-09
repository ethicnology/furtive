# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
