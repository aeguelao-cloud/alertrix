import 'package:flutter/material.dart';

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';

class SensorCard extends StatelessWidget {
  const SensorCard({super.key, required this.sensor});

  final SensorReading sensor;

  @override
  Widget build(BuildContext context) {
    final metricColor = sensorColorOf(sensor.type);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: metricColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(sensor.type.icon, color: metricColor),
                ),
                const Spacer(),
                _LevelPill(level: sensor.level),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              sensor.type.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3A4A50),
              ),
            ),
            const Spacer(),
            Text(
              sensor.formattedValue,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(sensor.type.unit, style: const TextStyle(color: Color(0xFF72858C))),
            const SizedBox(height: 6),
            Text(
              sensor.trendText,
              style: TextStyle(color: metricColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level});

  final SensorLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          color: level.color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
