import '../models/auth_models.dart';
import '../models/monitoring_models.dart';

abstract class MonitoringApi {
  Future<MonitoringSnapshot> fetchSnapshot({MonitoringSnapshot? previous});

  Future<void> updateAlertStatus({
    required String alertId,
    required AlertStatus status,
    required UserRole role,
  });

  Future<String> createWorkOrder({
    required String alertId,
    required UserRole role,
    String assignee = 'Emergency Team',
    String note = 'Generated from alert workflow',
  });

  Future<void> silenceBuzzer({
    required String zone,
    required UserRole role,
    required String requestedBy,
    int durationSeconds = 120,
  });
}

enum AlertStatus {
  open('OPEN'),
  confirmed('CONFIRMED'),
  ignored('IGNORED'),
  workOrderCreated('WORK_ORDER_CREATED');

  const AlertStatus(this.apiValue);
  final String apiValue;
}
