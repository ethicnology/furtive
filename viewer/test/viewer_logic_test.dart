import 'package:furtive_leaflet_viewer/viewer_logic.dart';
import 'package:furtive_share/furtive_share.dart';
import 'package:nostr/nostr.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes browser and copied fragment forms', () {
    expect(normalizeShareFragment(' #/v1.a.b.c/ '), '#v1.a.b.c');
    expect(normalizeShareFragment('%2Fv1.a.b.c'), '#v1.a.b.c');
    expect(normalizeShareFragment(''), isEmpty);
  });

  test('fragment diagnostics disclose shape, not content', () {
    final shape = shareFragmentShape('#v1.publisher.secret.relays');

    expect(shape, 'length 27, 4 segments, segment lengths 2/9/6/6');
    expect(shape, isNot(contains('secret')));
  });

  test('duration and pace carry rounded seconds correctly', () {
    expect(formatViewerDuration(const Duration(seconds: 65)), '01:05');
    expect(
      formatViewerDuration(const Duration(hours: 1, seconds: 5)),
      '1:00:05',
    );
    expect(
      formatViewerPace(
        distanceMeters: 998.33,
        elapsed: const Duration(seconds: 359),
      ),
      '6:00',
    );
    expect(
      formatViewerPace(distanceMeters: 0, elapsed: Duration.zero),
      '--:--',
    );
  });

  test('display reduction keeps endpoints and status boundaries', () {
    final start = DateTime.utc(2026);
    final points = [
      for (var i = 0; i < 20; i++)
        SharePosition(
          time: start.add(Duration(seconds: i)),
          latitude: 45 + i / 1000,
          longitude: -73,
          status: i == 9
              ? SharePointStatus.signalLost
              : SharePointStatus.active,
        ),
    ];

    final reduced = reduceTrackForDisplay(points, maxPoints: 5);

    expect(reduced.first, same(points.first));
    expect(reduced.last, same(points.last));
    expect(reduced, contains(same(points[9])));
    expect(reduced, contains(same(points[10])));
  });

  group('viewer track state', () {
    final now = DateTime.utc(2026, 7, 31, 12);

    ShareUpdate updateAt(
      DateTime time, {
      double distance = 100,
      Duration elapsed = const Duration(minutes: 1),
    }) => ShareUpdate(
      position: SharePosition(
        time: time,
        latitude: 45,
        longitude: -73,
        status: SharePointStatus.active,
      ),
      startedAt: DateTime.utc(2026, 7, 31, 10),
      distanceMeters: distance,
      elapsed: elapsed,
    );

    test('rejects stale and implausibly future positions', () {
      final state = ViewerTrackState();
      expect(
        state.add(
          updateAt(
            now.subtract(viewerMaximumUpdateAge + const Duration(seconds: 1)),
          ),
          now: now,
        ),
        ViewerUpdateResult.tooOld,
      );
      expect(
        state.add(
          updateAt(
            now.add(viewerMaximumFutureSkew + const Duration(seconds: 1)),
          ),
          now: now,
        ),
        ViewerUpdateResult.tooFarInFuture,
      );
      expect(state.points, isEmpty);
    });

    test('deduplicates bootstrap/live overlap and keeps totals monotonic', () {
      final state = ViewerTrackState();
      final latest = updateAt(
        now,
        distance: 500,
        elapsed: const Duration(minutes: 5),
      );
      expect(state.add(latest, now: now), ViewerUpdateResult.accepted);
      expect(state.add(latest, now: now), ViewerUpdateResult.duplicate);
      expect(
        state.add(
          updateAt(now.subtract(const Duration(seconds: 10)), distance: 100),
          now: now,
        ),
        ViewerUpdateResult.accepted,
      );
      expect(state.points, hasLength(2));
      expect(state.lastFixAt, now);
      expect(state.distanceMeters, 500);
      expect(state.elapsed, const Duration(minutes: 5));
      expect(state.startedAt, DateTime.utc(2026, 7, 31, 10));
    });

    test('keeps status boundaries that share one millisecond', () {
      final state = ViewerTrackState();
      final active = updateAt(now);
      final boundary = ShareUpdate(
        position: SharePosition(
          time: now,
          latitude: 45,
          longitude: -73,
          status: SharePointStatus.signalLost,
        ),
        startedAt: DateTime.utc(2026, 7, 31, 10),
        distanceMeters: 100,
        elapsed: const Duration(minutes: 1),
      );
      expect(state.add(active, now: now), ViewerUpdateResult.accepted);
      expect(state.add(boundary, now: now), ViewerUpdateResult.accepted);
      expect(state.points, hasLength(2));
    });

    test('uses the transmitted start across a long pause', () {
      final state = ViewerTrackState();
      final resumedAt = now.subtract(const Duration(minutes: 1));
      final update = updateAt(resumedAt, elapsed: const Duration(minutes: 5));

      expect(state.add(update, now: now), ViewerUpdateResult.accepted);
      expect(state.startedAt, DateTime.utc(2026, 7, 31, 10));
      expect(
        state.startedAt,
        isNot(resumedAt.subtract(const Duration(minutes: 5))),
      );
    });
  });

  test(
    'permanent relay rejection prefixes are distinguished from retryable ones',
    () {
      expect(isPermanentRelayClosure('auth-required: login'), isTrue);
      expect(isPermanentRelayClosure('restricted: sign up'), isTrue);
      expect(isPermanentRelayClosure('rate-limited: slow down'), isFalse);
    },
  );

  test('relay ingress is bounded by queue depth and window rate', () {
    final now = DateTime.utc(2026, 7, 31, 12);
    final limiter = RelayIngressLimiter(
      maxQueuedFrames: 2,
      maxFramesPerWindow: 3,
    );
    expect(limiter.admit(now), RelayIngressDecision.accepted);
    expect(limiter.admit(now), RelayIngressDecision.accepted);
    expect(limiter.admit(now), RelayIngressDecision.queueFull);
    limiter.didDequeue();
    expect(limiter.admit(now), RelayIngressDecision.accepted);
    limiter.didDequeue();
    expect(limiter.admit(now), RelayIngressDecision.rateLimited);
    expect(
      limiter.admit(now.add(const Duration(seconds: 10))),
      RelayIngressDecision.accepted,
    );
  });

  test('nostr deserialization rejects a forged signature', () {
    final event = Event.from(
      kind: shareLiveKind,
      content: 'ciphertext',
      secretKey: Keys.generate().secret,
    );
    final frame = event.serialize().replaceFirst('ciphertext', 'tampered');
    expect(
      () => Message.deserialize(frame),
      throwsA(isA<EventValidationException>()),
    );
  });
}
