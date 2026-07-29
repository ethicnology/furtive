import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/position_entity.dart';

/// Ingestion-time quality gate for the continuous tracking stream. Rejects
/// fixes that are more likely GPS noise (multipath, urban canyon reflection,
/// momentary provider glitch) than real movement. The output feeds the map and
/// the recorder, but those consumers have one intentional difference: this
/// stream may occasionally admit a vague fix so the cursor never disappears,
/// while MapBloc applies [MovementTuning.acceptsAccuracy] strictly before an
/// active fix reaches the recorded trace.
///
/// Deliberately conservative: every check only rejects when the platform
/// actually reported the relevant field. A provider that doesn't supply
/// accuracy is never penalised for it — the gate can only get stricter as
/// better metadata becomes available, never block a fix outright for lack of
/// data. See docs/AUDIT-2026-07.md §4.2.
///
/// Thresholds come from [MovementTuning], i.e. from the activity the user
/// picked, because a single set of constants cannot serve a hiker and a car.
/// Two properties matter more than the numbers themselves:
///
///  * **Uncertainty is subtracted before judging speed.** Two consecutive
///    fixes each reported ±10 m can sit 20 m apart with nobody moving; charging
///    that displacement to the mover manufactures teleports at low speed.
///  * **No rejection is permanent.** Every check has an escape hatch, because
///    a filter that can starve its own output is indistinguishable from a dead
///    position stream. After [reanchorAfterSuspiciousFixes] consecutive speed
///    suspicions the filter accepts and re-anchors; after
///    [acceptVagueAfterConsecutiveDrops] consecutive vague fixes it accepts one
///    anyway. Without the former, a sustained speed above the profile's ceiling
///    silences the stream *for as long as it lasts*: the anchor never advances,
///    so every later fix is measured against an ever-more-distant point and
///    keeps failing. That is not hypothetical — the previous single 35 m/s
///    (126 km/h) ceiling did exactly this to a car on a motorway, dropping the
///    entire drive rather than degrading it.
///
/// Stateful (tracks the last *accepted* fix), so use one instance per stream
/// subscription — `LocationRepository.getPositionStream()` creates a fresh
/// one on every call, matching one instance per stream (re)open.
class GpsQualityFilter {
  /// Consecutive speed-suspicious fixes tolerated before the filter concludes
  /// that the movement is real and re-anchors on it. Three at the profile's
  /// interval is long enough that an isolated multipath spike (which is, by
  /// nature, one or two fixes before the receiver recovers) is still dropped,
  /// and short enough that a genuine acceleration past the ceiling costs a
  /// couple of points rather than the rest of the recording.
  static const int reanchorAfterSuspiciousFixes = 3;

  /// Consecutive fixes dropped as [GpsRejectionReason.tooVague] before the
  /// filter accepts one regardless of its accuracy.
  ///
  /// The accuracy check used to be the one path with no escape hatch, which
  /// contradicted this class's own invariant and was observed on device: a
  /// phone indoors reported 67–150 m against a 60 m tolerance and every fix was
  /// dropped, roughly one every two seconds, so the map cursor never moved and
  /// never explained why. A stale position is *definitely* wrong; a vague one is
  /// merely imprecise, and it carries its own accuracy so the UI can draw the
  /// radius and be honest about it.
  ///
  /// Set so the tolerated blind spell is a few dozen seconds at typical
  /// intervals. Note the counter resets on every acceptance, including the
  /// forced one: a sustained bad-signal stretch therefore degrades to roughly
  /// one accepted fix in [acceptVagueAfterConsecutiveDrops], which is the
  /// intended outcome — a slow, visibly imprecise cursor rather than a frozen
  /// one.
  static const int acceptVagueAfterConsecutiveDrops = 5;

  /// Tuning for the activity being recorded. Defaults to the generic profile,
  /// which is intentionally permissive: when the caller does not know what is
  /// moving, refusing to guess is safer than guessing wrong.
  final MovementTuning tuning;

  GpsQualityFilter({MovementTuning? tuning})
    : tuning = tuning ?? MovementProfileEntity.generic.tuning;

  PositionEntity? _lastAccepted;
  int _consecutiveSuspicious = 0;
  int _consecutiveVague = 0;

