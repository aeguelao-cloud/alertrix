import '../models/auth_models.dart';
import '../models/monitoring_models.dart';

abstract class MonitoringApi {
  Future<MonitoringSnapshot> fetchSnapshot({
    MonitoringSnapshot? previous,
    int incidentPages = 1,
  });

  Future<void> updateAlertStatus({
    required String incidentId,
    required AlertStatus status,
    required UserRole role,
  });

  Future<String> createWorkOrder({
    required String incidentId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  });

  Future<List<IncidentSensorEvent>> fetchIncidentEvents({
    required String incidentId,
    int limit = 200,
  });

  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  });
}

enum AlertStatus {
  active('ACTIVE'),
  acknowledged('ACKNOWLEDGED'),
  resolved('RESOLVED'),
  closed('CLOSED');

  const AlertStatus(this.apiValue);
  final String apiValue;
}
