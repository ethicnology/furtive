/// Activity profiles: what the user picks, and what the recorder does with it.
///
/// Two levels, though the split is now thinner than it was:
///
///  * [ActivityTypeEntity] is the *label* — what the user chose, what the
///    activity list shows, what a GPX export carries.
///  * [MovementProfileEntity] is the *behaviour* — how fast the thing plausibly
///    moves and how often it is worth asking the GNSS chip.
///
/// This started at 25 types over 10 profiles, modelled on the public
/// taxonomies (Strava groups sports into foot/cycle/water/winter/other, Health
/// Connect enumerates ~60 exercise types, OsmAnd ships car/bike/walk/boat/
/// aircraft/train). That was the wrong instinct, for a reason specific to how
/// this data is stored: drift's `textEnum` keeps the enum *name* in a plain
/// TEXT column with no CHECK constraint, so **adding** a value costs no
/// migration at all, while **removing** one strands every stored row that
/// holds it. Cheap to add, expensive to remove — so the right starting point
/// is the smallest set that is certainly needed, extended on demand.
///
/// Fourteen of the original types were also pure labels: kayak, canoe,
/// paddleboard and rowing produced a bit-identical recording, as did the three
/// snow sports and the three motor types. Twenty-five choices yielded ten
/// behaviours, at six mapping sites per entry.
///
/// The type/profile split therefore now maps almost one-to-one, and its
/// remaining value is forward-looking: a future "mountain bike" or "trail run"
/// label attaches to an existing profile without inventing new constants.
library;

/// What the user selects before recording and sees afterwards.
enum ActivityTypeEntity {
  walk,
  run,
  bike,
  car,
  swim,
  aircraft,

  /// Anything not listed. Deliberately present: it is what makes the short
  /// list safe. Dropping kayak, ski and hiking is only defensible because
  /// there is a neutral, permissive choice to fall back on — without it a
  /// kayaker would have to pick a profile that is actively wrong.
  other,

  /// Activities recorded before profiles existed, and GPX imports whose file
  /// carries no usable type. NOT offered in the picker: it exists so a
  /// migration never has to guess what a past recording was. Behaves as
  /// [MovementProfileEntity.generic].
  unknown;

  MovementProfileEntity get movementProfile => switch (this) {
    walk => MovementProfileEntity.slowGround,
    run => MovementProfileEntity.running,
    bike => MovementProfileEntity.humanWheels,
    car => MovementProfileEntity.road,
    swim => MovementProfileEntity.swimming,
    aircraft => MovementProfileEntity.air,
    other || unknown => MovementProfileEntity.generic,
  };
}

/// How a thing moves, from the receiver's point of view.
enum MovementProfileEntity {
  slowGround,
  running,
  humanWheels,
  road,
  swimming,
  air,
  generic;

