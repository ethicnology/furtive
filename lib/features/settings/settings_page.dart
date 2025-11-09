import 'package:flutter/material.dart';
import 'package:furtive/core/widgets/app_version_widget.dart';
import 'package:furtive/features/permissions/presentation/pages/permissions_page.dart';
import 'package:furtive/features/preferences/page.dart';
import 'package:furtive/features/logs/logs_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Permissions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PermissionsPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PreferencesPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (context) => const LogsPage()));
            },
          ),
          Spacer(),
          AppVersionWidget(),
        ],
      ),
    );
  }
}
