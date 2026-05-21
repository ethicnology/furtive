// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Furtive';

  @override
  String get btnNext => 'Suivant';

  @override
  String get btnFinish => 'Terminer';

  @override
  String get btnGrant => 'Autoriser';

  @override
  String get btnGrantPermission => 'Autoriser';

  @override
  String get btnFollow => 'Suivre';

  @override
  String get btnPause => 'Pause';

  @override
  String get btnResume => 'Reprendre';

  @override
  String get btnStart => 'Démarrer';

  @override
  String get btnStarting => 'Démarrage';

  @override
  String get btnStop => 'Stop';

  @override
  String get btnContinue => 'Continuer';

  @override
  String get btnGrantToContinue =>
      'Autorise les permissions requises pour continuer';

  @override
  String get btnViewStats => 'Voir les statistiques';

  @override
  String get btnCancel => 'Annuler';

  @override
  String get btnRename => 'Renommer';

  @override
  String get btnDelete => 'Supprimer';

  @override
  String get btnApply => 'Appliquer';

  @override
  String get btnShare => 'Partager';

  @override
  String get btnStarGitHub => 'Étoile sur GitHub';

  @override
  String get btnSponsor => 'Sponsoriser';

  @override
  String shareSummary(String distance, String duration) {
    return '$distance km en $duration avec Furtive';
  }

  @override
  String shareFailed(String error) {
    return 'Impossible de partager l\'\'activité : $error';
  }

  @override
  String get shareTooltip => 'Partager l\'\'activité';

  @override
  String get navMap => 'Carte';

  @override
  String get navActivities => 'Activités';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get menuPermissions => 'Permissions';

  @override
  String get menuPreferences => 'Préférences';

  @override
  String get menuLogs => 'Journaux';

  @override
  String get onboardWelcomeTitle => 'Bienvenue dans Furtive';

  @override
  String get onboardWelcomeSubtitle =>
      'Suivi d\'\'activité respectueux de la vie privée. Pas de comptes, pas de télémétrie, pas de services Google. Choisissons quelques préférences.';

  @override
  String get onboardSettingsTitle => 'Paramètres de la carte';

  @override
  String get onboardSettingsSubtitle =>
      'Choisis tes préférences — tu pourras les changer plus tard dans les paramètres.';

  @override
  String get onboardPermissionsTitle => 'Permissions';

  @override
  String get onboardPermissionsSubtitle =>
      'Autorise la localisation pour suivre tes courses. Les notifications et l\'\'accès en arrière-plan sont optionnels.';

  @override
  String onboardSaveError(String error) {
    return 'Impossible d\'\'enregistrer tes choix : $error';
  }

  @override
  String get settingsThemeLabel => 'Thème';

  @override
  String get settingsLanguageLabel => 'Langue';

  @override
  String get settingsAccuracyLabel => 'Précision GPS';

  @override
  String get settingsAccuracyHint =>
      'Distance minimale (m) entre deux points enregistrés. Moins = plus de détails, plus de batterie. 0 = chaque position.';

  @override
  String get settingsUiLanguageLabel => 'Langue de l\'\'app';

  @override
  String get settingsUiLanguageSystem => 'Système';

  @override
  String get preferencesTitle => 'Préférences';

  @override
  String get prefMapTheme => 'Thème de la carte';

  @override
  String get prefMapLanguage => 'Langue de la carte';

  @override
  String get prefAppLanguage => 'Langue de l\'\'application';

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get permissionsInstructions =>
      'Cette application nécessite les permissions suivantes pour fonctionner correctement';

  @override
  String get permOptional => 'Optionnel';

  @override
  String get permDeniedMsg =>
      'Refusé — active-le dans les paramètres de l\'\'application.';

  @override
  String get permPermanentlyDenied =>
      'Cette permission doit être activée dans les paramètres de l\'\'application.';

  @override
  String get permLocationWhileUsingName => 'Localisation à l\'\'utilisation';

  @override
  String get permLocationWhileUsingDesc =>
      'Requise pour suivre ta position et l\'\'afficher sur la carte.';

  @override
  String get permLocationAlwaysName => 'Localisation continue';

  @override
  String get permLocationAlwaysDesc =>
      'Optionnel : maintient le suivi précis pendant les longues activités, même si le système suspend l\'\'app.';

  @override
  String get mapActivityStartedMsg => 'Activité lancée';

  @override
  String get mapStopHint =>
      'Maintiens Stop 3 secondes pour terminer l\'\'activité';

  @override
  String get mapLoadFailed => 'Impossible de charger la carte';

  @override
  String get statsRecordingTitle => 'Enregistrement';

  @override
  String get statDistance => 'Distance';

  @override
  String get statDuration => 'Durée';

  @override
  String get statPace => 'Allure';

  @override
  String get statSpeed => 'Vitesse';

  @override
  String get statElevation => 'Dénivelé';

  @override
  String get splitsTitle => 'Splits';

  @override
  String get splitsNotEnoughData => 'Pas assez de données pour les splits.';

  @override
  String get metricPace => 'Allure';

  @override
  String get metricSpeed => 'Vitesse';

  @override
  String get activitiesEmpty => 'Aucune activité';

  @override
  String get activitiesImportTooltip => 'Importer un fichier GPX';

  @override
  String get importStarted => 'Import en cours…';

  @override
  String get importSuccess => 'Activité importée';

  @override
  String get activityNameLabel => 'Nom de l\'\'activité';

  @override
  String get activityDeleteSuccess => 'Activité supprimée';

  @override
  String get dlgRenameTitle => 'Renommer';

  @override
  String get dlgDeleteTitle => 'Supprimer';

  @override
  String get dlgDeleteConfirm =>
      'Es-tu sûr de vouloir supprimer cette activité ?';

  @override
  String get gpxExportSuccess => 'GPX exporté avec succès';

  @override
  String gpxExportFailed(String error) {
    return 'Échec de l\'\'export : $error';
  }

  @override
  String get logsTitle => 'Journaux';

  @override
  String get logsEmpty => 'Aucun journal';

  @override
  String get logsTooltipClear => 'Effacer les journaux';

  @override
  String get logsTooltipFilterDate => 'Filtrer par date';

  @override
  String get logsTooltipClearFilter => 'Effacer le filtre';

  @override
  String get logsTooltipShare => 'Partager';

  @override
  String logsFiltered(String start, String end) {
    return 'Filtré : $start - $end';
  }

  @override
  String logsShowingCount(int shown, int total) {
    return '$shown sur $total';
  }

  @override
  String get activityDefaultName => 'Sortie';

  @override
  String logsLoadError(String error) {
    return 'Impossible de charger les journaux : $error';
  }

  @override
  String get logCopiedMsg => 'Journal copié dans le presse-papiers';

  @override
  String logsCopiedMsg(int count) {
    return '$count journaux copiés dans le presse-papiers';
  }

  @override
  String get dlgDeleteLogsTitle => 'Supprimer les journaux';

  @override
  String get dlgDeleteLogsConfirm =>
      'Es-tu sûr de vouloir supprimer tous les journaux ? Cette action est irréversible.';

  @override
  String get supportTitle => 'Soutenir le développement';

  @override
  String get supportDescription =>
      'Cette app est construite et maintenue sur mon temps libre. Ton soutien aide à la garder vivante.';

  @override
  String get notifBgTrackingTitle => 'Suivi actif';

  @override
  String get notifBgTrackingMsg =>
      'Balaye pour arrêter le suivi en arrière-plan.';

  @override
  String get changelogTitle => 'Nouveautés';

  @override
  String get changelogGotIt => 'Compris';

  @override
  String get changelogV110I18n =>
      'L\'\'application est désormais disponible en anglais, français, russe et ukrainien.';

  @override
  String get changelogV110Splits =>
      'Graphique des splits par kilomètre sur la fiche d\'\'activité, avec bascule allure ⇄ vitesse.';

  @override
  String get changelogV110HoldToStop =>
      'Maintiens Stop 3 secondes pour terminer une activité — fini les arrêts accidentels.';

  @override
  String get changelogV110MapLabels =>
      'Les libellés de la carte s\'\'affichent maintenant dans la langue sélectionnée.';

  @override
  String get changelogV110NanDefense =>
      'Le pipeline GPS résiste aux relevés aberrants qui faisaient planter la carte de la fiche d\'\'activité.';
}
