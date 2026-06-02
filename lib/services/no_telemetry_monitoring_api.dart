import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import 'monitoring_api.dart';

class NoTelemetryMonitoringApi implements MonitoringApi {
  @override
  Future<MonitoringSnapshot> fetchSnapshot(
      {MonitoringSnapshot? previous, int incidentPages = 1}) async {
    const overview = DashboardOverview(
      systemStatus: DashboardSystemStatus.noTelemetry,
      currentRisk: 'UNKNOWN',
      activeIncidents: 0,
      criticalQueue: 0,
      warningQueue: 0,
      telemetryCoverage: 0,
      latestSync: '--:--',
      banner: DashboardBanner(
        type: 'NO_TELEMETRY',
        title: 'Telemetry unavailable',
        message:
            'No live sensor data received. Please check device connection.',
      ),
      sensorStatus: <SensorType, SensorTelemetryState>{
        SensorType.waterLevel: SensorTelemetryState(live: false),
        SensorType.vibration: SensorTelemetryState(live: false),
        SensorType.temperature: SensorTelemetryState(live: false),
      },
      latestReadingAt: null,
      latestReadingAgeSeconds: null,
      liveWindowSeconds: 60,
    );
    return MonitoringSnapshot(
      siteName: previous?.siteName ?? 'Pilot Monitoring Site',
      readings: const <SensorReading>[],
      alerts: const <AlertEvent>[],
      history: const <SensorType, List<double>>{},
      updatedAt: DateTime.now(),
      overview: overview,
      lastSeenBySensor: previous?.lastSeenBySensor ??
          const <SensorType, DateTime?>{
            SensorType.waterLevel: null,
            SensorType.vibration: null,
            SensorType.temperature: null,
          },
      activeIncidentsNextCursor: null,
      activeIncidentsHasMore: false,
      activeIncidentsLoadedPages: 1,
    );
  }

  @override
  Future<void> updateAlertStatus({
    required String incidentId,
    required AlertStatus status,
    required UserRole role,
  }) async {
    throw UnsupportedError('Cloud API is not configured.');
  }

  @override
  Future<String> createWorkOrder({
    required String incidentId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  }) async {
    throw UnsupportedError('Cloud API is not configured.');
  }

  @override
  Future<List<IncidentSensorEvent>> fetchIncidentEvents({
    required String incidentId,
    int limit = 200,
  }) async {
    throw UnsupportedError('Cloud API is not configured.');
  }

  @override
  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  }) async {
    throw UnsupportedError('Cloud API is not configured.');
  }
}
