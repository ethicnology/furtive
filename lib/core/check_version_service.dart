import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

Future<void> checkNewVersion(BuildContext context) async {
  try {
    final latestUrlApi = Uri.parse(
      'https://api.github.com/repos/ethicnology/furtive/releases/latest',
    );

    final latestUrl = Uri.parse(
      'https://github.com/ethicnology/furtive/releases/latest',
    );

    final response = await http.get(latestUrlApi);
    if (response.statusCode != 200) {
      throw Exception('Failed to get latest version: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body);
    final latest = jsonBody['tag_name'].toString().replaceAll('v', '');
    final current = Global.app.version;
    if (latest == current) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Download the latest version $latest',
          style: TextStyle(
            color: AppColors.primary.foreground,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary.background,
        duration: Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () => launchUrl(latestUrl),
        ),
      ),
    );
  } catch (e) {
    logs.warning('Error checking new version: $e');
  }
}
