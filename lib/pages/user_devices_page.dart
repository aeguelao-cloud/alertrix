import 'package:flutter/material.dart';

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui_kit.dart';

class UserDevicesPage extends StatelessWidget {
  const UserDevicesPage({super.key, required this.snapshot});

  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final readingsByType = <SensorType, SensorReading>{};
    for (final reading in snapshot.readings) {
      readingsByType[reading.type] = reading;
    }
    final rows = activeSensorTypes
        .map((type) => _UserDeviceRow.fromSnapshot(
              type: type,
              zone: snapshot.siteName,
              updatedAt: snapshot.updatedAt,
              reading: readingsByType[type],
            ))
        .toList(growable: false);
    final compact = uiIsCompactLayout(context);

    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertrix User',
          title: 'My Devices',
          subtitle: 'View device status and latest sensor readings.',
        ),
        const SizedBox(height: UiSpace.section),
        if (rows.isEmpty)
          const UiCard(
            child: UiEmptyState(
              icon: Icons.devices_other_outlined,
              title: 'No devices found',
              subtitle:
                  'Device status will appear after telemetry is received.',
            ),
          )
        else if (compact)
          ...rows.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: UiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.deviceName, style: UiText.cardTitle),
                    const SizedBox(height: 6),
                    Text('Device ID: ${row.deviceId}', style: UiText.helper),
                    Text('Zone: ${row.zone}', style: UiText.helper),
                    Text('Last Sync: ${row.lastSync}', style: UiText.helper),
                    const SizedBox(height: 8),
                    Text('Reading: ${row.readingSummary}', style: UiText.body),
                    const SizedBox(height: 8),
                    StatusBadge(label: row.statusLabel, tone: row.statusTone),
                  ],
                ),
              ),
            ),
          )
        else
          UiCard(
            big: true,
            child: UiResponsiveTable(
              minWidth: 860,
              child: Column(
                children: [
                  const UiTableHeaderRow(
                    children: [
                      Expanded(
                          flex: 3,
                          child: Text('Device', style: UiText.cardTitle)),
                      Expanded(
                          flex: 2,
                          child: Text('Device ID', style: UiText.cardTitle)),
                      Expanded(
                          flex: 3,
                          child: Text('Zone', style: UiText.cardTitle)),
                      Expanded(
                          flex: 2,
                          child: Text('Status', style: UiText.cardTitle)),
                      Expanded(
                          flex: 2,
                          child: Text('Last Sync', style: UiText.cardTitle)),
                      Expanded(
                          flex: 3,
                          child: Text('Reading', style: UiText.cardTitle)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...rows.map(
                    (row) => UiTableBodyRow(
                      height: 62,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.deviceName,
                            style: UiText.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: UiColors.textStrong,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row.deviceId,
                            style: UiText.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: UiColors.textStrong,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(row.zone, style: UiText.helper),
                        ),
                        Expanded(
                          flex: 2,
                          child: StatusBadge(
                              label: row.statusLabel, tone: row.statusTone),
                        ),
                        Expanded(
                            flex: 2,
                            child: Text(row.lastSync, style: UiText.helper)),
                        Expanded(
                            flex: 3,
                            child:
                                Text(row.readingSummary, style: UiText.body)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _UserDeviceRow {
  const _UserDeviceRow({
    required this.deviceName,
    required this.deviceId,
    required this.zone,
    required this.statusLabel,
    required this.statusTone,
    required this.lastSync,
    required this.readingSummary,
  });

  final String deviceName;
  final String deviceId;
  final String zone;
  final String statusLabel;
  final UiBadgeTone statusTone;
  final String lastSync;
  final String readingSummary;

  factory _UserDeviceRow.fromSnapshot({
    required SensorType type,
    required String zone,
    required DateTime updatedAt,
    required SensorReading? reading,
  }) {
    if (reading == null) {
      return _UserDeviceRow(
        deviceName: type.label,
        deviceId: _deviceIdFor(type),
        zone: zone,
        statusLabel: 'No live telemetry',
        statusTone: UiBadgeTone.noTelemetry,
        lastSync: '--',
        readingSummary: '-- ${type.unit}',
      );
    }

    final tone = reading.level == SensorLevel.critical
        ? UiBadgeTone.critical
        : (reading.level == SensorLevel.warning
            ? UiBadgeTone.warning
            : UiBadgeTone.stable);
    final status = reading.level == SensorLevel.critical
        ? 'Critical'
        : (reading.level == SensorLevel.warning ? 'Warning' : 'Stable');
    return _UserDeviceRow(
      deviceName: type.label,
      deviceId: _deviceIdFor(type),
      zone: zone,
      statusLabel: status,
      statusTone: tone,
      lastSync: _formatDateTime(updatedAt),
      readingSummary: _formatSensorValue(reading.value, type),
    );
  }

  static String _deviceIdFor(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'WL-01';
      case SensorType.vibration:
        return 'VB-01';
      case SensorType.temperature:
        return 'TP-01';
    }
  }

  static String _formatSensorValue(double value, SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return '${value.toStringAsFixed(0)}%';
      case SensorType.vibration:
        return '${value.toStringAsFixed(1)} index';
      case SensorType.temperature:
        return '${value.toStringAsFixed(1)}deg C';
    }
  }

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
