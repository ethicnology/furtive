// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Furtive';

  @override
  String get btnNext => 'Next';

  @override
  String get btnFinish => 'Finish';

  @override
  String get btnGrant => 'Grant';

  @override
  String get btnGrantPermission => 'Grant Permission';

  @override
  String get btnFollow => 'Follow';

  @override
  String get btnPause => 'Pause';

  @override
  String get btnResume => 'Resume';

  @override
  String get btnStart => 'Start';

  @override
  String get btnStarting => 'Starting';

  @override
  String get btnStop => 'Stop';

  @override
  String get btnContinue => 'Continue';

  @override
  String get btnGrantToContinue => 'Grant Required Permissions to Continue';

  @override
  String get btnViewStats => 'View Statistics';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnRename => 'Rename';

  @override
  String get btnDelete => 'Delete';

  @override
  String get btnApply => 'Apply';

  @override
  String get btnStarGitHub => 'Star on GitHub';

  @override
  String get btnSponsor => 'Sponsor';

  @override
  String get navMap => 'Map';

  @override
  String get navActivities => 'Activities';

  @override
  String get navSettings => 'Settings';

  @override
  String get menuPermissions => 'Permissions';

  @override
  String get menuPreferences => 'Preferences';

  @override
  String get menuLogs => 'Logs';

  @override
  String get onboardWelcomeTitle => 'Welcome to Furtive';

  @override
  String get onboardWelcomeSubtitle =>
      'Privacy-first activity tracking. No accounts, no telemetry, no Google services. Let\'\'s pick a few defaults.';

  @override
  String get onboardSettingsTitle => 'Map settings';

  @override
  String get onboardSettingsSubtitle =>
      'Pick your defaults — you can change them later in settings.';

  @override
  String get onboardPermissionsTitle => 'Permissions';

  @override
  String get onboardPermissionsSubtitle =>
      'Grant location to track your runs. Notifications and background access are optional.';

  @override
  String onboardSaveError(String error) {
    return 'Could not save your choices: $error';
  }

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsAccuracyLabel => 'GPS accuracy';

  @override
  String get settingsAccuracyHint =>
      'Minimum distance (m) between recorded points. Lower = more detail, more battery. 0 = every fix.';

  @override
  String get settingsUiLanguageLabel => 'App language';

  @override
  String get settingsUiLanguageSystem => 'System default';

  @override
  String get preferencesTitle => 'Preferences';

  @override
  String get prefMapTheme => 'Map Theme';

  @override
  String get prefMapLanguage => 'Map Language';

  @override
  String get prefAppLanguage => 'App Language';

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get permissionsInstructions =>
      'This app needs the following permissions to work properly';

  @override
  String get permOptional => 'Optional';

  @override
  String get permDeniedMsg => 'Denied — enable it in app settings.';

  @override
  String get permPermanentlyDenied =>
      'This permission has to be enabled in app settings.';

  @override
  String get permLocationWhileUsingName => 'Location While Using';

  @override
  String get permLocationWhileUsingDesc =>
      'Required to track your position and display it on the map.';

  @override
  String get permLocationAlwaysName => 'Location Always';

  @override
  String get permLocationAlwaysDesc =>
      'Optional: keeps tracking accurate during long activities, even if the OS suspends the app.';

  @override
  String get mapActivityStartedMsg => 'Activity started';

  @override
  String get mapStopHint => 'Hold Stop for 3 seconds to end activity';

  @override
  String get mapLoadFailed => 'Failed to load map';

  @override
  String get statsRecordingTitle => 'Recording Activity';

  @override
  String get statDistance => 'Distance';

  @override
  String get statPace => 'Pace';

  @override
  String get statSpeed => 'Speed';

  @override
  String get statElevation => 'Elevation';

  @override
  String get splitsTitle => 'Splits';

  @override
  String get splitsNotEnoughData => 'Not enough data for splits yet.';

  @override
  String get metricPace => 'Pace';

  @override
  String get metricSpeed => 'Speed';

  @override
  String get activitiesEmpty => 'No activities found';

  @override
  String get activityNameLabel => 'Activity name';

  @override
  String get activityDeleteSuccess => 'Activity deleted successfully';

  @override
  String get dlgRenameTitle => 'Rename';

  @override
  String get dlgDeleteTitle => 'Delete';

  @override
  String get dlgDeleteConfirm =>
      'Are you sure you want to delete this activity?';

  @override
  String get gpxExportSuccess => 'GPX exported successfully';

  @override
  String gpxExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsEmpty => 'No logs found';

  @override
  String get logsTooltipClear => 'Clear log';

  @override
  String get logsTooltipFilterDate => 'Filter by date';

  @override
  String get logsTooltipClearFilter => 'Clear filter';

  @override
  String get logsTooltipShare => 'Share';

  @override
  String logsFiltered(String start, String end) {
    return 'Filtered: $start - $end';
  }

  @override
  String logsShowingCount(int shown, int total) {
    return 'Showing $shown of $total';
  }

  @override
  String get activityDefaultName => 'Track';

  @override
  String logsLoadError(String error) {
    return 'Failed to load logs: $error';
  }

  @override
  String get logCopiedMsg => 'Log copied to clipboard';

  @override
  String logsCopiedMsg(int count) {
    return '$count logs copied to clipboard';
  }

  @override
  String get dlgDeleteLogsTitle => 'Delete logs';

  @override
  String get dlgDeleteLogsConfirm =>
      'Are you sure you want to delete all logs? This action cannot be undone.';

  @override
  String get supportTitle => 'Support Development';

  @override
  String get supportDescription =>
      'This app is built and maintained on my free time. Your support helps keep it alive and growing.';

  @override
  String get notifBgTrackingTitle => 'Tracking active';

  @override
  String get notifBgTrackingMsg => 'Swipe to stop background tracking.';

  @override
  String get changelogTitle => 'What\'\'s new';

  @override
  String get changelogGotIt => 'Got it';

  @override
  String get changelogV110I18n =>
      'App is now available in English, French, Russian and Ukrainian.';

  @override
  String get changelogV110Splits =>
      'Per-kilometre splits chart on the activity detail page, with pace ⇄ speed toggle.';

  @override
  String get changelogV110HoldToStop =>
      'Hold the Stop button for 3 seconds to end an activity — no accidental taps.';

  @override
  String get changelogV110MapLabels =>
      'Map labels now render in your selected language.';

  @override
  String get changelogV110NanDefense =>
      'Hardened GPS pipeline against junk fixes that used to crash the activity detail map.';
}
