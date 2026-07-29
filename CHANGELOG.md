# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Activity profiles.** Furtive is no longer implicitly a running app: pick
  what you are about to do — walk, run, bike, drive, swim, fly or another
  activity — from the record screen, next to Start. The last choice is
  remembered, so the common case costs no interaction.

  The type is not a label. It sizes the GPS sampling interval, the horizontal
  accuracy tolerance, the implied-speed ceiling, and the iOS Core Location
  activity type, and it is stored on the activity so a later preference change
  cannot retroactively restate what an old recording meant.

  The list deliberately starts short. `Other` uses a permissive profile for
  activities that do not yet deserve their own label, while new labels can be
  added later without rewriting existing database rows.
- **Map controls can move to the left**, for left-handed use. Every control
  touched mid-activity lives in that column, one-handed and often while
  moving. The attribution badge moves to the opposite corner with it — it is
  legally required to stay visible and the button column had already covered
  it once.
- **The location puck is drawn by the app, from the position the app
  actually trusts.** Previously it came from MapLibre's native
  LocationComponent, which ran a *second* location engine: a
  `PRIORITY_HIGH_ACCURACY` request at a hardcoded 750 ms that also subscribed
  to Android's `network` provider — wifi and cell positioning, tens to
  thousands of metres out — and never passed through the app's quality filter.

  The result was visible on screen: Follow centred the camera on the filtered
  fix while the dot wandered off on a wifi-derived one. The plugin exposes no
  way to point that engine at our own stream, so the component is gone. The
  puck now reads the same value the Follow button does, which makes the two
  incapable of disagreeing.

  It shows a plain dot at a standstill and a chevron along the direction of
  travel once moving, since a course over ground derived from no movement is
  meaningless. The accuracy circle is drawn as a real polygon in metres rather
  than MapLibre's pixel-radius circle, which is only correct at one zoom level.
  Being a Flutter widget, it also renders identically on iOS, where the native
  component ignored most of its options.

  Android device orientation now comes from the fused rotation-vector sensor,
  corrected to true north. The puck no longer interpolates between GPS fixes.
- **Recording detail** (precise / balanced / endurance) scales the sampling
  interval around whatever the chosen activity already implies. Expressed as
  an intent rather than a number of seconds on purpose: iOS exposes no
  interval knob at all and Android's is a *requested* rate, so a literal
  "every N seconds" field would promise something neither platform delivers.

### Fixed
- **A car above 126 km/h recorded nothing at all.** The quality gate rejected
  any fix implying more than 35 m/s, and — by design, to avoid chaining off an
  untrusted fix — a rejection did not advance the comparison anchor. Above
  that speed every subsequent fix was therefore measured against an
  ever-more-distant point and kept failing, so the trace froze at the last
  accepted position until the vehicle slowed below 126 km/h. A legal French
  motorway speed is 130.

  Three changes, not one. Ceilings now come from the activity. Reported
  accuracy is subtracted before judging speed, so two vague fixes of a
  stationary phone stop looking like a teleport. And no rejection is permanent
  any more: after a few consecutive suspicions the filter accepts and
  re-anchors, so even a wildly wrong profile degrades the trace instead of
  erasing it.
- **Dropped fixes are logged with a reason.** They were discarded silently,
  which made "the filter is rejecting everything" (urban canyon, wrong
  profile) indistinguishable from "the foreground service died" — the single
  biggest obstacle to explaining a hole in a recorded trace after the fact.
- **iOS was told every activity was a workout.** `ActivityType.fitness` was
  hardcoded, including for vehicles and boats; Core Location now gets the
  right hint per profile.
- The stream-stall watchdog derived "no fix for 20 s" from the old hardcoded
  5 s cadence. It now scales with the active profile's interval, so a sparse
  profile is not mistaken for a dead service and torn down in a loop.

