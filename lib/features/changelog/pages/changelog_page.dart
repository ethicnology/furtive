import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/features/changelog/changelog_entries.dart';
import 'package:furtive/l10n/app_localizations.dart';

/// Full-screen "What's New" shown after an app upgrade. Pushed by
/// CheckPermissionPage between the permission check and the bottom-nav with
/// the set of releases newer than the version the user last saw. The Got It
/// button pops the route — the caller persists the new version once the
/// future resolves.
class ChangelogPage extends StatelessWidget {
  /// Releases to display, already filtered to those newer than the user's
  /// last-seen version (newest first).
  final List<ChangelogRelease> releases;

  const ChangelogPage({super.key, required this.releases});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.changelogTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: releases.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _ReleaseCard(release: releases[index]),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.screenPadding),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.changelogGotIt),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final ChangelogRelease release;
  const _ReleaseCard({required this.release});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.quaternary.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${release.version}',
              style: TextStyle(
                color: AppColors.primary.background,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            for (final bullet in release.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(color: AppColors.tertiary.foreground),
                    ),
                    Expanded(
                      child: Text(
                        bullet,
                        style: TextStyle(
                          color: AppColors.tertiary.foreground,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
