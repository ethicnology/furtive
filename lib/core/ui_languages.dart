import 'package:furtive/core/entities/preferences_entity.dart';

/// Native language names for the UI-language dropdown. Kept untranslated so
/// a user landing in a wrong locale can still recognise their language.
const uiLanguageNativeNames = <String, String>{
  'en': 'English',
  'fr': 'Français',
  'ru': 'Русский',
  'uk': 'Українська',
};

/// Dropdown options: null = follow device locale, then one entry per
/// supported UI language. Sourced from MapLanguageEntity since the UI
/// language set intentionally mirrors the supported map label languages.
final uiLanguageOptions = <String?>[
  null,
  ...MapLanguageEntity.values.map((e) => e.name),
];
