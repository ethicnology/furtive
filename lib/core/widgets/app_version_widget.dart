import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';

class AppVersionWidget extends StatelessWidget {
  const AppVersionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SelectableText(
          "version ${Global.app.version}+${Global.app.buildNumber}",
          style: const TextStyle(
            color: kTextMuted,
            fontSize: 12,
            fontFeatures: kTabularFigures,
          ),
        ),
      ),
    );
  }
}
