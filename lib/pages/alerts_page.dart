import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import '../widgets/ui_kit.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.snapshot,
    required this.role,
    required this.onOpenAlertDetail,
    required this.onAcknowledgeVisible,
  });

  final MonitoringSnapshot snapshot;
  final UserRole role;
  final ValueChanged<AlertEvent> onOpenAlertDetail;
  final Future<int> Function(List<String> alertIds) onAcknowledgeVisible;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  bool _incidentMode = true;
  SensorLevel? _severityFilter;
  bool _ackProcessing = false;

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

    final incidents = _aggregateIncidents(filteredEvents);
    final displayed = _incidentMode
        ? incidents
        : filteredEvents.map(_DisplayAlert.fromEvent).toList(growable: false);

    final criticalCount =
        displayed.where((a) => a.severity == SensorLevel.critical).length;
    final warningCount =
        displayed.where((a) => a.severity == SensorLevel.warning).length;
    final ackDisabled = filteredEvents.isEmpty || _ackProcessing;

    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertix',
          title: 'Incident Queue',
          subtitle:
              'Review incidents, acknowledge visible items, and escalate when needed.',
        ),
        SizedBox(height: sectionSpace),
        _TopStatGrid(
          items: [
            _TopStatItem(
              label: 'Open Incidents',
              value: '${displayed.length}',
              tone: UiBadgeTone.warning,
            ),
            _TopStatItem(
              label: 'Critical',
              value: '$criticalCount',
              tone: UiBadgeTone.critical,
            ),
            _TopStatItem(
              label: 'Warning',
              value: '$warningCount',
              tone: UiBadgeTone.warning,
            ),
            const _TopStatItem(
              label: 'Resolved Today',
              value: '0',
              tone: UiBadgeTone.stable,
            ),
          ],
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Incident mode'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Event mode'),
                  ),
                ],
                selected: {_incidentMode},
                onSelectionChanged: (selection) =>
                    setState(() => _incidentMode = selection.first),
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
                            : () => _acknowledgeVisible(filteredEvents),
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
                            : 'Acknowledge Visible'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      filteredEvents.isEmpty
                          ? 'No visible incidents to acknowledge'
                          : '${filteredEvents.length} visible incident(s) in current filter',
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
                          : () => _acknowledgeVisible(filteredEvents),
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
                          : 'Acknowledge Visible'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filteredEvents.isEmpty
                            ? 'No visible incidents to acknowledge'
                            : '${filteredEvents.length} visible incident(s) in current filter',
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
                    onSelected: (_) => setState(() => _severityFilter = null),
                  ),
                  ...SensorLevel.values.map(
                    (level) => ChoiceChip(
                      label: Text(
                          level == SensorLevel.normal ? 'Stable' : level.label),
                      selected: _severityFilter == level,
                      onSelected: (_) =>
                          setState(() => _severityFilter = level),
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
              ? SizedBox(
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
                          onPressed: () =>
                              setState(() => _severityFilter = null),
                          style: uiSecondaryButton(),
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  ),
                )
              : compact
                  ? Column(
                      children: displayed
                          .map((item) => _buildCompactIncidentCard(item))
                          .toList(growable: false),
                    )
                  : UiResponsiveTable(
                      minWidth: 980,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const UiTableHeaderRow(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('Triggered At',
                                    style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Device/Zone',
                                    style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 3,
                                child:
                                    Text('Alert Type', style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text('Count', style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 2,
                                child:
                                    Text('Severity', style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Status', style: UiText.cardTitle),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Action', style: UiText.cardTitle),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...displayed.map(
                            (item) => UiTableBodyRow(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDateTime(item.latestTimestamp),
                                    style: UiText.helper,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(item.source.zone,
                                      style: UiText.body),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _titleCaseAlert(item.source.title),
                                    style: UiText.body,
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    _incidentMode
                                        ? 'x${item.occurrences}'
                                        : '--',
                                    style: UiText.body,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: UiBadge(
                                      label: item.source.severity ==
                                              SensorLevel.critical
                                          ? 'Critical'
                                          : 'Warning',
                                      tone: item.source.severity ==
                                              SensorLevel.critical
                                          ? UiBadgeTone.critical
                                          : UiBadgeTone.warning,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: UiBadge(
                                      label: 'Active',
                                      tone: UiBadgeTone.warning,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () =>
                                          widget.onOpenAlertDetail(item.source),
                                      style: uiLinkButton(),
                                      child: Text(_incidentMode
                                          ? 'Open incident'
                                          : 'Open detail'),
                                    ),
                                  ),
                                ),
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

  Widget _buildCompactIncidentCard(_DisplayAlert item) {
    final critical = item.source.severity == SensorLevel.critical;
    final severityLabel = critical ? 'Critical' : 'Warning';
    final severityTone = critical ? UiBadgeTone.critical : UiBadgeTone.warning;
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
                child: Text(
                  _titleCaseAlert(item.source.title),
                  style: UiText.cardTitle,
                ),
              ),
              UiBadge(label: severityLabel, tone: severityTone),
            ],
          ),
          const SizedBox(height: 6),
          Text(item.source.zone, style: UiText.body),
          const SizedBox(height: 2),
          Text(_formatDateTime(item.latestTimestamp), style: UiText.helper),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _incidentMode
                    ? 'Count: x${item.occurrences}'
                    : 'Status: Active',
                style: UiText.helper,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => widget.onOpenAlertDetail(item.source),
                style: uiLinkButton(),
                child: Text(_incidentMode ? 'Open incident' : 'Open detail'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledgeVisible(List<AlertEvent> filteredEvents) async {
    if (_ackProcessing) return;
    final ids = filteredEvents.map((e) => e.id).toSet().toList(growable: false);

    setState(() => _ackProcessing = true);
    try {
      final success = await widget.onAcknowledgeVisible(ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Acknowledged $success / ${ids.length} alert(s).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to acknowledge alerts.')),
      );
    } finally {
      if (mounted) {
        setState(() => _ackProcessing = false);
      }
    }
  }

  List<_DisplayAlert> _aggregateIncidents(List<AlertEvent> events) {
    final buckets = <String, List<AlertEvent>>{};
    for (final event in events) {
      final bucketStart = DateTime(
        event.timestamp.year,
        event.timestamp.month,
        event.timestamp.day,
        event.timestamp.hour,
        (event.timestamp.minute ~/ 10) * 10,
      );
      final key =
          '${event.zone}|${event.severity.name}|${bucketStart.toIso8601String()}|${_sensorKey(event.title)}';
      buckets.putIfAbsent(key, () => <AlertEvent>[]).add(event);
    }

    final incidents = buckets.values.map((group) {
      group.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return _DisplayAlert.fromIncident(
        source: group.first,
        occurrences: group.length,
        latestTimestamp: group.first.timestamp,
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

  static String _titleCaseAlert(String raw) {
    if (raw.isEmpty) return raw;
    final normalized = raw
        .replaceAll('waterLevel', 'Water level')
        .replaceAll('temperature', 'Temperature')
        .replaceAll('vibration', 'Vibration')
        .trim();
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
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
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - UiSpace.gap * 3) / 4
            : constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: UiCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: UiText.helper),
                        const SizedBox(height: 6),
                        compact
                            ? Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    item.value,
                                    style: UiText.bigNumber
                                        .copyWith(fontSize: 30),
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
                                    style: UiText.bigNumber
                                        .copyWith(fontSize: 34),
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
          const Color(0xFFFFF0F0),
          const Color(0xFFA85656),
        ),
      UiBadgeTone.warning => (
          const Color(0xFFFFF8EC),
          const Color(0xFF9B7B43),
        ),
      UiBadgeTone.stable => (
          const Color(0xFFF0F6F2),
          const Color(0xFF6A8A72),
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

class _DisplayAlert {
  const _DisplayAlert({
    required this.source,
    required this.occurrences,
    required this.latestTimestamp,
  });

  final AlertEvent source;
  final int occurrences;
  final DateTime latestTimestamp;

  SensorLevel get severity => source.severity;

  factory _DisplayAlert.fromEvent(AlertEvent event) {
    return _DisplayAlert(
      source: event,
      occurrences: 1,
      latestTimestamp: event.timestamp,
    );
  }

  factory _DisplayAlert.fromIncident({
    required AlertEvent source,
    required int occurrences,
    required DateTime latestTimestamp,
  }) {
    return _DisplayAlert(
      source: source,
      occurrences: occurrences,
      latestTimestamp: latestTimestamp,
    );
  }
}
