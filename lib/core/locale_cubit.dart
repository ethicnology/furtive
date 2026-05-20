import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleCubit extends Cubit<Locale?> {
  LocaleCubit(super.initialState);

  void setLocale(String? languageCode) {
    emit(languageCode != null ? Locale(languageCode) : null);
  }
}
