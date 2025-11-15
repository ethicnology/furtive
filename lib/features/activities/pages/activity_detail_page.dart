import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/export_activity_to_gpx_use_case.dart';
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

  @override
  void initState() {
    super.initState();
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
        title: Text(widget.activity.name),

        actions: [
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToGpx,
            label: const Text('Export'),
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
                    bottom: Global.padding,
                    left: Global.padding,
                    right: Global.padding,
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
    final stoppedAt = activity.stoppedAt ?? activity.points.last.time;

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
}
