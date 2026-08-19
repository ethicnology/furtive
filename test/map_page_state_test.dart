import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/pages/map_page_logic.dart';

void main() {
  group('shouldRenderMap', () {
    test('renders a resolved basemap before the first GPS fix', () {
      const state = MapState(styleUrl: 'https://example.com/style.json');

      expect(shouldRenderMap(state), isTrue);
    });

    test('keeps waiting while a tileless style is still being resolved', () {
      const state = MapState(loadingStatus: LoadingStatus.loadingMap);

      expect(shouldRenderMap(state), isFalse);
    });

    test('renders the intentional tileless map after resolution finishes', () {
      const state = MapState();

      expect(shouldRenderMap(state), isTrue);
    });
  });

  group('shouldMoveToLocation', () {
    final first = PositionEntity(
      latitude: 48.85,
      longitude: 2.35,
      elevation: 0,
    );
    final second = PositionEntity(
      latitude: 48.86,
      longitude: 2.36,
      elevation: 0,
    );

    test('centres on the first GPS fix without requiring follow mode', () {
      expect(
        shouldMoveToLocation(const MapState(), MapState(userLocation: first)),
        isTrue,
      );
    });

    test('does not chase later fixes while follow mode is off', () {
      expect(
        shouldMoveToLocation(
          MapState(userLocation: first),
          MapState(userLocation: second),
        ),
        isFalse,
      );
    });

    test('follows later fixes while follow mode is on', () {
      expect(
        shouldMoveToLocation(
          MapState(userLocation: first),
          MapState(userLocation: second, isFollowingUser: true),
        ),
        isTrue,
      );
    });
  });
}