  /// Default tuning.
  ///
  /// These numbers are **estimates**, not measured constants, and are labelled
  /// as such deliberately. An attempt to derive the sampling intervals from
  /// first principles was abandoned once the underlying literature was
  /// checked: Ranacher et al., "Why GPS makes distances bigger than they are"
  /// (IJGIS 30(2), 2016, arXiv:1504.04504) confirms that measurement error
  /// biases recorded distance *upward*, and that this dominates at high
  /// sampling frequency — but also that the bias depends on the
  /// autocorrelation of that error, which is strong in real pedestrian and car
  /// traces and largely cancels along a trajectory. A back-of-envelope model
  /// assuming independent errors overstates the effect badly.
  ///
  /// The same work names the opposing error: interpolation, i.e. the straight
  /// line between two fixes cutting corners, which biases distance *downward*
  /// and grows as sampling gets sparser. There is an optimum rather than a
  /// monotonic rule, so the intervals below are left at their current values
  /// until measured against a route of known length. Read-side smoothing is
  /// the approach that attacks the measurement bias without paying the
  /// corner-cutting penalty.
  MovementTuning get tuning => switch (this) {
    slowGround => const MovementTuning(
      baseInterval: Duration(seconds: 3),
      plausibleSpeedMps: 6, // ~22 km/h, covers a stumble or a jog
      accuracyToleranceMeters: 40,
      navigationKind: NavigationKind.fitness,
    ),
    running => const MovementTuning(
      baseInterval: Duration(seconds: 1),
      plausibleSpeedMps: 12.5, // ~45 km/h, above any human sprint
      accuracyToleranceMeters: 35,
      navigationKind: NavigationKind.fitness,
    ),
    humanWheels => const MovementTuning(
      baseInterval: Duration(seconds: 1),
      plausibleSpeedMps: 36, // ~130 km/h, a fast descent
      accuracyToleranceMeters: 35,
      navigationKind: NavigationKind.fitness,
    ),
    road => const MovementTuning(
      baseInterval: Duration(seconds: 1),
      plausibleSpeedMps: 97, // ~350 km/h, unrestricted autobahn and then some
      accuracyToleranceMeters: 50,
      navigationKind: NavigationKind.automotive,
    ),
    swimming => const MovementTuning(
      baseInterval: Duration(seconds: 3),
      // ~14 km/h. The 50 m freestyle world record is close to 2.4 m/s, so this
      // leaves generous room for a current or a tow.
      plausibleSpeedMps: 4,
      // Deliberately the loosest tolerance of any human-powered profile.
      // Garmin's own guidance on open-water swims is explicit about why: "the
      // GPS signal cannot travel through water and the watch is repeatedly
      // submerged while swimming". A tolerance sized for a runner would reject
      // essentially every fix of a swim.
      accuracyToleranceMeters: 60,
      navigationKind: NavigationKind.otherNavigation,
    ),
    air => const MovementTuning(
      baseInterval: Duration(seconds: 5),
      plausibleSpeedMps: 361, // ~1300 km/h
      accuracyToleranceMeters: 100,
      navigationKind: NavigationKind.airborne,
    ),
    generic => const MovementTuning(
      baseInterval: Duration(seconds: 2),
      // No meaningful ceiling for "we don't know what this is": anything below
      // orbital velocity is allowed through rather than guessed at. This is
      // what carries every activity the short list drops — a kayak, a ski run,
      // a train — so it must not be opinionated.
      plausibleSpeedMps: 361,
      accuracyToleranceMeters: 60,
      navigationKind: NavigationKind.other,
    ),
  };
}

/// Platform-neutral spelling of the five behaviours Core Location exposes.
/// Mapped to `geolocator`'s `ActivityType` in LocationGpsDataSource; Android
/// has no equivalent knob and ignores it.
enum NavigationKind { fitness, automotive, otherNavigation, airborne, other }

/// How densely to sample. The user-facing knob, deliberately expressed as an
/// intent rather than a number of seconds: on iOS there is no interval setting
/// at all, and on Android the interval is a *requested* rate the OS is free to
/// miss, so a raw "every N seconds" field would promise something no platform
/// guarantees.
enum RecordingDetailEntity {
  /// Denser than the profile default — sharper corners, more battery.
  precise,

  /// The profile default.
  balanced,

  /// Sparser than the profile default, for all-day recordings.
  endurance;

  /// Multiplier applied to [MovementTuning.baseInterval].
  double get intervalFactor => switch (this) {
    precise => 0.5,
    balanced => 1,
    endurance => 3,
  };
}

/// The tuning constants a [MovementProfileEntity] implies.
class MovementTuning {
  const MovementTuning({
    required this.baseInterval,
    required this.plausibleSpeedMps,
    required this.accuracyToleranceMeters,
    required this.navigationKind,
  });

  /// Requested spacing between fixes before [RecordingDetailEntity] is applied.
  final Duration baseInterval;

  /// Ground speed above which a fix stops looking like movement and starts
  /// looking like multipath. NOT a hard rejection ceiling: exceeding it makes a
  /// fix *suspicious*, and GpsQualityFilter re-anchors after a few consecutive
  /// suspicions so a genuinely fast vehicle can never be filtered into silence.
  /// That distinction is the whole point — the previous single 35 m/s ceiling
  /// rejected every fix of a car above 126 km/h, permanently, because a
  /// rejection did not move the comparison anchor.
  final double plausibleSpeedMps;

  /// Horizontal accuracy above which a fix is treated as too vague to trust.
  final double accuracyToleranceMeters;

  final NavigationKind navigationKind;

  /// Whether a fix carries enough horizontal precision to contribute to the
  /// recorded trace. A missing estimate stays usable: null means the provider
  /// did not report quality, not that it reported poor quality.
  bool acceptsAccuracy(double? accuracy) =>
      accuracy == null || accuracy <= accuracyToleranceMeters;

  Duration intervalFor(RecordingDetailEntity detail) => Duration(
    milliseconds: (baseInterval.inMilliseconds * detail.intervalFactor).round(),
  );
}
