import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/features/map/map_navigation.dart';

void main() {
  test('a stopped activity opens only from the visible map tab', () {
    expect(
      shouldOpenStoppedActivity(routeIsCurrent: true, selectedTab: 0),
      isTrue,
    );
    expect(
      shouldOpenStoppedActivity(routeIsCurrent: true, selectedTab: 1),
      isFalse,
    );
    expect(
      shouldOpenStoppedActivity(routeIsCurrent: false, selectedTab: 0),
      isFalse,
    );
  });
}
