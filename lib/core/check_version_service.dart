import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/l10n/app_localizations.dart';
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

  // Respect the user's opt-out: no network call at all when disabled.
  try {
    final prefs = await GetPreferencesUseCase()();
    if (!prefs.checkUpdates) return;
  } catch (e) {
    logs.warning('Update check: failed to read preference: $e');
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
        // GitHub's API requires a User-Agent header; send a neutral one
        // rather than the default dart:io UA.
        .get(latestUrlApi, headers: const {'User-Agent': 'furtive-app'})
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
    final latest = stripLeadingV(jsonBody['tag_name'] as String);
    final current = Global.app.version;
    // Only nag when the published release is strictly newer. Plain equality
    // also prompted on dev/test builds whose version is *ahead* of the latest
    // release, and replaceAll('v', '') used to corrupt any tag containing a
    // non-leading 'v'.
    if (!isNewerVersion(latest, current)) return;

    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.newVersionAvailable(latest),
          style: TextStyle(
            color: AppColors.primary.foreground,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary.background,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.btnDownload,
          onPressed: () async {
            final ok = await launchUrl(
              latestUrl,
              mode: LaunchMode.externalApplication,
            );
            if (!ok) logs.warning('Could not launch releases page: $latestUrl');
          },
        ),
      ),
    );
  } catch (e) {
    logs.warning('Error checking new version: $e');
  }
}

/// Strip a single leading `v`/`V` from a release tag (`v1.2.0` -> `1.2.0`).
/// Unlike `replaceAll('v', '')` this leaves a `v` elsewhere in the tag intact.
String stripLeadingV(String tag) {
  final t = tag.trim();
  return (t.startsWith('v') || t.startsWith('V')) ? t.substring(1) : t;
}

/// True when [latest] is a strictly higher version than [current]. Compares
/// dot-separated numeric components (`1.2.10` > `1.2.9`), ignoring any
/// pre-release / build suffix (`1.2.0-rc1`, `1.2.0+3`). Missing trailing
/// components count as 0 (`1.2` == `1.2.0`). Falls back to "not newer" on
/// unparseable input so a malformed tag never nags the user.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) =>
      v
          .split(RegExp(r'[-+]'))
          .first
          .split('.')
          .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D'), '')) ?? 0)
          .toList();

  final a = parse(latest);
  final b = parse(current);
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
