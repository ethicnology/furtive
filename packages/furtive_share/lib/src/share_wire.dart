import 'dart:convert';

/// Raised when something arriving from a relay, or from a share link, does not
/// match the v1 wire contract in docs/SHARE-TRACKING.md.
///
/// Every failure here is attacker-reachable: a relay can return anything, and a
/// link can be hand-edited. So parsing refuses rather than coerces, and the
/// message never echoes the offending value — a malformed link may contain key
/// material, and this app exports its logs.
class ShareFormatException implements Exception {
  const ShareFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether a shared point was recorded while moving, while paused, or as a
/// boundary of a GPS outage.
///
/// Mirrors ActivityPointStatusEntity, and is deliberately a separate type. Two
/// reasons, the second one being the load-bearing one:
///
///  * ActivityPointStatusEntity lives in activity_entity.dart, which imports
///    geolocator and dart_mappable — neither belongs in a viewer that only
///    draws a line.
///  * A rename in the domain layer must not silently change what goes over the
///    wire. Viewers are already-opened browser tabs and links pasted into
///    conversations: they cannot be migrated. This is the same reasoning that
///    makes ActivityTypeColumn a separate enum from ActivityTypeEntity for
///    on-disk data (see preferences_model.dart) — applied to the wire, where
///    it matters more, because we control neither side's deployment.
///
/// The wire spelling is a single letter because it is sent every few seconds.
enum SharePointStatus {
  active('a'),
  paused('p'),
  signalLost('s');

  const SharePointStatus(this.wire);

  /// The single-character form used in JSON. Part of the v1 contract: never
  /// change one of these without bumping the link version.
  final String wire;

  static SharePointStatus fromWire(String value) => switch (value) {
    'a' => SharePointStatus.active,
    'p' => SharePointStatus.paused,
    's' => SharePointStatus.signalLost,
    // No default-to-active: an unknown status means the sender speaks a
    // dialect we do not, and guessing would draw a solid line through
    // something that was never recorded.
    _ => throw const ShareFormatException('unknown point status'),
  };
}

/// One position as it travels to an observer.
///
/// Keys are terse (`t`, `y`, `x`, …) because this is the payload that repeats:
/// NIP-44 pads to a power-of-two bucket, so shaving the envelope genuinely
/// changes which bucket a position update lands in.
///
/// `y`/`x` rather than `lat`/`lon`: the pair reads as (latitude, longitude)
/// everywhere in this codebase, and abbreviating to `la`/`lo` invites exactly
/// the transposition bug that a two-letter difference hides.
class SharePosition {
  const SharePosition({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.elevation,
    this.accuracy,
  });

  /// When the fix was obtained, always UTC.
  final DateTime time;
  final double latitude;
  final double longitude;
  final SharePointStatus status;

  /// Metres above the ellipsoid, or null when the platform did not report it.
  final double? elevation;

  /// Horizontal accuracy in metres, or null when unknown. Forwarded so the
  /// viewer can draw the same uncertainty the recorder saw, rather than
  /// implying a precision nobody measured.
  final double? accuracy;

  Map<String, Object?> toJson() => {
    't': time.toUtc().millisecondsSinceEpoch,
    'y': latitude,
    'x': longitude,
    's': status.wire,
    if (elevation != null) 'e': elevation,
    if (accuracy != null) 'a': accuracy,
  };

  void validate() {
    final millis = time.toUtc().millisecondsSinceEpoch;
    if (millis < 0 || millis > _maxTimeMillis) {
      throw ArgumentError.value(time, 'time', 'is outside the v1 range');
    }
    _validateFinite(latitude, 'latitude', min: -90, max: 90);
    _validateFinite(longitude, 'longitude', min: -180, max: 180);
    if (elevation != null) {
      _validateFinite(elevation!, 'elevation', min: -500, max: 20000);
    }
    if (accuracy != null) {
      _validateFinite(accuracy!, 'accuracy', min: 0, max: 100000);
    }
  }

  static SharePosition fromJson(Map<String, Object?> json) => SharePosition(
    time: DateTime.fromMillisecondsSinceEpoch(
      _readInt(json, 't', min: 0, max: _maxTimeMillis),
      isUtc: true,
    ),
    latitude: _readFinite(json, 'y', min: -90, max: 90),
    longitude: _readFinite(json, 'x', min: -180, max: 180),
    status: SharePointStatus.fromWire(_readString(json, 's')),
    // Bounded, not merely finite: 1e300 is a perfectly finite elevation that
    // would wreck a chart axis, and a negative accuracy is not a radius.
    elevation: _readOptionalFinite(json, 'e', min: -500, max: 20000),
    accuracy: _readOptionalFinite(json, 'a', min: 0, max: 100000),
  );
}

/// A single update pushed to observers: where the sharer is, plus the running
/// totals so the viewer displays the same figures as the phone.
///
/// Totals are sent rather than recomputed because a viewer sees a sampled
/// subset of the track — ephemeral events it missed are gone, and summing what
/// it did receive would under-report distance and quietly disagree with the
/// recorder's own screen.
///
/// There is no sequence number. Relays may deliver out of order and the
/// observer sorts by [SharePosition.time], which it needs to do anyway to merge
/// the addressable bootstrap event with the live stream. Exact de-duplication
/// also includes status and coordinates because signal-boundary points may
/// share a millisecond.
class ShareUpdate {
  const ShareUpdate({
    required this.position,
    required this.startedAt,
    required this.distanceMeters,
    required this.elapsed,
  });

