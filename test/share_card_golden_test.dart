import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/share_card.dart';
import 'package:furtive/l10n/app_localizations.dart';

/// Golden coverage for the share card.
///
/// This widget is rendered OFFSCREEN at a fixed 1080x1350 and captured straight
/// to a PNG the user posts publicly — they never see it on screen first. It is
/// therefore the one widget in the app where a layout regression is both
/// invisible during development and permanent once shared, and the only one
/// where a pixel comparison is clearly worth its maintenance cost.
///
/// The RTL and large-font variants exist because the app ships 26 locales
/// (including Arabic) and the card is now pinned to TextScaler.noScaling — the
/// large-font golden is what proves that pin actually holds.
///
/// Regenerate deliberately with: flutter test --update-goldens
void main() {
  ActivityEntity buildActivity() {
    final start = DateTime.utc(2026, 7, 26, 8, 30);
    // A small L-shaped route with a steady 1 m/s pace, so distance, duration and
    // the drawn polyline are all deterministic.
    final points = <ActivityPointEntity>[];
    for (var i = 0; i < 40; i++) {
      points.add(
        ActivityPointEntity(
          position: PositionEntity(
            latitude: 48.85 + i * 0.0002,
            longitude: 2.35 + (i < 20 ? 0 : (i - 20) * 0.0002),
            elevation: 30 + i * 0.5,
          ),
          time: start.add(Duration(seconds: i * 10)),
          status: ActivityPointStatusEntity.active,
        ),
      );
    }
    return ActivityEntity(
      id: 'golden',
      name: 'Morning run',
      description: '',
      createdAt: start,
      startedAt: start,
      stoppedAt: points.last.time,
      points: points,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(ShareCard.width, ShareCard.height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: MaterialApp(
          theme: appTheme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: direction,
            child: SizedBox(
              width: ShareCard.width,
              height: ShareCard.height,
              child: ShareCard(activity: buildActivity()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('share card renders as expected (ltr)', (tester) async {
    await pumpCard(tester);
    await expectLater(
      find.byType(ShareCard),
      matchesGoldenFile('goldens/share_card_ltr.png'),
    );
  });

  testWidgets('share card renders as expected (rtl, arabic)', (tester) async {
    await pumpCard(
      tester,
      direction: TextDirection.rtl,
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(ShareCard),
      matchesGoldenFile('goldens/share_card_rtl.png'),
    );
  });

  testWidgets(
    'a 3x system font scale does not change the card — TextScaler.noScaling '
    'keeps the exported PNG identical for every user',
    (tester) async {
      await pumpCard(tester, textScaler: const TextScaler.linear(3));
      await expectLater(
        find.byType(ShareCard),
        matchesGoldenFile('goldens/share_card_ltr.png'),
      );
    },
  );
}
