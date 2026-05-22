// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Furtive';

  @override
  String get btnNext => 'Далі';

  @override
  String get btnFinish => 'Готово';

  @override
  String get btnGrant => 'Дозволити';

  @override
  String get btnGrantPermission => 'Дозволити';

  @override
  String get btnFollow => 'За мною';

  @override
  String get btnPause => 'Пауза';

  @override
  String get btnResume => 'Відновити';

  @override
  String get btnStart => 'Старт';

  @override
  String get btnStarting => 'Запуск';

  @override
  String get btnStop => 'Стоп';

  @override
  String get btnContinue => 'Продовжити';

  @override
  String get btnGrantToContinue =>
      'Дозволь обов\'\'язкові доступи, щоб продовжити';

  @override
  String get btnViewStats => 'Статистика';

  @override
  String get btnCancel => 'Скасувати';

  @override
  String get btnRename => 'Перейменувати';

  @override
  String get btnDelete => 'Видалити';

  @override
  String get btnApply => 'Застосувати';

  @override
  String get btnStarGitHub => 'Зірка на GitHub';

  @override
  String get btnSponsor => 'Підтримати';

  @override
  String linkOpenFailed(String url) {
    return 'Не вдалося відкрити $url';
  }

  @override
  String shareSummary(String distance, String duration) {
    return '$distance км за $duration з Furtive';
  }

  @override
  String shareFailed(String error) {
    return 'Не вдалося поділитися тренуванням: $error';
  }

  @override
  String get shareTooltip => 'Поділитися тренуванням';

  @override
  String get navMap => 'Мапа';

  @override
  String get navActivities => 'Тренування';

  @override
  String get navSettings => 'Налаштування';

  @override
  String get menuPermissions => 'Дозволи';

  @override
  String get menuPreferences => 'Параметри';

  @override
  String get menuLogs => 'Журнали';

  @override
  String get onboardWelcomeTitle => 'Вітаємо у Furtive';

  @override
  String get onboardWelcomeSubtitle =>
      'Відстеження активності з повагою до приватності. Без акаунтів, телеметрії та сервісів Google. Оберімо кілька налаштувань.';

  @override
  String get onboardSettingsTitle => 'Налаштування мапи';

  @override
  String get onboardSettingsSubtitle =>
      'Обери налаштування за замовчуванням — їх можна змінити пізніше в налаштуваннях.';

  @override
  String get onboardPermissionsTitle => 'Дозволи';

  @override
  String get onboardPermissionsSubtitle =>
      'Дозволь доступ до геолокації, щоб відстежувати свої тренування. Сповіщення та фоновий доступ — необов\'\'язково.';

  @override
  String onboardSaveError(String error) {
    return 'Не вдалося зберегти налаштування: $error';
  }

  @override
  String get settingsThemeLabel => 'Тема';

  @override
  String get settingsLanguageLabel => 'Мова';

  @override
  String get settingsAccuracyLabel => 'Точність GPS';

  @override
  String get settingsAccuracyHint =>
      'Мінімальна відстань (м) між записаними точками. Менше = детальніше, більше витрати батареї. 0 = кожна точка.';

  @override
  String get settingsUiLanguageLabel => 'Мова застосунку';

  @override
  String get settingsUiLanguageSystem => 'Системна';

  @override
  String get preferencesTitle => 'Параметри';

  @override
  String get prefMapTheme => 'Тема мапи';

  @override
  String get prefMapLanguage => 'Мова мапи';

  @override
  String get prefAppLanguage => 'Мова застосунку';

  @override
  String get permissionsTitle => 'Дозволи';

  @override
  String get permissionsInstructions =>
      'Цей застосунок потребує наступних дозволів для коректної роботи';

  @override
  String get permOptional => 'Необов\'\'язково';

  @override
  String get permDeniedMsg => 'Відхилено — увімкни в налаштуваннях застосунку.';

  @override
  String get permPermanentlyDenied =>
      'Цей дозвіл потрібно увімкнути в налаштуваннях застосунку.';

  @override
  String get permLocationWhileUsingName => 'Геолокація під час використання';

  @override
  String get permLocationWhileUsingDesc =>
      'Потрібно для відстеження твоєї позиції та її відображення на мапі.';

  @override
  String get permLocationAlwaysName => 'Геолокація завжди';

  @override
  String get permLocationAlwaysDesc =>
      'Необов\'\'язково: тримає точне відстеження під час довгих тренувань, навіть коли система призупиняє застосунок.';

  @override
  String get mapActivityStartedMsg => 'Тренування розпочато';

  @override
  String get mapStopHint => 'Утримуй Стоп 3 секунди, щоб завершити тренування';

  @override
  String get mapLoadFailed => 'Не вдалося завантажити мапу';

  @override
  String get statsRecordingTitle => 'Запис';

  @override
  String get statDistance => 'Відстань';

  @override
  String get statDuration => 'Час';

  @override
  String get statPace => 'Темп';

  @override
  String get statSpeed => 'Швидкість';

  @override
  String get statElevation => 'Набір висоти';

  @override
  String get splitsTitle => 'Відрізки';

  @override
  String get splitsNotEnoughData => 'Поки що недостатньо даних для відрізків.';

  @override
  String get metricPace => 'Темп';

  @override
  String get metricSpeed => 'Швидкість';

  @override
  String get activitiesEmpty => 'Тренувань немає';

  @override
  String get activitiesImportTooltip => 'Імпорт GPX-файлу';

  @override
  String get importStarted => 'Імпорт…';

  @override
  String get importSuccess => 'Тренування імпортовано';

  @override
  String get activityNameLabel => 'Назва тренування';

  @override
  String get activityDeleteSuccess => 'Тренування видалено';

  @override
  String get dlgRenameTitle => 'Перейменувати';

  @override
  String get dlgDeleteTitle => 'Видалити';

  @override
  String get dlgDeleteConfirm => 'Точно хочеш видалити це тренування?';

  @override
  String get gpxExportSuccess => 'GPX успішно експортовано';

  @override
  String gpxExportFailed(String error) {
    return 'Помилка експорту: $error';
  }

  @override
  String get logsTitle => 'Журнали';

  @override
  String get logsEmpty => 'Журналів немає';

  @override
  String get logsTooltipClear => 'Очистити журнали';

  @override
  String get logsTooltipFilterDate => 'Фільтр за датою';

  @override
  String get logsTooltipClearFilter => 'Скинути фільтр';

  @override
  String get logsTooltipShare => 'Поділитися';

  @override
  String logsFiltered(String start, String end) {
    return 'Фільтр: $start - $end';
  }

  @override
  String logsShowingCount(int shown, int total) {
    return '$shown з $total';
  }

  @override
  String get activityDefaultName => 'Тренування';

  @override
  String logsLoadError(String error) {
    return 'Не вдалося завантажити журнали: $error';
  }

  @override
  String get logCopiedMsg => 'Запис скопійовано в буфер обміну';

  @override
  String logsCopiedMsg(int count) {
    return '$count записів скопійовано в буфер обміну';
  }

  @override
  String get dlgDeleteLogsTitle => 'Видалити журнали';

  @override
  String get dlgDeleteLogsConfirm =>
      'Точно хочеш видалити всі журнали? Цю дію неможливо скасувати.';

  @override
  String newVersionAvailable(String version) {
    return 'Завантаж останню версію $version';
  }

  @override
  String get btnDownload => 'Завантажити';

  @override
  String get supportTitle => 'Підтримати розробку';

  @override
  String get supportDescription =>
      'Цей застосунок створюється та підтримується у вільний час. Твоя підтримка допомагає йому розвиватися.';

  @override
  String get changelogTitle => 'Що нового';

  @override
  String get changelogGotIt => 'Зрозуміло';

  @override
  String get changelogV120Share =>
      'Поділися тренуванням як карточкою з мапою та статистикою.';

  @override
  String get changelogV120GpxImport =>
      'Імпорт GPX-файлів з інших застосунків (Garmin, Strava тощо).';

  @override
  String get changelogV120LocaleDates =>
      'Дати тренувань тепер у форматі твоєї локалі.';

  @override
  String get changelogV120Stability =>
      'Стабільність: укріплений GPS-конвеєр, автоматична ротація журналів, суворіша валідація GPX.';
}
