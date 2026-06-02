import 'package:flutter/material.dart';

import '../theme/severity_colors.dart';
import 'ui_kit.dart';

class IncidentZeroState extends StatelessWidget {
  const IncidentZeroState({
    super.key,
    this.minHeight = 260,
  });

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_rounded,
              size: 72,
              color: SeverityColors.normal,
            ),
            const SizedBox(height: 14),
            Text(
              'All Systems Normal',
              style: UiText.sectionTitle.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'No active incidents currently detected.',
              style: UiText.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
