import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';

class RiskSummaryCard extends StatelessWidget {
  const RiskSummaryCard({super.key, required this.readings});

  final List<SensorReading> readings;

  @override
  Widget build(BuildContext context) {
    final criticalCount = readings.where((r) => r.level == SensorLevel.critical).length;
    final warningCount = readings.where((r) => r.level == SensorLevel.warning).length;
    final normalCount = readings.where((r) => r.level == SensorLevel.normal).length;
    final total = readings.isEmpty ? 1 : readings.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _RiskBar(
              label: 'Critical',
              value: criticalCount / total,
              count: criticalCount,
              total: readings.length,
              color: SensorLevel.critical.color,
            ),
            const SizedBox(height: 8),
            _RiskBar(
              label: 'Warning',
              value: warningCount / total,
              count: warningCount,
              total: readings.length,
              color: SensorLevel.warning.color,
            ),
            const SizedBox(height: 8),
            _RiskBar(
              label: 'Normal',
              value: normalCount / total,
              count: normalCount,
              total: readings.length,
              color: SensorLevel.normal.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskBar extends StatelessWidget {
  const _RiskBar({
    required this.label,
    required this.value,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final double value;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: const Color(0xFFE8EEF0),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            total == 0 ? '0 (0%)' : '$count (${(value * 100).round()}%)',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

