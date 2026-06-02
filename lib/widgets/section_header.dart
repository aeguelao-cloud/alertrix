import 'package:flutter/material.dart';

import 'ui_kit.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final titleRow = Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: UiColors.brandSoft,
              borderRadius: BorderRadius.circular(UiRadius.input),
            ),
            child: Icon(icon, color: UiColors.brand, size: 18),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(title, style: UiText.sectionTitle)),
      ],
    );

    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: UiText.helper),
        ],
      ],
    );

    if (trailing == null) return textBlock;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          textBlock,
          const SizedBox(height: 10),
          trailing!,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: textBlock),
        const SizedBox(width: 16),
        trailing!,
      ],
    );
  }
}
