import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/km_splits_chart.dart';
import 'package:furtive/l10n/app_localizations.dart';

/// Widget coverage for the splits chart.
///
/// The pure ranking helper was already unit-tested; the 108-line widget around
/// it — bar scaling, the pace/speed toggle, the degenerate-split rendering and
/// the non-finite guards — was at 9.3%. Each of those guards exists because a
/// specific bad input produced either a wrong label or a thrown
/// FractionallySizedBox, so they are worth exercising rather than trusting.
void main() {
  final start = DateTime.utc(2026, 7, 26, 10);

  /// Builds an activity whose active track covers [kmCount] kilometres, each
  /// taking `secondsPerKm[i]` — so pace and speed per split are deterministic.
  ActivityEntity activityWithSplits(List<int> secondsPerKm) {
    // ~0.0001 deg latitude is ~11.1 m; walk in a straight line north so
    // distance is a clean function of the number of steps.
    const stepsPerKm = 90; // 90 * 11.1 m ~= 1 km
    const degPerStep = 0.0001;
    final points = <ActivityPointEntity>[];
    var lat = 48.0;
    var time = start;

    points.add(
      ActivityPointEntity(
        position: PositionEntity(latitude: lat, longitude: 2.0, elevation: 0),
        time: time,
        status: ActivityPointStatusEntity.active,
      ),
    );
    for (final seconds in secondsPerKm) {
      final perStep = Duration(
        microseconds: (seconds * 1000000 / stepsPerKm).round(),
      );
      for (var i = 0; i < stepsPerKm; i++) {
        lat += degPerStep;
        time = time.add(perStep);
        points.add(
          ActivityPointEntity(
            position: PositionEntity(
              latitude: lat,
              longitude: 2.0,
              elevation: 0,
            ),
            time: time,
            status: ActivityPointStatusEntity.active,
          ),
        );
      }
    }

    return ActivityEntity(
      id: 'splits',
      name: 'Track',
      description: '',
      createdAt: start,
      startedAt: start,
      stoppedAt: time,
      points: points,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    ActivityEntity activity, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: MaterialApp(
          theme: appTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: KmSplitsChart(activity: activity),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an activity too short for a single split shows a placeholder', (
    tester,
  ) async {
    final tooShort = ActivityEntity(
      id: 'tiny',
      name: 'Track',
      description: '',
      createdAt: start,
      startedAt: start,
      stoppedAt: start,
      points: [
        ActivityPointEntity(
          position: PositionEntity(latitude: 48, longitude: 2, elevation: 0),
          time: start,
          status: ActivityPointStatusEntity.active,
        ),
      ],
    );
    await pump(tester, tooShort);
    expect(find.text('Not enough data for splits yet.'), findsOneWidget);
  });

  testWidgets('one row per split, labelled by kilometre', (tester) async {
    await pump(tester, activityWithSplits([300, 330, 360]));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('pace is the default metric and renders as m:ss /km', (
    tester,
  ) async {
    await pump(tester, activityWithSplits([300, 360]));
    // 300 s/km = 5:00, 360 s/km = 6:00. Allow a neighbouring second for the
    // interpolation at the km boundary.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('/km') ?? false),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('switching to speed re-labels every row in km/h', (tester) async {
    await pump(tester, activityWithSplits([300, 360]));
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('km/h') ?? false),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('km/h') ?? false),
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('/km') ?? false),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'the fastest and slowest bars get distinct colours, and they SWAP when the '
    'metric flips — a smaller pace is fast, a smaller speed is slow',
    (tester) async {
      // km 1 fast (4:00), km 2 slow (8:00), km 3 middling.
      await pump(tester, activityWithSplits([240, 480, 360]));

      Set<Color> barColours() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => (d.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toSet();

      final pace = barColours();
      expect(
        pace,
        containsAll([
          AppColors.primary.background,
          AppColors.destructive.background,
        ]),
        reason: 'fastest in primary, slowest in destructive',
      );

      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();

      // Both extremes must still be present — if the comparison direction did
      // not flip with the metric, the same split would be labelled fastest
      // under both metrics, which is the bug this guards.
      expect(
        barColours(),
        containsAll([
          AppColors.primary.background,
          AppColors.destructive.background,
        ]),
      );
    },
  );

  testWidgets(
    'a trailing partial kilometre is labelled by distance, not index',
    (tester) async {
      // Two full km plus ~0.5 km.
      final activity = activityWithSplits([300, 300]);
      final extended = ActivityEntity(
        id: activity.id,
        name: activity.name,
        description: '',
        createdAt: activity.createdAt,
        startedAt: activity.startedAt,
        stoppedAt: activity.stoppedAt,
        points: [
          ...activity.points,
          // 45 more steps ~= 0.5 km
          for (var i = 1; i <= 45; i++)
            ActivityPointEntity(
              position: PositionEntity(
                latitude: activity.points.last.position.latitude + i * 0.0001,
                longitude: 2.0,
                elevation: 0,
              ),
              time: activity.points.last.time.add(Duration(seconds: i * 3)),
              status: ActivityPointStatusEntity.active,
            ),
        ],
      );

      await pump(tester, extended);
      // The partial row shows a fractional distance like "0.50" rather than "3".
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('.') ?? false) &&
              w.data!.length == 4,
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('a degenerate zero-duration split renders "--" instead of a '
      'bogus pace, and is not ranked as the fastest', (tester) async {
    // Duplicate timestamps: only reachable via a pathological GPX import, but
    // it produced a 0-value split that sorted as the fastest kilometre.
    final points = <ActivityPointEntity>[];
    var lat = 48.0;
    for (var i = 0; i <= 180; i++) {
      points.add(
        ActivityPointEntity(
          position: PositionEntity(latitude: lat, longitude: 2.0, elevation: 0),
          // Every point shares the same instant for the first km.
          time: i <= 90 ? start : start.add(Duration(seconds: (i - 90) * 4)),
          status: ActivityPointStatusEntity.active,
        ),
      );
      lat += 0.0001;
    }
    await pump(
      tester,
      ActivityEntity(
        id: 'degenerate',
        name: 'Track',
        description: '',
        createdAt: start,
        startedAt: start,
        stoppedAt: points.last.time,
        points: points,
      ),
    );

    expect(find.text('--'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflowing at a 2x system font scale', (
    tester,
  ) async {
    await pump(
      tester,
      activityWithSplits([300, 330]),
      textScaler: const TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
  });
}
