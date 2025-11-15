import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/bloc/activities_state.dart';
import 'package:furtive/features/activities/pages/activity_detail_page.dart';

class ActivitiesListPage extends StatefulWidget {
  const ActivitiesListPage({super.key});

  @override
  State<ActivitiesListPage> createState() => _ActivitiesListPageState();
}

class _ActivitiesListPageState extends State<ActivitiesListPage> {
  @override
  void initState() {
    super.initState();
    context.read<ActivitiesBloc>().add(const FetchActivities());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActivitiesBloc, ActivitiesState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.errorMessage!.message,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activities'),
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
        ),
        body: BlocBuilder<ActivitiesBloc, ActivitiesState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.activities.isEmpty) {
              return Center(
                child: Text(
                  'No activities found',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.tertiary.foreground,
                  ),
                ),
              );
            }

            return ListView.builder(
              itemCount: state.activities.length,
              itemBuilder: (context, index) {
                final activity = state.activities[index];
                return _buildActivityCard(activity);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildActivityCard(ActivityEntity activity) {
    var title = activity.startedAt.toLocal().toString().substring(0, 19);
    if (activity.name.isNotEmpty && activity.name != "Track") {
      title = activity.name;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.quaternary.background,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          title,
          style: TextStyle(
            color: AppColors.tertiary.foreground,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                _buildStatChip(activity.activeDuration.toHHMMSS()),
                _buildStatChip(
                  '${activity.activeDistanceInKm.toStringAsFixed(1)} km',
                ),
                _buildStatChip(
                  '${activity.activeSpeedKmh.toStringAsFixed(1)} km/h',
                ),
                _buildStatChip(activity.activePaceMinPerKm),
              ],
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: AppColors.tertiary.foreground,
          size: 16,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActivityDetailPage(activity: activity),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.primary.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
