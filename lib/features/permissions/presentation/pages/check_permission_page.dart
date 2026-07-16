import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/check_version_service.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/changelog/changelog_entries.dart';
import 'package:furtive/features/changelog/pages/changelog_page.dart';
import 'package:furtive/features/onboarding/onboarding_page.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';
import 'package:furtive/features/permissions/presentation/pages/permissions_page.dart';

class CheckPermissionPage extends StatefulWidget {
  const CheckPermissionPage({super.key});

  @override
  State<CheckPermissionPage> createState() => _PermissionCheckPageState();
}

class _PermissionCheckPageState extends State<CheckPermissionPage> {
  bool _hasNavigated = false;
  final _getPreferences = GetPreferencesUseCase();
  final _updatePreferences = UpdatePreferencesUseCase();

  @override
  void initState() {
    super.initState();
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  Future<void> _navigate(bool allGranted) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final prefs = await _getPreferences();
    if (!mounted) return;

    // Fire-and-forget — version check is informational, not gating.
    // No BuildContext needed: checkNewVersion uses Global.scaffoldMessengerKey
    // instead, since this page's context is unmounted (pushReplacement below)
    // well before the HTTP call can settle. See M4 in
    // docs/REVIEW-2026-07-FULL-APP.md.
    //
    // Gated on hasCompletedOnboarding: this page runs on EVERY launch,
    // including the very first, before the onboarding wizard has shown the
    // user anything (let alone the Preferences toggle that opts out of this
    // check). checkUpdates defaults to true, so an ungated call here made a
    // brand-new install phone home to GitHub before the user had any chance
    // to see or decline that. See docs/REVIEW-2026-07-FULL-APP.md / the privacy
    // audit's "update check phones home before consent" finding.
    if (prefs.hasCompletedOnboarding) unawaited(checkNewVersion());

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
        await _updatePreferences(
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
      child: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
