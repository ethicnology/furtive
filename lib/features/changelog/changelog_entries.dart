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
List<ChangelogRelease> changelogReleases(AppLocalizations l10n) => [
  ChangelogRelease(
    version: '1.2.0',
    bullets: [
      l10n.changelogV120Share,
      l10n.changelogV120GpxImport,
      l10n.changelogV120LocaleDates,
      l10n.changelogV120Stability,
    ],
  ),
];
