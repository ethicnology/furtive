bool shouldOpenStoppedActivity({
  required bool routeIsCurrent,
  required int selectedTab,
}) => routeIsCurrent && selectedTab == 0;
