import '../config/metrics_config.dart';
import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import 'monitoring_api.dart';

class FakeMonitoringApi implements MonitoringApi {
  FakeMonitoringApi({int? seed})
      : _seed = seed ?? DateTime.now().millisecondsSinceEpoch;

  final int _seed;

  @override
  Future<MonitoringSnapshot> fetchSnapshot(
      {MonitoringSnapshot? previous}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();

    final base = <SensorType, double>{
      SensorType.waterLevel: 68,
      SensorType.vibration: 2.3,
      SensorType.temperature: 33.5,
    };

    final readings = activeSensorTypes.map((type) {
      final prev = _previousReading(previous, type);
      final prevValue = prev?.value ?? base[type]!;
      final noise = _noise(type, now.millisecondsSinceEpoch + _seed);
      final value = _clamp(type, prevValue + noise);
      return SensorReading(
          type: type,
          value: value,
          level: _resolveLevel(type, value),
          delta: value - prevValue);
    }).toList(growable: false);

    final history = <SensorType, List<double>>{};
    for (final reading in readings) {
      final old = previous?.history[reading.type] ?? <double>[];
      final merged = [...old, reading.value];
      if (merged.length > 12) merged.removeAt(0);
      history[reading.type] = merged;
    }

    final alerts = readings
        .where((r) => r.level != SensorLevel.normal)
        .map(
          (r) => AlertEvent(
            id: '${r.type.name}-${now.millisecondsSinceEpoch}',
            title:
                '${r.type.label} ${r.level == SensorLevel.critical ? 'critical' : 'near threshold'}',
            zone: _zoneByType(r.type),
            timestamp: now,
            severity: r.level,
            triggerValue:
                '${r.value.toStringAsFixed(r.type == SensorType.waterLevel ? 0 : 1)} ${r.type.unit}',
          ),
        )
        .toList(growable: false);

    return MonitoringSnapshot(
      siteName: 'Pilot Monitoring Site',
      readings: readings,
      alerts: alerts,
      history: history,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateAlertStatus(
      {required String alertId,
      required AlertStatus status,
      required UserRole role}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  @override
  Future<String> createWorkOrder({
    required String alertId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    return 'WO-${now.substring(now.length - 6)}';
  }

  @override
  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  double _noise(SensorType type, int t) {
    final bucket = (t ~/ 1000) % 11;
    switch (type) {
      case SensorType.waterLevel:
        return ((bucket % 5) - 2) * 0.8;
      case SensorType.vibration:
        return ((bucket % 7) - 3) * 0.12;
      case SensorType.temperature:
        return ((bucket % 9) - 4) * 0.18;
    }
  }

  double _clamp(SensorType type, double value) {
    switch (type) {
      case SensorType.waterLevel:
        return value.clamp(20, 98).toDouble();
      case SensorType.vibration:
        return value.clamp(0.2, 5.5).toDouble();
      case SensorType.temperature:
        return value.clamp(18, 49).toDouble();
    }
  }

  SensorLevel _resolveLevel(SensorType type, double value) {
    switch (type) {
      case SensorType.waterLevel:
        if (value >= 85) return SensorLevel.critical;
        if (value >= 70) return SensorLevel.warning;
        return SensorLevel.normal;
      case SensorType.vibration:
        if (value >= 4.0) return SensorLevel.critical;
        if (value >= 2.8) return SensorLevel.warning;
        return SensorLevel.normal;
      case SensorType.temperature:
        if (value >= 40) return SensorLevel.critical;
        if (value >= 35) return SensorLevel.warning;
        return SensorLevel.normal;
    }
  }

  SensorReading? _previousReading(
      MonitoringSnapshot? previous, SensorType type) {
    final source = previous?.readings;
    if (source == null) return null;
    for (final item in source) {
      if (item.type == type) return item;
    }
    return null;
  }

  String _zoneByType(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'Zone A - Pump Station';
      case SensorType.vibration:
        return 'Zone D - Motor Room';
      case SensorType.temperature:
        return 'Zone C - Generator Bay';
    }
  }
}
