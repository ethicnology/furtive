import 'package:flutter/material.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';

class AppVersionWidget extends StatelessWidget {
  const AppVersionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SelectableText(
            "version ${Global.app.version}+${Global.app.buildNumber}",
            style: TextStyle(
              color: AppColors.primary.foreground,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
