import 'package:furtive_share/furtive_share.dart';

const viewerMaximumUpdateAge = Duration(minutes: 15);
const viewerMaximumFutureSkew = Duration(minutes: 2);

enum ViewerUpdateResult { accepted, duplicate, tooOld, tooFarInFuture }

enum RelayIngressDecision { accepted, rateLimited, queueFull }

/// Bounds work accepted from one untrusted relay.
class RelayIngressLimiter {
  RelayIngressLimiter({
    this.window = const Duration(seconds: 10),
    this.maxFramesPerWindow = 128,
    this.maxQueuedFrames = 64,
  });

  final Duration window;
  final int maxFramesPerWindow;
  final int maxQueuedFrames;

  DateTime? _windowStartedAt;
  int _framesInWindow = 0;
  int _queuedFrames = 0;

  RelayIngressDecision admit(DateTime now) {
    final startedAt = _windowStartedAt;
    if (startedAt == null ||
        now.isBefore(startedAt) ||
        now.difference(startedAt) >= window) {
      _windowStartedAt = now;
      _framesInWindow = 0;
    }
    if (_framesInWindow >= maxFramesPerWindow) {
      return RelayIngressDecision.rateLimited;
    }
    if (_queuedFrames >= maxQueuedFrames) {
      return RelayIngressDecision.queueFull;
    }
    _framesInWindow++;
    _queuedFrames++;
    return RelayIngressDecision.accepted;
  }

  void didDequeue() {
    if (_queuedFrames > 0) _queuedFrames--;
  }
}

bool isPermanentRelayClosure(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('auth-required') ||
      normalized.contains('restricted') ||
      normalized.contains('blocked');
}

class ViewerTrackState {
  ViewerTrackState({this.maxRetainedPoints = 10000});

  final int maxRetainedPoints;
  final Map<String, SharePosition> _points = {};

  double distanceMeters = 0;
  Duration elapsed = Duration.zero;
  DateTime? startedAt;
  DateTime? lastFixAt;

  /// Whether the publisher said the share is over.
  ///
  /// Latched: it never reverts, because a relay replaying an older event must
  /// not resurrect a finished share.
  bool finished = false;

  List<SharePosition> get points {
    final result = _points.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  ViewerUpdateResult add(ShareUpdate update, {required DateTime now}) {
    // Read before every filter below. The end of a share is session state, not a
    // property of the point carrying it, and the final update deliberately
    // repeats the last known position — so the position itself is a duplicate
    // and gets dropped. Reading the flag afterwards would lose it every time.
    if (update.finished) finished = true;

    final timestamp = update.position.time.toUtc();
    final age = now.toUtc().difference(timestamp);
    if (age > viewerMaximumUpdateAge) return ViewerUpdateResult.tooOld;
    if (age < -viewerMaximumFutureSkew) {
      return ViewerUpdateResult.tooFarInFuture;
    }

    final key =
        '${timestamp.millisecondsSinceEpoch}:${update.position.status.wire}:'
        '${update.position.latitude}:${update.position.longitude}';
    if (_points.containsKey(key)) return ViewerUpdateResult.duplicate;
    _points[key] = update.position;
    if (_points.length > maxRetainedPoints) {
      final oldest = _points.entries.reduce(
        (a, b) => a.value.time.isBefore(b.value.time) ? a : b,
      );
      _points.remove(oldest.key);
    }

    if (update.distanceMeters > distanceMeters) {
      distanceMeters = update.distanceMeters;
    }
    if (update.elapsed > elapsed) elapsed = update.elapsed;
    final candidateStart = update.startedAt.toUtc();
    if (startedAt == null || candidateStart.isBefore(startedAt!)) {
      startedAt = candidateStart;
    }
    if (lastFixAt == null || timestamp.isAfter(lastFixAt!)) {
      lastFixAt = timestamp;
    }
    return ViewerUpdateResult.accepted;
  }
}

String normalizeShareFragment(String input) {
  var value = input.trim();
  if (value.startsWith('#')) value = value.substring(1);
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    // ShareLink.parse reports the malformed input without guessing.
  }
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.isEmpty ? '' : '#$value';
}

String shareFragmentShape(String fragment) {
  final descriptor = fragment.startsWith('#')
      ? fragment.substring(1)
      : fragment;
  final parts = descriptor.split('.');
  return 'length ${fragment.length}, ${parts.length} segments, '
      'segment lengths ${parts.map((part) => part.length).join('/')}';
}

String formatViewerDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatViewerPace({
  required double distanceMeters,
  required Duration elapsed,
}) {
  if (distanceMeters < 20 || elapsed.inSeconds == 0) return '--:--';
  final secondsPerKm = elapsed.inSeconds / (distanceMeters / 1000);
  if (!secondsPerKm.isFinite) return '--:--';
  var minutes = secondsPerKm ~/ 60;
  var seconds = (secondsPerKm % 60).round();
  if (seconds == 60) {
    minutes++;
    seconds = 0;
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

List<SharePosition> reduceTrackForDisplay(
  List<SharePosition> points, {
  int maxPoints = 2000,
}) {
  if (maxPoints < 2) {
    throw ArgumentError.value(maxPoints, 'maxPoints', 'must be at least two');
  }
  if (points.length <= maxPoints) return points;
  final stride = (points.length / maxPoints).ceil();
  return [
    points.first,
    for (var i = 1; i < points.length - 1; i++)
      if (i % stride == 0 ||
          points[i].status != points[i - 1].status ||
          points[i].status != points[i + 1].status)
        points[i],
    points.last,
  ];
}
