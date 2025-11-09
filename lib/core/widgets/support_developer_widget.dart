import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportDeveloperWidget extends StatelessWidget {
  const SupportDeveloperWidget({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Colors.redAccent, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Support Development',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This app is built and maintained on my free time. Your support helps keep it alive and growing.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primary.foreground,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        () => _launchUrl(
                          'https://github.com/ethicnology/furtive',
                        ),
                    icon: Icon(
                      Icons.star_border,
                      color: AppColors.quaternary.foreground,
                    ),
                    label: Text(
                      'Star on GitHub',
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
                    onPressed:
                        () => _launchUrl(
                          'https://github.com/sponsors/ethicnology',
                        ),
                    icon: Icon(
                      Icons.volunteer_activism,
                      color: AppColors.quaternary.foreground,
                    ),
                    label: Text(
                      'Sponsor',
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
