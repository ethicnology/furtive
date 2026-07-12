import 'package:flutter/material.dart';

/// Background/foreground colour pairs used across the app. Kept as an enum
/// (rather than one const per role) so call sites read `AppColors.x.y`
/// consistently regardless of whether "x" is an accent, a surface, or a
/// status colour.
///
/// Design language: pure black is reserved for the app's outermost
/// background (Scaffold/bottom nav) — good outdoor/OLED contrast for a
/// tracker used in daylight and at night. Everything that should read as a
/// distinct surface (cards, sheets, list rows) sits one step up on
/// [kSurface]/[kSurfaceHigh] instead of black-on-black or solid accent
/// fills — see AUDIT-DESIGN.md for the full rationale.
enum AppColors {
  // Primary accent: call-to-action fills (Start/Follow FAB, primary
  // buttons, progress indicators, the live-recording accent colour).
  primary(kMint, Colors.black),
  // "Active/engaged" state distinct from primary — e.g. the Follow FAB once
  // following is toggled on. Deliberately a step down in saturation from
  // primary so an active toggle doesn't compete with a call-to-action.
  secondary(kMintMuted, Colors.white),
  // Generic on-black foreground text/icon colour; background is rarely
  // used (kept for call sites built around the (background, foreground)
  // pair shape).
  tertiary(kSurfaceHigh, Colors.white),
  // Card/surface fill for anything that should read as "a distinct block
  // of content" without being an accent — settings rows, the activities
  // list, the app-version footer. This used to be pure black (invisible
  // against the black background); it's now one step up the surface scale.
  quaternary(kSurface, Colors.white),
  destructive(kDestructive, Colors.white);

  final Color background;
  final Color foreground;

  const AppColors(this.background, this.foreground);
}

// --- Design tokens -----------------------------------------------------
//
// Standalone constants for roles that don't fit the (background,
// foreground) pair shape above: borders, muted text, elevated-within-a-
// surface fills, and status colours used outside the primary/destructive
// pair.

/// Core accent. Same hue as the Material `tealAccent` this app shipped with
/// (0xFF64FFDA) — pinned to a literal so it no longer depends on which
/// Material shade `Colors.tealAccent` happens to resolve to.
const kMint = Color(0xFF64FFDA);

/// Desaturated/darkened accent for "already active" states and secondary
/// data (e.g. paused-segment stats) — keeps a single bright mint reserved
/// for the one thing on screen that should draw the eye first.
///
/// Darkened from an earlier 0xFF3D8C7A (4.01:1 with white text — fails
/// WCAG AA's 4.5:1 for normal text) to 4.80:1, comfortably above AA and
/// close to AAA (7:1), for outdoor/sunlight use where effective contrast
/// drops well below the lab-measured ratio.
const kMintMuted = Color(0xFF377E6E);

/// Outermost background. Pure black: best contrast for outdoor daylight
/// use and the cheapest pixels on an OLED screen during a long recording.
const kBackground = Colors.black;

/// First surface step above [kBackground] — cards, list rows, sheets,
/// bottom navigation. Dark enough to stay unobtrusive at night, distinct
/// enough from pure black to read as "a card" without needing an accent
/// fill or a loud border.
const kSurface = Color(0xFF121214);

/// Second surface step — nested content within a [kSurface] card (chip
/// backgrounds, the disabled state of an already-granted permission
/// button) that needs to read as one level "more elevated" again.
const kSurfaceHigh = Color(0xFF1C1C1F);

/// Hairline border colour for surfaces that need a visible edge instead of
/// (or in addition to) a fill step — e.g. an outlined button on a filled
/// card, or a divider between list rows.
const kOutline = Color(0xFF2C2C30);

/// De-emphasised text — captions, stat labels, timestamps. One step down
/// from white so the numbers/titles they annotate stay the visual focus.
const kTextMuted = Color(0xFFA0A0A8);

/// Status colour for a recoverable problem the user should notice but that
/// isn't destructive — e.g. the "tracking gap" banner. Previously an inline
/// `Colors.orange.shade900` in map_page.dart; centralised here so every
/// warning surface matches.
const kWarning = Color(0xFFFFB74D);

/// Darkened from an earlier 0xFFFF5449 (3.17:1 with white text — the worst
/// ratio in this palette, well under WCAG AA's 4.5:1 for normal text and
/// the color most likely to carry an actual error message) to 4.74:1. Use
/// for FILLED surfaces (buttons, snackbars) that carry white/black text —
/// for red used AS text/icon colour directly on a dark surface, use
/// [kDangerText] instead: darkening a colour helps it as a fill with light
/// text on top, but hurts it as a foreground colour on a dark background —
/// a single token can't serve both roles at once (mirrors Material 3's
/// separate `error` vs `errorContainer` roles).
const kDestructive = Color(0xFFCC433A);

