import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';
import 'ui_kit.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.item,
    this.onTap,
  });

  final AlertEvent item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = item.severity == SensorLevel.critical
        ? UiBadgeTone.critical
        : UiBadgeTone.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadius.card),
        border:
            Border.all(color: uiToneBorderColor(tone).withValues(alpha: 0.55)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: uiToneSoftColor(tone),
          child: Icon(
            Icons.notification_important_outlined,
            color: uiToneColor(tone),
            size: 18,
          ),
        ),
        title: Text(item.title, style: UiText.cardTitle),
        subtitle: Text(item.zone, style: UiText.helper),
        trailing: Text(
          _formatTime(item.timestamp),
          style: const TextStyle(
            color: UiColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
