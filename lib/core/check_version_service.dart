import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Process-lifetime cache. Github's API is unauthenticated-rate-limited
// to 60 req/h per IP — we don't want to burn budget on every cold start.
DateTime? _lastCheck;
const _checkCacheTtl = Duration(hours: 24);

Future<void> checkNewVersion(BuildContext context) async {
  if (_lastCheck != null &&
      DateTime.now().difference(_lastCheck!) < _checkCacheTtl) {
    return;
  }
  _lastCheck = DateTime.now();

  try {
    final latestUrlApi = Uri.parse(
      'https://api.github.com/repos/ethicnology/furtive/releases/latest',
    );

    final latestUrl = Uri.parse(
      'https://github.com/ethicnology/furtive/releases/latest',
    );

    final response = await http
        .get(latestUrlApi)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Failed to get latest version: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body);
    // Guard the shape — GitHub occasionally returns error objects with a
    // 200 status (e.g. rate-limit), and a future schema change shouldn't
    // crash the app on a noisy `toString()` call.
    if (jsonBody is! Map || jsonBody['tag_name'] is! String) {
      throw Exception('Unexpected GitHub release payload shape');
    }
    final latest = (jsonBody['tag_name'] as String).replaceAll('v', '');
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
