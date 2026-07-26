import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/hold_to_confirm_button.dart';
import 'package:furtive/core/widgets/stat_block.dart';
import 'package:furtive/l10n/app_localizations.dart';

/// Automated accessibility guarantees.
///
/// The palette in theme.dart already documents its WCAG contrast ratios and
/// records colours that were darkened to clear the threshold — but nothing
/// verified that, so a future palette tweak could silently undo the work.
/// These tests use flutter_test's own guideline matchers so contrast, tap-target
/// size and label presence are checked rather than asserted in a comment.
void main() {
  Widget host(Widget child, {TextScaler? textScaler}) {
    return MediaQuery(
      data: MediaQueryData(textScaler: textScaler ?? TextScaler.noScaling),
      child: MaterialApp(
        theme: appTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('HoldToConfirmButton — the only way to stop a recording', () {
    testWidgets('exposes a button role, a label and a hint', (tester) async {
      await tester.pumpWidget(
        host(
          HoldToConfirmButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            shortTapHint: 'Hold to stop',
            onConfirmed: () {},
          ),
        ),
      );

      // A bare GestureDetector — what this used to be — exposes none of this,
      // leaving the Stop control unreachable with a screen reader.
      expect(
        tester.getSemantics(find.byType(HoldToConfirmButton)),
        matchesSemantics(
          isButton: true,
          label: 'Stop',
          hint: 'Hold to stop',
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
    });

    testWidgets('meets the tap-target and labelled-target guidelines', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HoldToConfirmButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            shortTapHint: 'Hold to stop',
            onConfirmed: () {},
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('the label does not overflow at a 2x system font scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 115, // the width MapPage gives the FAB column
            child: HoldToConfirmButton(
              icon: Icons.stop_rounded,
              label: 'Stop',
              shortTapHint: 'Hold to stop',
              onConfirmed: () {},
            ),
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short tap surfaces the discovery hint instead of firing', (
      tester,
    ) async {
      var confirmed = false;
      await tester.pumpWidget(
        host(
          HoldToConfirmButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            shortTapHint: 'Hold to stop',
            onConfirmed: () => confirmed = true,
          ),
        ),
      );

      await tester.tap(find.byType(HoldToConfirmButton));
      await tester.pump();
      expect(confirmed, isFalse, reason: 'a tap must never stop a recording');
      expect(find.text('Hold to stop'), findsOneWidget);
    });

    testWidgets('releasing before the hold completes cancels', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        host(
          HoldToConfirmButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            shortTapHint: 'Hold to stop',
            holdDuration: const Duration(seconds: 3),
            onConfirmed: () => confirmed = true,
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToConfirmButton)),
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });

    testWidgets('holding for the full duration confirms', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        host(
          HoldToConfirmButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            shortTapHint: 'Hold to stop',
            holdDuration: const Duration(seconds: 3),
            onConfirmed: () => confirmed = true,
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToConfirmButton)),
      );
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pumpAndSettle();
      await gesture.up();
      expect(confirmed, isTrue);
    });
  });

  group('theme palette', () {
    testWidgets('body text on the app surface clears the WCAG AA ratio the '
        'palette comments claim', (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Distance 12.34 km'),
              SizedBox(height: 8),
              StatBlock(
                icon: Icons.straighten,
                label: 'DISTANCE',
                value: '12.34 km',
              ),
            ],
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });
}
