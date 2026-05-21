import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:furtive/core/widgets/km_milestones_layer.dart';
import 'package:furtive/core/widgets/km_splits_chart.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/export_activity_to_gpx_use_case.dart';
import 'package:furtive/core/usecases/share_activity_use_case.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

class ActivityDetailPage extends StatefulWidget {
  final ActivityEntity activity;

  const ActivityDetailPage({super.key, required this.activity});

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

// Fallback when an activity has zero usable points (Place de la Concorde,
// Paris). Picked arbitrarily — the map only renders without points if the
// user ceased before any GPS fix arrived.
const _kFallbackCenter = LatLng(48.8566, 2.3522);

LatLng _initialCenter(ActivityEntity activity) {
  for (final point in activity.points) {
    final lat = point.position.latitude;
    final lon = point.position.longitude;
    if (lat.isFinite && lon.isFinite) return LatLng(lat, lon);
  }
  return _kFallbackCenter;
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  final _mapController = MapController();
  final _getMapConfigUseCase = GetMapConfigUseCase();
  final _exportActivityToGpxUseCase = ExportActivityToGpxUseCase();
  final _shareActivityUseCase = ShareActivityUseCase();
  Style? _mapStyle;
  bool _isLoading = true;
  bool _isSharing = false;
  late String _currentName;

  @override
  void initState() {
    super.initState();
    _currentName = widget.activity.name;
    _loadMapStyle();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await _getMapConfigUseCase();
      setState(() {
        _mapStyle = style;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Un-renamed activities carry the English sentinel 'Track' — swap for
    // the localised display copy so RU/UK/FR users don't see English in
    // the AppBar.
    final l10n = AppLocalizations.of(context);
    final displayName =
        _currentName == kDefaultActivityName
            ? l10n.activityDefaultName
            : _currentName;
    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showRenameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _showDeleteDialog,
          ),
          IconButton(
            onPressed: (_isLoading || _isSharing) ? null : _share,
            tooltip: AppLocalizations.of(context).shareTooltip,
            icon: _isSharing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.share),
          ),
          IconButton(
            onPressed: (_isLoading || _isSharing) ? null : _exportToGpx,
            icon:
                _isLoading
                    ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    )
                    : const Icon(Icons.file_download),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  Container(
                    color: AppColors.tertiary.background,
                    child:
                        _mapStyle != null
                            ? FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                // Use the first point that has finite lat/lon
                                // — `points.first` can be NaN if the GPS
                                // emitted a junk fix and we'd crash
                                // FlutterMap's LatLng constructor.
                                initialCenter: _initialCenter(widget.activity),
                                initialZoom: Global.maxZoom,
                                maxZoom: Global.maxZoom,
                              ),
                              children: [
                                VectorTileLayer(
                                  maximumZoom: Global.maxZoom,
                                  theme: _mapStyle!.theme,
                                  tileProviders: _mapStyle!.providers,
                                  sprites: _mapStyle!.sprites,
                                ),
                                widget.activity.toPolylineLayer(),
                                KmMilestonesLayer(activity: widget.activity),
                              ],
                            )
                            : Center(
                              child: Text(
                                AppLocalizations.of(context).mapLoadFailed,
                              ),
                            ),
                  ),
                  Positioned(
                    bottom: context.screenPadding,
                    left: context.screenPadding,
                    right: context.screenPadding,
                    child: ElevatedButton.icon(
                      onPressed:
                          () => _showStatisticsBottomSheet(
                            context,
                            widget.activity,
                          ),
                      icon: const Icon(Icons.analytics),
                      label: Text(AppLocalizations.of(context).btnViewStats),
                    ),
                  ),
                ],
              ),
    );
  }

  void _showStatisticsBottomSheet(
    BuildContext context,
    ActivityEntity activity,
  ) {
    // B37: fall back to startedAt for activities with zero recorded points
    // (start + immediate stop before any GPS fix). Previously crashed on
    // points.last.
    final stoppedAt =
        activity.stoppedAt ??
        (activity.points.isNotEmpty
            ? activity.points.last.time
            : activity.startedAt);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.3,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (_, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      ActivityStatsWidget(
                        activity: activity,
                        elapsedTime: stoppedAt.difference(activity.startedAt),
                      ),
                      const SizedBox(height: 16),
                      KmSplitsChart(activity: activity),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _exportToGpx() async {
    setState(() => _isLoading = true);

    try {
      await _exportActivityToGpxUseCase(widget.activity.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).gpxExportSuccess),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).gpxExportFailed(e.toString()),
            ),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await _shareActivityUseCase(context, widget.activity);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).shareFailed(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _showRenameDialog() async {
    // B36: dispose the controller in `finally` to avoid a leak per dialog open.
    final textController = TextEditingController(text: _currentName);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.dlgRenameTitle),
            content: TextField(
              controller: textController,
              decoration: InputDecoration(labelText: l10n.activityNameLabel),
              autofocus: true,
              style: TextStyle(color: AppColors.primary.foreground),
            ),
            actionsAlignment: MainAxisAlignment.spaceAround,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.tertiary.background,
                  foregroundColor: AppColors.tertiary.foreground,
                ),
                child: Text(l10n.btnCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, textController.text),
                child: Text(l10n.btnRename),
              ),
            ],
          );
        },
      );

      if (result != null && result.isNotEmpty && result != _currentName) {
        if (!mounted) return;
        context.read<ActivitiesBloc>().add(
          UpdateActivityName(activityId: widget.activity.id, newName: result),
        );
        setState(() => _currentName = result);
      }
    } finally {
      textController.dispose();
    }
  }

  Future<void> _showDeleteDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.dlgDeleteTitle),
          content: Text(l10n.dlgDeleteConfirm),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.tertiary.background,
                foregroundColor: AppColors.tertiary.foreground,
              ),
              child: Text(l10n.btnCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.destructive.background,
                foregroundColor: AppColors.destructive.foreground,
              ),
              child: Text(l10n.btnDelete),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      context.read<ActivitiesBloc>().add(
        DeleteActivity(activityId: widget.activity.id),
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).activityDeleteSuccess),
        ),
      );
    }
  }
}
