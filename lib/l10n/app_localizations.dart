import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('ru'),
    Locale('uk'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Furtive'**
  String get appTitle;

  /// No description provided for @btnNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get btnNext;

  /// No description provided for @btnFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get btnFinish;

  /// No description provided for @btnGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get btnGrant;

  /// No description provided for @btnGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant Permission'**
  String get btnGrantPermission;

  /// No description provided for @btnFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get btnFollow;

  /// No description provided for @btnPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get btnPause;

  /// No description provided for @btnResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get btnResume;

  /// No description provided for @btnStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get btnStart;

  /// No description provided for @btnStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get btnStarting;

  /// No description provided for @btnStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get btnStop;

  /// No description provided for @btnContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get btnContinue;

  /// No description provided for @btnGrantToContinue.
  ///
  /// In en, this message translates to:
  /// **'Grant Required Permissions to Continue'**
  String get btnGrantToContinue;

  /// No description provided for @btnViewStats.
  ///
  /// In en, this message translates to:
  /// **'View Statistics'**
  String get btnViewStats;

  /// No description provided for @btnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btnCancel;

  /// No description provided for @btnRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get btnRename;

  /// No description provided for @btnDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get btnDelete;

  /// No description provided for @btnApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get btnApply;

  /// No description provided for @btnStarGitHub.
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get btnStarGitHub;

  /// No description provided for @btnSponsor.
  ///
  /// In en, this message translates to:
  /// **'Sponsor'**
  String get btnSponsor;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open {url}'**
  String linkOpenFailed(String url);

  /// No description provided for @shareSummary.
  ///
  /// In en, this message translates to:
  /// **'{distance} km in {duration} with Furtive'**
  String shareSummary(String distance, String duration);

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t share activity: {error}'**
  String shareFailed(String error);

  /// No description provided for @shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share activity'**
  String get shareTooltip;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get navActivities;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @menuPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get menuPermissions;

  /// No description provided for @menuPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get menuPreferences;

  /// No description provided for @menuLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get menuLogs;

  /// No description provided for @onboardWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Furtive'**
  String get onboardWelcomeTitle;

  /// No description provided for @onboardWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy-first activity tracking. No accounts, no telemetry, no Google services. Let\'\'s pick a few defaults.'**
  String get onboardWelcomeSubtitle;

  /// No description provided for @onboardSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Map settings'**
  String get onboardSettingsTitle;

  /// No description provided for @onboardSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick your defaults — you can change them later in settings.'**
  String get onboardSettingsSubtitle;

  /// No description provided for @onboardPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get onboardPermissionsTitle;

  /// No description provided for @onboardPermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Grant location to track your runs. Notifications and background access are optional.'**
  String get onboardPermissionsSubtitle;

  /// No description provided for @onboardSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your choices: {error}'**
  String onboardSaveError(String error);

  /// No description provided for @settingsThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeLabel;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsAccuracyLabel.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy'**
  String get settingsAccuracyLabel;

  /// No description provided for @settingsAccuracyHint.
  ///
  /// In en, this message translates to:
  /// **'Minimum distance (m) between recorded points. Lower = more detail, more battery. 0 = every fix.'**
  String get settingsAccuracyHint;

  /// No description provided for @settingsUiLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsUiLanguageLabel;

  /// No description provided for @settingsUiLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsUiLanguageSystem;

  /// No description provided for @preferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferencesTitle;

  /// No description provided for @prefMapTheme.
  ///
  /// In en, this message translates to:
  /// **'Map Theme'**
  String get prefMapTheme;

  /// No description provided for @prefMapLanguage.
  ///
  /// In en, this message translates to:
  /// **'Map Language'**
  String get prefMapLanguage;

  /// No description provided for @prefAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get prefAppLanguage;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsTitle;

  /// No description provided for @permissionsInstructions.
  ///
  /// In en, this message translates to:
  /// **'This app needs the following permissions to work properly'**
  String get permissionsInstructions;

  /// No description provided for @permOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get permOptional;

  /// No description provided for @permDeniedMsg.
  ///
  /// In en, this message translates to:
  /// **'Denied — enable it in app settings.'**
  String get permDeniedMsg;

  /// No description provided for @permPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'This permission has to be enabled in app settings.'**
  String get permPermanentlyDenied;

  /// No description provided for @permLocationWhileUsingName.
  ///
  /// In en, this message translates to:
  /// **'Location While Using'**
  String get permLocationWhileUsingName;

  /// No description provided for @permLocationWhileUsingDesc.
  ///
  /// In en, this message translates to:
  /// **'Required to track your position and display it on the map.'**
  String get permLocationWhileUsingDesc;

  /// No description provided for @permLocationAlwaysName.
  ///
  /// In en, this message translates to:
  /// **'Location Always'**
  String get permLocationAlwaysName;

  /// No description provided for @permLocationAlwaysDesc.
  ///
  /// In en, this message translates to:
  /// **'Optional: keeps tracking accurate during long activities, even if the OS suspends the app.'**
  String get permLocationAlwaysDesc;

  /// No description provided for @mapActivityStartedMsg.
  ///
  /// In en, this message translates to:
  /// **'Activity started'**
  String get mapActivityStartedMsg;

  /// No description provided for @mapStopHint.
  ///
  /// In en, this message translates to:
  /// **'Hold Stop for 3 seconds to end activity'**
  String get mapStopHint;

  /// No description provided for @mapLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load map'**
  String get mapLoadFailed;

  /// No description provided for @statsRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording Activity'**
  String get statsRecordingTitle;

  /// No description provided for @statDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get statDistance;

  /// No description provided for @statDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get statDuration;

  /// No description provided for @statPace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get statPace;

  /// No description provided for @statSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get statSpeed;

  /// No description provided for @statElevation.
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get statElevation;

  /// No description provided for @splitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Splits'**
  String get splitsTitle;

  /// No description provided for @splitsNotEnoughData.
  ///
  /// In en, this message translates to:
  /// **'Not enough data for splits yet.'**
  String get splitsNotEnoughData;

  /// No description provided for @metricPace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get metricPace;

  /// No description provided for @metricSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get metricSpeed;

  /// No description provided for @activitiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No activities found'**
  String get activitiesEmpty;

  /// No description provided for @activitiesImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import a GPX file'**
  String get activitiesImportTooltip;

  /// No description provided for @importStarted.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importStarted;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Activity imported'**
  String get importSuccess;

  /// No description provided for @activityNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Activity name'**
  String get activityNameLabel;

  /// No description provided for @activityDeleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Activity deleted successfully'**
  String get activityDeleteSuccess;

  /// No description provided for @dlgRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get dlgRenameTitle;

  /// No description provided for @dlgDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dlgDeleteTitle;

  /// No description provided for @dlgDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this activity?'**
  String get dlgDeleteConfirm;

  /// No description provided for @gpxExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'GPX exported successfully'**
  String get gpxExportSuccess;

  /// No description provided for @gpxExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String gpxExportFailed(String error);

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// No description provided for @logsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No logs found'**
  String get logsEmpty;

  /// No description provided for @logsTooltipClear.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get logsTooltipClear;

  /// No description provided for @logsTooltipFilterDate.
  ///
  /// In en, this message translates to:
  /// **'Filter by date'**
  String get logsTooltipFilterDate;

  /// No description provided for @logsTooltipClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get logsTooltipClearFilter;

  /// No description provided for @logsTooltipShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get logsTooltipShare;

  /// No description provided for @logsFiltered.
  ///
  /// In en, this message translates to:
  /// **'Filtered: {start} - {end}'**
  String logsFiltered(String start, String end);

  /// No description provided for @logsShowingCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String logsShowingCount(int shown, int total);

  /// No description provided for @activityDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get activityDefaultName;

  /// No description provided for @logsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load logs: {error}'**
  String logsLoadError(String error);

  /// No description provided for @logCopiedMsg.
  ///
  /// In en, this message translates to:
  /// **'Log copied to clipboard'**
  String get logCopiedMsg;

  /// No description provided for @logsCopiedMsg.
  ///
  /// In en, this message translates to:
  /// **'{count} logs copied to clipboard'**
  String logsCopiedMsg(int count);

  /// No description provided for @dlgDeleteLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete logs'**
  String get dlgDeleteLogsTitle;

  /// No description provided for @dlgDeleteLogsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all logs? This action cannot be undone.'**
  String get dlgDeleteLogsConfirm;

  /// No description provided for @newVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Download the latest version {version}'**
  String newVersionAvailable(String version);

  /// No description provided for @btnDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get btnDownload;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support Development'**
  String get supportTitle;

  /// No description provided for @supportDescription.
  ///
  /// In en, this message translates to:
  /// **'This app is built and maintained on my free time. Your support helps keep it alive and growing.'**
  String get supportDescription;

  /// No description provided for @changelogTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'\'s new'**
  String get changelogTitle;

  /// No description provided for @changelogGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get changelogGotIt;

  /// No description provided for @changelogV120Share.
  ///
  /// In en, this message translates to:
  /// **'Share an activity as a card with map and stats.'**
  String get changelogV120Share;

  /// No description provided for @changelogV120GpxImport.
  ///
  /// In en, this message translates to:
  /// **'Import GPX files exported from other apps (Garmin, Strava, etc.).'**
  String get changelogV120GpxImport;

  /// No description provided for @changelogV120LocaleDates.
  ///
  /// In en, this message translates to:
  /// **'Activity dates now follow your locale\'\'s format.'**
  String get changelogV120LocaleDates;

  /// No description provided for @changelogV120Stability.
  ///
  /// In en, this message translates to:
  /// **'Stability: hardened GPS pipeline, automatic log rotation, stricter GPX validation.'**
  String get changelogV120Stability;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr', 'ru', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'ru':
      return AppLocalizationsRu();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
