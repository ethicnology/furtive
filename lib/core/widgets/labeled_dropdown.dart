import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';

/// Drop-in replacement for `DropdownButtonFormField` that ignores the
/// global `inputDecorationTheme` (which fills inputs with tealAccent — fine
/// for text fields, illegible for dropdown trigger text) and renders a
/// consistent trigger across the app: dark fill + light text + teal accent
/// border. Used in the onboarding wizard and the preferences page.
class LabeledDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const LabeledDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: Colors.black,
      iconEnabledColor: AppColors.primary.background,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary.background),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary.background),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.primary.background,
            width: 2,
          ),
        ),
      ),
      items:
          items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelFor(item)),
                ),
              )
              .toList(),
      onChanged: (v) {
        // `null is T` is true when T is nullable (e.g. String?), allowing
        // null through as a valid selection (e.g. "System default" option).
        if (v != null || null is T) onChanged(v as T);
      },
    );
  }
}
