import 'package:flutter/material.dart';

enum AppColors {
  primary(Colors.tealAccent, Colors.black),
  secondary(Colors.teal, Colors.white),
  tertiary(Colors.blueGrey, Colors.white),
  quaternary(Colors.black, Colors.white);

  final Color background;
  final Color foreground;

  const AppColors(this.background, this.foreground);
}

ThemeData get appTheme => ThemeData.dark().copyWith(
  appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0),
  scaffoldBackgroundColor: Colors.black,
  iconTheme: IconThemeData(color: AppColors.primary.background),
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: AppColors.primary.background,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary.background,
      foregroundColor: AppColors.primary.foreground,
      disabledBackgroundColor: Colors.grey,
      disabledForegroundColor: Colors.blueGrey,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary.background,
    foregroundColor: AppColors.primary.foreground,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: Colors.black,
    selectedItemColor: AppColors.primary.background,
  ),
  listTileTheme: ListTileThemeData(iconColor: AppColors.primary.background),
);
