import 'package:flutter/material.dart';

import '../theme/severity_colors.dart';

enum SensorType {
  waterLevel('Water Level', '%', Icons.water_drop_outlined),
  vibration('Vibration', 'mm/s RMS', Icons.vibration_outlined),
  temperature('Temperature', 'deg C', Icons.thermostat_outlined);

  const SensorType(this.label, this.unit, this.icon);
  final String label;
  final String unit;
  final IconData icon;
}

enum SensorLevel {
  normal('Normal', SeverityColors.normal),
  warning('Warning', SeverityColors.warning),
  critical('Critical', SeverityColors.critical);

  const SensorLevel(this.label, this.color);
  final String label;
  final Color color;
}

enum IncidentStatus {
  active('ACTIVE', 'Active'),
  acknowledged('ACKNOWLEDGED', 'Acknowledged'),
  resolved('RESOLVED', 'Resolved'),
  closed('CLOSED', 'Closed');

  const IncidentStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

enum DashboardSystemStatus {
  noTelemetry('NO_TELEMETRY', 'No Telemetry'),
  normal('NORMAL', 'Normal'),
  warning('WARNING', 'Warning'),
  critical('CRITICAL', 'Critical');

  const DashboardSystemStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class SensorReading {
  const SensorReading({
    required this.type,
    required this.value,
    required this.level,
    required this.delta,
    required this.capturedAt,
  });

  final SensorType type;
  final double value;
  final SensorLevel level;
  final double delta;
  final DateTime capturedAt;

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
    final suffix = type == SensorType.temperature ? ' deg C' : '';
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
    this.status = IncidentStatus.active,
    this.triggerValue,
    this.incidentId,
    this.deviceId,
    this.sensorType,
    this.eventCount = 1,
    this.createdAt,
    this.acknowledgedAt,
    this.resolvedAt,
  });

  final String id;
  final String title;
  final String zone;
  final DateTime timestamp;
  final SensorLevel severity;
  final IncidentStatus status;
  final String? triggerValue;
  final String? incidentId;
  final String? deviceId;
  final String? sensorType;
  final int eventCount;
  final DateTime? createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
}

class IncidentSensorEvent {
  const IncidentSensorEvent({
    required this.eventId,
    required this.incidentId,
    required this.capturedAt,
    required this.severity,
    this.measuredValue,
    this.value,
    this.zone,
    this.deviceId,
    this.sensorType,
    this.thresholdWarning,
    this.thresholdCritical,
    this.unit,
    this.ingestTransport,
  });

  final String eventId;
  final String incidentId;
  final DateTime capturedAt;
  final SensorLevel severity;
  final String? measuredValue;
  final double? value;
  final String? zone;
  final String? deviceId;
  final String? sensorType;
  final double? thresholdWarning;
  final double? thresholdCritical;
  final String? unit;
  final String? ingestTransport;
}

class DashboardBanner {
  const DashboardBanner({
    required this.type,
    required this.title,
    required this.message,
  });

  final String type;
  final String title;
  final String message;
}

class SensorTelemetryState {
  const SensorTelemetryState({
    required this.live,
    this.lastSeenAt,
    this.value,
  });

  final bool live;
  final DateTime? lastSeenAt;
  final double? value;
}

class DashboardOverview {
  const DashboardOverview({
    required this.systemStatus,
    required this.currentRisk,
    required this.activeIncidents,
    required this.criticalQueue,
    required this.warningQueue,
    required this.telemetryCoverage,
    required this.latestSync,
    required this.banner,
    required this.sensorStatus,
    this.latestReadingAt,
    this.latestReadingAgeSeconds,
    this.liveWindowSeconds,
  });

  final DashboardSystemStatus systemStatus;
  final String currentRisk;
  final int activeIncidents;
  final int criticalQueue;
  final int warningQueue;
  final int telemetryCoverage;
  final String latestSync;
  final DashboardBanner banner;
  final Map<SensorType, SensorTelemetryState> sensorStatus;
  final DateTime? latestReadingAt;
  final int? latestReadingAgeSeconds;
  final int? liveWindowSeconds;

  String get currentRiskLabel {
    switch (currentRisk.toUpperCase()) {
      case 'CRITICAL':
        return 'Critical';
      case 'WARNING':
        return 'Warning';
      case 'NORMAL':
        return 'Normal';
      case 'UNKNOWN':
      default:
        return 'Unknown';
    }
  }
}

class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.siteName,
    required this.readings,
    required this.alerts,
    required this.history,
    required this.updatedAt,
    this.overview,
    this.lastSeenBySensor = const <SensorType, DateTime?>{},
    this.activeIncidentsNextCursor,
    this.activeIncidentsHasMore = false,
    this.activeIncidentsLoadedPages = 1,
  });

  final String siteName;
  final List<SensorReading> readings;
  final List<AlertEvent> alerts;
  final Map<SensorType, List<double>> history;
  final DateTime updatedAt;
  final DashboardOverview? overview;
  final Map<SensorType, DateTime?> lastSeenBySensor;
  final String? activeIncidentsNextCursor;
  final bool activeIncidentsHasMore;
  final int activeIncidentsLoadedPages;
}

IncidentStatus incidentStatusFromApi(String? raw) {
  switch (raw?.trim().toUpperCase()) {
    case 'ACKNOWLEDGED':
    case 'CONFIRMED':
    case 'WORK_ORDER_CREATED':
      return IncidentStatus.acknowledged;
    case 'RESOLVED':
      return IncidentStatus.resolved;
    case 'CLOSED':
    case 'IGNORED':
      return IncidentStatus.closed;
    case 'ACTIVE':
    case 'OPEN':
    default:
      return IncidentStatus.active;
  }
}

DashboardSystemStatus dashboardSystemStatusFromApi(String? raw) {
  switch (raw?.trim().toUpperCase()) {
    case 'CRITICAL':
      return DashboardSystemStatus.critical;
    case 'WARNING':
      return DashboardSystemStatus.warning;
    case 'NORMAL':
      return DashboardSystemStatus.normal;
    case 'NO_TELEMETRY':
    default:
      return DashboardSystemStatus.noTelemetry;
  }
}
