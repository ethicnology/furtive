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
/// The `version:` values here are what gate and label the in-app changelog:
/// CheckPermissionPage shows every entry strictly newer than the user's
/// `lastShownChangelogVersion`, then stamps the current app version.
///
/// On build numbers: the versionCode had stayed at 1 across every release up
/// to 1.1.0+1, which F-Droid and Android both require to strictly increase
/// between releases. It was bumped in place to 1.2.0+2, so 1.3.0 must be +3.
List<ChangelogRelease> changelogReleases(AppLocalizations l10n) => [
  ChangelogRelease(
    version: '1.3.0',
    bullets: [
      l10n.changelogV130LiveShare,
      l10n.changelogV130Profiles,
      l10n.changelogV130Map,
      l10n.changelogV130Puck,
      l10n.changelogV130Detail,
      l10n.changelogV130Left,
      l10n.changelogV130CarFix,
    ],
  ),
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
