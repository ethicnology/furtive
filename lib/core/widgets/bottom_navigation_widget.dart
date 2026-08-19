import 'package:flutter/material.dart';
import 'package:furtive/features/activities/pages/activities_list_page.dart';
import 'package:furtive/features/map/pages/map_page.dart';
import 'package:furtive/features/settings/settings_page.dart';
import 'package:furtive/l10n/app_localizations.dart';

class BottomNavigationWidget extends StatefulWidget {
  const BottomNavigationWidget({super.key});

  @override
  State<BottomNavigationWidget> createState() => _BottomNavigationWidgetState();
}

class _BottomNavigationWidgetState extends State<BottomNavigationWidget> {
  late final PageController _pageController;
  late final ValueNotifier<int> _selectedTab;
  late final List<Widget> _pages;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _selectedTab = ValueNotifier(0);
    _pages = [
      MapPage(selectedTab: _selectedTab),
      const ActivitiesListPage(),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _selectedTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          _selectedTab.value = index;
          setState(() => _currentIndex = index);
        },
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _selectedTab.value = index;
          setState(() => _currentIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.map_outlined),
            activeIcon: const Icon(Icons.map_rounded),
            label: AppLocalizations.of(context).navMap,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.list_alt_outlined),
            activeIcon: const Icon(Icons.list_alt_rounded),
            label: AppLocalizations.of(context).navActivities,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings_rounded),
            label: AppLocalizations.of(context).navSettings,
          ),
        ],
      ),
    );
  }
}
