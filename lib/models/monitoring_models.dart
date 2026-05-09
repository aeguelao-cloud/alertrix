import 'package:flutter/material.dart';

enum SensorType {
  waterLevel('Water Level', 'Tank Capacity', Icons.water_drop_outlined),
  vibration('Vibration', 'mm/s RMS', Icons.vibration_outlined),
  temperature('Temperature', '°C', Icons.thermostat_outlined);

  const SensorType(this.label, this.unit, this.icon);
  final String label;
  final String unit;
  final IconData icon;
}

enum SensorLevel {
  normal('Normal', Color(0xFF2F8F46)),
  warning('Warning', Color(0xFFE09D25)),
  critical('Critical', Color(0xFFC93C3C));

  const SensorLevel(this.label, this.color);
  final String label;
  final Color color;
}

class SensorReading {
  const SensorReading({
    required this.type,
    required this.value,
    required this.level,
    required this.delta,
  });

  final SensorType type;
  final double value;
  final SensorLevel level;
  final double delta;

  String get formattedValue {
    if (type == SensorType.waterLevel) {
      return '${value.toStringAsFixed(0)}%';
    }
    if (type == SensorType.vibration) {
      return value.toStringAsFixed(1);
    }
    if (type == SensorType.temperature) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(1);
  }

  String get trendText {
    final sign = delta >= 0 ? '+' : '';
    final suffix = type == SensorType.temperature ? '°C' : '';
    return '$sign${delta.toStringAsFixed(1)}$suffix / 1h';
  }
}

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.title,
    required this.zone,
    required this.timestamp,
    required this.severity,
    this.triggerValue,
  });

  final String id;
  final String title;
  final String zone;
  final DateTime timestamp;
  final SensorLevel severity;
  final String? triggerValue;
}

class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.siteName,
    required this.readings,
    required this.alerts,
    required this.history,
    required this.updatedAt,
  });

  final String siteName;
  final List<SensorReading> readings;
  final List<AlertEvent> alerts;
  final Map<SensorType, List<double>> history;
  final DateTime updatedAt;
}
