import 'package:flutter/material.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportDeveloperWidget extends StatelessWidget {
  const SupportDeveloperWidget({super.key});

  Future<void> _launchUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
      if (!context.mounted) return;
      _showLaunchFailed(context, url);
    } catch (e, st) {
      logs.warning('Failed to launch $url', error: e, trace: st);
      if (!context.mounted) return;
      _showLaunchFailed(context, url);
    }
  }

  void _showLaunchFailed(BuildContext context, String url) {
    // No browser / no handler installed — surface a localised snackbar
    // instead of silently throwing up the widget tree (the previous code
    // raised an Exception that nothing caught, killing the gesture).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).linkOpenFailed(url))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: AppColors.primary.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
                const SizedBox(width: 12),
                Text(
                  l10n.supportTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.supportDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primary.foreground,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launchUrl(
                      context,
                      'https://github.com/ethicnology/furtive',
                    ),
                    icon: Icon(
                      Icons.star_border,
                      color: AppColors.quaternary.foreground,
                    ),
                    label: Text(
                      l10n.btnStarGitHub,
                      style: TextStyle(color: AppColors.quaternary.foreground),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.quaternary.background,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launchUrl(
                      context,
                      'https://github.com/sponsors/ethicnology',
                    ),
                    icon: Icon(
                      Icons.volunteer_activism,
                      color: AppColors.quaternary.foreground,
                    ),
                    label: Text(
                      l10n.btnSponsor,
                      style: TextStyle(color: AppColors.quaternary.foreground),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.quaternary.background,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
