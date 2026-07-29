import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/widgets/activity_type_picker.dart';

void main() {
  group('taxonomy', () {
    test('every activity maps to a movement profile', () {
      // A switch over an enum without a default is a compile-time
      // exhaustiveness check, but only if something calls it for every value —
      // otherwise a new activity can be added and never wired.
      for (final type in ActivityTypeEntity.values) {
        expect(type.movementProfile, isNotNull, reason: type.name);
      }
    });

    test('unknown behaves as the permissive generic profile', () {
      // Legacy rows and GPX imports land here. Guessing "walk" for them would
      // restate what a past recording meant.
      expect(
        ActivityTypeEntity.unknown.movementProfile,
        MovementProfileEntity.generic,
      );
    });

    test('the list stays short — it is cheap to add a type and expensive to '
        'remove one', () {
      // drift's textEnum needs no migration to gain a value but strands stored
      // rows when it loses one, so the taxonomy starts minimal and grows on
      // demand. This is a tripwire, not a law: raise it deliberately.
      expect(
        ActivityTypeEntity.values.length,
        lessThanOrEqualTo(10),
        reason: 'adding is fine; just do it on purpose',
      );
    });

    test('unknown is never offered as a choice', () {
      expect(selectableActivityTypes, isNot(contains(ActivityTypeEntity.unknown)));
      expect(
        selectableActivityTypes.length,
        ActivityTypeEntity.values.length - 1,
      );
    });

    test('"other" exists and is permissive — it is what makes the short list '
        'safe', () {
      // Dropping kayak, ski and hiking is only defensible because a neutral
      // fallback exists. Without it those users would have to pick a profile
      // that is actively wrong for them.
      final fallback = ActivityTypeEntity.other.movementProfile;
      expect(fallback, MovementProfileEntity.generic);
      expect(
        fallback.tuning.plausibleSpeedMps,
        greaterThanOrEqualTo(
          MovementProfileEntity.air.tuning.plausibleSpeedMps,
        ),
        reason: 'must not reject a kayak, a ski run or a train',
      );
    });
  });

  group('speed ceilings', () {
    test('the road profile covers real motorway speed', () {
      // The regression this taxonomy exists to fix: a single 35 m/s ceiling
      // (126 km/h) rejected every fix of a car at a legal 130 km/h, and
      // because a rejection did not advance the comparison anchor it kept
      // rejecting for the rest of the drive.
      const motorwayMps = 130 / 3.6;
      expect(
        MovementProfileEntity.road.tuning.plausibleSpeedMps,
        greaterThan(motorwayMps),
      );
      expect(
        motorwayMps,
        greaterThan(35),
        reason: 'the old global ceiling really was below legal speed',
      );
    });

    test('ceilings rise with how fast the thing moves', () {
      double cap(MovementProfileEntity p) => p.tuning.plausibleSpeedMps;
      expect(
        cap(MovementProfileEntity.swimming),
        lessThan(cap(MovementProfileEntity.slowGround)),
      );
      expect(
        cap(MovementProfileEntity.slowGround),
        lessThan(cap(MovementProfileEntity.running)),
      );
      expect(
        cap(MovementProfileEntity.running),
        lessThan(cap(MovementProfileEntity.humanWheels)),
      );
      expect(
        cap(MovementProfileEntity.humanWheels),
        lessThan(cap(MovementProfileEntity.road)),
      );
      expect(
        cap(MovementProfileEntity.road),
        lessThan(cap(MovementProfileEntity.air)),
      );
    });

    test('the swim ceiling clears the world record with room to spare', () {
      // ~2.4 m/s is around the 50 m freestyle record; a swimmer in a current
      // or under tow goes faster, and the ceiling must not clip them.
      expect(
        MovementProfileEntity.swimming.tuning.plausibleSpeedMps,
        greaterThan(2.4),
      );
    });
  });

  group('accuracy tolerance', () {
    test('missing accuracy is unknown, not automatically bad', () {
      final tuning = MovementProfileEntity.running.tuning;
      expect(tuning.acceptsAccuracy(null), isTrue);
      expect(tuning.acceptsAccuracy(35), isTrue);
      expect(tuning.acceptsAccuracy(35.1), isFalse);
    });

    test('swimming is the loosest human-powered profile', () {
      // Garmin's own guidance is explicit that GPS cannot pass through water
      // and that the device is repeatedly submerged, so a tolerance sized for
      // a runner would reject essentially every fix of a swim.
      final swim = MovementProfileEntity.swimming.tuning.accuracyToleranceMeters;
      for (final profile in [
        MovementProfileEntity.running,
        MovementProfileEntity.humanWheels,
        MovementProfileEntity.slowGround,
      ]) {
        expect(
          swim,
          greaterThan(profile.tuning.accuracyToleranceMeters),
          reason: 'looser than ${profile.name}',
        );
      }
    });
  });

  group('sampling interval', () {
    test('a car samples more often than a swimmer', () {
      expect(
        MovementProfileEntity.road.tuning.baseInterval,
        lessThan(MovementProfileEntity.swimming.tuning.baseInterval),
      );
    });

    test('detail scales the profile interval without replacing it', () {
      final walking = MovementProfileEntity.slowGround.tuning;
      final precise = walking.intervalFor(RecordingDetailEntity.precise);
      final balanced = walking.intervalFor(RecordingDetailEntity.balanced);
      final endurance = walking.intervalFor(RecordingDetailEntity.endurance);

      expect(balanced, walking.baseInterval);
      expect(precise, lessThan(balanced));
      expect(endurance, greaterThan(balanced));
    });

    test('the fastest profile at its sparsest still samples often enough to '
        'be usable', () {
      final sparsest = MovementProfileEntity.road.tuning.intervalFor(
        RecordingDetailEntity.endurance,
      );
      expect(sparsest, lessThanOrEqualTo(const Duration(seconds: 5)));
    });
  });

  group('platform navigation kind', () {
    test('a car is not told to optimise like a run', () {
      // iOS had ActivityType.fitness hardcoded for everything, which is wrong
      // for a vehicle and for a swimmer.
      expect(
        MovementProfileEntity.road.tuning.navigationKind,
        NavigationKind.automotive,
      );
      expect(
        MovementProfileEntity.running.tuning.navigationKind,
        NavigationKind.fitness,
      );
      expect(
        MovementProfileEntity.air.tuning.navigationKind,
        NavigationKind.airborne,
      );
      expect(
        MovementProfileEntity.swimming.tuning.navigationKind,
        NavigationKind.otherNavigation,
      );
    });
  });
}
