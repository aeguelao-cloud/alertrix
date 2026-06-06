import 'package:flutter/material.dart';

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import 'status_badge.dart';
import 'ui_kit.dart';

class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.sensor,
    this.updatedAt,
    this.deviceId,
    this.zone,
  });

  final SensorReading sensor;
  final DateTime? updatedAt;
  final String? deviceId;
  final String? zone;

  @override
  Widget build(BuildContext context) {
    final metricColor = sensorColorOf(sensor.type);
    final critical = sensor.level == SensorLevel.critical;
    final compact = uiIsCompactLayout(context);
    return UiCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      big: critical,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 7 : 8),
                  decoration: BoxDecoration(
                    color: metricColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    sensor.type.icon,
                    color: metricColor,
                    size: compact ? 20 : 24,
                  ),
                ),
                const Spacer(),
                StatusBadge.fromLevel(sensor.level, prominent: critical),
              ],
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(
              sensor.type.label,
              style: UiText.cardTitle,
            ),
            const SizedBox(height: 2),
            Text(
              deviceId == null
                  ? sensor.type.unit
                  : (zone == null ? deviceId! : '${deviceId!} | $zone'),
              style: UiText.helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              sensor.formattedValue,
              style: UiText.bigNumber.copyWith(fontSize: compact ? 28 : 34),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    sensor.type.unit,
                    style: UiText.helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  sensor.delta >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: metricColor,
                ),
                const SizedBox(width: 4),
                Text(
                  sensor.trendText,
                  style: UiText.helper.copyWith(
                    color: metricColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (updatedAt != null) ...[
              SizedBox(height: compact ? 8 : 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: UiColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(UiRadius.input),
                  border: Border.all(color: UiColors.border),
                ),
                child: Text(
                  'Latest reading: ${_formatTime(updatedAt!)}',
                  style: UiText.helper,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