/// Red for text/icons directly on a dark surface (an inline error caption,
/// the "permanently denied" notice, a destructive icon in an AppBar) —
/// kept at the original brighter coral, which reaches 5.36:1 on
/// [kSurfaceHigh] and 6.62:1 on [kBackground]. See [kDestructive]'s doc for
/// why these are two different tokens instead of one.
const kDangerText = Color(0xFFFF5449);

/// Font family bundled locally (assets/fonts, SIL OFL 1.1) — no runtime
/// fetching, see pubspec.yaml. Exposed as a constant so widgets that build
/// their own TextStyle (rather than pulling from Theme.of(context).textTheme)
/// still pick up the same family instead of falling back to the platform
/// default.
const kFontFamily = 'SpaceGrotesk';

/// Tabular-figure numerals so a live stat (pace, distance, elapsed time)
/// doesn't visually jitter in width as its digits change several times a
/// second while recording.
const kTabularFigures = [FontFeature.tabularFigures()];

ThemeData get appTheme {
  const outlineBorder = BorderSide(color: kOutline);
  final base = ThemeData.dark();

  return base.copyWith(
    // Backstop for any Material 3 widget that reads ColorScheme directly
    // rather than a specific component theme below (SegmentedButton, Chip,
    // ...) — without this they'd fall back to ThemeData.dark()'s default
    // seed-generated purple-leaning scheme, clashing with the mint accent
    // used everywhere else.
    colorScheme: ColorScheme.dark(
      primary: kMint,
      onPrimary: Colors.black,
      secondary: kMintMuted,
      onSecondary: Colors.white,
      surface: kSurface,
      onSurface: Colors.white,
      surfaceContainerHighest: kSurfaceHigh,
      outline: kOutline,
      error: kDestructive,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: kBackground,
    canvasColor: kBackground,
    dividerColor: kOutline,
    textTheme: base.textTheme
        .apply(fontFamily: kFontFamily)
        .copyWith(
          // Big numeric readouts (activity stats, elapsed time).
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w700,
            fontFeatures: kTabularFigures,
            color: Colors.white,
          ),
          // Page titles (AppBar titles use headlineSmall by default in M2-style
          // AppBarTheme.titleTextStyle below, kept here too for consistency).
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          // Card headers, list item titles.
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: kFontFamily,
            color: Colors.white,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontFamily: kFontFamily,
            color: kTextMuted,
          ),
          // Uppercase-style stat labels ("DISTANCE", "PACE"): letter-spacing
          // reads better than the default when the widget itself upper-cases
          // the string (see StatBlock).
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: kTextMuted,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    iconTheme: const IconThemeData(color: kMint),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kMint,
      refreshBackgroundColor: kSurfaceHigh,
      circularTrackColor: kSurfaceHigh,
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: outlineBorder,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kMint,
        foregroundColor: Colors.black,
        disabledBackgroundColor: kSurfaceHigh,
        disabledForegroundColor: kTextMuted,
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kMint,
        foregroundColor: Colors.black,
        disabledBackgroundColor: kSurfaceHigh,
        disabledForegroundColor: kTextMuted,
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: outlineBorder,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(kMint)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kMint,
      foregroundColor: Colors.black,
      elevation: 0,
      extendedTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      shape: StadiumBorder(),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kBackground,
      selectedItemColor: kMint,
      unselectedItemColor: kTextMuted,
      type: BottomNavigationBarType.fixed,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: kMint,
      textColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurfaceHigh,
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: outlineBorder,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      titleTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
        fontSize: 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: outlineBorder,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kMint,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      iconColor: kMint,
      labelStyle: const TextStyle(fontFamily: kFontFamily, color: kTextMuted),
      hintStyle: const TextStyle(fontFamily: kFontFamily, color: kTextMuted),
      errorStyle: const TextStyle(
        // kDangerText, not kDestructive: this is red text directly on a
        // dark surface, not white/black text on a red fill — see the two
        // tokens' doc comments above.
        fontFamily: kFontFamily,
        color: kDangerText,
      ),
      helperStyle: const TextStyle(fontFamily: kFontFamily, color: kTextMuted),
      prefixStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
      ),
      suffixStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
      ),
      counterStyle: const TextStyle(fontFamily: kFontFamily, color: kTextMuted),
      floatingLabelStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: kMint,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: outlineBorder,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: outlineBorder,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kMint, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? kMintMuted : kSurfaceHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(kOutline),
    ),
  );
}