### Removed
- The dead `accuracy_in_meters` preferences column (schema v12): always
  written as 0, threaded through the entity, model and data source, never read
  to drive anything. It was the residue of a user-facing GPS precision setting
  removed some versions ago as "confusing more than it helped" — which is
  precisely why sampling is now exposed as an intent instead of a number.

### Changed
- **The map is rendered by MapLibre Native** instead of
  `flutter_map` + `vector_map_tiles`. Protomaps remains the tile provider and
  the tile opt-out is unchanged. Zoom was the one interaction that janked
  consistently, because the old renderer rasterises per zoom level; measured on
  a Pixel 5 in profile, a zoom sweep went from 5 frames over budget to none.
  An idle map and the recording loop already dropped no frames in either stack,
  so this was not a fix for the app's central use case.

  The larger half of the case is structural: Protomaps' styles are now used
  verbatim. The old renderer cannot parse MapLibre `format` expressions and a
  real Protomaps style nests 91 of them in its label logic, so the app rewrote
  every `text-field`, replacing Protomaps' multi-script fallback with a flat
  coalesce. No third-party style document is parsed in Dart any more. Dropping
  the old renderer also lifts the `protobuf ^3` ceiling that made `pmtiles` 2.x
  unresolvable, which is a prerequisite for offline maps.

  Costs taken on knowingly: a ~13 MB opaque native library per ABI in a project
  whose premise is auditability; glyphs and sprites are fetched from
  `protomaps.github.io`, a host the old stack contacted for sprites only;
  the native SDK version must stay pinned because upstream declares a dynamic
  `13.0.+` range that does not exclude pre-releases; and R8/minify must stay
  off, upstream having had two release-only rendering bugs tied to it.
  Panning horizontally on the map no longer swipes between tabs — a platform
  view has to claim the gesture outright, or the bottom navigation takes it.
- **Toolchain** — Flutter 3.44.8; dependencies refreshed to their newest
  resolvable versions. `build_runner` / `drift_dev` / `dart_mappable_builder`
  are pinned behind their latest because every newer release requires
  `analyzer ^13`, which no Flutter stable ships yet — see the note in
  `pubspec.yaml`.
- **Architecture** — dependencies are now injected through constructors (with
  real defaults) instead of being constructed in place, and `get_it` is confined
  to the composition root. The four-layer bloc → use case → repository →
  datasource chain had no injection point anywhere, which is why most of the app
  was untestable; 11 pass-through use cases and 2 alias repositories were
  removed, and the `permissions` feature was flattened to match the structure
  every other feature uses.
- **Recording** — the recording state machine moved out of `MapBloc` into a
  dedicated `RecordingBloc`, and the GPS stream lifecycle into
  `PositionStreamController`. `MapBloc` is now map presentation only. Behaviour
  is unchanged; the map subtree no longer rebuilds on the 1 s elapsed tick by
  construction rather than by a `buildWhen` allowlist.
- **Time** — every wall-clock read goes through an injectable `Clock`, making the
  12 h abandoned-recording window, the 20 s stale-stream threshold and the
  pause/elapsed bookkeeping directly testable.

### Fixed
- **Preferences could silently fail to save.** The page dispatched Apply and
  popped in the same frame, so a failed write had no UI left to report to and was
  only logged — the user believed their settings were stored. Apply now waits for
  the write, reports failures, and only then closes.
- **The Preferences page overflowed** on a short viewport (and at large system
  font sizes), pushing the Apply button off screen and making the settings
  impossible to save. The page now scrolls.
- **The share card ignored the system font scale**, so a user with large
  accessibility text exported a visibly broken PNG they never saw before sharing.
  The card is pinned to `TextScaler.noScaling` and covered by golden tests.
- **`activity_points` → `activities` foreign key now cascades** (schema v10). It
  previously declared a reference with no `ON DELETE` action, so nothing at the
  SQLite level prevented orphan point rows; only the app's own transaction did.
- Indexed `activities.stopped_at`, used by the resume-after-kill lookup on every
  cold start.
