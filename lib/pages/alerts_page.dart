import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import '../theme/severity_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/alert_card.dart';
import '../widgets/dashboard_layout.dart';
import '../widgets/incident_zero_state.dart';
import '../widgets/section_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui_kit.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.snapshot,
    required this.role,
    this.apiBaseUrl,
    required this.onOpenAlertDetail,
    required this.onAcknowledgeVisible,
    required this.onLoadMoreIncidents,
    required this.onLeaveIncidentQueue,
  });

  final MonitoringSnapshot snapshot;
  final UserRole role;
  final String? apiBaseUrl;
  final ValueChanged<AlertEvent> onOpenAlertDetail;
  final Future<int> Function(List<String> alertIds) onAcknowledgeVisible;
  final Future<bool> Function() onLoadMoreIncidents;
  final Future<void> Function() onLeaveIncidentQueue;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  static const int _incidentPageSize = 60;
  static const int _rawEventsPageSize = 80;
  static const int _userDetailsPageSize = 40;

  bool _incidentMode = true;
  SensorLevel? _severityFilter;
  int _incidentVisibleLimit = _incidentPageSize;
  int _rawEventsVisibleLimit = _rawEventsPageSize;
  int _userDetailsVisibleLimit = _userDetailsPageSize;
  bool _ackProcessing = false;
  final Set<String> _acknowledgedIds = <String>{};
  bool _historyLoading = false;
  bool _loadingMoreIncidents = false;
  bool _allowAutoLoadFromServer = false;
  String? _historyError;
  List<_HistoryAlert> _historyAlerts = const <_HistoryAlert>[];

  bool get _isAdmin => widget.role == UserRole.admin;
  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!_isAdmin) {
      _fetchUserAlertHistory();
    }
  }

  @override
  void dispose() {
    unawaited(widget.onLeaveIncidentQueue());
    super.dispose();
  }

  Widget _buildUserAlertsView({
    required bool compact,
    required double sectionSpace,
    required List<AlertEvent> activeAlerts,
  }) {
    final sortedActive = activeAlerts.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final criticalCount = sortedActive
        .where((alert) => alert.severity == SensorLevel.critical)
        .length;
    final warningCount = sortedActive
        .where((alert) => alert.severity == SensorLevel.warning)
        .length;
    final acknowledgedCount = sortedActive
        .where((alert) =>
            _acknowledgedIds.contains(alert.id) ||
            alert.status == IncidentStatus.acknowledged)
        .length;
    final visibleActive =
        sortedActive.take(_userDetailsVisibleLimit).toList(growable: false);
    final visibleDetailRows = visibleActive
        .map(
          (alert) => _HistoryAlert.fromActiveAlert(
            alert,
            acknowledged: _acknowledgedIds.contains(alert.id),
          ),
        )
        .toList(growable: false);
    final hasMoreDetailRows = sortedActive.length > visibleActive.length;

    return DashboardLayout(
      title: 'Active Incidents',
      subtitle:
          'Track active incidents, open details, review history, and acknowledge incidents.',
      trailing: StatusBadge(
        label:
            sortedActive.isEmpty ? 'No active incidents' : 'Active incidents',
        tone: criticalCount > 0
            ? UiBadgeTone.critical
            : (warningCount > 0 ? UiBadgeTone.warning : UiBadgeTone.healthy),
        icon: sortedActive.isEmpty
            ? Icons.check_circle_rounded
            : Icons.notifications_active_rounded,
        prominent: true,
      ),
      children: [
        _TopStatGrid(
          items: [
            _TopStatItem(
              label: 'Active Incidents',
              value: '${sortedActive.length}',
              tone: sortedActive.isEmpty
                  ? UiBadgeTone.stable
                  : (criticalCount > 0
                      ? UiBadgeTone.critical
                      : UiBadgeTone.warning),
            ),
            _TopStatItem(
              label: 'Critical',
              value: '$criticalCount',
              tone: criticalCount == 0
                  ? UiBadgeTone.stable
                  : UiBadgeTone.critical,
            ),
            _TopStatItem(
              label: 'Warning',
              value: '$warningCount',
              tone:
                  warningCount == 0 ? UiBadgeTone.stable : UiBadgeTone.warning,
            ),
            _TopStatItem(
              label: 'Acknowledged',
              value: '$acknowledgedCount',
              tone: acknowledgedCount == 0
                  ? UiBadgeTone.stable
                  : UiBadgeTone.healthy,
            ),
          ],
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Active Incidents',
                subtitle:
                    'Current warning and critical alerts that need review.',
                icon: Icons.notification_important_rounded,
              ),
              const SizedBox(height: 10),
              if (sortedActive.isEmpty)
                const IncidentZeroState(minHeight: 220)
              else
                ...sortedActive.take(6).map(
                      (alert) => AlertCard(
                        alertType: _titleCaseAlert(alert.title),
                        deviceId: _sensorIdForAlert(alert),
                        zone: alert.zone,
                        measuredValue: alert.triggerValue ?? 'Not reported',
                        threshold:
                            _thresholdByAlertTitle(alert.title, alert.severity),
                        timestamp: formatIncidentRelativeTime(alert.timestamp),
                        status: _acknowledgedIds.contains(alert.id)
                            ? IncidentStatus.acknowledged.label
                            : alert.status.label,
                        severity: alert.severity,
                        occurrences: alert.eventCount,
                        onOpen: () => widget.onOpenAlertDetail(alert),
                        onAcknowledge: (_ackProcessing ||
                                _acknowledgedIds.contains(alert.id) ||
                                alert.status != IncidentStatus.active)
                            ? null
                            : () => _acknowledgeVisible([alert]),
                        acknowledgeBusy: _ackProcessing,
                        compact: compact,
                      ),
                    ),
            ],
          ),
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          big: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Incident Details',
                subtitle: 'Simplified alert table for user response actions.',
                icon: Icons.table_chart_rounded,
              ),
              const SizedBox(height: 10),
              if (sortedActive.isEmpty)
                const IncidentZeroState(minHeight: 220)
              else if (compact)
                ...visibleDetailRows.map(_buildUserAlertDetailCard)
              else
                UiResponsiveTable(
                  minWidth: 980,
                  child: Column(
                    children: [
                      const UiTableHeaderRow(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text('Time', style: UiText.cardTitle)),
                          Expanded(
                              flex: 3,
                              child:
                                  Text('Alert Type', style: UiText.cardTitle)),
                          Expanded(
                              flex: 2,
                              child: Text('Severity', style: UiText.cardTitle)),
                          Expanded(
                              flex: 3,
                              child: Text('Location', style: UiText.cardTitle)),
                          Expanded(
                              flex: 2,
                              child: Text('Status', style: UiText.cardTitle)),
                          Expanded(
                              flex: 3,
                              child: Text('Action', style: UiText.cardTitle)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...visibleDetailRows.map(_buildUserAlertDetailRow),
                    ],
                  ),
                ),
              if (hasMoreDetailRows) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: compact ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: _showMoreUserDetailRows,
                    style: uiSecondaryButton(),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'Load more details (${sortedActive.length - visibleDetailRows.length} remaining)',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Incident History',
                subtitle:
                    'Recent incident records, including acknowledged/resolved status.',
                icon: Icons.history_rounded,
              ),
              const SizedBox(height: 10),
              if (_historyLoading)
                const LinearProgressIndicator()
              else if (_historyError != null)
                Text(_historyError!, style: UiText.helper),
              const SizedBox(height: 8),
              if (_historyAlerts.isEmpty)
                const Text('No incident history available yet.',
                    style: UiText.body)
              else
                ..._historyAlerts.take(8).map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${formatIncidentRelativeTime(item.timestamp)} - ${item.alertType}',
                                style: UiText.body,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(
                              label: item.statusLabel,
                              tone: _statusTone(item.statusLabel),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserAlertDetailRow(_HistoryAlert alert) {
    final status = alert.statusLabel;
    final canAck = status == 'Active' && !_ackProcessing;
    final critical = alert.severity == SensorLevel.critical;
    return UiTableBodyRow(
      height: 62,
      children: [
        Expanded(
          flex: 2,
          child: Text(formatIncidentRelativeTime(alert.timestamp),
              style: UiText.helper),
        ),
        Expanded(
          flex: 3,
          child: Text(
            alert.alertType,
            style: UiText.body.copyWith(
              fontWeight: FontWeight.w700,
              color: UiColors.textStrong,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: UiSeverityPill(
            label: alert.severityLabel,
            tone: critical ? UiBadgeTone.critical : UiBadgeTone.warning,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(alert.zone, style: UiText.helper),
        ),
        Expanded(
          flex: 2,
          child: StatusBadge(label: status, tone: _statusTone(status)),
        ),
        Expanded(
          flex: 3,
          child: Wrap(
            spacing: 2,
            children: [
              TextButton(
                onPressed: () => widget.onOpenAlertDetail(alert.source),
                style: uiLinkButton(),
                child: const Text('View Details'),
              ),
              TextButton(
                onPressed:
                    canAck ? () => _acknowledgeVisible([alert.source]) : null,
                style: uiLinkButton(),
                child: const Text('Acknowledge Incident'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserAlertDetailCard(_HistoryAlert alert) {
    final status = alert.statusLabel;
    final canAck = status == 'Active' && !_ackProcessing;
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
          Text(alert.alertType, style: UiText.cardTitle),
          const SizedBox(height: 6),
          Text('Time: ${formatIncidentRelativeTime(alert.timestamp)}',
              style: UiText.helper),
          Text('Location: ${alert.zone}', style: UiText.helper),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(
                label: alert.severityLabel,
                tone: alert.severity == SensorLevel.critical
                    ? UiBadgeTone.critical
                    : UiBadgeTone.warning,
              ),
              StatusBadge(label: status, tone: _statusTone(status)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 2,
            children: [
              TextButton(
                onPressed: () => widget.onOpenAlertDetail(alert.source),
                style: uiLinkButton(),
                child: const Text('View Details'),
              ),
              TextButton(
                onPressed:
                    canAck ? () => _acknowledgeVisible([alert.source]) : null,
                style: uiLinkButton(),
                child: const Text('Acknowledge Incident'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AlertsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isAdmin) return;
    if (oldWidget.snapshot.updatedAt != widget.snapshot.updatedAt ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.role != widget.role) {
      _fetchUserAlertHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final sectionSpace = uiSectionSpacing(context);
    final events = widget.snapshot.alerts;
    final filteredEvents = events.where((event) {
      if (_severityFilter != null && event.severity != _severityFilter) {
        return false;
      }
      return true;
    }).toList(growable: false);

    final incidents = _incidentMode
        ? _aggregateIncidents(filteredEvents)
        : const <_DisplayAlert>[];
    final rawEvents = _incidentMode
        ? const <_DisplayAlert>[]
        : filteredEvents.map(_DisplayAlert.fromEvent).toList(growable: false);
    final allDisplayed = _incidentMode ? incidents : rawEvents;
    final displayed = _incidentMode
        ? allDisplayed.take(_incidentVisibleLimit).toList(growable: false)
        : allDisplayed.take(_rawEventsVisibleLimit).toList(growable: false);
    final ackTargetEvents =
        displayed.map((item) => item.source).toList(growable: false);
    final hasHiddenRows = allDisplayed.length > displayed.length;
    _allowAutoLoadFromServer = _isAdmin &&
        _incidentMode &&
        !hasHiddenRows &&
        widget.snapshot.activeIncidentsHasMore;

    final criticalCount =
        allDisplayed.where((a) => a.severity == SensorLevel.critical).length;
    final warningCount =
        allDisplayed.where((a) => a.severity == SensorLevel.warning).length;
    final hasCritical = criticalCount > 0;
    final hasWarning = warningCount > 0;
    final ackDisabled = ackTargetEvents.isEmpty || _ackProcessing;
    final showZeroState = events.isEmpty;

    if (!_isAdmin) {
      return _buildUserAlertsView(
        compact: compact,
        sectionSpace: sectionSpace,
        activeAlerts: filteredEvents,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: DashboardLayout(
        title: 'Incident Queue',
        subtitle:
            'Review active incidents, acknowledge visible items, and escalate when needed.',
        trailing: StatusBadge(
          label: hasCritical
              ? 'Critical active'
              : (hasWarning ? 'Warning active' : 'Queue clear'),
          tone: hasCritical
              ? UiBadgeTone.critical
              : (hasWarning ? UiBadgeTone.warning : UiBadgeTone.healthy),
          icon: hasCritical
              ? Icons.crisis_alert_rounded
              : (hasWarning
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_rounded),
          prominent: true,
        ),
        children: [
          _QueueCommandBanner(
            hasCritical: hasCritical,
            hasWarning: hasWarning,
            criticalCount: criticalCount,
            warningCount: warningCount,
            visibleCount: filteredEvents.length,
            incidentMode: _incidentMode,
          ),
          SizedBox(height: sectionSpace),
          _TopStatGrid(
            items: [
              _TopStatItem(
                label: 'Active Incidents',
                value: '${allDisplayed.length}',
                tone: hasCritical
                    ? UiBadgeTone.critical
                    : (hasWarning ? UiBadgeTone.warning : UiBadgeTone.stable),
              ),
              _TopStatItem(
                label: 'Critical',
                value: '$criticalCount',
                tone: criticalCount == 0
                    ? UiBadgeTone.stable
                    : UiBadgeTone.critical,
              ),
              _TopStatItem(
                label: 'Warning',
                value: '$warningCount',
                tone: warningCount == 0
                    ? UiBadgeTone.stable
                    : UiBadgeTone.warning,
              ),
              _TopStatItem(
                label: 'Visible Events',
                value: '${filteredEvents.length}',
                tone: UiBadgeTone.stable,
              ),
            ],
          ),
          SizedBox(height: sectionSpace),
          UiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Queue Controls',
                  subtitle:
                      'Filter severity, switch grouping, and acknowledge the current view.',
                  icon: Icons.tune_rounded,
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Incident clusters'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Raw events'),
                    ),
                  ],
                  selected: {_incidentMode},
                  onSelectionChanged: (selection) => setState(() {
                    _incidentMode = selection.first;
                    _incidentVisibleLimit = _incidentPageSize;
                    _rawEventsVisibleLimit = _rawEventsPageSize;
                    _userDetailsVisibleLimit = _userDetailsPageSize;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _incidentMode
                      ? 'Showing ${displayed.length} of ${allDisplayed.length} incident clusters grouped by zone, severity, and 10-minute response windows.'
                      : 'Showing ${displayed.length} of ${rawEvents.length} raw event records.',
                  style: UiText.helper,
                ),
                const SizedBox(height: 10),
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: ackDisabled
                              ? null
                              : () => _acknowledgeVisible(ackTargetEvents),
                          style: uiPrimaryButton(),
                          icon: _ackProcessing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.done_all_rounded),
                          label: Text(_ackProcessing
                              ? 'Confirming...'
                              : 'Acknowledge Visible Incidents'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        filteredEvents.isEmpty
                            ? 'No visible incidents to acknowledge'
                            : '${ackTargetEvents.length} visible incident(s) in current view',
                        style: UiText.helper,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: ackDisabled
                            ? null
                            : () => _acknowledgeVisible(ackTargetEvents),
                        style: uiPrimaryButton(),
                        icon: _ackProcessing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.done_all_rounded),
                        label: Text(_ackProcessing
                            ? 'Confirming...'
                            : 'Acknowledge Visible Incidents'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filteredEvents.isEmpty
                              ? 'No visible incidents to acknowledge'
                              : '${ackTargetEvents.length} visible incident(s) in current view',
                          style: UiText.helper,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All Severity'),
                      selected: _severityFilter == null,
                      onSelected: (_) => setState(() {
                        _severityFilter = null;
                        _incidentVisibleLimit = _incidentPageSize;
                        _rawEventsVisibleLimit = _rawEventsPageSize;
                        _userDetailsVisibleLimit = _userDetailsPageSize;
                      }),
                    ),
                    ...SensorLevel.values.map(
                      (level) => ChoiceChip(
                        label: Text(level == SensorLevel.normal
                            ? 'Stable'
                            : level.label),
                        selected: _severityFilter == level,
                        onSelected: (_) => setState(() {
                          _severityFilter = level;
                          _incidentVisibleLimit = _incidentPageSize;
                          _rawEventsVisibleLimit = _rawEventsPageSize;
                          _userDetailsVisibleLimit = _userDetailsPageSize;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: sectionSpace),
          UiCard(
            big: true,
            child: displayed.isEmpty
                ? showZeroState
                    ? const IncidentZeroState(minHeight: 320)
                    : SizedBox(
                        height: 280,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 42,
                                color: Color(0xFF7B8D95),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No incidents match current filters',
                                style: UiText.cardTitle,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Try another severity filter or clear all filters',
                                style: UiText.body,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton(
                                onPressed: () => setState(() {
                                  _severityFilter = null;
                                  _incidentVisibleLimit = _incidentPageSize;
                                  _rawEventsVisibleLimit = _rawEventsPageSize;
                                  _userDetailsVisibleLimit =
                                      _userDetailsPageSize;
                                }),
                                style: uiSecondaryButton(),
                                child: const Text('Clear filters'),
                              ),
                            ],
                          ),
                        ),
                      )
                : compact
                    ? Column(
                        children: [
                          ...displayed.map(_buildCompactIncidentCard),
                          if (hasHiddenRows ||
                              (_incidentMode &&
                                  widget.snapshot.activeIncidentsHasMore)) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _resolveLoadMoreAction(hasHiddenRows),
                                style: uiSecondaryButton(),
                                icon: _loadingMoreIncidents
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more_rounded),
                                label: Text(
                                  hasHiddenRows
                                      ? 'Load more (${allDisplayed.length - displayed.length} remaining)'
                                      : (_loadingMoreIncidents
                                          ? 'Loading incidents...'
                                          : 'Load next incident page'),
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : UiResponsiveTable(
                        minWidth: 1560,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const UiTableHeaderRow(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text('Last Updated',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Device/Zone',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Device ID',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text('Alert Type',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text('Measured Value',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('First Seen / Last Seen',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child:
                                      Text('Severity', style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child:
                                      Text('Status', style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Threshold',
                                      style: UiText.cardTitle),
                                ),
                                Expanded(
                                  flex: 3,
                                  child:
                                      Text('Action', style: UiText.cardTitle),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...displayed.map(
                              (item) {
                                final critical = item.source.severity ==
                                    SensorLevel.critical;
                                final tone = critical
                                    ? UiBadgeTone.critical
                                    : UiBadgeTone.warning;
                                return UiTableBodyRow(
                                  height: 68,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        formatIncidentRelativeTime(
                                            item.latestTimestamp),
                                        style: UiText.helper,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(item.source.zone,
                                          style: UiText.helper),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _sensorIdForAlert(item.source),
                                        style: UiText.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: UiColors.textStrong,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _titleCaseAlert(item.source.title),
                                        style: UiText.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: UiColors.textStrong,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _measuredValueSummary(item),
                                        style: UiText.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: UiColors.textStrong,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${formatIncidentRelativeTime(item.firstTimestamp)}\n${formatIncidentRelativeTime(item.latestTimestamp)}',
                                        style: UiText.helper,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: UiSeverityPill(
                                          label:
                                              critical ? 'Critical' : 'Warning',
                                          tone: tone,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: StatusBadge(
                                          label: item.source.status.label,
                                          tone: tone,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _thresholdByAlertTitle(
                                            item.source.title,
                                            item.source.severity,
                                          ),
                                          style: UiText.helper,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 2,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  widget.onOpenAlertDetail(
                                                      item.source),
                                              style: uiLinkButton(),
                                              child: const Text('View Details'),
                                            ),
                                            TextButton(
                                              onPressed: _ackProcessing
                                                  ? null
                                                  : () => _acknowledgeVisible(
                                                        [item.source],
                                                      ),
                                              style: uiLinkButton(),
                                              child: const Text(
                                                  'Acknowledge Incident'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (hasHiddenRows ||
                                (_incidentMode &&
                                    widget
                                        .snapshot.activeIncidentsHasMore)) ...[
                              const SizedBox(height: 12),
                              Center(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _resolveLoadMoreAction(hasHiddenRows),
                                  style: uiSecondaryButton(),
                                  icon: _loadingMoreIncidents
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_more_rounded),
                                  label: Text(
                                    hasHiddenRows
                                        ? 'Load more (${allDisplayed.length - displayed.length} remaining)'
                                        : (_loadingMoreIncidents
                                            ? 'Loading incidents...'
                                            : 'Load next incident page'),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIncidentCard(_DisplayAlert item) {
    return AlertCard(
      alertType: _titleCaseAlert(item.source.title),
      deviceId: _sensorIdForAlert(item.source),
      zone: item.source.zone,
      measuredValue: _measuredValueSummary(item),
      threshold:
          _thresholdByAlertTitle(item.source.title, item.source.severity),
      timestamp: formatIncidentRelativeTime(item.latestTimestamp),
      status: item.source.status.label,
      severity: item.source.severity,
      occurrences: item.occurrences,
      acknowledgeBusy: _ackProcessing,
      onOpen: () => widget.onOpenAlertDetail(item.source),
      onAcknowledge:
          _ackProcessing ? null : () => _acknowledgeVisible([item.source]),
      compact: true,
    );
  }

  void _showMoreRows() {
    setState(() {
      if (_incidentMode) {
        _incidentVisibleLimit += _incidentPageSize;
      } else {
        _rawEventsVisibleLimit += _rawEventsPageSize;
      }
    });
  }

  VoidCallback? _resolveLoadMoreAction(bool hasHiddenRows) {
    if (hasHiddenRows) {
      return _showMoreRows;
    }
    if (!_incidentMode ||
        !widget.snapshot.activeIncidentsHasMore ||
        _loadingMoreIncidents) {
      return null;
    }
    return () => unawaited(_loadMoreIncidentsFromServer());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_allowAutoLoadFromServer) return false;
    if (_loadingMoreIncidents) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.extentAfter > 260) return false;
    unawaited(_loadMoreIncidentsFromServer());
    return false;
  }

  Future<void> _loadMoreIncidentsFromServer() async {
    if (_loadingMoreIncidents) return;
    if (!_incidentMode || !widget.snapshot.activeIncidentsHasMore) return;
    setState(() => _loadingMoreIncidents = true);
    try {
      await widget.onLoadMoreIncidents();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load more incidents.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMoreIncidents = false);
      }
    }
  }

  void _showMoreUserDetailRows() {
    setState(() {
      _userDetailsVisibleLimit += _userDetailsPageSize;
    });
  }

  Future<void> _acknowledgeVisible(List<AlertEvent> filteredEvents) async {
    if (_ackProcessing) return;
    final ids = filteredEvents.map((e) => e.id).toSet().toList(growable: false);

    setState(() => _ackProcessing = true);
    try {
      final success = await widget.onAcknowledgeVisible(ids);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _acknowledgedIds.add(id);
        }
      });
      if (!_isAdmin) {
        _fetchUserAlertHistory();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Acknowledged $success / ${ids.length} incident(s).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to acknowledge incidents.')),
      );
    } finally {
      if (mounted) {
        setState(() => _ackProcessing = false);
      }
    }
  }

  Future<void> _fetchUserAlertHistory() async {
    if (!_hasApi) {
      if (mounted) {
        setState(() {
          _historyAlerts = widget.snapshot.alerts
              .map((alert) => _HistoryAlert.fromActiveAlert(
                    alert,
                    acknowledged: _acknowledgedIds.contains(alert.id),
                  ))
              .toList(growable: false);
          _historyError = null;
        });
      }
      return;
    }

    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final uri = Uri.parse('${widget.apiBaseUrl}/api/alerts').replace(
        queryParameters: {
          'limit': '120',
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final resp = await http.get(uri);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Failed to load incident history (${resp.statusCode})');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (body['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_HistoryAlert.fromApi)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _historyAlerts = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = '$error'.replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _historyLoading = false);
      }
    }
  }

  UiBadgeTone _statusTone(String statusLabel) {
    switch (statusLabel) {
      case 'Acknowledged':
        return UiBadgeTone.healthy;
      case 'Resolved':
        return UiBadgeTone.stable;
      default:
        return UiBadgeTone.warning;
    }
  }

  List<_DisplayAlert> _aggregateIncidents(List<AlertEvent> events) {
    final buckets = <String, List<AlertEvent>>{};
    for (final event in events) {
      final incidentId = event.incidentId?.trim();
      final key = (incidentId != null && incidentId.isNotEmpty)
          ? 'INCIDENT#$incidentId'
          : (() {
              final bucketStart = DateTime(
                event.timestamp.year,
                event.timestamp.month,
                event.timestamp.day,
                event.timestamp.hour,
                (event.timestamp.minute ~/ 10) * 10,
              );
              return '${event.zone}|${event.severity.name}|${bucketStart.toIso8601String()}|${_sensorKey(event.title)}';
            })();
      buckets.putIfAbsent(key, () => <AlertEvent>[]).add(event);
    }

    final incidents = buckets.values.map((group) {
      group.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final first = group
          .map((item) => item.createdAt ?? item.timestamp)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final latest = group.first.timestamp;
      final occurrences = group.fold<int>(
        0,
        (sum, item) => sum + (item.eventCount < 1 ? 1 : item.eventCount),
      );
      return _DisplayAlert.fromIncident(
        source: group.first,
        occurrences: occurrences,
        firstTimestamp: first,
        latestTimestamp: latest,
      );
    }).toList(growable: false);

    incidents.sort((a, b) {
      final sev = b.severity.index.compareTo(a.severity.index);
      if (sev != 0) return sev;
      return b.latestTimestamp.compareTo(a.latestTimestamp);
    });
    return incidents;
  }

  static String _sensorKey(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('water')) return 'water';
    if (lower.contains('vibration')) return 'vibration';
    if (lower.contains('temp')) return 'temperature';
    return 'misc';
  }

  static String _sensorIdForAlert(AlertEvent alert) {
    final lower = alert.title.toLowerCase();
    if (lower.contains('water')) return 'WL-01';
    if (lower.contains('vibration')) return 'VB-01';
    if (lower.contains('temp')) return 'TP-01';
    return 'SN-01';
  }

  static String _measuredValueSummary(_DisplayAlert item) {
    final trigger = item.source.triggerValue?.trim();
    if (trigger == null || trigger.isEmpty) {
      return 'Not reported';
    }
    return trigger;
  }

  static String _thresholdByAlertTitle(String title, SensorLevel severity) {
    final lower = title.toLowerCase();
    final isCritical = severity == SensorLevel.critical;
    final label = isCritical ? 'Critical' : 'Warning';
    if (lower.contains('water')) {
      return '$label ${isCritical ? '85%' : '70%'}';
    }
    if (lower.contains('vibration')) {
      return '$label ${isCritical ? '4.0' : '2.8'} mm/s';
    }
    if (lower.contains('temp')) {
      return '$label ${isCritical ? '40' : '35'}deg C';
    }
    return label;
  }

  static String _titleCaseAlert(String raw) {
    if (raw.isEmpty) return raw;
    final normalized = raw
        .replaceAll('waterLevel', 'Water level')
        .replaceAll('temperature', 'Temperature')
        .replaceAll('vibration', 'Vibration')
        .trim();
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? fallback;
  }
}

class _TopStatItem {
  const _TopStatItem({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final UiBadgeTone tone;
}

class _TopStatGrid extends StatelessWidget {
  const _TopStatGrid({required this.items});

  final List<_TopStatItem> items;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = uiIsCompactLayout(context);
        final compactSpacing = compact ? 10.0 : UiSpace.gap;
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - UiSpace.gap * 3) / 4
            : !singleColumn && constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : compact && constraints.maxWidth >= 320
                    ? (constraints.maxWidth - compactSpacing) / 2
                    : constraints.maxWidth;
        return Wrap(
          spacing: compactSpacing,
          runSpacing: compactSpacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: UiCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _QueueSeverityDot(tone: item.tone),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(item.label, style: UiText.helper)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        compact
                            ? Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    item.value,
                                    style:
                                        UiText.bigNumber.copyWith(fontSize: 22),
                                  ),
                                  _MutedStatBadge(
                                    label: item.label,
                                    tone: item.tone,
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Text(
                                    item.value,
                                    style:
                                        UiText.bigNumber.copyWith(fontSize: 34),
                                  ),
                                  const SizedBox(width: 8),
                                  _MutedStatBadge(
                                    label: item.label,
                                    tone: item.tone,
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _QueueCommandBanner extends StatelessWidget {
  const _QueueCommandBanner({
    required this.hasCritical,
    required this.hasWarning,
    required this.criticalCount,
    required this.warningCount,
    required this.visibleCount,
    required this.incidentMode,
  });

  final bool hasCritical;
  final bool hasWarning;
  final int criticalCount;
  final int warningCount;
  final int visibleCount;
  final bool incidentMode;

  @override
  Widget build(BuildContext context) {
    final tone = hasCritical
        ? UiBadgeTone.critical
        : (hasWarning ? UiBadgeTone.warning : UiBadgeTone.healthy);
    final bg = switch (tone) {
      UiBadgeTone.critical => SeverityColors.criticalSoft,
      UiBadgeTone.warning => SeverityColors.warningSoft,
      _ => SeverityColors.normalSoft,
    };
    final border = switch (tone) {
      UiBadgeTone.critical => SeverityColors.criticalBorder,
      UiBadgeTone.warning => SeverityColors.warningBorder,
      _ => SeverityColors.normalBorder,
    };
    final icon = hasCritical
        ? Icons.crisis_alert_rounded
        : (hasWarning
            ? Icons.warning_amber_rounded
            : Icons.check_circle_rounded);
    final title = hasCritical
        ? 'Critical alerts waiting for immediate acknowledgment'
        : (hasWarning
            ? 'Warning alerts pending operator review'
            : 'Queue stable with no active incidents');

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
            color: hasCritical
                ? UiColors.danger
                : (hasWarning ? UiColors.warning : UiColors.healthy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UiText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'Critical: $criticalCount | Warning: $warningCount | Visible: $visibleCount | Mode: ${incidentMode ? 'Incident clusters' : 'Raw events'}',
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

class _QueueSeverityDot extends StatelessWidget {
  const _QueueSeverityDot({required this.tone});

  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      UiBadgeTone.critical => UiColors.danger,
      UiBadgeTone.warning => UiColors.warning,
      UiBadgeTone.offline => UiColors.neutral,
      UiBadgeTone.noTelemetry => UiColors.neutral,
      UiBadgeTone.healthy => UiColors.healthy,
      UiBadgeTone.stable => UiColors.brand,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MutedStatBadge extends StatelessWidget {
  const _MutedStatBadge({
    required this.label,
    required this.tone,
  });

  final String label;
  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      UiBadgeTone.critical => (
          SeverityColors.criticalSoft,
          SeverityColors.criticalText,
        ),
      UiBadgeTone.warning => (
          SeverityColors.warningSoft,
          SeverityColors.warningText,
        ),
      UiBadgeTone.stable => (
          SeverityColors.normalSoft,
          SeverityColors.normalText,
        ),
      _ => (
          const Color(0xFFF2F5F7),
          const Color(0xFF73858D),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _HistoryAlert {
  const _HistoryAlert({
    required this.source,
    required this.statusLabel,
    required this.alertType,
    required this.zone,
    required this.timestamp,
  });

  final AlertEvent source;
  final String statusLabel;
  final String alertType;
  final String zone;
  final DateTime timestamp;

  SensorLevel get severity => source.severity;
  String get severityLabel =>
      severity == SensorLevel.critical ? 'Critical' : 'Warning';

  factory _HistoryAlert.fromActiveAlert(
    AlertEvent alert, {
    required bool acknowledged,
  }) {
    return _HistoryAlert(
      source: alert,
      statusLabel:
          acknowledged ? IncidentStatus.acknowledged.label : alert.status.label,
      alertType: _AlertsPageState._titleCaseAlert(alert.title),
      zone: alert.zone,
      timestamp: alert.timestamp,
    );
  }

  factory _HistoryAlert.fromApi(Map<String, dynamic> json) {
    final severityText =
        (json['severity']?.toString() ?? 'WARNING').toUpperCase();
    final severity =
        severityText == 'CRITICAL' ? SensorLevel.critical : SensorLevel.warning;
    final status = incidentStatusFromApi(json['status']?.toString());
    final detectedAt = DateTime.tryParse(
          json['detectedAt']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.now();
    final source = AlertEvent(
      id: json['incidentId']?.toString() ??
          json['alertId']?.toString() ??
          'ALERT-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Alert Triggered',
      zone: json['zone']?.toString() ?? 'Unknown Zone',
      timestamp: detectedAt,
      severity: severity,
      status: status,
      triggerValue: json['latestMeasuredValue']?.toString() ??
          json['triggerValue']?.toString(),
      incidentId: json['incidentId']?.toString(),
      deviceId: json['deviceId']?.toString(),
      sensorType: json['sensorType']?.toString(),
      eventCount: _AlertsPageState._asInt(json['eventCount'], fallback: 1),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
              detectedAt,
      acknowledgedAt:
          DateTime.tryParse(json['acknowledgedAt']?.toString() ?? '')
              ?.toLocal(),
      resolvedAt:
          DateTime.tryParse(json['resolvedAt']?.toString() ?? '')?.toLocal(),
    );
    return _HistoryAlert(
      source: source,
      statusLabel: status.label,
      alertType: _AlertsPageState._titleCaseAlert(source.title),
      zone: source.zone,
      timestamp: source.timestamp,
    );
  }
}

class _DisplayAlert {
  const _DisplayAlert({
    required this.source,
    required this.occurrences,
    required this.firstTimestamp,
    required this.latestTimestamp,
  });

  final AlertEvent source;
  final int occurrences;
  final DateTime firstTimestamp;
  final DateTime latestTimestamp;

  SensorLevel get severity => source.severity;

  factory _DisplayAlert.fromEvent(AlertEvent event) {
    return _DisplayAlert(
      source: event,
      occurrences: event.eventCount < 1 ? 1 : event.eventCount,
      firstTimestamp: event.timestamp,
      latestTimestamp: event.timestamp,
    );
  }

  factory _DisplayAlert.fromIncident({
    required AlertEvent source,
    required int occurrences,
    required DateTime firstTimestamp,
    required DateTime latestTimestamp,
  }) {
    return _DisplayAlert(
      source: source,
      occurrences: occurrences,
      firstTimestamp: firstTimestamp,
      latestTimestamp: latestTimestamp,
    );
  }
}
