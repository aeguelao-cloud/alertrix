import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/metrics_config.dart';
import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import 'monitoring_api.dart';

class AwsMonitoringApi implements MonitoringApi {
  AwsMonitoringApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<MonitoringSnapshot> fetchSnapshot(
      {MonitoringSnapshot? previous}) async {
    final nonce = DateTime.now().millisecondsSinceEpoch.toString();
    final readingResp = await _client.get(
      Uri.parse('$baseUrl/api/readings/latest')
          .replace(queryParameters: {'_': nonce}),
    );
    if (readingResp.statusCode < 200 || readingResp.statusCode >= 300) {
      throw Exception('Failed to fetch readings');
    }

    final alertsResp = await _client.get(
      Uri.parse('$baseUrl/api/alerts').replace(
        queryParameters: {'status': 'ACTIVE', '_': nonce},
      ),
    );
    if (alertsResp.statusCode < 200 || alertsResp.statusCode >= 300) {
      throw Exception('Failed to fetch alerts');
    }

    final readingsJson = jsonDecode(readingResp.body) as Map<String, dynamic>;
    final alertsJson = jsonDecode(alertsResp.body) as Map<String, dynamic>;

    final updatedAt =
        _parseApiTime(readingsJson['updatedAt']?.toString()) ?? DateTime.now();
    final rawSiteName =
        readingsJson['siteName']?.toString() ?? 'Pilot Monitoring Site';
    final siteName =
        rawSiteName.contains('CAT403') ? 'Pilot Monitoring Site' : rawSiteName;

    final readingItems =
        (readingsJson['readings'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

    final readingMap = <SensorType, SensorReading>{};
    for (final item in readingItems) {
      final type = _sensorTypeFromApi(item['sensorType']?.toString());
      if (type == null || !activeSensorTypes.contains(type)) continue;
      final rawValue = item['value'];
      if (rawValue is! num) continue;
      final value = rawValue.toDouble();
      final prevValue = _previousValue(previous, type) ?? value;
      final delta = value - prevValue;
      readingMap[type] = SensorReading(
        type: type,
        value: value,
        delta: delta,
        level: _resolveLevel(type, value),
      );
    }

    final readings = activeSensorTypes
        .map((t) => readingMap[t])
        .whereType<SensorReading>()
        .toList(growable: false);

    final history = <SensorType, List<double>>{};
    for (final type in activeSensorTypes) {
      final reading = readingMap[type];
      if (reading == null) {
        // Keep previous samples when current poll misses this sensor, so
        // dashboard trends don't instantly collapse to empty.
        history[type] = previous?.history[type] ?? const <double>[];
        continue;
      }
      final old = previous?.history[type] ?? <double>[];
      final merged = [...old, reading.value];
      if (merged.length > 12) merged.removeAt(0);
      history[type] = merged;
    }

    final alerts = (alertsJson['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_alertFromApi)
        .toList(growable: false);

    return MonitoringSnapshot(
      siteName: siteName,
      readings: readings,
      alerts: alerts,
      history: history,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> updateAlertStatus({
    required String alertId,
    required AlertStatus status,
    required UserRole role,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/alerts/$alertId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': status.apiValue,
        'actorRole': role.label,
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to update alert status: ${resp.statusCode}');
    }
  }

  @override
  Future<String> createWorkOrder({
    required String alertId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/alerts/$alertId/work-orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'actorRole': role.label,
        'assignee': assignee,
        'note': note,
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to create work order: ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final item = body['item'] as Map<String, dynamic>?;
    return item?['workOrderId']?.toString() ?? 'WO-UNKNOWN';
  }

  @override
  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/device/buzzer/silence'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'zone': zone,
        'actorRole': role.label,
        'requestedBy': requestedBy,
        'durationSeconds': durationSeconds,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to silence buzzer: ${resp.statusCode}');
    }
  }

  SensorType? _sensorTypeFromApi(String? value) {
    switch (value) {
      case 'waterLevel':
        return SensorType.waterLevel;
      case 'vibration':
        return SensorType.vibration;
      case 'temperature':
        return SensorType.temperature;
      default:
        return null;
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

  double? _previousValue(MonitoringSnapshot? previous, SensorType type) {
    return _previousReading(previous, type)?.value;
  }

  AlertEvent _alertFromApi(Map<String, dynamic> json) {
    final severityText =
        (json['severity']?.toString() ?? 'WARNING').toUpperCase();
    final severity = switch (severityText) {
      'CRITICAL' => SensorLevel.critical,
      'NORMAL' => SensorLevel.normal,
      _ => SensorLevel.warning,
    };

    final detectedAt =
        _parseApiTime(json['detectedAt']?.toString()) ?? DateTime.now();

    return AlertEvent(
      id: json['alertId']?.toString() ??
          'ALERT-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Alert Triggered',
      zone: json['zone']?.toString() ?? 'Unknown Zone',
      timestamp: detectedAt,
      severity: severity,
      triggerValue: json['triggerValue']?.toString(),
    );
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

  DateTime? _parseApiTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    return parsed.toLocal();
  }
}
