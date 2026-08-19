import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

import 'package:furtive_share/furtive_share.dart';
import 'package:furtive_leaflet_viewer/viewer_logic.dart';
import 'package:nostr/nostr.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

const _shareKinds = [shareLiveKind, shareLastKnownKind];
const _maxSeenEvents = 4096;
const _maxRelayFrameCharacters = 64 * 1024;

/// Where the basemap comes from, fixed at compile time.
///
/// The default is same-origin: a self-hosted viewer terminates tiles under its
/// own origin, so the browser contacts no third party and the CSP stays as
/// narrow as it can be. Pointing this at a public basemap is a deliberate
/// privacy trade — tile requests disclose the area being watched to whoever
/// serves them — and `tool/package_viewer.py` then has to widen `img-src` to
/// match. See docs/SHARE-TRACKING.md.
const _tileUrlTemplate = String.fromEnvironment(
  'TILE_URL',
  defaultValue: '/tiles/{z}/{x}/{y}.png',
);

@JS('L.map')
external LeafletMap _createMap(String elementId, JSAny options);

@JS('L.tileLayer')
external LeafletTileLayer _createTileLayer(String url, JSAny options);

@JS('L.polyline')
external LeafletLayer _createPolyline(JSArray<JSAny> points, JSAny options);

@JS('L.circleMarker')
external LeafletMarker _createCircleMarker(
  JSArray<JSNumber> point,
  JSAny options,
);

extension type LeafletMap(JSObject _) implements JSObject {
  external LeafletMap setView(JSArray<JSNumber> center, double zoom);
  external LeafletMap fitBounds(JSArray<JSAny> bounds, JSAny options);
  external LeafletMap panTo(JSArray<JSNumber> center, JSAny options);
  external LeafletMap removeLayer(JSObject layer);
  external LeafletBounds getBounds();
  external LeafletMap on(String event, JSFunction callback);
}

extension type LeafletBounds(JSObject _) implements JSObject {
  external LeafletBounds pad(double amount);
  external bool contains(JSArray<JSNumber> point);
}

extension type LeafletLayer(JSObject _) implements JSObject {
  external LeafletLayer addTo(LeafletMap map);
}

extension type LeafletTileLayer(JSObject _) implements JSObject {
  external LeafletTileLayer addTo(LeafletMap map);
  external LeafletTileLayer on(String event, JSFunction callback);
}

extension type LeafletMarker(JSObject _) implements JSObject {
  external LeafletMarker addTo(LeafletMap map);
  external LeafletMarker setLatLng(JSArray<JSNumber> point);
}

void main() {
  unawaited(LiveViewer().start());
}

class LiveViewer {
  final _startup = Stopwatch()..start();
  final _trackState = ViewerTrackState();
  final _seenEventIds = <String>{};
  final _channels = <String, WebSocketChannel>{};
  final _subscriptions = <String, StreamSubscription<dynamic>>{};
  final _reconnectTimers = <String, Timer>{};
  final _reconnectAttempts = <String, int>{};
  final _relayUp = <String, bool>{};
  final _rejectedRelays = <String>{};
  final _relayMessages = <String, String>{};
  final _frameQueues = <String, ListQueue<String>>{};
  final _frameLimiters = <String, RelayIngressLimiter>{};
  final _drainingRelays = <String>{};
  final _lineLayers = <LeafletLayer>[];

  late final web.HTMLElement _loading = _element('map-loading');
  late final web.HTMLElement _loadingLabel = _element('map-loading-label');
  late final web.HTMLElement _fatal = _element('fatal');
  late final web.HTMLElement _fatalTitle = _element('fatal-title');
  late final web.HTMLElement _fatalDetail = _element('fatal-detail');
  late final web.HTMLElement _freshness = _element('freshness');
  late final web.HTMLElement _liveBadge = _element('live-badge');
  late final web.HTMLElement _relays = _element('relays');
  late final web.HTMLElement _distanceElement = _element('distance');
  late final web.HTMLElement _durationElement = _element('duration');
  late final web.HTMLElement _paceElement = _element('pace');
  late final web.HTMLElement _startedElement = _element('started');
  late final web.HTMLElement _privacy = _element('privacy');
  late final web.HTMLElement _activityNote = _element('activity-note');
  late final web.HTMLButtonElement _mapButton = _button('map-toggle');
  late final web.HTMLButtonElement _followButton = _button('follow-toggle');
  late final web.HTMLFormElement _passwordPrompt =
      _element('password-prompt') as web.HTMLFormElement;
  late final web.HTMLInputElement _passwordInput =
      _element('share-password') as web.HTMLInputElement;
  late final web.HTMLElement _passwordError = _element('password-error');