  final SharePosition position;

  /// Wall-clock start of the recording. This cannot be reconstructed from
  /// [elapsed], which excludes pauses.
  final DateTime startedAt;

  /// Active distance so far, in metres — excluding paused and signal-lost
  /// stretches, exactly as the app computes it.
  final double distanceMeters;

  /// Active elapsed time so far.
  final Duration elapsed;

  /// Private on purpose: [encode] is the only way an update leaves this class.
  ///
  /// A public `toJson` is a footgun here — `jsonEncode(update.toJson())` looks
  /// like the obvious serialisation and silently skips the padding, which
  /// reinstates the ciphertext-length leak measured below. Making it
  /// unreachable is cheaper than documenting the trap.
  Map<String, Object?> _toJson() => {
    'v': 1,
    'p': position.toJson(),
    'b': startedAt.toUtc().millisecondsSinceEpoch,
    'd': distanceMeters,
    'el': elapsed.inSeconds,
  };

  void validate() {
    position.validate();
    final startedMillis = startedAt.toUtc().millisecondsSinceEpoch;
    if (startedMillis < 0 || startedMillis > _maxTimeMillis) {
      throw ArgumentError.value(
        startedAt,
        'startedAt',
        'is outside the v1 range',
      );
    }
    _validateFinite(distanceMeters, 'distanceMeters', min: 0, max: 40075000);
    if (elapsed.isNegative || elapsed.inSeconds > _maxElapsedSeconds) {
      throw ArgumentError.value(elapsed, 'elapsed', 'is outside the v1 range');
    }
  }

  /// Serialised form handed to NIP-44 for encryption, padded to a constant
  /// length.
  ///
  /// NIP-44 pads to 32-byte buckets, which is not enough here. Measured without
  /// this: a fresh share encrypts to 220 characters and one a few kilometres in
  /// to 260, because the distance and elapsed numbers grow digits and the
  /// optional fields come and go. That lets a relay operator — who sees every
  /// ciphertext — tell a share that just started from one well underway, and
  /// watch it progress, without decrypting anything.
  ///
  /// Padding to a fixed length puts every update in one bucket, so every
  /// ciphertext is the same size. The filler goes in an unknown key, which
  /// [decode] already ignores along with any other key it does not recognise.
  String encode() {
    validate();
    final base = jsonEncode(_toJson());
    // The exact cost of adding `,"z":""` to the object.
    const overhead = 7;
    final filler = _paddedPlaintextLength - base.length - overhead;
    // A payload longer than the target is not padded rather than truncated:
    // losing a position to hide its size is the wrong trade, and the comment
    // above stops being true silently. The margin is wide enough that this needs
    // a format change to happen.
    if (filler < 0) {
      throw StateError('validated update exceeds the v1 padding envelope');
    }
    return jsonEncode({..._toJson(), 'z': ''.padRight(filler, 'x')});
  }

  static ShareUpdate decode(String plaintext) {
    final Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } on FormatException {
      throw const ShareFormatException('update is not valid JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ShareFormatException('update is not a JSON object');
    }
    // Refuse a version we do not know rather than parsing it hopefully: a
    // future v2 may reuse a key with a different meaning.
    final version = _readInt(decoded, 'v');
    if (version != 1) {
      throw const ShareFormatException('unsupported update version');
    }
    final position = decoded['p'];
    if (position is! Map<String, Object?>) {
      throw const ShareFormatException('update has no position object');
    }
    return ShareUpdate(
      position: SharePosition.fromJson(position),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(decoded, 'b', min: 0, max: _maxTimeMillis),
        isUtc: true,
      ),
      distanceMeters: _readFinite(decoded, 'd', min: 0, max: 40075000),
      elapsed: Duration(
        seconds: _readInt(decoded, 'el', min: 0, max: _maxElapsedSeconds),
      ),
    );
  }
}

/// Bounded recent history stored in the addressable bootstrap event.
///
/// Sixty samples represent ten minutes at the v1 live cadence. The plaintext is
/// padded independently from live updates so a relay cannot infer how many
/// samples the snapshot currently contains.
class ShareSnapshot {
  ShareSnapshot(Iterable<ShareUpdate> updates)
    : updates = List.unmodifiable(updates) {
    if (this.updates.isEmpty) {
      throw ArgumentError.value(updates, 'updates', 'must not be empty');
    }
    if (this.updates.length > maxUpdates) {
      throw ArgumentError.value(
        this.updates.length,
        'updates',
        'must contain at most $maxUpdates updates',
      );
    }
  }

