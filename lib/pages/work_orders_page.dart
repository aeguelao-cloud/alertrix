import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/ui_kit.dart';

class WorkOrdersPage extends StatefulWidget {
  const WorkOrdersPage({super.key, this.apiBaseUrl});

  final String? apiBaseUrl;

  @override
  State<WorkOrdersPage> createState() => _WorkOrdersPageState();
}

class _WorkOrdersPageState extends State<WorkOrdersPage> {
  final TextEditingController _alertIdController = TextEditingController();
  String _statusFilter = 'ALL';
  bool _loading = false;
  String? _error;
  List<_WorkOrderItem> _items = const <_WorkOrderItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _alertIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final sectionSpace = uiSectionSpacing(context);
    final openCount =
        _items.where((item) => item.status.toUpperCase() == 'OPEN').length;
    final closedCount =
        _items.where((item) => item.status.toUpperCase() == 'CLOSED').length;
    final criticalCount = _items
        .where((item) =>
            _normalizeSeverity(item.alertInfo?.severity).toLowerCase() ==
            'critical')
        .length;
    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertrix',
          title: 'Work Orders',
          subtitle: 'Track escalated incidents and field response status.',
        ),
        SizedBox(height: sectionSpace),
        _WorkOrderOpsBanner(
          totalCount: _items.length,
          openCount: openCount,
          closedCount: closedCount,
          criticalCount: criticalCount,
          loading: _loading,
          hasError: _error != null,
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  uiIsCompactLayout(context) || constraints.maxWidth < 920;
              final searchInput = SizedBox(
                height: 52,
                child: TextField(
                  controller: _alertIdController,
                  decoration: const InputDecoration(
                    hintText: 'Search by Alert ID (e.g. ALERT-1774450055956)',
                  ),
                  onSubmitted: (_) => _load(),
                ),
              );
              final statusFilter = DropdownButtonFormField<String>(
                initialValue: _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All status')),
                  DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                  DropdownMenuItem(value: 'CLOSED', child: Text('Closed')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _statusFilter = value);
                  _load();
                },
              );
              final searchBtn = SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _load,
                  style: uiPrimaryButton(),
                  child: const Text('Search'),
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchInput,
                    const SizedBox(height: UiSpace.gap),
                    statusFilter,
                    const SizedBox(height: UiSpace.gap),
                    searchBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: searchInput),
                  const SizedBox(width: UiSpace.gap),
                  SizedBox(width: 180, child: statusFilter),
                  const SizedBox(width: UiSpace.gap),
                  SizedBox(width: 120, child: searchBtn),
                ],
              );
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: UiSpace.gap),
          Container(
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
        Text('Work Orders (${_items.length})', style: UiText.sectionTitle),
        const SizedBox(height: UiSpace.gap),
        UiCard(
          big: true,
          child: _items.isEmpty && !_loading
              ? UiEmptyState(
                  icon: Icons.assignment_late_outlined,
                  title: 'No escalated incidents yet.',
                  subtitle:
                      'When an alert is escalated from the Incident Queue, a work order will be created here for field response tracking.',
                  primaryAction: OutlinedButton(
                    onPressed: () {
                      _alertIdController.clear();
                      setState(() => _statusFilter = 'ALL');
                      _load();
                    },
                    style: uiSecondaryButton(),
                    child: const Text('Clear search'),
                  ),
                )
              : compact
                  ? Column(
                      children: _items
                          .map((item) => _buildCompactWorkOrderCard(item))
                          .toList(growable: false),
                    )
                  : UiResponsiveTable(
                      minWidth: 1180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const UiTableHeaderRow(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text('Work Order ID',
                                      style: UiText.cardTitle)),
                              Expanded(
                                  flex: 2,
                                  child: Text('Alert ID',
                                      style: UiText.cardTitle)),
                              Expanded(
                                  flex: 5,
                                  child: Text('Issue Detail',
                                      style: UiText.cardTitle)),
                              Expanded(
                                  flex: 2,
                                  child: Text('Priority',
                                      style: UiText.cardTitle)),
                              Expanded(
                                  flex: 2,
                                  child:
                                      Text('Status', style: UiText.cardTitle)),
                              Expanded(
                                  flex: 2,
                                  child: Text('Updated At',
                                      style: UiText.cardTitle)),
                              Expanded(
                                  flex: 1,
                                  child:
                                      Text('Action', style: UiText.cardTitle)),
                            ],
                          ),
                          const SizedBox(height: UiSpace.gap),
                          ..._items
                              .map((item) => _buildDesktopWorkOrderRow(item)),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDesktopWorkOrderRow(_WorkOrderItem item) {
    final issueTitle = item.alertInfo?.title ?? 'No linked alert detail';
    final severityText = _normalizeSeverity(item.alertInfo?.severity);
    final zoneText = item.alertInfo?.zone ?? '--';
    final triggerText = item.alertInfo?.triggerValue ?? '--';
    final timeText = item.alertInfo?.detectedAt ?? '--';
    final priority = _priorityLabel(item, severityText);
    final priorityTone = _priorityTone(priority);
    final statusTone = _statusTone(item.status);
    return UiTableBodyRow(
      height: 70,
      children: [
        Expanded(flex: 2, child: Text(item.workOrderId, style: UiText.body)),
        Expanded(flex: 2, child: Text(item.alertId, style: UiText.body)),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(issueTitle,
                  style: UiText.cardTitle, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(
                children: [
                  UiBadge(
                    label: severityText == '--' ? 'No severity' : severityText,
                    tone: _severityTone(severityText),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$zoneText | Trigger $triggerText | $timeText',
                      style: UiText.helper,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: UiBadge(label: priority, tone: priorityTone),
          ),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: UiBadge(label: _statusLabel(item.status), tone: statusTone),
          ),
        ),
        Expanded(flex: 2, child: Text(item.createdAt, style: UiText.helper)),
        Expanded(
          flex: 1,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showWorkOrderDetail(item),
              style: uiLinkButton(),
              child: const Text('Open'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactWorkOrderCard(_WorkOrderItem item) {
    final issueTitle = item.alertInfo?.title ?? 'No linked alert detail';
    final severityText = _normalizeSeverity(item.alertInfo?.severity);
    final zoneText = item.alertInfo?.zone ?? '--';
    final triggerText = item.alertInfo?.triggerValue ?? '--';
    final priority = _priorityLabel(item, severityText);
    final priorityTone = _priorityTone(priority);
    final statusTone = _statusTone(item.status);
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
              Expanded(child: Text(item.workOrderId, style: UiText.cardTitle)),
              UiBadge(label: _statusLabel(item.status), tone: statusTone),
            ],
          ),
          const SizedBox(height: 4),
          Text('Alert: ${item.alertId}', style: UiText.helper),
          const SizedBox(height: 8),
          Text(issueTitle, style: UiText.body),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              UiBadge(
                label: severityText == '--' ? 'No severity' : severityText,
                tone: _severityTone(severityText),
              ),
              UiBadge(label: priority, tone: priorityTone),
            ],
          ),
          const SizedBox(height: 6),
          Text('Zone: $zoneText', style: UiText.helper),
          Text('Trigger: $triggerText', style: UiText.helper),
          Text('Updated: ${item.createdAt}', style: UiText.helper),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showWorkOrderDetail(item),
              style: uiLinkButton(),
              child: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWorkOrderDetail(_WorkOrderItem item) async {
    final issueTitle = item.alertInfo?.title ?? 'No linked alert detail';
    final severityText = _normalizeSeverity(item.alertInfo?.severity);
    final zoneText = item.alertInfo?.zone ?? '--';
    final triggerText = item.alertInfo?.triggerValue ?? '--';
    final timeText = item.alertInfo?.detectedAt ?? '--';
    final priority = _priorityLabel(item, severityText);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Work Order ${item.workOrderId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(issueTitle, style: UiText.cardTitle),
            const SizedBox(height: 8),
            Text('Alert ID: ${item.alertId}', style: UiText.body),
            const SizedBox(height: 4),
            Text('Status: ${_statusLabel(item.status)}', style: UiText.body),
            const SizedBox(height: 4),
            Text('Priority: $priority', style: UiText.body),
            const SizedBox(height: 4),
            Text('Severity: $severityText', style: UiText.body),
            const SizedBox(height: 4),
            Text('Zone: $zoneText', style: UiText.body),
            const SizedBox(height: 4),
            Text('Trigger: $triggerText', style: UiText.body),
            const SizedBox(height: 4),
            Text('Detected At: $timeText', style: UiText.body),
            const SizedBox(height: 4),
            Text('Updated At: ${item.createdAt}', style: UiText.body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final apiBaseUrl = (widget.apiBaseUrl ?? '').trim();
    if (apiBaseUrl.isEmpty) {
      setState(() {
        _items = const <_WorkOrderItem>[];
        _error = 'API base URL missing.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = <String, String>{'limit': '100'};
      if (_statusFilter != 'ALL') query['status'] = _statusFilter;
      final alertId = _alertIdController.text.trim();
      if (alertId.isNotEmpty) query['alertId'] = alertId;

      final uri = Uri.parse('$apiBaseUrl/api/work-orders')
          .replace(queryParameters: query);
      final resp = await http.get(uri);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Query failed (${resp.statusCode})');
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final baseList = (body['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_WorkOrderItem.fromJson)
          .toList(growable: false);

      final alertsResp = await http.get(Uri.parse('$apiBaseUrl/api/alerts'));
      final alertById = <String, _AlertInfo>{};
      if (alertsResp.statusCode >= 200 && alertsResp.statusCode < 300) {
        final alertsBody = jsonDecode(alertsResp.body) as Map<String, dynamic>;
        final alerts =
            (alertsBody['items'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>();
        for (final alert in alerts) {
          final id = alert['alertId']?.toString();
          if (id == null || id.isEmpty) continue;
          alertById[id] = _AlertInfo(
            title: alert['title']?.toString() ?? '--',
            severity: alert['severity']?.toString() ?? '--',
            zone: alert['zone']?.toString() ?? '--',
            triggerValue: alert['triggerValue']?.toString() ?? '--',
            detectedAt:
                _WorkOrderItem.formatTime(alert['detectedAt']?.toString()),
          );
        }
      }

      final list = baseList
          .map((item) => item.copyWith(alertInfo: alertById[item.alertId]))
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  static String _normalizeSeverity(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    if (value.isEmpty) return '--';
    if (value == 'CRITICAL') return 'Critical';
    if (value == 'WARNING') return 'Warning';
    return value[0] + value.substring(1).toLowerCase();
  }

  static String _priorityLabel(_WorkOrderItem item, String severityText) {
    if (severityText == 'Critical') return 'Critical';
    if (severityText == 'Warning') return 'Warning';
    return item.status.toUpperCase() == 'OPEN' ? 'Open' : 'Normal';
  }

  static UiBadgeTone _priorityTone(String priority) {
    switch (priority) {
      case 'Critical':
        return UiBadgeTone.critical;
      case 'Warning':
        return UiBadgeTone.warning;
      case 'Open':
        return UiBadgeTone.warning;
      default:
        return UiBadgeTone.stable;
    }
  }

  static UiBadgeTone _statusTone(String status) {
    return status.toUpperCase() == 'OPEN'
        ? UiBadgeTone.warning
        : UiBadgeTone.healthy;
  }

  static UiBadgeTone _severityTone(String severity) {
    switch (severity) {
      case 'Critical':
        return UiBadgeTone.critical;
      case 'Warning':
        return UiBadgeTone.warning;
      case 'No severity':
      case '--':
        return UiBadgeTone.noTelemetry;
      default:
        return UiBadgeTone.stable;
    }
  }

  static String _statusLabel(String status) {
    return status.toUpperCase() == 'OPEN' ? 'Open' : 'Closed';
  }
}

class _WorkOrderOpsBanner extends StatelessWidget {
  const _WorkOrderOpsBanner({
    required this.totalCount,
    required this.openCount,
    required this.closedCount,
    required this.criticalCount,
    required this.loading,
    required this.hasError,
  });

  final int totalCount;
  final int openCount;
  final int closedCount;
  final int criticalCount;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final tone = hasError
        ? UiBadgeTone.warning
        : (criticalCount > 0
            ? UiBadgeTone.critical
            : (openCount > 0 ? UiBadgeTone.warning : UiBadgeTone.healthy));
    final bg = switch (tone) {
      UiBadgeTone.critical => const Color(0xFFFFECEC),
      UiBadgeTone.warning => const Color(0xFFFFF5E6),
      _ => const Color(0xFFEAF7EF),
    };
    final border = switch (tone) {
      UiBadgeTone.critical => const Color(0xFFF3B0B0),
      UiBadgeTone.warning => const Color(0xFFF2D094),
      _ => const Color(0xFFB8DFC4),
    };
    final icon = hasError
        ? Icons.sync_problem_rounded
        : (criticalCount > 0
            ? Icons.assignment_late_rounded
            : (openCount > 0
                ? Icons.assignment_ind_rounded
                : Icons.assignment_turned_in_rounded));
    final title = hasError
        ? 'Work order sync degraded'
        : (criticalCount > 0
            ? 'Critical work orders require field action'
            : (openCount > 0
                ? 'Open work orders pending execution'
                : 'Work order queue stable'));

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
            icon,
            color: tone == UiBadgeTone.critical
                ? UiColors.danger
                : (tone == UiBadgeTone.warning
                    ? UiColors.warning
                    : UiColors.healthy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UiText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'Total: $totalCount | Open: $openCount | Closed: $closedCount | Critical: $criticalCount${loading ? ' | Syncing...' : ''}',
                  style: UiText.helper,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkOrderItem {
  const _WorkOrderItem({
    required this.workOrderId,
    required this.alertId,
    required this.status,
    required this.assignee,
    required this.createdAt,
    required this.alertInfo,
  });

  final String workOrderId;
  final String alertId;
  final String status;
  final String assignee;
  final String createdAt;
  final _AlertInfo? alertInfo;

  factory _WorkOrderItem.fromJson(Map<String, dynamic> json) {
    return _WorkOrderItem(
      workOrderId: json['workOrderId']?.toString() ?? '--',
      alertId: json['alertId']?.toString() ?? '--',
      status: json['status']?.toString() ?? '--',
      assignee: json['assignee']?.toString() ?? '--',
      createdAt: formatTime(json['createdAt']?.toString()),
      alertInfo: null,
    );
  }

  _WorkOrderItem copyWith({_AlertInfo? alertInfo}) {
    return _WorkOrderItem(
      workOrderId: workOrderId,
      alertId: alertId,
      status: status,
      assignee: assignee,
      createdAt: createdAt,
      alertInfo: alertInfo,
    );
  }

  static String formatTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '--';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _AlertInfo {
  const _AlertInfo({
    required this.title,
    required this.severity,
    required this.zone,
    required this.triggerValue,
    required this.detectedAt,
  });

  final String title;
  final String severity;
  final String zone;
  final String triggerValue;
  final String detectedAt;
}
