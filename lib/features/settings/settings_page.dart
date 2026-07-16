import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/app_version_widget.dart';
import 'package:furtive/core/widgets/support_developer_widget.dart';
import 'package:furtive/features/permissions/presentation/pages/permissions_page.dart';
import 'package:furtive/features/preferences/page.dart';
import 'package:furtive/features/logs/logs_page.dart';
import 'package:furtive/l10n/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: Text(l10n.menuPermissions),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: kTextMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const PermissionsPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(l10n.menuPreferences),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: kTextMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const PreferencesPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(l10n.menuLogs),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: kTextMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LogsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Spacer(),
            const SupportDeveloperWidget(),
            const SizedBox(height: 12),
            const AppVersionWidget(),
          ],
        ),
      ),
    );
  }
}
