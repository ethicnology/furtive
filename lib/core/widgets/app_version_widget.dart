import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';

class AppVersionWidget extends StatelessWidget {
  const AppVersionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.quaternary.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SelectableText(
              "version ${Global.app.version}+${Global.app.buildNumber}",
              style: TextStyle(
                color: AppColors.quaternary.foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