  /// Why a fix was dropped, for the caller that wants to log or count it.
  /// Fires only for rejections; accepted fixes are silent.
  void Function(PositionEntity position, GpsRejectionReason reason)? onRejected;

  /// Wraps [source], filtering out fixes that fail the quality gate.
  Stream<PositionEntity> apply(Stream<PositionEntity> source) =>
      source.where(_accept);

  bool _reject(PositionEntity position, GpsRejectionReason reason) {
    onRejected?.call(position, reason);
    return false;
  }

  bool _accept(PositionEntity position) {
    if (!tuning.acceptsAccuracy(position.accuracy)) {
      // With no anchor yet, accept immediately whatever the accuracy. This is
      // the cold-start case, and it is the worst one to be strict about: the
      // first fixes after a stream opens are the least accurate the receiver
      // will ever produce, and rejecting them leaves the app with *no* position
      // at all rather than an imprecise one. A ±100 m fix still puts the map on
      // the right block, and the accuracy circle says how much to trust it.
      if (_lastAccepted != null) {
        _consecutiveVague++;
        if (_consecutiveVague < acceptVagueAfterConsecutiveDrops) {
          return _reject(position, GpsRejectionReason.tooVague);
        }
        // Sustained: stop starving the output. Fall through — the speed check
        // below still applies, and its slack term is large precisely because
        // this fix reported poor accuracy, so a vague fix cannot smuggle in a
        // teleport.
      }
    }

    final previous = _lastAccepted;
    if (previous != null && previous.time != null && position.time != null) {
      final dtSeconds =
          position.time!.difference(previous.time!).inMilliseconds / 1000;
      // dtSeconds <= 0: out-of-order/duplicate-timestamp fix (a backlogged
      // fix the OS delivers after the fact — LocationManager does this).
      // Reject it WITHOUT moving _lastAccepted: accepting it would move the
      // teleport anchor backwards in space/time, and
      // score_activity_use_case/activity_entity's mergeSort would later
      // re-order it back into chronological position — splicing a spurious
      // zig-zag (out-and-back) into the trace that inflates
      // activeDistanceMeters, and leaving the *next* genuine fix's speed
      // check comparing against the wrong anchor. Downstream guards handle
      // non-positive deltas for the case where such a fix slips through some
      // other path, but this filter should not be the one letting it back
      // the anchor up.
      if (dtSeconds <= 0) {
        return _reject(position, GpsRejectionReason.outOfOrder);
      }

      final meters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      // Charge only the displacement that exceeds what the two reported
      // accuracy radii can explain on their own. Without this the gate is
      // strictest exactly where fixes are worst — a stationary phone under
      // tree cover jitters tens of metres between fixes.
      final slack = (previous.accuracy ?? 0) + (position.accuracy ?? 0);
      final unexplained = math.max(0.0, meters - slack);
      if (meters.isFinite &&
          (unexplained / dtSeconds) > tuning.plausibleSpeedMps) {
        _consecutiveSuspicious++;
        if (_consecutiveSuspicious < reanchorAfterSuspiciousFixes) {
          // Reject without moving _lastAccepted: keep comparing subsequent
          // fixes against the last known-good anchor rather than chaining
          // off a fix we just decided not to trust.
          return _reject(position, GpsRejectionReason.implausibleSpeed);
        }
        // Sustained: the ceiling was wrong for what is actually happening
        // (wrong profile, a tow, a vehicle). Fall through and re-anchor
        // rather than keep dropping fixes forever.
      }
    }

    _lastAccepted = position;
    _consecutiveSuspicious = 0;
    _consecutiveVague = 0;
    return true;
  }
}

/// Why [GpsQualityFilter] dropped a fix. Exposed so a rejection can be counted
/// and logged: silent dropping is what made a stretched fix cadence
/// indistinguishable from a dead position stream.
enum GpsRejectionReason {
  /// Reported horizontal accuracy exceeded the profile's tolerance.
  tooVague,

  /// Timestamp at or before the last accepted fix (backlogged delivery).
  outOfOrder,

  /// Implied ground speed above the profile's plausible ceiling, and not yet
  /// sustained long enough to be believed.
  implausibleSpeed,
}