  static const int maxUpdates = 60;
  static const int _paddedPlaintextLength = 12288;

  final List<ShareUpdate> updates;

  String encode() {
    for (final update in updates) {
      update.validate();
    }
    final body = <String, Object?>{
      'v': 1,
      'u': [for (final update in updates) update._toJson()],
    };
    final base = jsonEncode(body);
    const overhead = 7;
    final filler = _paddedPlaintextLength - base.length - overhead;
    if (filler < 0) {
      throw StateError('validated snapshot exceeds the v1 padding envelope');
    }
    return jsonEncode({...body, 'z': ''.padRight(filler, 'x')});
  }

  static ShareSnapshot decode(String plaintext) {
    final Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } on FormatException {
      throw const ShareFormatException('snapshot is not valid JSON');
    }
    if (decoded is! Map<String, Object?> || _readInt(decoded, 'v') != 1) {
      throw const ShareFormatException('unsupported snapshot');
    }
    final rawUpdates = decoded['u'];
    if (rawUpdates is! List ||
        rawUpdates.isEmpty ||
        rawUpdates.length > maxUpdates) {
      throw const ShareFormatException('snapshot update count is out of range');
    }
    final updates = <ShareUpdate>[];
    for (final value in rawUpdates) {
      if (value is! Map<String, Object?>) {
        throw const ShareFormatException('snapshot contains an invalid update');
      }
      updates.add(ShareUpdate.decode(jsonEncode(value)));
    }
    return ShareSnapshot(updates);
  }
}

/// Every update is padded to this many characters before encryption, so that
/// ciphertext length carries no information. Chosen with headroom: the largest
/// worst case the field bounds allow measures 139 characters (see the test), and
/// 192 is itself a NIP-44 bucket
/// boundary, so the padded plaintext is not padded again.
const int _paddedPlaintextLength = 192;

/// Latest instant the wire accepts, 2100-01-01Z in unix milliseconds.
///
/// Not paranoia about the year 2100: an observer sorts the track by timestamp,
/// so a single point claiming the year 5138 pins itself to the end of the trace
/// for the whole session and cannot be dislodged.
const int _maxTimeMillis = 4102444800000;

/// 30 days. Longer than any recording, shorter than the nonsense a negative or
/// unbounded value produces — a negative elapsed makes the viewer compute a
/// negative pace, which renders as a plausible-looking number.
const int _maxElapsedSeconds = 30 * 24 * 60 * 60;

/// Reads an integer, accepting the same values on the VM and on the web.
///
/// dart2js has a single number type, so `60.0` satisfies `is int` there while
/// the VM sees a double and refuses it. The publisher runs on the VM and the
/// viewer in a browser: parsing must not depend on which one decoded the JSON,
/// or a payload accepted by the phone would be rejected by the observer for
/// reasons neither could see.
int _readInt(Map<String, Object?> json, String key, {int? min, int? max}) {
  final value = json[key];
  final int result;
  if (value is int) {
    result = value;
  } else if (value is double &&
      value.isFinite &&
      value == value.roundToDouble()) {
    result = value.toInt();
  } else {
    throw ShareFormatException('"$key" must be an integer');
  }
  if ((min != null && result < min) || (max != null && result > max)) {
    throw ShareFormatException('"$key" is out of range');
  }
  return result;
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw ShareFormatException('"$key" must be a string');
}

/// Reads a number and rejects NaN, infinities and out-of-range values.
///
/// A non-finite coordinate is not cosmetic: it poisons MapLibre's camera and
/// every later gesture throws (see MapLibreMapView.moveTo, which carries the
/// belt to this braces). Refusing at the parse boundary keeps that guarantee
/// on the viewer side, where the data is fully untrusted.
double _readFinite(
  Map<String, Object?> json,
  String key, {
  required double min,
  required double max,
}) {
  final value = json[key];
  if (value is! num) throw ShareFormatException('"$key" must be a number');
  final result = value.toDouble();
  if (!result.isFinite) {
    throw ShareFormatException('"$key" must be finite');
  }
  if (result < min || result > max) {
    throw ShareFormatException('"$key" is out of range');
  }
  return result;
}

/// Optional fields degrade instead of failing.
///
/// Absent and "present but nonsense" are different, but neither is usable, and
/// an unusable optional must not cost the observer the position it came with: a
/// garbled elevation is worth dropping, not worth losing the fix over. The
/// required fields above take the opposite stance, because a position without
/// coordinates is not a position.
double? _readOptionalFinite(
  Map<String, Object?> json,
  String key, {
  required double min,
  required double max,
}) {
  final value = json[key];
  if (value is! num) return null;
  final result = value.toDouble();
  if (!result.isFinite || result < min || result > max) return null;
  return result;
}

void _validateFinite(
  double value,
  String name, {
  required double min,
  required double max,
}) {
  if (!value.isFinite || value < min || value > max) {
    throw ArgumentError.value(value, name, 'is outside the v1 range');
  }
}
