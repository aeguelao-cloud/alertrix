import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import '../services/aws_monitoring_api.dart';
import '../services/fake_monitoring_api.dart';
import '../services/monitoring_api.dart';

class MonitoringController extends ChangeNotifier {
  MonitoringController({MonitoringApi? api, String? apiBaseUrl})
      : _api = api ?? _buildApi(apiBaseUrl),
        _apiBaseUrl = apiBaseUrl;

  final MonitoringApi _api;
  final String? _apiBaseUrl;

  MonitoringSnapshot? _snapshot;
  DateTime? _lastSuccessfulSyncAt;
  bool _loading = true;
  bool _refreshInFlight = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;
  String? _errorMessage;
  Timer? _timer;

  static const Duration _criticalRefreshInterval = Duration(seconds: 1);
  static const Duration _warningRefreshInterval = Duration(seconds: 2);
  static const Duration _stableRefreshInterval = Duration(seconds: 3);
  static const Duration _baseFailureInterval = Duration(seconds: 6);
  static const Duration _maxFailureInterval = Duration(seconds: 12);
  static const Duration _requestTimeout = Duration(seconds: 5);

  MonitoringSnapshot? get snapshot => _snapshot;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  bool get usingRemoteApi => _api is AwsMonitoringApi;
  String get modeLabel => usingRemoteApi ? 'API' : 'Mock';
  String? get apiBaseUrl => _apiBaseUrl;

  static MonitoringApi _buildApi(String? apiBaseUrl) {
    final trimmed = (apiBaseUrl ?? '').trim();
    if (trimmed.isNotEmpty) {
      return AwsMonitoringApi(baseUrl: trimmed);
    }
    return FakeMonitoringApi();
  }

  Future<void> initialize() async {
    _loading = true;
    notifyListeners();
    await _refreshInternal();
    _loading = false;
    notifyListeners();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _scheduleNextRefresh();
  }

  void _scheduleNextRefresh([Duration? delay]) {
    _timer?.cancel();
    if (_disposed) return;
    final wait = delay ?? _nextRefreshInterval();
    _timer = Timer(wait, () async {
      await _refreshInternal();
      if (_disposed) return;
      _scheduleNextRefresh();
    });
  }

  Duration _nextRefreshInterval() {
    if (_errorMessage != null) {
      final extraSeconds = (_consecutiveFailures - 1).clamp(0, 4) * 2;
      final candidate =
          Duration(seconds: _baseFailureInterval.inSeconds + extraSeconds);
      if (candidate > _maxFailureInterval) return _maxFailureInterval;
      return candidate;
    }

    final alerts = _snapshot?.alerts ?? const <AlertEvent>[];
    if (alerts.any((a) => a.severity == SensorLevel.critical)) {
      return _criticalRefreshInterval;
    }
    if (alerts.any((a) => a.severity == SensorLevel.warning)) {
      return _warningRefreshInterval;
    }
    return _stableRefreshInterval;
  }

  Future<void> _refreshInternal({bool force = false}) async {
    if (_refreshInFlight && !force) return;
    _refreshInFlight = true;
    try {
      _snapshot = await _api
          .fetchSnapshot(previous: _snapshot)
          .timeout(_requestTimeout);
      _lastSuccessfulSyncAt = _snapshot?.updatedAt ?? DateTime.now();
      _errorMessage = null;
      _consecutiveFailures = 0;
    } on TimeoutException {
      _errorMessage =
          'Sync timeout from ${usingRemoteApi ? 'API' : 'mock source'}';
      _consecutiveFailures += 1;
    } catch (_) {
      _errorMessage =
          'Failed to sync from ${usingRemoteApi ? 'API' : 'mock source'}';
      _consecutiveFailures += 1;
    } finally {
      _refreshInFlight = false;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> manualRefresh() async {
    await _refreshInternal(force: true);
    if (!_disposed) {
      _scheduleNextRefresh();
    }
  }

  Future<void> confirmAlert(String alertId, UserRole role) async {
    await _api.updateAlertStatus(
        alertId: alertId, status: AlertStatus.confirmed, role: role);
    await manualRefresh();
  }

  Future<int> confirmAlerts(Iterable<String> alertIds, UserRole role) async {
    var successCount = 0;
    for (final alertId in alertIds) {
      try {
        await _api.updateAlertStatus(
          alertId: alertId,
          status: AlertStatus.confirmed,
          role: role,
        );
        successCount += 1;
      } catch (_) {
        // Keep going so one failed record does not block the rest.
      }
    }
    await manualRefresh();
    return successCount;
  }

  Future<void> ignoreAlert(String alertId, UserRole role) async {
    await _api.updateAlertStatus(
        alertId: alertId, status: AlertStatus.ignored, role: role);
    await manualRefresh();
  }

  Future<String> createWorkOrder(String alertId, UserRole role) async {
    final id = await _api.createWorkOrder(alertId: alertId, role: role);
    await manualRefresh();
    return id;
  }

  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  }) async {
    await _api.silenceBuzzer(
      zone: zone,
      role: role,
      requestedBy: requestedBy,
      durationSeconds: durationSeconds,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
