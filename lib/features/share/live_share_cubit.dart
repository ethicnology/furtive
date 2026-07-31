import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';
import 'package:furtive_share/furtive_share.dart';
import 'package:nostr/nostr.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const shareViewerUrl = String.fromEnvironment('SHARE_VIEWER_URL');
const _shareRelayConfig = String.fromEnvironment(
  'SHARE_RELAYS',
  defaultValue: defaultShareRelayConfig,
);

enum LiveShareStatus { idle, starting, active }

class LiveShareState {
  const LiveShareState({
    this.status = LiveShareStatus.idle,
    this.link,
    this.connectedRelays = 0,
    this.totalRelays = 0,
    this.rejectedRelays = 0,
    this.error,
  });

  final LiveShareStatus status;
  final String? link;
  final int connectedRelays;
  final int totalRelays;
  final int rejectedRelays;
  final String? error;

  bool get isActive => status == LiveShareStatus.active;
  bool get isStarting => status == LiveShareStatus.starting;
}

abstract interface class LiveShareRelay {
  Stream<String> get messages;
  void send(String message);
  Future<void> close();
}

typedef LiveShareRelayConnector = Future<LiveShareRelay> Function(String url);

class WebSocketLiveShareRelay implements LiveShareRelay {
  WebSocketLiveShareRelay._(this._channel);

  final WebSocketChannel _channel;

  static Future<LiveShareRelay> connect(String url) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready;
    return WebSocketLiveShareRelay._(channel);
  }

  @override
  Stream<String> get messages =>
      _channel.stream.map((value) => value.toString());

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close() => _channel.sink.close();
}

class LiveShareCubit extends Cubit<LiveShareState> {
  LiveShareCubit({
    required RecordingBloc recording,
    LiveShareRelayConnector? relayConnector,
    Clock? clock,
    Random? random,
    String viewerBase = shareViewerUrl,
    List<String>? relayUrls,
  }) : _recording = recording,
       _connectRelay = relayConnector ?? WebSocketLiveShareRelay.connect,
       _clock = clock ?? const SystemClock(),
       _random = random ?? Random.secure(),
       viewerBase = viewerBase.trim(),
       relayUrls = List.unmodifiable(
         relayUrls ??
             _shareRelayConfig
                 .split(',')
                 .map((relay) => relay.trim())
                 .where((relay) => relay.isNotEmpty),
       ),
       super(const LiveShareState()) {
    _recordingSubscription = _recording.stream.listen(_onRecordingState);
  }

  static const liveCadence = Duration(seconds: 10);
  static const snapshotCadence = Duration(seconds: 30);
  static const shareLifetime = Duration(hours: 12);

  final RecordingBloc _recording;
  final LiveShareRelayConnector _connectRelay;
  final Clock _clock;
  final Random _random;
  final String viewerBase;
  final List<String> relayUrls;

  late final StreamSubscription<RecordingState> _recordingSubscription;
  final Map<String, LiveShareRelay> _relays = {};
  final Map<String, StreamSubscription<String>> _relaySubscriptions = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Set<String> _rejectedRelays = {};
  _LiveShareSession? _session;
  Future<void> _publishQueue = Future.value();

  bool get isConfigured => viewerBase.isNotEmpty && relayUrls.isNotEmpty;