  ShareLink? _link;
  ShareKeys? _keys;
  LeafletMap? _map;
  LeafletTileLayer? _tileLayer;
  LeafletMarker? _positionMarker;
  Timer? _clock;
  Timer? _tileFallback;
  Completer<String>? _passwordCompleter;
  String? _subscriptionRequest;

  bool _tiles = true;
  bool _following = true;
  bool _tilesReady = false;
  bool _trackVisible = false;
  bool _stopping = false;
  List<SharePosition> get _track => _trackState.points;

  Future<void> start() async {
    try {
      await _start();
    } on Object catch (error) {
      _log('Viewer startup failed: ${error.runtimeType}');
      _showFatal(
        'The viewer could not start',
        detail: error.runtimeType.toString(),
      );
    }
  }

  Future<void> _start() async {
    _bindControls();
    _log('Dart viewer ready');
    _clock = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _renderStatus(),
    );

    final href = web.window.location.href;
    final hashIndex = href.indexOf('#');
    final locationHash = web.window.location.hash;
    final capturedFragment = locationHash.isNotEmpty
        ? locationHash
        : hashIndex < 0
        ? ''
        : href.substring(hashIndex);
    final fragment = normalizeShareFragment(capturedFragment);
    _log('Fragment captured (${fragment.length} characters)');
    if (fragment.isEmpty) {
      _showFatal('This link is incomplete');
      return;
    }
    try {
      _link = ShareLink.parse(fragment);
      _log('Share link decoded');
    } on Object catch (error) {
      final shape = shareFragmentShape(fragment);
      _log('Share link rejected: ${error.runtimeType}: $error ($shape)');
      _showFatal('This link is not valid', detail: '$error · $shape');
      return;
    }
    String? password;
    if (_link!.passwordProtected) {
      password = await _requestPassword();
      _loadingLabel.textContent = 'Deriving encryption keys';
      _loading.classList.remove('hidden');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      _keys = deriveShareKeys(
        shareSecret: _link!.shareSecret,
        password: password,
      );
      _log('Share keys derived');
    } on Object catch (error) {
      _log('Key derivation failed: ${error.runtimeType}');
      _showFatal(
        'This browser could not open the encrypted link',
        detail: error.runtimeType.toString(),
      );
      return;
    }

    _subscriptionRequest = Request(
      subscriptionId: 'furtive-live',
      filters: [
        Filter(
          authors: [_link!.publisherPublicKey],
          kinds: _shareKinds,
          tagFilters: {
            'd': [_keys!.topic],
          },
          limit: 80,
        ),
      ],
    ).serialize();

