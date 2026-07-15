import 'package:furtive/l10n/app_localizations.dart';

/// One release's worth of "what's new" copy. Built from ARB strings so the
/// bullets are localised.
class ChangelogRelease {
  final String version;
  final List<String> bullets;
  const ChangelogRelease({required this.version, required this.bullets});
}

/// Per-release changelog entries, newest first. Keep only the last few
/// versions on disk; rotate older ones out as they become irrelevant.
///
/// The ARB keys below are still named `changelogV120*` even though this
/// release actually ships as 1.3.0: the versionCode had stayed at 1 across
/// every prior release (1.0.0+1, 1.1.0+1, 1.2.0+1), which F-Droid and
/// Android both require to strictly increase between releases, so the
/// version was bumped to 1.3.0+2 late in this pass (see the
/// `com.ethicnology.furtive` applicationId rename commit). Renaming the
/// keys themselves would touch all 26 locale ARB files for a cosmetic
/// mismatch only visible in source; the `version:` value below is what
/// actually gates and labels the in-app changelog, and it must match
/// pubspec.yaml's `1.3.0+2`.
List<ChangelogRelease> changelogReleases(AppLocalizations l10n) => [
  ChangelogRelease(
    version: '1.3.0',
    bullets: [
      l10n.changelogV120I18n,
      l10n.changelogV120Wizard,
      l10n.changelogV120Recording,
      l10n.changelogV120Stats,
      l10n.changelogV120Share,
      l10n.changelogV120GpxImport,
      l10n.changelogV120MapThemes,
      l10n.changelogV120Reproducible,
      l10n.changelogV120Stability,
    ],
  ),
];
