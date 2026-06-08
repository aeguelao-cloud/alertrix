import '../models/monitoring_models.dart';

String formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

double warningThreshold(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return 70;
    case SensorType.vibration:
      return 10.0;
    case SensorType.temperature:
      return 35;
  }
}

double criticalThreshold(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return 85;
    case SensorType.vibration:
      return 14.0;
    case SensorType.temperature:
      return 40;
  }
}

String displayUnit(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return '%';
    case SensorType.vibration:
      return 'index';
    case SensorType.temperature:
      return 'deg C';
  }
}

String formatSensorValue(double value, SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return '${value.toStringAsFixed(0)}%';
    case SensorType.vibration:
      return '${value.toStringAsFixed(1)} index';
    case SensorType.temperature:
      return '${value.toStringAsFixed(1)}deg C';
  }
}

String normalizeSensorDisplayValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  return value.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*index\b', caseSensitive: false),
    (match) => '${match.group(1)} index',
  );
}

SensorType inferSensorTypeFromAlertTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('water')) return SensorType.waterLevel;
  if (lower.contains('vibration')) return SensorType.vibration;
  if (lower.contains('temp')) return SensorType.temperature;
  return SensorType.waterLevel;
}

String titleCaseAlert(String raw) {
  if (raw.isEmpty) return raw;
  final normalized = raw
      .replaceAll('waterLevel', 'Water level')
      .replaceAll('temperature', 'Temperature')
      .replaceAll('vibration', 'Vibration')
      .trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