    for (final url in _link!.relays) {
      _relayUp[url] = false;
      _connectRelay(url);
    }
    _renderStatus();
  }

  void _bindControls() {
    _mapButton.addEventListener(
      'click',
      ((web.Event _) => _toggleTiles()).toJS,
    );
    _followButton.addEventListener(
      'click',
      ((web.Event _) => _resumeFollowing()).toJS,
    );
    _passwordPrompt.addEventListener(
      'submit',
      ((web.Event event) {
        event.preventDefault();
        final password = _passwordInput.value;
        if (password.isEmpty) {
          _passwordError.removeAttribute('hidden');
          return;
        }
        _passwordError.setAttribute('hidden', '');
        _passwordPrompt.setAttribute('hidden', '');
        final completer = _passwordCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(password);
        }
        _passwordInput.value = '';
      }).toJS,
    );
    web.window.addEventListener(
      'beforeunload',
      ((web.Event _) => _stop()).toJS,
    );
  }

  Future<String> _requestPassword() {
    _loading.classList.add('hidden');
    _passwordPrompt.removeAttribute('hidden');
    _passwordInput.focus();
    return (_passwordCompleter = Completer<String>()).future;
  }

  void _connectRelay(String url) {
    if (_stopping || _channels.containsKey(url)) return;
    final request = _subscriptionRequest;
    if (request == null) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channels[url] = channel;
      _subscriptions[url] = channel.stream.listen(
        (dynamic raw) {
          _enqueueFrame(url, raw.toString());
        },
        onError: (Object _) => _relayDisconnected(url, channel),
        onDone: () => _relayDisconnected(url, channel),
        cancelOnError: true,
      );
      channel.sink.add(request);
    } on Object {
      _channels.remove(url);
      _subscriptions.remove(url);
      _scheduleReconnect(url);
    }
  }

  void _relayDisconnected(String url, WebSocketChannel channel) {
    if (!identical(_channels[url], channel)) return;
    _channels.remove(url);
    _subscriptions.remove(url);
    _clearRelayIngress(url);
    _setRelay(url, false);
    _scheduleReconnect(url);
  }

  void _scheduleReconnect(String url) {
    if (_stopping ||
        _rejectedRelays.contains(url) ||
        _reconnectTimers.containsKey(url)) {
      return;
    }
    final attempt = (_reconnectAttempts[url] ?? 0) + 1;
    _reconnectAttempts[url] = attempt;
    const delays = [1, 2, 4, 8, 16, 30];
    final seconds = delays[(attempt - 1).clamp(0, delays.length - 1)];
    _reconnectTimers[url] = Timer(Duration(seconds: seconds), () {
      _reconnectTimers.remove(url);
      _connectRelay(url);
    });
  }

  void _stop() {
    if (_stopping) return;
    _stopping = true;
    _clock?.cancel();
    _tileFallback?.cancel();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final channel in _channels.values) {
      unawaited(channel.sink.close());
    }
    _channels.clear();
    _frameQueues.clear();
    _frameLimiters.clear();
    _drainingRelays.clear();
  }

  void _enqueueFrame(String url, String raw) {
    if (_stopping || !_channels.containsKey(url)) return;
    if (raw.length > _maxRelayFrameCharacters) {
      _rejectRelay(url, 'blocked: relay frame exceeded 64 KiB');
      return;
    }
    final limiter = _frameLimiters.putIfAbsent(url, RelayIngressLimiter.new);
    final decision = limiter.admit(DateTime.now().toUtc());
    if (decision != RelayIngressDecision.accepted) {
      _rejectRelay(
        url,
        decision == RelayIngressDecision.rateLimited
            ? 'blocked: relay sent too many frames'
            : 'blocked: relay frame queue overflowed',
      );
      return;
    }
    _frameQueues.putIfAbsent(url, ListQueue<String>.new).add(raw);
    if (_drainingRelays.add(url)) unawaited(_drainRelay(url));
  }

  Future<void> _drainRelay(String url) async {
    try {
      final queue = _frameQueues[url];
      final limiter = _frameLimiters[url];
      while (!_stopping &&
          _channels.containsKey(url) &&
          queue != null &&
          queue.isNotEmpty) {
        final raw = queue.removeFirst();
        limiter?.didDequeue();
        await _onFrame(url, raw);
      }
    } finally {
      _drainingRelays.remove(url);
      final queue = _frameQueues[url];
      if (!_stopping &&
          _channels.containsKey(url) &&
          queue != null &&
          queue.isNotEmpty &&
          _drainingRelays.add(url)) {
        unawaited(_drainRelay(url));
      }
    }
  }

  void _clearRelayIngress(String url) {
    _frameQueues.remove(url);
    _frameLimiters.remove(url);
    _drainingRelays.remove(url);
  }

  void _rejectRelay(String url, String reason) {
    _relayMessages[url] = reason;
    _rejectedRelays.add(url);
    _clearRelayIngress(url);
    final subscription = _subscriptions.remove(url);
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channels.remove(url);
    if (channel != null) unawaited(channel.sink.close());
    _setRelay(url, false);
    _renderStatus();
  }

  Future<void> _onFrame(String url, String raw) async {
    if (raw.length > _maxRelayFrameCharacters) {
      _log('Relay frame refused: too large');
      return;
    }
    final Message message;
    try {
      message = Message.deserialize(raw);
    } on Object {
      return;
    }

    if (message.messageType == MessageType.closed) {
      final body = message.message as Map<String, dynamic>;
      _handleRelayClosed(
        url,
        body['message']?.toString() ?? 'subscription closed',
      );
      return;
    }
    if (message.messageType == MessageType.eose) {
      _reconnectAttempts[url] = 0;
      _setRelay(url, true);
      return;
    }
    if (message.messageType == MessageType.auth) {
      _rejectRelay(url, 'auth-required: NIP-42 is not supported');
      return;
    }
    if (message.messageType == MessageType.notice) {
      _setRelay(url, true);
      return;
    }
    if (message.messageType != MessageType.event) return;

    _reconnectAttempts[url] = 0;
    _setRelay(url, true);
    final event = message.message as Event;

    if (event.pubkey != _link!.publisherPublicKey) return;
    if (!_shareKinds.contains(event.kind)) return;
    final dTag = event.tags.firstWhere(
      (tag) => tag.isNotEmpty && tag.first == 'd',
      orElse: () => const <String>[],
    );
    if (dTag.length < 2 || dTag[1] != _keys!.topic) return;
    if (!_seenEventIds.add(event.id)) return;
    if (_seenEventIds.length > _maxSeenEvents) {
      _seenEventIds.remove(_seenEventIds.first);
    }

    final List<ShareUpdate> updates;
    try {
      if (event.kind == shareLastKnownKind) {
        updates = (await decryptShareSnapshot(
          payload: event.content,
          recipientSecretKey: _keys!.recipientSecretKey,
          publisherPublicKey: _link!.publisherPublicKey,
        )).updates;
      } else {
        updates = [
          await decryptShareUpdate(
            payload: event.content,
            recipientSecretKey: _keys!.recipientSecretKey,
            publisherPublicKey: _link!.publisherPublicKey,
          ),
        ];
      }
    } on Object {
      return;
    }

    try {
      final firstPosition = _track.isEmpty;
      final wasFinished = _trackState.finished;
      var accepted = false;
      final now = DateTime.now().toUtc();
      for (final update in updates) {
        if (_trackState.add(update, now: now) == ViewerUpdateResult.accepted) {
          accepted = true;
        }
      }
      // The final update repeats the last position, so it is a duplicate and
      // accepts nothing. Render the badge on the flag alone, or the observer
      // waits for the next clock tick to learn the share ended.
      if (_trackState.finished != wasFinished) _renderStatus();
      if (!accepted) return;

      if (firstPosition) {
        _log('First position decrypted');
        _ensureMap();
      }
      _renderTelemetry();
      if (_trackVisible) _renderTrack();
      final latest = _track.lastOrNull;
      if (latest != null) _follow(latest);
    } on Object catch (error) {
      _log('Viewer update failed: ${error.runtimeType}');
    }
  }

  void _handleRelayClosed(String url, String reason) {
    final permanent = isPermanentRelayClosure(reason);
    _relayMessages[url] = reason.length > 160
        ? reason.substring(0, 160)
        : reason;
    if (permanent) _rejectedRelays.add(url);

    final subscription = _subscriptions.remove(url);
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channels.remove(url);
    if (channel != null) unawaited(channel.sink.close());
    _clearRelayIngress(url);
    _setRelay(url, false);
    if (!permanent) _scheduleReconnect(url);
  }

  void _ensureMap() {
    if (_map != null) return;
    final track = _track;
    final latest = track.last;
    final map = _map = _createMap(
      'map',
      <String, Object>{'zoomControl': true, 'preferCanvas': true}.jsify()!,
    ).setView(_latLng(latest), 16);
    map.on(
      'dragstart',
      ((JSAny? _) {
        if (_following) {
          _following = false;
          _renderButtons();
        }
      }).toJS,
    );
    _log('Leaflet map created');

    if (track.length > 1) {
      map.fitBounds(
        <JSAny>[for (final point in track) _latLng(point)].toJS,
        <String, Object>{
          'padding': [48, 48],
          'maxZoom': 16,
        }.jsify()!,
      );
    }
    _installTiles();
  }

  void _installTiles() {
    final map = _map;
    if (map == null || !_tiles || _tileLayer != null) return;
    final tileLayer = _tileLayer = _createTileLayer(
      _tileUrlTemplate,
      <String, Object>{
        'maxZoom': 19,
        'keepBuffer': 1,
        'updateWhenIdle': true,
        'attribution': 'OpenStreetMap contributors, CARTO',
      }.jsify()!,
    );
    var firstTile = true;
    tileLayer.on(
      'tileload',
      ((JSAny? _) {
        if (!firstTile) return;
        firstTile = false;
        _loading.classList.add('hidden');
        _log('First tile painted');
      }).toJS,
    );
    tileLayer.on(
      'load',
      ((JSAny? _) {
        if (!_tilesReady) {
          _tilesReady = true;
          _log('Visible tiles painted');
          _showTrack();
        }
      }).toJS,
    );
    tileLayer.addTo(map);
    _loadingLabel.textContent = 'Loading map';
    _tileFallback?.cancel();
    _tileFallback = Timer(const Duration(seconds: 4), _showTrack);
    _log('Basemap requested');
  }

  void _showTrack() {
    if (_trackVisible) return;
    _trackVisible = true;
    _tileFallback?.cancel();
    _loading.classList.add('hidden');
    _renderTrack();
    _log('Track rendered');
  }

  void _renderTrack() {
    final map = _map;
    final track = reduceTrackForDisplay(_track);
    if (map == null || track.isEmpty) return;
    for (final layer in _lineLayers) {
      map.removeLayer(layer);
    }
    _lineLayers.clear();

    for (final segment in _segments(track)) {
      final coordinates = <JSAny>[
        for (final point in segment.points) _latLng(point),
      ].toJS;
      final casing = _createPolyline(
        coordinates,
        <String, Object>{
          'color': '#07100f',
          'weight': segment.status == SharePointStatus.active ? 9 : 8,
          'opacity': .72,
          'lineCap': 'round',
          'lineJoin': 'round',
          if (segment.status == SharePointStatus.signalLost) 'dashArray': '4 8',
        }.jsify()!,
      ).addTo(map);
      final line = _createPolyline(
        coordinates,
        <String, Object>{
          'color': segment.status == SharePointStatus.active
              ? '#53e6cf'
              : '#a7b0bc',
          'weight': segment.status == SharePointStatus.active ? 5 : 4,
          'opacity': segment.status == SharePointStatus.active ? 1 : .7,
          'lineCap': 'round',
          'lineJoin': 'round',
          if (segment.status == SharePointStatus.signalLost) 'dashArray': '4 8',
        }.jsify()!,
      ).addTo(map);
      _lineLayers
        ..add(casing)
        ..add(line);
    }

    final latest = track.last;
    final marker = _positionMarker;
    if (marker == null) {
      _positionMarker = _createCircleMarker(
        _latLng(latest),
        <String, Object>{
          'radius': 7,
          'color': '#f4f7f8',
          'weight': 2,
          'fillColor': '#53e6cf',
          'fillOpacity': 1,
        }.jsify()!,
      ).addTo(map);
    } else {
      marker.setLatLng(_latLng(latest));
    }
  }

  List<_Segment> _segments(List<SharePosition> points) {
    if (points.length < 2) return const [];
    final segments = <_Segment>[];
    var status = points[1].status;
    var positions = <SharePosition>[points[0], points[1]];
    for (var i = 2; i < points.length; i++) {
      final point = points[i];
      if (point.status == status) {
        positions.add(point);
      } else {
        segments.add(_Segment(status, positions));
        status = point.status;
        positions = [points[i - 1], point];
      }
    }
    segments.add(_Segment(status, positions));
    return segments;
  }

  void _follow(SharePosition point, {bool force = false}) {
    final map = _map;
    if (map == null || !_following) return;
    final coordinate = _latLng(point);
    if (!force && map.getBounds().pad(-.22).contains(coordinate)) return;
    map.panTo(
      coordinate,
      <String, Object>{'animate': true, 'duration': .35}.jsify()!,
    );
  }

  void _toggleTiles() {
    final map = _map;
    _tiles = !_tiles;
    if (map != null) {
      final tileLayer = _tileLayer;
      if (_tiles) {
        _tileLayer = null;
        _installTiles();
      } else if (tileLayer != null) {
        map.removeLayer(tileLayer);
        _tileLayer = null;
        _showTrack();
      }
    }
    _renderButtons();
  }

  void _resumeFollowing() {
    _following = true;
    _renderButtons();
    final latest = _track.lastOrNull;
    if (latest != null) _follow(latest, force: true);
  }

  void _setRelay(String url, bool connected) {
    if (_relayUp[url] == connected) return;
    _relayUp[url] = connected;
    if (connected) _log('Relay connected: $url');
    _renderStatus();
  }

  void _renderTelemetry() {
    final distance = _trackState.distanceMeters;
    final elapsed = _trackState.elapsed;
    _distanceElement.textContent = distance < 1000
        ? '${distance.round()} m'
        : '${(distance / 1000).toStringAsFixed(2)} km';
    _durationElement.textContent = formatViewerDuration(elapsed);
    _paceElement.textContent = formatViewerPace(
      distanceMeters: distance,
      elapsed: elapsed,
    );
    final started = _trackState.startedAt?.toLocal();
    _startedElement.textContent = started == null
        ? '--:--'
        : '${started.hour.toString().padLeft(2, '0')}:'
              '${started.minute.toString().padLeft(2, '0')}';

    final latest = _track.lastOrNull;
    _privacy.textContent = latest?.accuracy == null
        ? 'End-to-end encrypted'
        : 'Encrypted · ±${latest!.accuracy!.round()} m';
    final note = switch (latest?.status) {
      SharePointStatus.paused => 'Activity paused',
      SharePointStatus.signalLost => 'GPS signal unavailable',
      _ => null,
    };
    _activityNote.textContent = note ?? '';
    if (note == null) {
      _activityNote.setAttribute('hidden', '');
    } else {
      _activityNote.removeAttribute('hidden');
    }
    _renderStatus();
  }

  void _renderStatus() {
    final last = _trackState.lastFixAt;
    var label = 'WAITING';
    var live = false;
    if (_trackState.finished) {
      // No age counter once it is over: it would only invite the observer to
      // wait for a position that is never coming.
      label = 'ENDED';
    } else if (last != null) {
      final measuredAge = DateTime.now().toUtc().difference(last);
      final age = measuredAge.isNegative ? Duration.zero : measuredAge;
      if (age.inSeconds < 20) {
        label = 'LIVE';
        live = true;
      } else if (age.inMinutes < 1) {
        label = '${age.inSeconds}S AGO';
      } else if (age.inHours < 1) {
        label = '${age.inMinutes} MIN AGO';
      } else {
        label = '${age.inHours} H AGO';
      }
    }
    _freshness.textContent = label;
    _liveBadge.classList.toggle('live', live);
    _liveBadge.classList.toggle('waiting', !live);
    final connected = _relayUp.values.where((value) => value).length;
    final rejected = _rejectedRelays.length;
    _relays.textContent = rejected == 0
        ? '$connected/${_relayUp.length} relays'
        : '$connected/${_relayUp.length} relays · $rejected rejected';
    _relays.title = _relayMessages.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }

  void _renderButtons() {
    _mapButton
      ..classList.toggle('active', _tiles)
      ..setAttribute('aria-pressed', '$_tiles');
    _mapButton.querySelector('.action-label')?.textContent = _tiles
        ? 'Map on'
        : 'Map off';
    _followButton
      ..classList.toggle('active', _following)
      ..setAttribute('aria-pressed', '$_following');
    _followButton.querySelector('.action-label')?.textContent = _following
        ? 'Following'
        : 'Follow';
  }

  void _showFatal(
    String title, {
    String detail =
        'Open the complete share link, including everything after the #.',
  }) {
    _loading.classList.add('hidden');
    _fatalTitle.textContent = title;
    _fatalDetail.textContent = detail;
    _fatal.removeAttribute('hidden');
  }

  void _log(String message) {
    web.console.info(
      '[Furtive Leaflet +${_startup.elapsedMilliseconds}ms] $message'.toJS,
    );
  }

  web.HTMLElement _element(String id) =>
      web.document.getElementById(id)! as web.HTMLElement;

  web.HTMLButtonElement _button(String id) =>
      web.document.getElementById(id)! as web.HTMLButtonElement;

  JSArray<JSNumber> _latLng(SharePosition point) =>
      <JSNumber>[point.latitude.toJS, point.longitude.toJS].toJS;
}

class _Segment {
  const _Segment(this.status, this.points);
  final SharePointStatus status;
  final List<SharePosition> points;
}
