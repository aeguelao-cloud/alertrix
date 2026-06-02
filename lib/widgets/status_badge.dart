import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';
import 'ui_kit.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.prominent = false,
  });

  final String label;
  final UiBadgeTone tone;
  final IconData? icon;
  final bool prominent;

  factory StatusBadge.fromLevel(
    SensorLevel level, {
    String? label,
    bool prominent = false,
  }) {
    return StatusBadge(
      label: label ?? level.label,
      tone: switch (level) {
        SensorLevel.normal => UiBadgeTone.healthy,
        SensorLevel.warning => UiBadgeTone.warning,
        SensorLevel.critical => UiBadgeTone.critical,
      },
      icon: switch (level) {
        SensorLevel.normal => Icons.check_circle_rounded,
        SensorLevel.warning => Icons.warning_amber_rounded,
        SensorLevel.critical => Icons.crisis_alert_rounded,
      },
      prominent: prominent,
    );
  }

  factory StatusBadge.online({
    required bool online,
    String? label,
  }) {
    return StatusBadge(
      label: label ?? (online ? 'Online' : 'Offline'),
      tone: online ? UiBadgeTone.healthy : UiBadgeTone.offline,
      icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = uiToneColor(tone);
    final bg = uiToneSoftColor(tone);
    final border = uiToneBorderColor(tone);
    final padding = prominent
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: prominent ? 16 : 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: prominent ? 13 : 12,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
