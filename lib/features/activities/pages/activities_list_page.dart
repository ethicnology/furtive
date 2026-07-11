import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/get_activities_use_case.dart';
import 'package:furtive/core/widgets/stat_block.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/bloc/activities_state.dart';
import 'package:furtive/features/activities/pages/activity_detail_page.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class ActivitiesListPage extends StatefulWidget {
  const ActivitiesListPage({super.key});

  @override
  State<ActivitiesListPage> createState() => _ActivitiesListPageState();
}

class _ActivitiesListPageState extends State<ActivitiesListPage> {
  // Set true the moment we dispatch ImportActivityFromGpx so the
  // BlocListener can distinguish an import's success transition from any
  // other isLoading=true→false transition (e.g. FetchActivities). Cleared
  // when the listener fires.
  bool _importPending = false;
  final _getActivity = GetActivityUseCase();

  @override
  void initState() {
    super.initState();
    context.read<ActivitiesBloc>().add(const FetchActivities());
  }

  Future<void> _pickAndImportGpx() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // file_selector with a .gpx-only filter. iOS / Android both honour
    // the extension list via UTType / MIME inference.
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'GPX', extensions: ['gpx']),
      ],
    );
    if (file == null || !mounted) return;
    _importPending = true;
    context.read<ActivitiesBloc>().add(
      ImportActivityFromGpx(filePath: file.path),
    );
    // Lightweight "import started" toast — the success/failure result
    // arrives via the bloc listener below.
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.importStarted),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<ActivitiesBloc, ActivitiesState>(
      listenWhen: (prev, curr) =>
          prev.isLoading != curr.isLoading || prev.error != curr.error,
      listener: (context, state) {
        if (state.error != null) {
          _importPending = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.error!.message,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        if (_importPending && !state.isLoading) {
          _importPending = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.importSuccess),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navActivities),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: l10n.activitiesImportTooltip,
              onPressed: _pickAndImportGpx,
            ),
          ],
        ),
        body: BlocBuilder<ActivitiesBloc, ActivitiesState>(
          builder: (context, state) {
            // B31: read state from the builder param, not via context.watch
            // (which would cause a second rebuild on every emit).
            final activities = state.activities;

            if (state.isLoading || activities == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (activities.isEmpty) {
              return Center(
                child: Text(
                  AppLocalizations.of(context).activitiesEmpty,
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.tertiary.foreground,
                  ),
                ),
              );
            }

            // Locale-aware "Mar 15, 2026 14:30" / "15/03/2026 14:30" etc.
            // — ISO substring used to leak a "T" separator into the UI.
            final localeName = Localizations.localeOf(context).toString();
            final dateFormat = DateFormat.yMMMd(localeName).add_Hm();
            return ListView.builder(
              itemCount: activities.length,
              itemBuilder: (context, index) {
                final activity = activities[index];
                var title = dateFormat.format(activity.startedAt.toLocal());
                if (activity.name.isNotEmpty &&
                    activity.name != kDefaultActivityName) {
                  title = activity.name;
                }
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          // Distance is the one stat emphasized in mint —
                          // the rest stay muted so the row reads as one
                          // headline number plus supporting detail instead
                          // of four equally-loud pills.
                          StatBlock.compact(
                            icon: Icons.straighten_rounded,
                            value: '${activity.activeDistanceInKm.fmt2} km',
                            emphasize: true,
                          ),
                          StatBlock.compact(
                            icon: Icons.timer_outlined,
                            value: activity.activeDuration.toHHMMSS(),
                          ),
                          StatBlock.compact(
                            icon: Icons.speed_rounded,
                            value: '${activity.activeSpeedKmh.fmt2} km/h',
                          ),
                          StatBlock.compact(
                            icon: Icons.timelapse_rounded,
                            value: activity.activePaceMinPerKm,
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: kTextMuted,
                    ),
                    onTap: () => unawaited(_openActivity(activity.id)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // The list holds lightweight summaries (no GPS points); load the full
  // activity with its points before opening the detail page.
  Future<void> _openActivity(String id) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final activity = await _getActivity(id);
      if (!mounted) return;
      unawaited(
        navigator.push(
          MaterialPageRoute(
            builder: (context) => ActivityDetailPage(activity: activity),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.activitiesLoadError),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
