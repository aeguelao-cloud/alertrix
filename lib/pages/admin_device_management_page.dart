import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import '../widgets/dashboard_layout.dart';
import '../widgets/section_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui_kit.dart';

class AdminDeviceManagementPage extends StatefulWidget {
  const AdminDeviceManagementPage({
    super.key,
    required this.snapshot,
    required this.actorUserId,
    this.apiBaseUrl,
  });

  final MonitoringSnapshot snapshot;
  final String actorUserId;
  final String? apiBaseUrl;

  @override
  State<AdminDeviceManagementPage> createState() =>
      _AdminDeviceManagementPageState();
}

class _AdminDeviceManagementPageState extends State<AdminDeviceManagementPage> {
  bool _loading = false;
  String? _error;
  List<_AdminDeviceItem> _items = const <_AdminDeviceItem>[];
  final Set<String> _busyIds = <String>{};

  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final sectionSpace = uiSectionSpacing(context);
    final onlineCount = _items.where((item) => item.status == 'Online').length;
    final offlineCount =
        _items.where((item) => item.status == 'Offline').length;
    final disabledCount =
        _items.where((item) => item.status == 'Disabled').length;

    return DashboardLayout(
      title: 'Device Management',
      subtitle:
          'Register and manage ESP32 sensor nodes, locations, telemetry health, and firmware status.',
      trailing: const StatusBadge(
        label: 'Admin only',
        tone: UiBadgeTone.healthy,
        icon: Icons.admin_panel_settings_rounded,
        prominent: true,
      ),
      children: [
        _DeviceOpsBanner(
          totalCount: _items.length,
          onlineCount: onlineCount,
          offlineCount: offlineCount,
          disabledCount: disabledCount,
          loading: _loading,
          hasApi: _hasApi,
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _openRegisterDialog,
                style: uiPrimaryButton(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Register device'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadDevices,
                style: uiSecondaryButton(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: UiSpace.gap),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFEF),
              borderRadius: BorderRadius.circular(UiRadius.input),
            ),
            child: Text(_error!, style: UiText.helper),
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: UiSpace.gap),
          const LinearProgressIndicator(),
        ],
        SizedBox(height: sectionSpace),
        UiCard(
          big: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Device Inventory',
                subtitle:
                    'Manage zone assignment, status, telemetry tests, and heartbeat visibility.',
                icon: Icons.devices_other_rounded,
              ),
              const SizedBox(height: 12),
              if (_items.isEmpty && !_loading)
                const UiEmptyState(
                  icon: Icons.memory_outlined,
                  title: 'No devices found',
                  subtitle:
                      'Register a device to start telemetry and response tracking.',
                )
              else if (compact)
                ..._items.map(_buildCompactCard)
              else
                UiResponsiveTable(
                  minWidth: 1240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const UiTableHeaderRow(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text('Device ID', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Sensor Type', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Zone', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Status', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Last Sync', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Firmware', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Heartbeat', style: UiText.cardTitle),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Action', style: UiText.cardTitle),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._items.map(_buildTableRow),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(_AdminDeviceItem item) {
    final busy = _busyIds.contains(item.deviceId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UiColors.tableRow,
        borderRadius: BorderRadius.circular(UiRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.deviceId, style: UiText.cardTitle),
              ),
              StatusBadge(label: item.status, tone: item.statusTone),
            ],
          ),
          const SizedBox(height: 8),
          Text('Sensor Type: ${item.sensorTypeLabel}', style: UiText.helper),
          Text('Zone: ${item.zone}', style: UiText.helper),
          Text(
            'Last Sync: ${_formatDateTime(item.lastSync)}',
            style: UiText.helper,
          ),
          Text('Firmware: ${item.firmwareVersion}', style: UiText.helper),
          Text(
            'Last Heartbeat: ${_formatDateTime(item.lastHeartbeat)}',
            style: UiText.helper,
          ),
          if (item.latestValueLabel != null)
            Text('Latest Reading: ${item.latestValueLabel}',
                style: UiText.helper),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: busy ? null : () => _openEditDialog(item),
                style: uiLinkButton(),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: busy ? null : () => _toggleDevice(item),
                style: uiLinkButton(),
                child: Text(item.status == 'Disabled' ? 'Enable' : 'Disable'),
              ),
              TextButton(
                onPressed: busy ? null : () => _requestTest(item),
                style: uiLinkButton(),
                child: const Text('Test'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(_AdminDeviceItem item) {
    final busy = _busyIds.contains(item.deviceId);
    return UiTableBodyRow(
      height: 64,
      children: [
        Expanded(flex: 2, child: Text(item.deviceId, style: UiText.body)),
        Expanded(
            flex: 2, child: Text(item.sensorTypeLabel, style: UiText.body)),
        Expanded(flex: 3, child: Text(item.zone, style: UiText.body)),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(label: item.status, tone: item.statusTone),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(_formatDateTime(item.lastSync), style: UiText.helper),
        ),
        Expanded(
            flex: 2, child: Text(item.firmwareVersion, style: UiText.body)),
        Expanded(
          flex: 2,
          child:
              Text(_formatDateTime(item.lastHeartbeat), style: UiText.helper),
        ),
        Expanded(
          flex: 3,
          child: Wrap(
            spacing: 2,
            children: [
              TextButton(
                onPressed: busy ? null : () => _openEditDialog(item),
                style: uiLinkButton(),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: busy ? null : () => _toggleDevice(item),
                style: uiLinkButton(),
                child: Text(item.status == 'Disabled' ? 'Enable' : 'Disable'),
              ),
              TextButton(
                onPressed: busy ? null : () => _requestTest(item),
                style: uiLinkButton(),
                child: const Text('Test'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadDevices() async {
    if (!_hasApi) {
      setState(() {
        _error = 'API base URL missing. Showing local snapshot device status.';
        _items = _fallbackFromSnapshot(widget.snapshot);
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBaseUrl}/api/admin/devices'),
        headers: _adminHeaders(),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to load admin devices'));
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_AdminDeviceItem.fromApi)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _items = _fallbackFromSnapshot(widget.snapshot);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openRegisterDialog() async {
    final payload = await _openDeviceDialog();
    if (payload == null) return;
    await _mutateDevice(
      action: 'register',
      payload: payload,
      busyId: payload['deviceId'] as String?,
    );
  }

  Future<void> _openEditDialog(_AdminDeviceItem item) async {
    final payload = await _openDeviceDialog(item: item);
    if (payload == null) return;
    await _mutateDevice(
      action: 'edit',
      payload: {
        'deviceId': item.deviceId,
        ...payload,
      },
      busyId: item.deviceId,
    );
  }

  Future<Map<String, dynamic>?> _openDeviceDialog(
      {_AdminDeviceItem? item}) async {
    final idController = TextEditingController(text: item?.deviceId ?? '');
    final zoneController =
        TextEditingController(text: item?.zone ?? widget.snapshot.siteName);
    final firmwareController =
        TextEditingController(text: item?.firmwareVersion ?? 'v1.0');

    String sensorType = item?.sensorTypeKey ?? 'gateway';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: Text(item == null ? 'Register Device' : 'Edit Device'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    enabled: item == null,
                    decoration: const InputDecoration(
                      labelText: 'Device ID',
                      hintText: 'ESP32-01',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sensorType,
                    items: const [
                      DropdownMenuItem(
                        value: 'gateway',
                        child: Text('Gateway / ESP32'),
                      ),
                      DropdownMenuItem(
                        value: 'waterLevel',
                        child: Text('Water Level'),
                      ),
                      DropdownMenuItem(
                        value: 'vibration',
                        child: Text('Vibration'),
                      ),
                      DropdownMenuItem(
                        value: 'temperature',
                        child: Text('Temperature'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setStateDialog(() => sensorType = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Sensor Type',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: zoneController,
                    decoration: const InputDecoration(
                      labelText: 'Zone',
                      hintText: 'Zone A - Pump Station',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: firmwareController,
                    decoration: const InputDecoration(
                      labelText: 'Firmware Version',
                      hintText: 'v1.0',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final id = idController.text.trim().toUpperCase();
                  final zone = zoneController.text.trim();
                  final firmware = firmwareController.text.trim();
                  if (id.isEmpty && item == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID is required.')),
                    );
                    return;
                  }
                  if (zone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Zone is required.')),
                    );
                    return;
                  }
                  Navigator.of(context).pop({
                    if (item == null) 'deviceId': id,
                    'sensorType': sensorType,
                    'zone': zone,
                    'firmwareVersion': firmware.isEmpty ? 'v1.0' : firmware,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    idController.dispose();
    zoneController.dispose();
    firmwareController.dispose();
    return result;
  }

  Future<void> _toggleDevice(_AdminDeviceItem item) async {
    final action = item.status == 'Disabled' ? 'enable' : 'disable';
    await _mutateDevice(
      action: action,
      payload: {'deviceId': item.deviceId},
      busyId: item.deviceId,
    );
  }

  Future<void> _requestTest(_AdminDeviceItem item) async {
    await _mutateDevice(
      action: 'test',
      payload: {'deviceId': item.deviceId},
      busyId: item.deviceId,
    );
  }

  Future<void> _mutateDevice({
    required String action,
    required Map<String, dynamic> payload,
    String? busyId,
  }) async {
    if (!_hasApi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud API is not configured.')),
      );
      return;
    }

    final marker = (busyId ?? payload['deviceId']?.toString() ?? action).trim();
    setState(() => _busyIds.add(marker));

    try {
      final body = {
        'action': action,
        ...payload,
      };

      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/admin/devices'),
        headers: {
          ..._adminHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_extractError(resp.body,
            fallback: 'Device operation failed ($action)'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device action "$action" completed.')),
      );
      await _loadDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(marker));
      }
    }
  }

  List<_AdminDeviceItem> _fallbackFromSnapshot(MonitoringSnapshot snapshot) {
    final readingByType = <SensorType, SensorReading>{};
    for (final reading in snapshot.readings) {
      readingByType[reading.type] = reading;
    }

    final now = snapshot.updatedAt;
    final items = <_AdminDeviceItem>[
      _AdminDeviceItem(
        deviceId: 'ESP32-01',
        sensorTypeKey: 'gateway',
        zone: snapshot.siteName,
        status: snapshot.readings.isEmpty ? 'Offline' : 'Online',
        firmwareVersion: 'v1.0',
        lastSync: snapshot.readings.isEmpty ? null : now,
        lastHeartbeat: snapshot.readings.isEmpty ? null : now,
        latestValueLabel: null,
      ),
    ];

    for (final type in activeSensorTypes) {
      final reading = readingByType[type];
      items.add(
        _AdminDeviceItem(
          deviceId: _deviceIdForType(type),
          sensorTypeKey: _sensorTypeKey(type),
          zone: snapshot.siteName,
          status: reading == null ? 'Offline' : 'Online',
          firmwareVersion: 'v1.0',
          lastSync: reading == null ? null : now,
          lastHeartbeat: reading == null ? null : now,
          latestValueLabel:
              reading == null ? null : _formatReading(reading.value, type),
        ),
      );
    }

    return items;
  }

  String _deviceIdForType(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'WL-01';
      case SensorType.vibration:
        return 'VB-01';
      case SensorType.temperature:
        return 'TP-01';
    }
  }

  String _sensorTypeKey(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'waterLevel';
      case SensorType.vibration:
        return 'vibration';
      case SensorType.temperature:
        return 'temperature';
    }
  }

  String _formatReading(double value, SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return '${value.toStringAsFixed(0)}%';
      case SensorType.vibration:
        return '${value.toStringAsFixed(1)} index';
      case SensorType.temperature:
        return '${value.toStringAsFixed(1)}deg C';
    }
  }

  Map<String, String> _adminHeaders() {
    return {
      'x-user-role': 'admin',
      'x-user-id': widget.actorUserId,
    };
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = json['message']?.toString();
      if (message != null && message.trim().isNotEmpty) return message;
    } catch (_) {
      // ignore
    }
    return fallback;
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _DeviceOpsBanner extends StatelessWidget {
  const _DeviceOpsBanner({
    required this.totalCount,
    required this.onlineCount,
    required this.offlineCount,
    required this.disabledCount,
    required this.loading,
    required this.hasApi,
  });

  final int totalCount;
  final int onlineCount;
  final int offlineCount;
  final int disabledCount;
  final bool loading;
  final bool hasApi;

  @override
  Widget build(BuildContext context) {
    final bg = loading
        ? const Color(0xFFEFF4FA)
        : (offlineCount > 0
            ? const Color(0xFFFFF5E6)
            : const Color(0xFFEAF7EF));
    final border = loading
        ? const Color(0xFFCCDAEF)
        : (offlineCount > 0
            ? const Color(0xFFF2D094)
            : const Color(0xFFB8DFC4));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.card),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            loading
                ? Icons.sync_rounded
                : (offlineCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded),
            color: loading
                ? UiColors.brand
                : (offlineCount > 0 ? UiColors.warning : UiColors.healthy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasApi
                  ? 'Total $totalCount | Online $onlineCount | Offline $offlineCount | Disabled $disabledCount'
                  : 'API not configured. Showing local snapshot fallback for devices.',
              style: UiText.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDeviceItem {
  const _AdminDeviceItem({
    required this.deviceId,
    required this.sensorTypeKey,
    required this.zone,
    required this.status,
    required this.firmwareVersion,
    required this.lastSync,
    required this.lastHeartbeat,
    required this.latestValueLabel,
  });

  final String deviceId;
  final String sensorTypeKey;
  final String zone;
  final String status;
  final String firmwareVersion;
  final DateTime? lastSync;
  final DateTime? lastHeartbeat;
  final String? latestValueLabel;

  String get sensorTypeLabel {
    switch (sensorTypeKey) {
      case 'gateway':
        return 'Gateway / ESP32';
      case 'waterLevel':
        return 'Water Level';
      case 'vibration':
        return 'Vibration';
      case 'temperature':
        return 'Temperature';
      default:
        return sensorTypeKey;
    }
  }

  UiBadgeTone get statusTone {
    switch (status) {
      case 'Online':
        return UiBadgeTone.healthy;
      case 'Disabled':
        return UiBadgeTone.noTelemetry;
      default:
        return UiBadgeTone.warning;
    }
  }

  static _AdminDeviceItem fromApi(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString())?.toLocal();
    }

    final latestValue = json['latestValue'];
    final latestUnit = (json['latestUnit'] ?? '').toString();
    String? latestValueLabel;
    if (latestValue is num) {
      final v = latestValue.toDouble();
      if (latestUnit.trim().isEmpty) {
        latestValueLabel = v.toStringAsFixed(2);
      } else {
        final text =
            latestUnit == '%' ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
        latestValueLabel = '$text $latestUnit'.trim();
      }
    }

    return _AdminDeviceItem(
      deviceId: (json['deviceId'] ?? '--').toString(),
      sensorTypeKey: (json['sensorType'] ?? 'gateway').toString(),
      zone: (json['zone'] ?? 'Unknown Zone').toString(),
      status: (json['status'] ?? 'Offline').toString(),
      firmwareVersion: (json['firmwareVersion'] ?? 'v1.0').toString(),
      lastSync: parseDate(json['lastSync']),
      lastHeartbeat: parseDate(json['lastHeartbeat']),
      latestValueLabel: latestValueLabel,
    );
  }
}
