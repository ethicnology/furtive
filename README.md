# furtive

Privacy first. No accounts. No Google services. Full access to your GPS sensor.

[Download the latest apk](https://github.com/ethicnology/furtive/releases/latest)

## Screenshots

<div align="center">

| | |
|:-------------------------:|:-------------------------:|
| <img src="assets/readme/map.png" width="100%" /> | <img src="assets/readme/activity_started.png" width="100%" /> |
| <img src="assets/readme/activity_stats.png" width="100%" /> | <img src="assets/readme/settings.png" width="100%" /> |
| <img src="assets/readme/activities.png" width="100%" /> | <img src="assets/readme/permissions.png" width="100%" /> |

</div>

## Releases

Release artifacts are produced unsigned by Flutter (`signingConfig = null`
in `android/app/build.gradle.kts`) and signed out-of-band with
`apksigner` / `zipalign`. Keystores never enter this repository — do
not add a `key.properties` or wire signing into Gradle.

## Reproducible builds

`make apk` produces byte-identical output for the same source on any
host. The toolchain is pinned end-to-end:

- `debian:trixie@sha256:…` (multi-arch index digest, in `Containerfile.tools`)
- Flutter `3.41.9` via `.fvmrc`
- Android NDK / SDK / build-tools / JVM in `android/gradle.properties`
- `pubspec.lock` enforced via `flutter pub get --enforce-lockfile`
- `SOURCE_DATE_EPOCH = $(git log -1 --format=%ct)` passed to the container
  so Gradle/AGP/Kotlin emit deterministic timestamps

Verify locally with `make verify-reproducible` (builds twice, compares
SHA-256, fails with a diffoscope hint on mismatch).

Empty/missing `PROTOMAPS_KEY` produces the FOSS path (no map tiles, but
otherwise functional) — that's the variant anyone in the world can
rebuild and verify bit-for-bit. The keyed variant is reproducible by
anyone holding the same key. Mobile API keys are not secret in any
case: anyone can extract one from a shipped APK via `strings`.
