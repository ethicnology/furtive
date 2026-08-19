import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/share/live_share_cubit.dart';
import 'package:furtive_share/furtive_share.dart';
import 'package:nostr/nostr.dart';

import 'support/fakes.dart';

void main() {
  late LocalDatabase db;
  late FixedClock clock;
  late FakeLocationRepository location;
  late RecordingBloc recording;
  late _FakeRelay relay;
  final startedAt = DateTime.utc(2026, 7, 31, 10);

  setUp(() {
    db = inMemoryDatabase();
    clock = FixedClock(startedAt);
    location = FakeLocationRepository(currentLocation: fixAt(startedAt));
    final repository = ActivityRepository(
      local: ActivityLocalDataSource(db: db, clock: clock),
      clock: clock,
    );
    recording = RecordingBloc(
      activities: repository,
      score: ScoreActivityUseCase(activities: repository, clock: clock),
      ensureBackgroundTracking: EnsureBackgroundTrackingUseCase(
        location: location,
      ),
      clock: clock,
    );
    relay = _FakeRelay();
  });

  tearDown(() async {
    await recording.close();
    await location.dispose();
    await db.close();
  });

  Future<void> startRecording() async {
    recording.add(const StartRecording());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(recording.state.isRecording, isTrue);
  }

  LiveShareCubit buildCubit({String viewerBase = 'http://localhost:8080'}) =>
      LiveShareCubit(
        recording: recording,
        relayConnector: (_) async => relay,
        clock: clock,
        random: Random(7),
        viewerBase: viewerBase,
        relayUrls: const ['wss://relay.example'],
      );

  Future<List<ShareUpdate>> decryptLiveUpdates(String link) async {
    final descriptor = ShareLink.parse(link);
    final keys = deriveShareKeys(shareSecret: descriptor.shareSecret);
    final updates = <ShareUpdate>[];
    for (final event in relay.sent.map(Event.deserialize)) {
      if (event.kind != shareLiveKind) continue;
      updates.add(
        await decryptShareUpdate(
          payload: event.content,
          recipientSecretKey: keys.recipientSecretKey,
          publisherPublicKey: descriptor.publisherPublicKey,
        ),
      );
    }
    return updates;
  }

  test('refuses to create a link when the build has no viewer', () async {
    await startRecording();
    final cubit = buildCubit(viewerBase: '');
    addTearDown(cubit.close);

    await expectLater(cubit.start(), throwsStateError);
    expect(cubit.state.isActive, isFalse);
  });

  test('publishes throttled live events and a decryptable snapshot', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final link = await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    for (final seconds in [1, 5, 11, 31]) {
      recording.add(
        ScoreFix(position: fixAt(startedAt.add(Duration(seconds: seconds)))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final events = relay.sent.map(Event.deserialize).toList();
    expect(events.where((event) => event.kind == shareLiveKind), hasLength(3));
    expect(
      events.where((event) => event.kind == shareLastKnownKind),
      hasLength(2),
    );

    final descriptor = ShareLink.parse(link);
    final keys = deriveShareKeys(shareSecret: descriptor.shareSecret);
    final snapshotEvent = events.lastWhere(
      (event) => event.kind == shareLastKnownKind,
    );
    final snapshot = await decryptShareSnapshot(
      payload: snapshotEvent.content,
      recipientSecretKey: keys.recipientSecretKey,
      publisherPublicKey: descriptor.publisherPublicKey,
    );
    expect(snapshot.updates, hasLength(3));
    expect(
      snapshot.updates.last.position.time,
      startedAt.add(const Duration(seconds: 31)),
    );
    expect(snapshot.updates.map((update) => update.startedAt), {startedAt});
    expect(cubit.state.connectedRelays, 1);
  });

  test('password-protected links derive off the UI isolate boundary', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final link = await cubit.start(password: 'separate passphrase');

    expect(ShareLink.parse(link).passwordProtected, isTrue);
    expect(cubit.state.isActive, isTrue);
  });

  test('a recording ending during derivation leaves the share armed', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final starting = cubit.start(password: 'separate passphrase');
    recording.add(const StopRecording());
    final link = await starting;

    // Deriving takes seconds, so the recording can end underneath it. Now that
    // a share may exist without one, that is no longer a failure: it waits.
    expect(ShareLink.parse(link).passwordProtected, isTrue);
    expect(cubit.state.isActive, isTrue);
    expect(relay.sent, isEmpty);
  });

  test('a share can be armed before any activity exists', () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final link = await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.state.isActive, isTrue);
    expect(relay.sent, isEmpty, reason: 'nothing to publish while armed');

    await startRecording();
    recording.add(
      ScoreFix(position: fixAt(startedAt.add(const Duration(seconds: 1)))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final updates = await decryptLiveUpdates(link);
    expect(updates, hasLength(1));
    expect(updates.single.startedAt, startedAt);
    expect(updates.single.finished, isFalse);
  });

  test('stopping announces the end, once, and in the snapshot too', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final link = await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    recording.add(
      ScoreFix(position: fixAt(startedAt.add(const Duration(seconds: 1)))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    recording.add(const StopRecording());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final updates = await decryptLiveUpdates(link);
    expect(updates.last.finished, isTrue);
    expect(
      updates.where((update) => update.finished),
      hasLength(1),
      reason: 'the recording stream keeps emitting; the end is announced once',
    );

    // A viewer opening the link afterwards only has the snapshot to read.
    final descriptor = ShareLink.parse(link);
    final keys = deriveShareKeys(shareSecret: descriptor.shareSecret);
    final snapshotEvent = relay.sent
        .map(Event.deserialize)
        .lastWhere((event) => event.kind == shareLastKnownKind);
    final snapshot = await decryptShareSnapshot(
      payload: snapshotEvent.content,
      recipientSecretKey: keys.recipientSecretKey,
      publisherPublicKey: descriptor.publisherPublicKey,
    );
    expect(snapshot.updates.last.finished, isTrue);

    expect(cubit.state.isActive, isFalse);
    expect(relay.closed, isTrue);
  });

  test('publishes pause and resume without waiting for another fix', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final link = await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    recording.add(
      ScoreFix(position: fixAt(startedAt.add(const Duration(seconds: 1)))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    relay.sent.clear();

    clock.advance(const Duration(seconds: 2));
    recording.add(const PauseRecording());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    clock.advance(const Duration(seconds: 3));
    recording.add(const PauseRecording());
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final updates = await decryptLiveUpdates(link);
    expect(updates.map((update) => update.position.status), [
      SharePointStatus.paused,
      SharePointStatus.active,
    ]);
    expect(updates.map((update) => update.position.time), [
      startedAt.add(const Duration(seconds: 2)),
      startedAt.add(const Duration(seconds: 5)),
    ]);
    expect(updates.map((update) => update.startedAt), {startedAt});
  });

  test('rejects a relay that requests NIP-42 authentication', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    relay.addIncoming('["AUTH","challenge"]');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(relay.closed, isTrue);
    expect(cubit.state.connectedRelays, 0);
    expect(cubit.state.rejectedRelays, 1);
    expect(cubit.state.error, contains('unsupported NIP-42 auth'));
  });

  test('one failed relay does not block healthy relay delivery', () async {
    await startRecording();
    final failed = _FakeRelay(throwOnSend: true);
    final healthy = _FakeRelay();
    final cubit = LiveShareCubit(
      recording: recording,
      relayConnector: (url) async => url.contains('failed') ? failed : healthy,
      clock: clock,
      random: Random(7),
      viewerBase: 'http://localhost:8080',
      relayUrls: const ['wss://failed.example', 'wss://healthy.example'],
    );
    addTearDown(cubit.close);

    await cubit.start();
    recording.add(
      ScoreFix(position: fixAt(startedAt.add(const Duration(seconds: 1)))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(failed.closed, isTrue);
    expect(healthy.sent, isNotEmpty);
    expect(healthy.sent.map(Event.deserialize).first.kind, shareLiveKind);
  });

  test('stopping the recording also stops the share', () async {
    await startRecording();
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    recording.add(const StopRecording());
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(cubit.state.isActive, isFalse);
    expect(relay.closed, isTrue);
  });
}

class _FakeRelay implements LiveShareRelay {
  _FakeRelay({this.throwOnSend = false});

  final _incoming = StreamController<String>.broadcast();
  final List<String> sent = [];
  final bool throwOnSend;
  bool closed = false;

  void addIncoming(String message) => _incoming.add(message);

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (throwOnSend) throw StateError('relay send failed');
    sent.add(message);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _incoming.close();
  }
}
