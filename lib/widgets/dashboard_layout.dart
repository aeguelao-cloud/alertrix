import 'package:flutter/material.dart';

import 'ui_kit.dart';

class DashboardLayout extends StatelessWidget {
  const DashboardLayout({
    super.key,
    required this.title,
    required this.children,
    this.systemName = 'Alertrix',
    this.subtitle,
    this.trailing,
  });

  final String systemName;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final verticalPadding = uiIsCompactLayout(context) ? 16.0 : UiSpace.page;
    final horizontalPadding = uiIsCompactLayout(context) ? 24.0 : 32.0;

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE7F1F7),
                  Color(0xFFEDF4F8),
                  Color(0xFFF4F8FB),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -100,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: const Color(0xFFBFDDE7).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -80,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFD2E7EF).withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        ListView(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    children: [
                      UiPageHeader(
                        systemName: systemName,
                        title: title,
                        subtitle: subtitle,
                        trailing: trailing,
                      ),
                      SizedBox(height: uiSectionSpacing(context)),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
