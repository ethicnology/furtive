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
    version: '1.1.0',
    bullets: [
      l10n.changelogV110I18n,
      l10n.changelogV110Splits,
      l10n.changelogV110HoldToStop,
      l10n.changelogV110MapLabels,
      l10n.changelogV110NanDefense,
    ],
  ),
];
