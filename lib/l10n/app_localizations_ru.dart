// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Furtive';

  @override
  String get btnNext => 'Далее';

  @override
  String get btnFinish => 'Готово';

  @override
  String get btnGrant => 'Разрешить';

  @override
  String get btnGrantPermission => 'Разрешить';

  @override
  String get btnFollow => 'За мной';

  @override
  String get btnPause => 'Пауза';

  @override
  String get btnResume => 'Возобновить';

  @override
  String get btnStart => 'Старт';

  @override
  String get btnStarting => 'Запуск';

  @override
  String get btnStop => 'Стоп';

  @override
  String get btnContinue => 'Продолжить';

  @override
  String get btnGrantToContinue =>
      'Разреши необходимые доступы, чтобы продолжить';

  @override
  String get btnViewStats => 'Статистика';

  @override
  String get btnCancel => 'Отмена';

  @override
  String get btnRename => 'Переименовать';

  @override
  String get btnDelete => 'Удалить';

  @override
  String get btnApply => 'Применить';

  @override
  String get btnStarGitHub => 'Звезда на GitHub';

  @override
  String get btnSponsor => 'Поддержать';

  @override
  String get navMap => 'Карта';

  @override
  String get navActivities => 'Тренировки';

  @override
  String get navSettings => 'Настройки';

  @override
  String get menuPermissions => 'Разрешения';

  @override
  String get menuPreferences => 'Параметры';

  @override
  String get menuLogs => 'Журналы';

  @override
  String get onboardWelcomeTitle => 'Добро пожаловать в Furtive';

  @override
  String get onboardWelcomeSubtitle =>
      'Отслеживание активности с заботой о приватности. Без аккаунтов, без телеметрии, без сервисов Google. Выберем несколько настроек.';

  @override
  String get onboardSettingsTitle => 'Настройки карты';

  @override
  String get onboardSettingsSubtitle =>
      'Выбери настройки по умолчанию — их можно изменить позже в настройках.';

  @override
  String get onboardPermissionsTitle => 'Разрешения';

  @override
  String get onboardPermissionsSubtitle =>
      'Разреши доступ к местоположению для отслеживания тренировок. Уведомления и фоновый доступ — необязательно.';

  @override
  String onboardSaveError(String error) {
    return 'Не удалось сохранить настройки: $error';
  }

  @override
  String get settingsThemeLabel => 'Тема';

  @override
  String get settingsLanguageLabel => 'Язык';

  @override
  String get settingsAccuracyLabel => 'Точность GPS';

  @override
  String get settingsAccuracyHint =>
      'Минимальное расстояние (м) между записанными точками. Меньше = подробнее, больше расход батареи. 0 = каждая точка.';

  @override
  String get settingsUiLanguageLabel => 'Язык приложения';

  @override
  String get settingsUiLanguageSystem => 'Системный';

  @override
  String get preferencesTitle => 'Параметры';

  @override
  String get prefMapTheme => 'Тема карты';

  @override
  String get prefMapLanguage => 'Язык карты';

  @override
  String get prefAppLanguage => 'Язык приложения';

  @override
  String get permissionsTitle => 'Разрешения';

  @override
  String get permissionsInstructions =>
      'Приложению нужны следующие разрешения для корректной работы';

  @override
  String get permOptional => 'Необязательно';

  @override
  String get permDeniedMsg => 'Отклонено — включи в настройках приложения.';

  @override
  String get permPermanentlyDenied =>
      'Это разрешение нужно включить в настройках приложения.';

  @override
  String get permLocationWhileUsingName => 'Местоположение при использовании';

  @override
  String get permLocationWhileUsingDesc =>
      'Необходимо для отслеживания позиции и отображения её на карте.';

  @override
  String get permLocationAlwaysName => 'Местоположение всегда';

  @override
  String get permLocationAlwaysDesc =>
      'Необязательно: точное отслеживание во время длинных тренировок, даже когда система приостанавливает приложение.';

  @override
  String get mapActivityStartedMsg => 'Тренировка запущена';

  @override
  String get mapStopHint =>
      'Удерживай Стоп 3 секунды, чтобы завершить тренировку';

  @override
  String get mapLoadFailed => 'Не удалось загрузить карту';

  @override
  String get statsRecordingTitle => 'Запись';

  @override
  String get statDistance => 'Расстояние';

  @override
  String get statPace => 'Темп';

  @override
  String get statSpeed => 'Скорость';

  @override
  String get statElevation => 'Набор высоты';

  @override
  String get splitsTitle => 'Отрезки';

  @override
  String get splitsNotEnoughData => 'Пока недостаточно данных для отрезков.';

  @override
  String get metricPace => 'Темп';

  @override
  String get metricSpeed => 'Скорость';

  @override
  String get activitiesEmpty => 'Нет тренировок';

  @override
  String get activityNameLabel => 'Название тренировки';

  @override
  String get activityDeleteSuccess => 'Тренировка удалена';

  @override
  String get dlgRenameTitle => 'Переименовать';

  @override
  String get dlgDeleteTitle => 'Удалить';

  @override
  String get dlgDeleteConfirm => 'Уверен, что хочешь удалить эту тренировку?';

  @override
  String get gpxExportSuccess => 'GPX успешно экспортирован';

  @override
  String gpxExportFailed(String error) {
    return 'Ошибка экспорта: $error';
  }

  @override
  String get logsTitle => 'Журналы';

  @override
  String get logsEmpty => 'Журналов нет';

  @override
  String get logsTooltipClear => 'Очистить журналы';

  @override
  String get logsTooltipFilterDate => 'Фильтр по дате';

  @override
  String get logsTooltipClearFilter => 'Сбросить фильтр';

  @override
  String get logsTooltipShare => 'Поделиться';

  @override
  String logsFiltered(String start, String end) {
    return 'Фильтр: $start - $end';
  }

  @override
  String logsShowingCount(int shown, int total) {
    return '$shown из $total';
  }

  @override
  String get activityDefaultName => 'Тренировка';

  @override
  String logsLoadError(String error) {
    return 'Не удалось загрузить журналы: $error';
  }

  @override
  String get logCopiedMsg => 'Запись скопирована в буфер обмена';

  @override
  String logsCopiedMsg(int count) {
    return '$count записей скопировано в буфер обмена';
  }

  @override
  String get dlgDeleteLogsTitle => 'Удалить журналы';

  @override
  String get dlgDeleteLogsConfirm =>
      'Уверен, что хочешь удалить все журналы? Это действие необратимо.';

  @override
  String get supportTitle => 'Поддержать разработку';

  @override
  String get supportDescription =>
      'Приложение создаётся и поддерживается в моё свободное время. Твоя поддержка помогает развивать его.';

  @override
  String get notifBgTrackingTitle => 'Отслеживание активно';

  @override
  String get notifBgTrackingMsg =>
      'Смахни, чтобы остановить фоновое отслеживание.';
}