- The GPX import size cap was lowered from 50 MB to 10 MB, which is what actually
  bounds peak memory (the file is read to a String and then copied to the parse
  isolate). The old comment justified it as billion-laughs/XXE mitigation; both
  claims were wrong and are now pinned by tests instead.

### Removed
- **The dead OpenStreetMap public-traces stack** (~600 lines). Its only trigger
  had been commented out and its tables dropped in schema v8, but the code — and
  its call to `api.openstreetmap.org` carrying the user's map viewport — was
  still compiled in. For an app whose premise is "no network calls beyond what
  you can see in the source", that was the worst possible place to keep dead
  code.
- The dead `map_language` preferences column (schema v9) and the unused
  `KmMilestone.time` field, which was also the only non-UTC timestamp in the app.
- Six direct dependencies, with the old renderer: `flutter_map`,
  `flutter_map_location_marker`, `vector_map_tiles`, `vector_tile_renderer`,
  `executor_lib` and `latlong2`. Sixteen resolved packages left and thirteen
  arrived, so the dependency graph is barely smaller (185 → 182) — the saving is
  in the code the app no longer owns, not in its footprint.

### Accessibility
- `HoldToConfirmButton` — the only way to stop a recording — now exposes a button
  role, label, hint and tap/long-press actions, and announces its countdown. It
  was a bare `GestureDetector`, i.e. invisible to screen readers.
- Hardcoded font sizes across the UI now derive from the theme's text scale, so
  the app honours the system font size. Fixed sizes are retained only where the
  canvas itself is fixed (share card, map markers) and pinned explicitly.
- Contrast, tap-target size and label presence are now verified by tests using
  Flutter's accessibility guidelines. The palette already documented its WCAG
  ratios; nothing checked them.

### Internal
- Test suite grown from 118 to 184; line coverage of hand-written code from
  ~19% to ~57%, with a floor enforced in CI (`tool/coverage_threshold.py`).
- Stricter analysis: `strict-casts`, `strict-raw-types`, `avoid_dynamic_calls`,
  `cancel_subscriptions`, `close_sinks` and others. These immediately surfaced
  unchecked `dynamic` casts in the third-party Protomaps style parsing, where a
  schema change would have broken the map for every user at once.

## [1.2.0] - 2026-07-15

Ships as 1.2.0+2 rather than 1.2.0+1: the Android versionCode had stayed at 1
across every prior release (1.0.0+1, 1.1.0+1, and this one was about to ship
as 1.2.0+1 too), which F-Droid and Android both require to strictly increase
between releases. 1.2.0 was never actually released before this, so the
build number is bumped in place rather than skipping ahead to a new version
name.

This release also includes a remediation pass following a full audit of
location tracking, permissions, GPS accuracy and privacy — see
`docs/AUDIT-2026-07.md` and `docs/REVIEW-2026-07-FULL-APP.md` for the detailed findings
and rationale behind the audit-related items below.

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
- Added the legally required OpenStreetMap / Protomaps map attribution.
- The device name is no longer written to diagnostic logs.
- iOS: the local database and log file are now excluded from iCloud/iTunes
  backups, matching the opt-out Android already had.
- Old shared activity-card images are cleaned up instead of accumulating in
  the app's temporary storage indefinitely.
- Removed the (already unused) local storage of third-party OSM traces
  fetched while panning the map; any residual data from before this fix is
  purged from the database on upgrade.
- Removed the GitHub update check entirely. Obtainium and F-Droid already
  track releases, so the app no longer contacts `api.github.com` or needs an
  update-check preference/build flag.
- Hardened error logging around the (currently unused) public-traces search
  so a future re-enable can't leak a precise map viewport into the log file.
- Exported GPX files and shared activity-card images no longer risk deleting
  each other out from under an in-flight share; each now purges only its own
  file type, and any leftover from a previous session is also cleaned up at
  the next app launch instead of only at the next share/export.

[1.2.0]: https://github.com/ethicnology/furtive/releases/tag/1.2.0
