import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/metrics_config.dart';
import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import 'monitoring_api.dart';

class AwsMonitoringApi implements MonitoringApi {
  static const int _activeIncidentsPageSize = 120;

  AwsMonitoringApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<MonitoringSnapshot> fetchSnapshot(
      {MonitoringSnapshot? previous, int incidentPages = 1}) async {
    final nonce = DateTime.now().millisecondsSinceEpoch.toString();
    final readingsUri = Uri.parse('$baseUrl/api/readings/latest')
        .replace(queryParameters: {'_': nonce});
    final overviewUri = Uri.parse('$baseUrl/api/v1/dashboard/overview')
        .replace(queryParameters: {'_': nonce});
    final readingsFuture = _client.get(readingsUri);
    final overviewFuture = _client.get(overviewUri);

    final incidentPageCount = incidentPages < 1 ? 1 : incidentPages;
    final firstIncidentPage = await _fetchActiveIncidentsPage(
      nonce: nonce,
      limit: _activeIncidentsPageSize,
      cursor: null,
    );
    final incidents = <Map<String, dynamic>>[...firstIncidentPage.items];
    var nextCursor = firstIncidentPage.nextCursor;
    var hasMore = firstIncidentPage.hasMore;
    var loadedPages = 1;

    while (loadedPages < incidentPageCount &&
        hasMore &&
        nextCursor != null &&
        nextCursor.isNotEmpty) {
      final nextPage = await _fetchActiveIncidentsPage(
        nonce: nonce,
        limit: _activeIncidentsPageSize,
        cursor: nextCursor,
      );
      incidents.addAll(nextPage.items);
      nextCursor = nextPage.nextCursor;
      hasMore = nextPage.hasMore;
      loadedPages += 1;
    }

    final responses = await Future.wait([readingsFuture, overviewFuture]);
    final readingResp = responses[0];
    final overviewResp = responses[1];

    if (readingResp.statusCode < 200 || readingResp.statusCode >= 300) {
      throw Exception('Failed to fetch readings');
    }
    if (overviewResp.statusCode < 200 || overviewResp.statusCode >= 300) {
      throw Exception('Failed to fetch dashboard overview');
    }

    final readingsJson = jsonDecode(readingResp.body) as Map<String, dynamic>;
    final overviewJson = jsonDecode(overviewResp.body) as Map<String, dynamic>;

    final overview = _overviewFromApi(overviewJson);
    final updatedAt =
        _parseApiTime(overviewJson['latestReadingAt']?.toString()) ??
            _parseApiTime(readingsJson['updatedAt']?.toString()) ??
            DateTime.now();
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
      final capturedAt =
          _parseApiTime(item['capturedAt']?.toString()) ?? updatedAt;
      readingMap[type] = SensorReading(
        type: type,
        value: value,
        delta: delta,
        level: _resolveLevel(type, value),
        capturedAt: capturedAt,
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

    final dedupedIncidentMap = <String, Map<String, dynamic>>{};
    for (final item in incidents) {
      final key = item['incidentId']?.toString() ??
          item['alertId']?.toString() ??
          item['id']?.toString() ??
          '';
      if (key.isEmpty) continue;
      dedupedIncidentMap[key] = item;
    }
    final alerts = dedupedIncidentMap.values
        .map(_alertFromApi)
        .toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final lastSeenBySensor = <SensorType, DateTime?>{
      ...?previous?.lastSeenBySensor,
    };
    overview.sensorStatus.forEach((type, status) {
      lastSeenBySensor[type] = status.lastSeenAt;
    });
    for (final type in activeSensorTypes) {
      final reading = readingMap[type];
      if (reading != null) {
        lastSeenBySensor[type] = reading.capturedAt;
      } else {
        lastSeenBySensor.putIfAbsent(type, () => null);
      }
    }

    return MonitoringSnapshot(
      siteName: siteName,
      readings: readings,
      alerts: alerts,
      history: history,
      updatedAt: updatedAt,
      overview: overview,
      lastSeenBySensor: lastSeenBySensor,
      activeIncidentsNextCursor: nextCursor,
      activeIncidentsHasMore: hasMore,
      activeIncidentsLoadedPages: loadedPages,
    );
  }

  Future<_ActiveIncidentPage> _fetchActiveIncidentsPage({
    required String nonce,
    required int limit,
    String? cursor,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      '_': nonce,
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      query['cursor'] = normalizedCursor;
    }

    final alertsUri = Uri.parse('$baseUrl/api/v1/incidents/active')
        .replace(queryParameters: query);
    final resp = await _client.get(alertsUri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to fetch incidents: ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final nextCursor = body['nextCursor']?.toString();
    final hasMore = body['hasMore'] == true ||
        (nextCursor != null && nextCursor.trim().isNotEmpty);
    return _ActiveIncidentPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<void> updateAlertStatus({
    required String incidentId,
    required AlertStatus status,
    required UserRole role,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    http.Response resp;
    if (status == AlertStatus.acknowledged) {
      resp = await _client.post(
        Uri.parse('$baseUrl/api/v1/incidents/$incidentId/acknowledge'),
        headers: headers,
        body: jsonEncode({'actorRole': role.label}),
      );
    } else if (status == AlertStatus.resolved) {
      resp = await _client.post(
        Uri.parse('$baseUrl/api/v1/incidents/$incidentId/resolve'),
        headers: headers,
        body: jsonEncode({'actorRole': role.label}),
      );
    } else {
      // Keep legacy endpoint fallback for "closed"/admin workflows.
      resp = await _client.post(
        Uri.parse('$baseUrl/api/alerts/$incidentId/status'),
        headers: headers,
        body: jsonEncode({
          'status': status.apiValue,
          'actorRole': role.label,
        }),
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to update incident status: ${resp.statusCode}');
    }
  }

  @override
  Future<String> createWorkOrder({
    required String incidentId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/alerts/$incidentId/work-orders'),
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
  Future<List<IncidentSensorEvent>> fetchIncidentEvents({
    required String incidentId,
    int limit = 200,
  }) async {
    final uri =
        Uri.parse('$baseUrl/api/v1/incidents/$incidentId/events').replace(
      queryParameters: {
        'limit': '$limit',
        'order': 'desc',
      },
    );
    final resp = await _client.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to fetch incident events: ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_incidentEventFromApi)
        .toList(growable: false);
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

    final detectedAt = _parseApiTime(json['lastUpdatedAt']?.toString()) ??
        _parseApiTime(json['latestEventAt']?.toString()) ??
        _parseApiTime(json['updatedAt']?.toString()) ??
        _parseApiTime(json['detectedAt']?.toString()) ??
        _parseApiTime(json['createdAt']?.toString()) ??
        DateTime.now();

    return AlertEvent(
      id: json['incidentId']?.toString() ??
          json['alertId']?.toString() ??
          'ALERT-${DateTime.now().millisecondsSinceEpoch}',
      incidentId: json['incidentId']?.toString(),
      deviceId: json['deviceId']?.toString(),
      sensorType: json['sensorType']?.toString(),
      title: json['title']?.toString() ?? 'Alert Triggered',
      zone: json['zone']?.toString() ?? 'Unknown Zone',
      timestamp: detectedAt,
      severity: severity,
      status: incidentStatusFromApi(json['status']?.toString()),
      triggerValue: json['latestMeasuredValue']?.toString() ??
          json['triggerValue']?.toString(),
      eventCount: _asInt(json['eventCount'], fallback: 1),
      createdAt: _parseApiTime(json['createdAt']?.toString()) ?? detectedAt,
      acknowledgedAt: _parseApiTime(json['acknowledgedAt']?.toString()),
      resolvedAt: _parseApiTime(json['resolvedAt']?.toString()),
    );
  }

  IncidentSensorEvent _incidentEventFromApi(Map<String, dynamic> json) {
    final severityText =
        (json['severity']?.toString() ?? 'WARNING').toUpperCase();
    final severity = switch (severityText) {
      'CRITICAL' => SensorLevel.critical,
      'NORMAL' => SensorLevel.normal,
      _ => SensorLevel.warning,
    };
    final capturedAt = _parseApiTime(json['capturedAt']?.toString()) ??
        _parseApiTime(json['receivedAt']?.toString()) ??
        DateTime.now();

    return IncidentSensorEvent(
      eventId: json['eventId']?.toString() ??
          'SE-${DateTime.now().millisecondsSinceEpoch}',
      incidentId: json['incidentId']?.toString() ?? '',
      capturedAt: capturedAt,
      severity: severity,
      measuredValue: json['measuredValue']?.toString(),
      value: json['value'] is num ? (json['value'] as num).toDouble() : null,
      zone: json['zone']?.toString(),
      deviceId: json['deviceId']?.toString(),
      sensorType: json['sensorType']?.toString(),
      thresholdWarning: _asNullableDouble(json['thresholdWarning']),
      thresholdCritical: _asNullableDouble(json['thresholdCritical']),
      unit: json['unit']?.toString(),
      ingestTransport: json['ingestTransport']?.toString(),
    );
  }

  DashboardOverview _overviewFromApi(Map<String, dynamic> json) {
    final sensorStatusJson = json['sensorStatus'] is Map<String, dynamic>
        ? json['sensorStatus'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final sensorStatus = <SensorType, SensorTelemetryState>{};
    for (final type in activeSensorTypes) {
      final key = _sensorTypeToApi(type);
      final dynamic raw = sensorStatusJson[key];
      final map = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
      final value =
          map['value'] is num ? (map['value'] as num).toDouble() : null;
      sensorStatus[type] = SensorTelemetryState(
        live: map['live'] == true,
        lastSeenAt: _parseApiTime(map['lastSeenAt']?.toString()),
        value: value,
      );
    }

    final bannerJson = json['banner'] is Map<String, dynamic>
        ? json['banner'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return DashboardOverview(
      systemStatus:
          dashboardSystemStatusFromApi(json['systemStatus']?.toString()),
      currentRisk: (json['currentRisk']?.toString() ?? 'UNKNOWN').toUpperCase(),
      activeIncidents: _asInt(json['activeIncidents']),
      criticalQueue: _asInt(json['criticalQueue']),
      warningQueue: _asInt(json['warningQueue']),
      telemetryCoverage: _asInt(json['telemetryCoverage']),
      latestSync: json['latestSync']?.toString() ?? '--:--',
      banner: DashboardBanner(
        type: bannerJson['type']?.toString() ?? 'NORMAL',
        title: bannerJson['title']?.toString() ?? 'System operating normally',
        message: bannerJson['message']?.toString() ??
            'All active sensors are within safe thresholds.',
      ),
      sensorStatus: sensorStatus,
      latestReadingAt: _parseApiTime(json['latestReadingAt']?.toString()),
      latestReadingAgeSeconds: _asNullableInt(json['latestReadingAgeSeconds']),
      liveWindowSeconds: _asNullableInt(json['liveWindowSeconds']),
    );
  }

  SensorLevel _resolveLevel(SensorType type, double value) {
    switch (type) {
      case SensorType.waterLevel:
        if (value >= 85) return SensorLevel.critical;
        if (value >= 70) return SensorLevel.warning;
        return SensorLevel.normal;
      case SensorType.vibration:
        if (value >= 14.0) return SensorLevel.critical;
        if (value >= 10.0) return SensorLevel.warning;
        return SensorLevel.normal;
      case SensorType.temperature:
        if (value >= 40) return SensorLevel.critical;
        if (value >= 35) return SensorLevel.warning;
        return SensorLevel.normal;
    }
  }

  String _sensorTypeToApi(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'waterLevel';
      case SensorType.vibration:
        return 'vibration';
      case SensorType.temperature:
        return 'temperature';
    }
  }

  DateTime? _parseApiTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    return parsed.toLocal();
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    final parsed = _asNullableInt(value);
    return parsed ?? fallback;
  }

  int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class _ActiveIncidentPage {
  const _ActiveIncidentPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool hasMore;
}
