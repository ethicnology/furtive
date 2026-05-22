import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleCubit extends Cubit<Locale?> {
  LocaleCubit(super.initialState);

  void setLocale(String? tag) {
    emit(tag != null ? parseLocaleTag(tag) : null);
  }
}

/// Parse a stored locale tag into a Flutter [Locale]. Accepts `language`,
/// `language_COUNTRY`, or `language_Script_COUNTRY` (separator `_` or `-`).
/// Without this, `Locale('fr_CA')` would create a single-string language
/// code that never matches the generated `fr_CA` locale.
Locale parseLocaleTag(String tag) {
  final parts = tag.split(RegExp(r'[_-]'));
  if (parts.length == 1) return Locale(parts[0]);
  if (parts.length == 2) return Locale(parts[0], parts[1]);
  return Locale.fromSubtags(
    languageCode: parts[0],
    scriptCode: parts[1],
    countryCode: parts[2],
  );
}
