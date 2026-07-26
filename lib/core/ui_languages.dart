/// Native language names for the UI-language dropdown. Kept untranslated so
/// a user landing in a wrong locale can still recognise their language.
///
/// UI locales are decoupled from map-label languages: the label language is
/// derived from the UI locale at fetch time and narrowed to whatever Protomaps
/// actually supports (see `resolveMapLabelLanguage` in
/// map_remote_data_source.dart), so the UI can be localised independently.
const uiLanguageNativeNames = <String, String>{
  'en': 'English',
  'fr': 'Français',
  'fr_CA': 'Français (Québec)',
  'es': 'Español',
  'de': 'Deutsch',
  'pt': 'Português',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'cs': 'Čeština',
  'sv': 'Svenska',
  'fi': 'Suomi',
  'ro': 'Română',
  'el': 'Ελληνικά',
  'tr': 'Türkçe',
  'ru': 'Русский',
  'uk': 'Українська',
  'hy': 'Հայերեն',
  'ar': 'العربية',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'id': 'Bahasa Indonesia',
  'sw': 'Kiswahili',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
};

/// Dropdown options: null = follow device locale, then one entry per
/// supported UI language. Order matches the human-curated list above so
/// users see locales grouped roughly by region/script.
final uiLanguageOptions = <String?>[null, ...uiLanguageNativeNames.keys];
