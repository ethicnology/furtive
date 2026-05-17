import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/export_activity_to_gpx_use_case.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

class ActivityDetailPage extends StatefulWidget {
  final ActivityEntity activity;

  const ActivityDetailPage({super.key, required this.activity});

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  final _mapController = MapController();
  final _getMapConfigUseCase = GetMapConfigUseCase();
  final _exportActivityToGpxUseCase = ExportActivityToGpxUseCase();
  Style? _mapStyle;
  bool _isLoading = true;
  late String _currentName;

  @override
  void initState() {
    super.initState();
    _currentName = widget.activity.name;
    _loadMapStyle();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentName),
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
            onPressed: _isLoading ? null : _exportToGpx,
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
                                initialCenter:
                                    widget.activity.points.isNotEmpty
                                        ? widget.activity.points.first.position
                                            .toLatLng()
                                        : const LatLng(48.8566, 2.3522),
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
                                if (widget.activity.points.isNotEmpty)
                                  widget.activity.toPolylineLayer(),
                              ],
                            )
                            : const Center(child: Text('Failed to load map')),
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
                      label: const Text('View Statistics'),
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
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.3,
            decoration: BoxDecoration(
              color: AppColors.tertiary.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: ActivityStatsWidget(
              activity: activity,
              elapsedTime: stoppedAt.difference(activity.startedAt),
            ),
          ),
    );
  }

  Future<void> _exportToGpx() async {
    setState(() => _isLoading = true);

    try {
      await _exportActivityToGpxUseCase(widget.activity.id);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('GPX exported successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showRenameDialog() async {
    // B36: dispose the controller in `finally` to avoid a leak per dialog open.
    final textController = TextEditingController(text: _currentName);
    try {
      final result = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Rename'),
              content: TextField(
                controller: textController,
                decoration: const InputDecoration(labelText: 'Activity name'),
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
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, textController.text),
                  child: const Text('Rename'),
                ),
              ],
            ),
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
      builder:
          (context) => AlertDialog(
            title: const Text('Delete'),
            content: const Text(
              'Are you sure you want to delete this activity?',
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.tertiary.background,
                  foregroundColor: AppColors.tertiary.foreground,
                ),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.destructive.background,
                  foregroundColor: AppColors.destructive.foreground,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (result == true && mounted) {
      context.read<ActivitiesBloc>().add(
        DeleteActivity(activityId: widget.activity.id),
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activity deleted successfully')),
      );
    }
  }
}
