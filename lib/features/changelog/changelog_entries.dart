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
/// This release ships as 1.2.0+2 rather than 1.2.0+1: the versionCode had
/// stayed at 1 across every prior release (1.0.0+1, 1.1.0+1), which F-Droid
/// and Android both require to strictly increase between releases, so the
/// build number was bumped in this pass (see the `com.ethicnology.furtive`
/// applicationId rename commit). The `version:` value below is what
/// actually gates and labels the in-app changelog, and it must match
/// pubspec.yaml's `1.2.0+2`.
List<ChangelogRelease> changelogReleases(AppLocalizations l10n) => [
  ChangelogRelease(
    version: '1.2.0',
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