  Future<String> start({String? password}) async {
    if (state.isActive) return state.link!;
    final activity = _recording.state.activity;
    if (activity == null) {
      throw StateError('Start an activity before sharing it live.');
    }
    if (!isConfigured) {
      throw StateError(
        'Live sharing is not configured in this build (SHARE_VIEWER_URL).',
      );
    }

    emit(
      LiveShareState(
        status: LiveShareStatus.starting,
        totalRelays: relayUrls.length,
      ),
    );
    try {
      final secret = Uint8List.fromList(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      );
      final derived = password == null
          ? deriveShareKeys(shareSecret: secret)
          : await compute(_derivePasswordProtectedKeys, (
              secret: secret,
              password: password,
            ));
      final currentActivity = _recording.state.activity;
      if (currentActivity == null || currentActivity.id != activity.id) {
        throw StateError('The activity ended before live sharing started.');
      }
      final publisher = Keys.generate();
      final link = ShareLink(
        publisherPublicKey: publisher.public,
        shareSecret: secret,
        relays: relayUrls,
        passwordProtected: password != null,
      ).toUri(viewerBase);
      final session = _session = _LiveShareSession(
        activityId: activity.id,
        publisher: publisher,
        recipientPublicKey: derived.recipientPublicKey,
        topic: derived.topic,
        expiresAt: _clock.nowUtc().add(shareLifetime),
        processedPointCount: currentActivity.points.isEmpty
            ? 0
            : currentActivity.points.length - 1,
      );
      emit(
        LiveShareState(
          status: LiveShareStatus.active,
          link: link,
          totalRelays: relayUrls.length,
        ),
      );
      for (final relay in relayUrls) {
        unawaited(_openRelay(session, relay));
      }
      _onRecordingState(_recording.state);
      return link;
    } on Object catch (error, trace) {
      logs.severe('Start live share', error: error, trace: trace);
      _session = null;
      emit(
        LiveShareState(totalRelays: relayUrls.length, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    _session = null;
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final subscription in _relaySubscriptions.values) {
      await subscription.cancel();
    }
    _relaySubscriptions.clear();
    for (final relay in _relays.values) {
      await relay.close();
    }
    _relays.clear();
    _rejectedRelays.clear();
    _reconnectAttempts.clear();
    if (!isClosed) emit(const LiveShareState());
  }

  void clearError() {
    if (state.error == null) return;
    emit(
      LiveShareState(
        status: state.status,
        link: state.link,
        connectedRelays: state.connectedRelays,
        totalRelays: state.totalRelays,
        rejectedRelays: state.rejectedRelays,
      ),
    );
  }

  Future<void> _openRelay(_LiveShareSession session, String url) async {
    if (_session != session || _relays.containsKey(url)) return;
    LiveShareRelay? openedRelay;
    try {
      final relay = await _connectRelay(url);
      openedRelay = relay;
      if (_session != session) {
        await relay.close();
        return;
      }
      _relays[url] = relay;
      _reconnectAttempts[url] = 0;
      _relaySubscriptions[url] = relay.messages.listen(
        (message) => _onRelayMessage(session, url, message),
        onError: (Object error, StackTrace trace) {
          logs.warning(
            'Live share relay disconnected: $url',
            error: error,
            trace: trace,
          );
          _relayClosed(session, url);
        },
        onDone: () => _relayClosed(session, url),
        cancelOnError: true,
      );
      _emitRelayHealth();
      if (session.history.isNotEmpty) {
        await _publishSnapshot(session, onlyRelay: relay);
      }
    } on Object catch (error, trace) {
      logs.warning(
        'Live share relay connection failed: $url',
        error: error,
        trace: trace,
      );
      if (identical(_relays[url], openedRelay)) {
        await _removeRelay(url);
      } else if (openedRelay != null) {
        await openedRelay.close();
      }
      _scheduleReconnect(session, url);
    }
  }

  void _onRelayMessage(_LiveShareSession session, String url, String raw) {
    if (_session != session || raw.length > 64 * 1024) return;
    try {
      final message = Message.deserialize(raw);
      if (message.messageType == MessageType.auth) {
        _rejectRelay(
          session,
          url,
          'Relay requires unsupported NIP-42 auth: $url',
        );
        return;
      }
      if (message.messageType != MessageType.ok) return;
      final result = message.message as CommandResult;
      if (result.status || result.message.startsWith('duplicate:')) return;
      final reason = result.message.toLowerCase();
      if (reason.contains('restricted') ||
          reason.contains('auth-required') ||
          reason.contains('blocked')) {
        _rejectRelay(session, url, 'Relay rejected anonymous publishing: $url');
      } else {
        _emitRelayHealth(error: 'Relay rejected an update: ${result.message}');
      }
    } on Object {
      // A relay is untrusted and may send unrelated or malformed frames.
    }
  }

  void _rejectRelay(_LiveShareSession session, String url, String error) {
    _rejectedRelays.add(url);
    unawaited(_removeRejectedRelay(session, url, error));
  }

  Future<void> _removeRejectedRelay(
    _LiveShareSession session,
    String url,
    String error,
  ) async {
    await _removeRelay(url);
    if (_session == session) _emitRelayHealth(error: error);
  }

  void _relayClosed(_LiveShareSession session, String url) {
    if (_session != session || !_relays.containsKey(url)) return;
    unawaited(_removeRelay(url));
    _scheduleReconnect(session, url);
  }

  Future<void> _removeRelay(String url) async {
    final subscription = _relaySubscriptions.remove(url);
    if (subscription != null) await subscription.cancel();
    final relay = _relays.remove(url);
    if (relay != null) await relay.close();
    _emitRelayHealth();
  }

  void _scheduleReconnect(_LiveShareSession session, String url) {
    if (_session != session ||
        _rejectedRelays.contains(url) ||
        _reconnectTimers.containsKey(url)) {
      return;
    }
    final attempt = (_reconnectAttempts[url] ?? 0) + 1;
    _reconnectAttempts[url] = attempt;
    const delays = [1, 2, 4, 8, 16, 30];
    final delay = delays[(attempt - 1).clamp(0, delays.length - 1)];
    _reconnectTimers[url] = Timer(Duration(seconds: delay), () {
      _reconnectTimers.remove(url);
      unawaited(_openRelay(session, url));
    });
    _emitRelayHealth();
  }

  void _onRecordingState(RecordingState recording) {
    final session = _session;
    final activity = recording.activity;
    if (session == null) return;
    if (activity == null || activity.id != session.activityId) {
      unawaited(stop());
      return;
    }
    if (activity.points.length > session.processedPointCount) {
      final start = session.processedPointCount;
      session.processedPointCount = activity.points.length;
      for (var index = start; index < activity.points.length; index++) {
        final point = activity.points[index];
        final status = _shareStatus(point.status);
        final statusChanged = status != session.lastPublishedStatus;
        final sinceLast = session.lastLiveAt == null
            ? null
            : point.time.difference(session.lastLiveAt!);
        if (!statusChanged && sinceLast != null && sinceLast < liveCadence) {
          continue;
        }

        final partial = activity.copyWith(
          points: activity.points.take(index + 1).toList(growable: false),
        );
        _queueUpdate(
          session,
          ShareUpdate(
            position: SharePosition(
              time: point.time,
              latitude: point.position.latitude,
              longitude: point.position.longitude,
              status: status,
              elevation: point.position.elevation,
              accuracy: point.position.accuracy,
            ),
            startedAt: activity.startedAt,
            distanceMeters: partial.activeDistanceMeters,
            elapsed: partial.activeDuration,
          ),
        );
      }
    }

    final pauseChanged = session.lastRecordingPaused != recording.isPaused;
    session.lastRecordingPaused = recording.isPaused;
    if (!pauseChanged || activity.points.isEmpty) return;
    final status = recording.isPaused
        ? SharePointStatus.paused
        : SharePointStatus.active;
    if (status == session.lastPublishedStatus) return;
    final point = activity.points.last;
    final now = _clock.nowUtc();
    final transitionTime =
        session.lastLiveAt != null && now.isBefore(session.lastLiveAt!)
        ? session.lastLiveAt!
        : now;
    _queueUpdate(
      session,
      ShareUpdate(
        position: SharePosition(
          time: transitionTime,
          latitude: point.position.latitude,
          longitude: point.position.longitude,
          status: status,
          elevation: point.position.elevation,
          accuracy: point.position.accuracy,
        ),
        startedAt: activity.startedAt,
        distanceMeters: activity.activeDistanceMeters,
        elapsed: activity.activeDuration,
      ),
    );
  }

  void _queueUpdate(_LiveShareSession session, ShareUpdate update) {
    session
      ..lastLiveAt = update.position.time
      ..lastPublishedStatus = update.position.status
      ..history.add(update);
    if (session.history.length > ShareSnapshot.maxUpdates) {
      session.history.removeAt(0);
    }
    _publishQueue = _publishQueue
        .catchError((Object error, StackTrace trace) {
          logs.warning('Live share publish', error: error, trace: trace);
        })
        .then((_) => _publishUpdate(session, update));
  }

  Future<void> _publishUpdate(
    _LiveShareSession session,
    ShareUpdate update,
  ) async {
    if (_session != session) return;
    if (!session.expiresAt.isAfter(_clock.nowUtc())) {
      await stop();
      return;
    }
    final content = await encryptShareUpdate(
      update: update,
      publisherSecretKey: session.publisher.secret,
      recipientPublicKey: session.recipientPublicKey,
    );
    _sendEvent(session, kind: shareLiveKind, content: content);

    final sinceSnapshot = session.lastSnapshotAt == null
        ? null
        : update.position.time.difference(session.lastSnapshotAt!);
    if (sinceSnapshot == null || sinceSnapshot >= snapshotCadence) {
      session.lastSnapshotAt = update.position.time;
      await _publishSnapshot(session);
    }
  }

  Future<void> _publishSnapshot(
    _LiveShareSession session, {
    LiveShareRelay? onlyRelay,
  }) async {
    if (_session != session || session.history.isEmpty) return;
    final content = await encryptShareSnapshot(
      snapshot: ShareSnapshot(session.history),
      publisherSecretKey: session.publisher.secret,
      recipientPublicKey: session.recipientPublicKey,
    );
    _sendEvent(
      session,
      kind: shareLastKnownKind,
      content: content,
      onlyRelay: onlyRelay,
    );
  }

  void _sendEvent(
    _LiveShareSession session, {
    required int kind,
    required String content,
    LiveShareRelay? onlyRelay,
  }) {
    if (_session != session) return;
    final event = Event.from(
      kind: kind,
      content: content,
      secretKey: session.publisher.secret,
      tags: shareEventTags(
        topic: session.topic,
        expiresAt: session.expiresAt,
        now: _clock.nowUtc(),
      ),
    );
    final message = event.serialize();
    final targets = onlyRelay == null
        ? _relays.entries.toList(growable: false)
        : _relays.entries
              .where((entry) => identical(entry.value, onlyRelay))
              .toList(growable: false);
    for (final entry in targets) {
      try {
        entry.value.send(message);
      } on Object catch (error, trace) {
        logs.warning(
          'Live share relay send failed: ${entry.key}',
          error: error,
          trace: trace,
        );
        _relayClosed(session, entry.key);
      }
    }
  }

  void _emitRelayHealth({String? error}) {
    if (isClosed || !state.isActive) return;
    emit(
      LiveShareState(
        status: state.status,
        link: state.link,
        connectedRelays: _relays.length,
        totalRelays: relayUrls.length,
        rejectedRelays: _rejectedRelays.length,
        error: error,
      ),
    );
  }

  static SharePointStatus _shareStatus(ActivityPointStatusEntity status) =>
      switch (status) {
        ActivityPointStatusEntity.active => SharePointStatus.active,
        ActivityPointStatusEntity.paused => SharePointStatus.paused,
        ActivityPointStatusEntity.signalLost => SharePointStatus.signalLost,
      };

  @override
  Future<void> close() async {
    await _recordingSubscription.cancel();
    await stop();
    return super.close();
  }
}

ShareKeys _derivePasswordProtectedKeys(
  ({Uint8List secret, String password}) input,
) => deriveShareKeys(shareSecret: input.secret, password: input.password);

class _LiveShareSession {
  _LiveShareSession({
    required this.activityId,
    required this.publisher,
    required this.recipientPublicKey,
    required this.topic,
    required this.expiresAt,
    required this.processedPointCount,
  });

  final String activityId;
  final Keys publisher;
  final String recipientPublicKey;
  final String topic;
  final DateTime expiresAt;
  final List<ShareUpdate> history = [];
  int processedPointCount;
  DateTime? lastLiveAt;
  DateTime? lastSnapshotAt;
  SharePointStatus? lastPublishedStatus;
  bool? lastRecordingPaused;
}
