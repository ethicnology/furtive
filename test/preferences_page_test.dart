import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/features/preferences/page.dart';
import 'package:furtive/l10n/app_localizations.dart';

import 'support/fakes.dart';

/// Widget coverage for the auto-apply flow.
///
/// There is no Apply button: every change is persisted as soon as the
/// control moves. The failed-save case is still the reason this file exists
/// — with no Apply spinner to absorb a failure, the page must report it and
/// the control must roll back to the value that is actually stored, or the
/// UI would show a setting that never landed.
class _FailingPreferencesRepository extends PreferencesRepository {
  _FailingPreferencesRepository(LocalDatabase db)
    : super(local: PreferencesLocalDataSource(db: db));

  @override
  Future<void> store(PreferencesEntity preferences) async {
    throw StateError('disk full');
  }
}

/// The page is pumped with the default (English) localisations, so labels can
/// be looked up directly instead of hardcoding display strings in the test.
final enLocalizations = lookupAppLocalizations(const Locale('en'));

void main() {
  late LocalDatabase db;

  setUp(() {
    db = inMemoryDatabase();
    if (getIt.isRegistered<LocaleCubit>()) getIt.unregister<LocaleCubit>();
    getIt.registerSingleton<LocaleCubit>(LocaleCubit(null));
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  Future<void> pumpPage(WidgetTester tester, PreferencesRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PreferencesPage(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The lock-screen switch specifically. Every other control on this page
  /// (map theme, map tiles) makes PreferencesBloc reach into the service
  /// locator for MapBloc to re-init the map, which would turn a preferences
  /// test into a test that has to stand up the GPS stack. This toggle only
  /// calls LockScreenFacade, which is a no-op off Android.
  ///
  /// Located by its label rather than by position: this used to be "the last
  /// switch", which silently started pointing at a different setting the
  /// moment one was added below it.
  Finder lockScreenSwitch() => find.ancestor(
    of: find.text(enLocalizations.prefShowOnLockScreen),
    matching: find.byType(SwitchListTile),
  );

  testWidgets('toggling a switch persists immediately, with no Apply button', (
    tester,
  ) async {
    final repo = PreferencesRepository(
      local: PreferencesLocalDataSource(db: db),
    );
    await pumpPage(tester, repo);

    expect(
      find.text('Apply'),
      findsNothing,
      reason: 'changes apply on their own now',
    );

    await tester.ensureVisible(lockScreenSwitch());
    await tester.pumpAndSettle();
    await tester.tap(lockScreenSwitch());
    await tester.pumpAndSettle();

    expect(
      (await repo.fetch()).showOnLockScreen,
      isFalse,
      reason: 'the write lands without any further interaction',
    );
    // The page stays open: there is nothing left to confirm.
    expect(find.byType(PreferencesPage), findsOneWidget);
  });

  testWidgets(
    'a failed auto-save reports the failure and rolls the control back to '
    'the persisted value',
    (tester) async {
      await pumpPage(tester, _FailingPreferencesRepository(db));

      await tester.ensureVisible(lockScreenSwitch());
      await tester.pumpAndSettle();
      await tester.tap(lockScreenSwitch());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(lockScreenSwitch());
      expect(
        tile.value,
        isTrue,
        reason: 'the write never landed, so the UI must not claim it did',
      );
    },
  );

  testWidgets('rapid successive toggles persist in order — last one wins', (
    tester,
  ) async {
    // The gated repository holds the first write in flight while the second
    // toggle is already queued: this is the race the serialised write queue
    // exists for — the older snapshot must not land after the newer one.
    final repo = _SlowPreferencesRepository(db);
    await pumpPage(tester, repo);

    await tester.ensureVisible(lockScreenSwitch());
    await tester.pumpAndSettle();
    await tester.tap(lockScreenSwitch()); // off; its write is gated
    await tester.pumpAndSettle(); // optimistic UI shows off, write in flight
    await tester.tap(lockScreenSwitch()); // on again; queued behind the first
    await tester.pump();
    repo.complete(); // release both writes, in dispatch order
    await tester.pumpAndSettle();

    expect((await repo.fetch()).showOnLockScreen, isTrue);
  });
}

/// Storage whose first write only completes when the test says so, so two
/// auto-applied writes can be forced to overlap.
class _SlowPreferencesRepository extends PreferencesRepository {
  _SlowPreferencesRepository(LocalDatabase db)
    : super(local: PreferencesLocalDataSource(db: db));

  final _gate = Completer<void>();

  void complete() => _gate.complete();

  @override
  Future<void> store(PreferencesEntity preferences) async {
    await _gate.future;
  }
}
