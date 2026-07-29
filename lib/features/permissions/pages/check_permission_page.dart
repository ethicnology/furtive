import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/utils/version.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/changelog/changelog_entries.dart';
import 'package:furtive/features/changelog/pages/changelog_page.dart';
import 'package:furtive/features/onboarding/onboarding_page.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:furtive/features/permissions/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/bloc/permissions_state.dart';
import 'package:furtive/features/permissions/pages/permissions_page.dart';

class CheckPermissionPage extends StatefulWidget {
  const CheckPermissionPage({super.key});

  @override
  State<CheckPermissionPage> createState() => _PermissionCheckPageState();
}

class _PermissionCheckPageState extends State<CheckPermissionPage> {
  bool _hasNavigated = false;
  String? _navigationError;
  final _preferences = PreferencesRepository();

  @override
  void initState() {
    super.initState();
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  Future<void> _navigate(bool allGranted) async {
    if (_hasNavigated || !mounted) return;
    setState(() {
      _hasNavigated = true;
      _navigationError = null;
    });

    final PreferencesEntity prefs;
    try {
      prefs = await _preferences.fetch();
    } catch (error, trace) {
      logs.severe('Load startup preferences', error: error, trace: trace);
      if (mounted) {
        setState(() {
          _hasNavigated = false;
          _navigationError = error.toString();
        });
      }
      return;
    }
    if (!mounted) return;

    // Show the post-upgrade changelog before the main UI, but only for
    // existing users who came from an older version. Fresh installs
    // (lastShownChangelogVersion == null until the wizard finishes) skip it.
    final lastSeen = prefs.lastShownChangelogVersion;
    if (prefs.hasCompletedOnboarding &&
        lastSeen != null &&
        lastSeen != Global.app.version) {
      // Only the releases newer than what the user last saw — so an upgrade
      // never shows stale "what's new" for a version they've already seen,
      // and a build with no matching release entry shows nothing.
      final newer = changelogReleases(
        AppLocalizations.of(context),
      ).where((r) => isNewerVersion(r.version, lastSeen)).toList();
      if (newer.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChangelogPage(releases: newer)),
        );
        if (!mounted) return;
      }
      try {
        // Persist the current version regardless, so the gate doesn't
        // re-evaluate on every launch once we've considered this upgrade.
        await _preferences.store(
          prefs.copyWith(lastShownChangelogVersion: Global.app.version),
        );
      } catch (e, st) {
        // Non-fatal — worst case the changelog shows again on next launch.
        logs.warning(
          'Failed to persist changelog version',
          error: e,
          trace: st,
        );
      }
      if (!mounted) return;
    }

    // The wizard now owns the permissions step, so onboarding takes priority
    // over the standalone PermissionsPage. PermissionsPage is only used as a
    // recovery fallback when an onboarded user has had a required permission
    // revoked (e.g. via system settings while the app was backgrounded).
    final Widget destination;
    if (!prefs.hasCompletedOnboarding) {
      destination = const OnboardingPage();
    } else if (!allGranted) {
      destination = const PermissionsPage();
    } else {
      destination = const BottomNavigationWidget();
    }

    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PermissionsBloc, PermissionsState>(
      listener: (context, state) {
        if (!state.isLoading) _navigate(state.requiredGranted);
      },
      child: Scaffold(
        body: Center(
          child: _navigationError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_navigationError!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _navigate(
                          context.read<PermissionsBloc>().state.requiredGranted,
                        ),
                        child: Text(AppLocalizations.of(context).btnRetry),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
