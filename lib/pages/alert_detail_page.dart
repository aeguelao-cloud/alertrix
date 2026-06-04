import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../models/monitoring_models.dart';

String formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

double warningThreshold(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return 70;
    case SensorType.vibration:
      return 2.8;
    case SensorType.temperature:
      return 35;
  }
}

double criticalThreshold(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return 85;
    case SensorType.vibration:
      return 4.0;
    case SensorType.temperature:
      return 40;
  }
}

String formatSensorValue(double value, SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return '${value.toStringAsFixed(0)}%';
    case SensorType.vibration:
      return '${value.toStringAsFixed(1)} mm/s RMS';
    case SensorType.temperature:
      return '${value.toStringAsFixed(1)}deg C';
  }
}

SensorType inferSensorTypeFromAlertTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('water')) return SensorType.waterLevel;
  if (lower.contains('vibration')) return SensorType.vibration;
  if (lower.contains('temp')) return SensorType.temperature;
  return SensorType.waterLevel;
}

String titleCaseAlert(String raw) {
  if (raw.isEmpty) return raw;
  final normalized = raw
      .replaceAll('waterLevel', 'Water level')
      .replaceAll('temperature', 'Temperature')
      .replaceAll('vibration', 'Vibration')
      .trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

enum AlertHandlingStatus {
  active('Active'),
  acknowledged('Acknowledged'),
  falseAlarm('False Alarm'),
  resolved('Resolved');

  const AlertHandlingStatus(this.label);
  final String label;
}

class AlertDetailPage extends StatefulWidget {
  const AlertDetailPage({
    super.key,
    required this.alert,
    required this.role,
    this.onConfirm,
    this.onResolve,
    this.onIgnore,
    this.onCreateWorkOrder,
    this.onSilenceBuzzer,
    this.deviceBuzzerSilenced = false,
    this.onLoadIncidentEvents,
  });

  final AlertEvent alert;
  final UserRole role;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onResolve;
  final Future<void> Function()? onIgnore;
  final Future<String> Function()? onCreateWorkOrder;
  final Future<void> Function()? onSilenceBuzzer;
  final bool deviceBuzzerSilenced;
  final Future<List<IncidentSensorEvent>> Function()? onLoadIncidentEvents;

  @override
  State<AlertDetailPage> createState() => _AlertDetailPageState();
}

class _AlertDetailPageState extends State<AlertDetailPage> {
  late AlertHandlingStatus _status;
  String? _workOrderId;
  String? _silenceDebugMessage;
  bool _busy = false;
  bool _eventLoading = false;
  String? _eventError;
  List<IncidentSensorEvent> _events = const <IncidentSensorEvent>[];

  bool get _isAdmin => widget.role == UserRole.admin;

  SensorType get _metric => inferSensorTypeFromAlertTitle(widget.alert.title);

  double get _warning => warningThreshold(_metric);
  double get _critical => criticalThreshold(_metric);

  String get _currentValueText {
    final raw = widget.alert.triggerValue?.trim();
    if (raw == null || raw.isEmpty) return 'No data';
    return raw;
  }

  double? get _currentValueNumber {
    final raw = widget.alert.triggerValue;
    if (raw == null) return null;
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  double? get _exceededBy {
    final current = _currentValueNumber;
    if (current == null) return null;
    return current - _critical;
  }

  @override
  void initState() {
    super.initState();
    _status = _mapIncidentStatus(widget.alert.status);
    _loadIncidentEvents();
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = widget.alert.severity.color;
    final severityLabel = widget.alert.severity.label;

    return Scaffold(
      appBar: AppBar(title: const Text('Incident Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.warning_amber_rounded,
                          color: severityColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titleCaseAlert(widget.alert.title),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 19),
                      ),
                    ),
                    _chip(severityLabel, severityColor.withValues(alpha: 0.14),
                        severityColor),
                    const SizedBox(width: 6),
                    _chip(_status.label, const Color(0xFFEAF3F5),
                        const Color(0xFF0A7E8C)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metaChip(Icons.place_outlined, widget.alert.zone),
                    _metaChip(Icons.memory_outlined, 'ESP32-01'),
                    _metaChip(
                        Icons.schedule, formatDateTime(widget.alert.timestamp)),
                    _metaChip(Icons.tag, 'ID: ${widget.alert.id}'),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2ECF0)),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _kv('Current value', _currentValueText),
                      _kv('Warning threshold',
                          formatSensorValue(_warning, _metric)),
                      _kv('Critical threshold',
                          formatSensorValue(_critical, _metric)),
                      _kv(
                        'Exceeded by',
                        _exceededBy == null
                            ? 'Unknown'
                            : (_exceededBy! <= 0
                                ? 'Not exceeded'
                                : formatSensorValue(_exceededBy!, _metric)),
                        valueColor: _exceededBy == null
                            ? const Color(0xFF5F727A)
                            : (_exceededBy! > 0
                                ? const Color(0xFFC93C3C)
                                : const Color(0xFF2F8F46)),
                      ),
                    ],
                  ),
                ),
                if (_workOrderId != null) ...[
                  const SizedBox(height: 10),
                  Text('Work order linked: $_workOrderId',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recommended Actions',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'Priority: acknowledge this incident first, then escalate to work order if field action is required.',
                  style: TextStyle(color: Color(0xFF5F727A), fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_busy ||
                            _status == AlertHandlingStatus.acknowledged ||
                            _status == AlertHandlingStatus.falseAlarm ||
                            _status == AlertHandlingStatus.resolved)
                        ? null
                        : _acknowledge,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Acknowledge Incident'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_busy || _status != AlertHandlingStatus.acknowledged)
                            ? null
                            : _markResolved,
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Resolve Incident'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _silenceBuzzer,
                    icon: Icon(widget.deviceBuzzerSilenced
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded),
                    label: Text(widget.deviceBuzzerSilenced
                        ? 'Enable Buzzer'
                        : 'Silence Buzzer'),
                  ),
                ),
                if (_silenceDebugMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _silenceDebugMessage!,
                    style: const TextStyle(
                      color: Color(0xFF0A7E8C),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _createWorkOrder,
                      icon: const Icon(Icons.assignment_outlined),
                      label: const Text('Escalate to Work Order'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _markFalseAlarm,
                      icon: const Icon(Icons.report_gmailerrorred,
                          color: Color(0xFFC93C3C)),
                      label: const Text('Mark as False Alarm',
                          style: TextStyle(color: Color(0xFFC93C3C))),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sensor Event History',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'Raw threshold-trigger events linked to this incident.',
                  style: TextStyle(color: Color(0xFF5F727A), fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (_eventLoading) const LinearProgressIndicator(minHeight: 2),
                if (_eventError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _eventError!,
                    style: const TextStyle(
                      color: Color(0xFFC93C3C),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (!_eventLoading && _events.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No raw events available for this incident yet.',
                    style: TextStyle(color: Color(0xFF5F727A)),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  ..._events.take(120).map(_eventRow),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  'Current role: ${widget.role.label}. '
                  '${_isAdmin ? 'Admin can acknowledge, resolve, and escalate.' : 'User can acknowledge only.'}',
                  style: const TextStyle(color: Color(0xFF5F727A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadIncidentEvents() async {
    final loader = widget.onLoadIncidentEvents;
    if (loader == null) return;
    setState(() {
      _eventLoading = true;
      _eventError = null;
    });
    try {
      final items = await loader();
      if (!mounted) return;
      setState(() {
        _events = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _eventError = '$error'.replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _eventLoading = false);
      }
    }
  }

  Widget _eventRow(IncidentSensorEvent event) {
    final toneColor = event.severity == SensorLevel.critical
        ? const Color(0xFFC93C3C)
        : (event.severity == SensorLevel.warning
            ? const Color(0xFFE09D25)
            : const Color(0xFF2F8F46));
    final primary = event.measuredValue ?? '--';
    final meta = [
      if (event.zone != null && event.zone!.trim().isNotEmpty) event.zone!,
      if (event.deviceId != null && event.deviceId!.trim().isNotEmpty)
        event.deviceId!,
      if (event.ingestTransport != null &&
          event.ingestTransport!.trim().isNotEmpty)
        event.ingestTransport!,
    ].join(' | ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: toneColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.severity.label} | $primary',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: const TextStyle(
                      color: Color(0xFF5F727A),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatDateTime(event.capturedAt),
            style: const TextStyle(color: Color(0xFF5F727A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFEAF2F6),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1A3540)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF1A3540), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _kv(String key, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(key,
            style: const TextStyle(color: Color(0xFF5F727A), fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
              fontWeight: FontWeight.w800,
              color: valueColor ?? const Color(0xFF12242B)),
        ),
      ],
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Future<void> _acknowledge() async {
    await _runAction(() async {
      if (widget.onConfirm != null) {
        await widget.onConfirm!();
      }
      setState(() => _status = AlertHandlingStatus.acknowledged);
      _toast('Incident acknowledged.');
    });
  }

  Future<void> _silenceBuzzer() async {
    if (mounted) {
      setState(
          () => _silenceDebugMessage = 'Button clicked, sending request...');
    }
    final action = widget.onSilenceBuzzer;
    if (action == null) {
      if (!mounted) return;
      setState(() => _silenceDebugMessage =
          'Button clicked, but action is not connected.');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unavailable'),
          content: const Text('Buzzer action is not connected on this page.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _silenceDebugMessage = 'Request succeeded.');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Success'),
          content: Text(widget.deviceBuzzerSilenced
              ? 'Buzzer has been enabled.'
              : 'Buzzer has been silenced.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _silenceDebugMessage = 'Request failed.');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Failed'),
          content: const Text('Failed to update buzzer. Please try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markFalseAlarm() async {
    await _runAction(() async {
      if (widget.onIgnore != null) {
        await widget.onIgnore!();
      }
      setState(() => _status = AlertHandlingStatus.falseAlarm);
      _toast('Marked as false alarm.');
    });
  }

  Future<void> _markResolved() async {
    await _runAction(() async {
      if (widget.onResolve != null) {
        await widget.onResolve!();
      }
      setState(() => _status = AlertHandlingStatus.resolved);
      _toast('Incident resolved.');
    });
  }

  Future<void> _createWorkOrder() async {
    await _runAction(() async {
      String id;
      if (widget.onCreateWorkOrder != null) {
        id = await widget.onCreateWorkOrder!();
      } else {
        final now = DateTime.now().millisecondsSinceEpoch.toString();
        id = 'WO-${now.substring(now.length - 6)}';
      }
      setState(() => _workOrderId = id);
      _toast('Work order created: $id');
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast('Action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  AlertHandlingStatus _mapIncidentStatus(IncidentStatus status) {
    return switch (status) {
      IncidentStatus.active => AlertHandlingStatus.active,
      IncidentStatus.acknowledged => AlertHandlingStatus.acknowledged,
      IncidentStatus.resolved => AlertHandlingStatus.resolved,
      IncidentStatus.closed => AlertHandlingStatus.falseAlarm,
    };
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A20303A), blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: child,
    );
  }
}
