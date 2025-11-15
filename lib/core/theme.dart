import 'package:flutter/material.dart';

enum AppColors {
  primary(Colors.tealAccent, Colors.black),
  secondary(Colors.teal, Colors.white),
  tertiary(Colors.blueGrey, Colors.white),
  quaternary(Colors.black, Colors.white),
  destructive(Colors.red, Colors.white);

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
    refreshBackgroundColor: AppColors.primary.foreground,
    circularTrackColor: AppColors.primary.foreground,
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
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary.background,
      foregroundColor: AppColors.primary.foreground,
      disabledBackgroundColor: Colors.grey,
      disabledForegroundColor: Colors.blueGrey,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(foregroundColor: AppColors.primary.background),
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
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.primary.background,
    contentTextStyle: TextStyle(color: AppColors.primary.foreground),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.primary.background,
    titleTextStyle: TextStyle(
      color: AppColors.primary.foreground,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    contentTextStyle: TextStyle(
      color: AppColors.primary.foreground,
      fontSize: 16,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      backgroundColor: AppColors.primary.foreground,
      foregroundColor: AppColors.primary.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.primary.background,
    hoverColor: AppColors.primary.foreground,
    focusColor: AppColors.primary.foreground,
    iconColor: AppColors.primary.foreground,
    labelStyle: TextStyle(color: AppColors.primary.foreground),
    hintStyle: TextStyle(color: AppColors.primary.foreground),
    errorStyle: TextStyle(color: AppColors.destructive.foreground),
    helperStyle: TextStyle(color: AppColors.primary.foreground),
    prefixStyle: TextStyle(color: AppColors.primary.foreground),
    suffixStyle: TextStyle(color: AppColors.primary.foreground),
    counterStyle: TextStyle(color: AppColors.primary.foreground),
    floatingLabelStyle: TextStyle(color: AppColors.primary.foreground),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.primary.foreground),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.primary.foreground),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.primary.foreground, width: 2),
    ),
  ),
);
