import 'package:flutter/material.dart';

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import '../widgets/trend_sparkline.dart';
import '../widgets/ui_kit.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.snapshot,
    required this.onOpenAlertDetail,
    required this.onNavigateToAlerts,
    required this.onRetrySync,
    required this.syncBusy,
  });

  final MonitoringSnapshot snapshot;
  final ValueChanged<AlertEvent> onOpenAlertDetail;
  final VoidCallback onNavigateToAlerts;
  final VoidCallback onRetrySync;
  final bool syncBusy;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey _deviceSectionKey = GlobalKey();
  SensorType _selectedMetric = SensorType.waterLevel;
  String _selectedRange = '1H';

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final sectionSpace = uiSectionSpacing(context);
    final snapshot = widget.snapshot;
    final alerts = snapshot.alerts;
    final readings = snapshot.readings;

    final incident = _topIncident(alerts);
    final criticalCount =
        alerts.where((e) => e.severity == SensorLevel.critical).length;
    final warningCount =
        alerts.where((e) => e.severity == SensorLevel.warning).length;
    final openAlerts = criticalCount + warningCount;
    final unavailableSensors = activeSensorTypes
        .where((t) => _readingByType(readings, t) == null)
        .length;
    final series =
        _seriesFor(_selectedMetric, snapshot.history, _selectedRange);

    final incidentCard = _IncidentCard(
      incident: incident,
      onOpenIncident: incident == null
          ? widget.onNavigateToAlerts
          : () => widget.onOpenAlertDetail(incident),
      onNavigateToAlerts: widget.onNavigateToAlerts,
    );
    final assetsCard = _AssetStatusCard(
      readings: readings,
      updatedAt: snapshot.updatedAt,
    );
    final alertsCard = _RecentAlertsCard(
      alerts: alerts,
      onOpen: widget.onOpenAlertDetail,
      onViewQueue: widget.onNavigateToAlerts,
    );
    final devicesCard = _DeviceOverviewCard(
      key: _deviceSectionKey,
      siteName: snapshot.siteName,
      readings: readings,
      updatedAt: snapshot.updatedAt,
    );

    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertix',
          title: 'Response Overview',
          subtitle: 'Live incident posture and device telemetry status.',
        ),
        SizedBox(height: sectionSpace),
        _SummaryGrid(
          cards: [
            _SummaryData(
              title: 'Current Risk',
              value: incident == null
                  ? 'Stable'
                  : (incident.severity == SensorLevel.critical
                      ? 'Critical'
                      : 'Warning'),
              helper: incident == null
                  ? 'No active critical incident'
                  : '${incident.zone} requires attention',
            ),
            _SummaryData(
              title: 'Open Alerts',
              value: '$openAlerts',
              helper: '$openAlerts requires acknowledgment',
            ),
            _SummaryData(
              title: 'Site Health',
              value: '${readings.isEmpty ? 0 : 1}/1',
              helper: '$unavailableSensors sensors unavailable',
            ),
            _SummaryData(
              title: 'Latest Sync',
              value: _hhmm(snapshot.updatedAt),
              helper: 'Cloud connected',
            ),
          ],
        ),
        SizedBox(height: sectionSpace),
        if (compact)
          Column(
            children: [
              incidentCard,
              const SizedBox(height: UiSpace.gap),
              assetsCard,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 12, child: incidentCard),
              const SizedBox(width: UiSpace.gap),
              Expanded(flex: 10, child: assetsCard),
            ],
          ),
        SizedBox(height: sectionSpace),
        _TrendsCard(
          selectedMetric: _selectedMetric,
          selectedRange: _selectedRange,
          values: series,
          syncedAt: snapshot.updatedAt,
          syncBusy: widget.syncBusy,
          onRetrySync: widget.onRetrySync,
          onViewDeviceStatus: _scrollToDeviceSection,
          onMetricChanged: (value) => setState(() => _selectedMetric = value),
          onRangeChanged: (value) => setState(() => _selectedRange = value),
        ),
        SizedBox(height: sectionSpace),
        if (compact)
          Column(
            children: [
              alertsCard,
              const SizedBox(height: UiSpace.gap),
              devicesCard,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 9, child: alertsCard),
              const SizedBox(width: UiSpace.gap),
              Expanded(flex: 15, child: devicesCard),
            ],
          ),
      ],
    );
  }

  Future<void> _scrollToDeviceSection() async {
    final ctx = _deviceSectionKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.06,
    );
  }

  static AlertEvent? _topIncident(List<AlertEvent> alerts) {
    if (alerts.isEmpty) return null;
    final sorted = alerts.toList()
      ..sort((a, b) {
        final sev = b.severity.index.compareTo(a.severity.index);
        if (sev != 0) return sev;
        return b.timestamp.compareTo(a.timestamp);
      });
    return sorted.first;
  }

  static List<double> _seriesFor(
    SensorType metric,
    Map<SensorType, List<double>> history,
    String range,
  ) {
    return buildTrendSeries(
      source: history[metric] ?? const <double>[],
      range: range,
      metric: metric,
    );
  }

  static SensorReading? _readingByType(
      List<SensorReading> readings, SensorType type) {
    for (final reading in readings) {
      if (reading.type == type) return reading;
    }
    return null;
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _SummaryData {
  const _SummaryData({
    required this.title,
    required this.value,
    required this.helper,
  });

  final String title;
  final String value;
  final String helper;
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.cards});

  final List<_SummaryData> cards;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final numberStyle = UiText.bigNumber.copyWith(fontSize: compact ? 26 : 34);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - (UiSpace.gap * 3)) / 4
            : constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: UiCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: SizedBox(
                      height: compact ? 96 : 106,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(card.title, style: UiText.helper),
                          SizedBox(height: compact ? 2 : 4),
                          Text(card.value, style: numberStyle),
                          const SizedBox(height: 3),
                          Text(
                            card.helper,
                            style: UiText.helper,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
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

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.onOpenIncident,
    required this.onNavigateToAlerts,
  });

  final AlertEvent? incident;
  final VoidCallback onOpenIncident;
  final VoidCallback onNavigateToAlerts;

  @override
  Widget build(BuildContext context) {
    final hasIncident = incident != null;
    final now = DateTime.now();
    final stripColor =
        hasIncident ? const Color(0xFFFFF2E4) : const Color(0xFFE9F7EE);
    final stripIcon = hasIncident
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;
    final stripIconColor = hasIncident ? UiColors.warning : UiColors.healthy;
    return UiCard(
      big: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Highest Priority Incident', style: UiText.sectionTitle),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: stripColor,
              borderRadius: BorderRadius.circular(UiRadius.button),
            ),
            child: Row(
              children: [
                Icon(stripIcon, color: stripIconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasIncident
                        ? 'Active incident requires immediate response.'
                        : 'No active incident. System is stable.',
                    style: UiText.cardTitle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IncidentMetaChip(
                label: 'Last evaluated',
                value: _hhmm(now),
              ),
              _IncidentMetaChip(
                label: 'Priority',
                value: hasIncident
                    ? (incident!.severity == SensorLevel.critical
                        ? 'Critical'
                        : 'Warning')
                    : 'None',
              ),
              _IncidentMetaChip(
                label: 'Incident queue',
                value: hasIncident ? 'Active' : 'Clear',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Incident Summary', style: UiText.cardTitle),
          const SizedBox(height: 6),
          Text(
            hasIncident
                ? '${incident!.title} in ${incident!.zone} at ${_hhmm(incident!.timestamp)}'
                : 'No active incident to summarize.',
            style: UiText.body,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: onOpenIncident,
                  style: uiPrimaryButton(),
                  child: const Text('Open Incident'),
                ),
              ),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onNavigateToAlerts,
                  style: uiSecondaryButton(),
                  child: const Text('Acknowledge'),
                ),
              ),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onNavigateToAlerts,
                  style: uiDangerButton(),
                  child: const Text('Escalate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _IncidentMetaChip extends StatelessWidget {
  const _IncidentMetaChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F8),
        borderRadius: BorderRadius.circular(UiRadius.pill),
      ),
      child: Text(
        '$label: $value',
        style: UiText.helper.copyWith(
          fontWeight: FontWeight.w600,
          color: UiColors.textBody,
        ),
      ),
    );
  }
}

class _AssetStatusCard extends StatelessWidget {
  const _AssetStatusCard({
    required this.readings,
    required this.updatedAt,
  });

  final List<SensorReading> readings;
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final rows = <_AssetRow>[
      _AssetRow(
        asset: 'ESP32 Node #01',
        statusLabel:
            readings.isEmpty ? 'Offline / Communication Lost' : 'Healthy',
        tone: readings.isEmpty ? UiBadgeTone.offline : UiBadgeTone.healthy,
        lastUpdate: readings.isEmpty ? '--' : _hhmm(updatedAt),
      ),
      ...activeSensorTypes.map((type) {
        final reading = _find(readings, type);
        if (reading == null) {
          return _AssetRow(
            asset: type.label,
            statusLabel: 'No telemetry',
            tone: UiBadgeTone.noTelemetry,
            lastUpdate: '--',
          );
        }
        return _AssetRow(
          asset: type.label,
          statusLabel: _levelLabel(reading.level),
          tone: _toneFromLevel(reading.level),
          lastUpdate: _hhmm(updatedAt),
        );
      }),
    ];

    return UiCard(
      big: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Affected Assets', style: UiText.sectionTitle),
          const SizedBox(height: 4),
          const Text(
            'Summary of asset impact and latest update time.',
            style: UiText.helper,
          ),
          const SizedBox(height: 10),
          ...rows.take(4).map(
                (row) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: UiColors.tableRow,
                    borderRadius: BorderRadius.circular(UiRadius.input),
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.asset, style: UiText.cardTitle),
                            const SizedBox(height: 4),
                            Text('Updated: ${row.lastUpdate}',
                                style: UiText.helper),
                            const SizedBox(height: 8),
                            UiBadge(label: row.statusLabel, tone: row.tone),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.asset, style: UiText.cardTitle),
                                  const SizedBox(height: 4),
                                  Text('Updated: ${row.lastUpdate}',
                                      style: UiText.helper),
                                ],
                              ),
                            ),
                            UiBadge(label: row.statusLabel, tone: row.tone),
                          ],
                        ),
                ),
              ),
        ],
      ),
    );
  }

  static SensorReading? _find(List<SensorReading> readings, SensorType type) {
    for (final reading in readings) {
      if (reading.type == type) return reading;
    }
    return null;
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static UiBadgeTone _toneFromLevel(SensorLevel level) {
    switch (level) {
      case SensorLevel.critical:
        return UiBadgeTone.critical;
      case SensorLevel.warning:
        return UiBadgeTone.warning;
      case SensorLevel.normal:
        return UiBadgeTone.stable;
    }
  }

  static String _levelLabel(SensorLevel level) {
    switch (level) {
      case SensorLevel.critical:
        return 'Critical';
      case SensorLevel.warning:
        return 'Warning';
      case SensorLevel.normal:
        return 'Stable';
    }
  }
}

class _AssetRow {
  const _AssetRow({
    required this.asset,
    required this.statusLabel,
    required this.tone,
    required this.lastUpdate,
  });

  final String asset;
  final String statusLabel;
  final UiBadgeTone tone;
  final String lastUpdate;
}

class _TrendsCard extends StatelessWidget {
  const _TrendsCard({
    required this.selectedMetric,
    required this.selectedRange,
    required this.values,
    required this.syncedAt,
    required this.syncBusy,
    required this.onMetricChanged,
    required this.onRangeChanged,
    required this.onRetrySync,
    required this.onViewDeviceStatus,
  });

  final SensorType selectedMetric;
  final String selectedRange;
  final List<double> values;
  final DateTime syncedAt;
  final bool syncBusy;
  final ValueChanged<SensorType> onMetricChanged;
  final ValueChanged<String> onRangeChanged;
  final VoidCallback onRetrySync;
  final VoidCallback onViewDeviceStatus;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final hasData = values.isNotEmpty;
    final timestamps = buildSeriesTimestamps(
      count: values.length,
      range: selectedRange,
      end: syncedAt,
    );
    final xTicks = buildXAxisTicks(
      range: selectedRange,
      end: timestamps.isNotEmpty ? timestamps.last : syncedAt,
    );
    final latestValue = hasData ? values.last : null;
    final latestTime = timestamps.isNotEmpty ? timestamps.last : null;
    return UiCard(
      big: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            const Text('Situation Trends', style: UiText.sectionTitle)
          else
            Row(
              children: [
                const Expanded(
                  child: Text('Situation Trends', style: UiText.sectionTitle),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: timeRangeLabels
                      .map(
                        (range) => ChoiceChip(
                          label: Text(range),
                          selected: selectedRange == range,
                          onSelected: (_) => onRangeChanged(range),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          if (compact) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: timeRangeLabels
                  .map(
                    (range) => ChoiceChip(
                      label: Text(range),
                      selected: selectedRange == range,
                      onSelected: (_) => onRangeChanged(range),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: activeSensorTypes
                .map(
                  (type) => ChoiceChip(
                    label: Text(type.label),
                    selected: selectedMetric == type,
                    onSelected: (_) => onMetricChanged(type),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: hasData ? 222 : 320,
            child: hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${selectedMetric.label} Trend',
                          style: UiText.cardTitle),
                      const SizedBox(height: 4),
                      Text(_thresholdLabel(selectedMetric),
                          style: UiText.helper),
                      const SizedBox(height: 2),
                      Text(
                        'Time window: ${rangeWindowLabel(selectedRange)} | Sampling interval: ${inferSamplingIntervalLabel(timestamps)}',
                        style: UiText.helper,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TrendSparkline(
                          values: values,
                          timestamps: timestamps,
                          xTicks: xTicks,
                          color: sensorColorOf(selectedMetric),
                          warningThreshold: _warning(selectedMetric),
                          criticalThreshold: _critical(selectedMetric),
                          metricLabel: selectedMetric.label,
                          yAxisUnit: selectedMetric.unit,
                          timeLabelBuilder: (dt) =>
                              formatRangeTickLabel(dt, selectedRange),
                          valueLabelBuilder: (v) =>
                              _formatSensorValue(v, selectedMetric),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const Spacer(),
                      UiEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'No telemetry available',
                        subtitle:
                            'No cloud data received for the selected time range',
                        reasons: const [
                          'device offline',
                          'network interruption',
                          'no samples received',
                        ],
                        primaryAction: FilledButton(
                          onPressed: syncBusy ? null : onRetrySync,
                          style: uiPrimaryButton(),
                          child: syncBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Retry sync'),
                        ),
                        secondaryAction: OutlinedButton(
                          onPressed: onViewDeviceStatus,
                          style: uiSecondaryButton(),
                          child: const Text('View device status'),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          if (latestValue != null && latestTime != null)
            Text(
              'Latest reading: ${_formatSensorValue(latestValue, selectedMetric)} at ${_hhmm(latestTime)}',
              style: UiText.helper,
            ),
          if (latestValue != null && latestTime != null)
            const SizedBox(height: 4),
          Text('Latest cloud sync: ${_hhmm(syncedAt)}', style: UiText.helper),
        ],
      ),
    );
  }

  static String _thresholdLabel(SensorType metric) {
    switch (metric) {
      case SensorType.waterLevel:
        return 'Warning threshold: 70% | Critical threshold: 85%';
      case SensorType.vibration:
        return 'Warning threshold: 2.8 mm/s RMS | Critical threshold: 4.0 mm/s RMS';
      case SensorType.temperature:
        return 'Warning threshold: 35°C | Critical threshold: 40°C';
    }
  }

  static double _warning(SensorType metric) {
    switch (metric) {
      case SensorType.waterLevel:
        return 70;
      case SensorType.vibration:
        return 2.8;
      case SensorType.temperature:
        return 35;
    }
  }

  static double _critical(SensorType metric) {
    switch (metric) {
      case SensorType.waterLevel:
        return 85;
      case SensorType.vibration:
        return 4.0;
      case SensorType.temperature:
        return 40;
    }
  }

  static String _formatSensorValue(double value, SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return '${value.toStringAsFixed(0)}%';
      case SensorType.vibration:
        return '${value.toStringAsFixed(1)} mm/s RMS';
      case SensorType.temperature:
        return '${value.toStringAsFixed(1)}°C';
    }
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _RecentAlertsCard extends StatelessWidget {
  const _RecentAlertsCard({
    required this.alerts,
    required this.onOpen,
    required this.onViewQueue,
  });

  final List<AlertEvent> alerts;
  final ValueChanged<AlertEvent> onOpen;
  final VoidCallback onViewQueue;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Alert Log', style: UiText.sectionTitle),
          const SizedBox(height: 10),
          if (alerts.isEmpty)
            SizedBox(
              height: 240,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.notifications_off_outlined,
                      size: 42,
                      color: Color(0xFF7B8D95),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No active alerts',
                      style: UiText.cardTitle.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New incidents will appear here when triggered',
                      style: UiText.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: onViewQueue,
                      style: uiSecondaryButton(),
                      child: const Text('Open incident queue'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...alerts.take(8).map(
                  (alert) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: UiColors.tableRow,
                      borderRadius: BorderRadius.circular(UiRadius.input),
                    ),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${alert.zone} | ${alert.title}',
                                  style: UiText.cardTitle),
                              const SizedBox(height: 4),
                              Text(_hhmm(alert.timestamp),
                                  style: UiText.helper),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  UiBadge(
                                    label: alert.severity ==
                                            SensorLevel.critical
                                        ? 'Critical'
                                        : 'Warning',
                                    tone: alert.severity ==
                                            SensorLevel.critical
                                        ? UiBadgeTone.critical
                                        : UiBadgeTone.warning,
                                  ),
                                  TextButton(
                                    onPressed: () => onOpen(alert),
                                    style: uiLinkButton(),
                                    child: const Text('Open'),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${alert.zone} | ${alert.title}',
                                        style: UiText.cardTitle),
                                    const SizedBox(height: 4),
                                    Text(_hhmm(alert.timestamp),
                                        style: UiText.helper),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              UiBadge(
                                label: alert.severity == SensorLevel.critical
                                    ? 'Critical'
                                    : 'Warning',
                                tone: alert.severity == SensorLevel.critical
                                    ? UiBadgeTone.critical
                                    : UiBadgeTone.warning,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => onOpen(alert),
                                style: uiLinkButton(),
                                child: const Text('Open'),
                              ),
                            ],
                          ),
                  ),
                ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _DeviceOverviewCard extends StatelessWidget {
  const _DeviceOverviewCard({
    super.key,
    required this.siteName,
    required this.readings,
    required this.updatedAt,
  });

  final String siteName;
  final List<SensorReading> readings;
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final rows = <_DeviceRow>[
      _nodeRow(readings, updatedAt, siteName),
      ...activeSensorTypes
          .map((type) => _sensorRow(type, readings, updatedAt, siteName)),
    ];

    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Field Device Overview', style: UiText.sectionTitle),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: UiColors.tableRow,
                borderRadius: BorderRadius.circular(UiRadius.input),
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.device, style: UiText.cardTitle),
                        const SizedBox(height: 3),
                        Text(row.zone, style: UiText.helper),
                        const SizedBox(height: 3),
                        Text('Latest telemetry: ${row.latestTelemetry}',
                            style: UiText.helper),
                        const SizedBox(height: 8),
                        UiBadge(label: row.statusLabel, tone: row.tone),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 2,
                          children: [
                            TextButton(
                              onPressed: () {},
                              style: uiLinkButton(),
                              child: Text(row.actionLabel),
                            ),
                            TextButton(
                              onPressed: () {},
                              style: uiLinkButton(),
                              child: const Text('More detail'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.device, style: UiText.cardTitle),
                              const SizedBox(height: 3),
                              Text(row.zone, style: UiText.helper),
                              const SizedBox(height: 3),
                              Text('Latest telemetry: ${row.latestTelemetry}',
                                  style: UiText.helper),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            UiBadge(label: row.statusLabel, tone: row.tone),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 2,
                              children: [
                                TextButton(
                                  onPressed: () {},
                                  style: uiLinkButton(),
                                  child: Text(row.actionLabel),
                                ),
                                TextButton(
                                  onPressed: () {},
                                  style: uiLinkButton(),
                                  child: const Text('More detail'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static _DeviceRow _nodeRow(
      List<SensorReading> readings, DateTime updatedAt, String zone) {
    final online = readings.isNotEmpty;
    return _DeviceRow(
      device: 'ESP32 Node #01',
      zone: zone,
      statusLabel: online ? 'Healthy' : 'Offline / Communication Lost',
      tone: online ? UiBadgeTone.healthy : UiBadgeTone.offline,
      latestTelemetry: online ? _hhmm(updatedAt) : '--',
      actionLabel: 'Retry',
    );
  }

  static _DeviceRow _sensorRow(
    SensorType type,
    List<SensorReading> readings,
    DateTime updatedAt,
    String zone,
  ) {
    SensorReading? reading;
    for (final item in readings) {
      if (item.type == type) {
        reading = item;
        break;
      }
    }

    if (reading == null) {
      return _DeviceRow(
        device: type.label,
        zone: zone,
        statusLabel: 'No telemetry',
        tone: UiBadgeTone.noTelemetry,
        latestTelemetry: '--',
        actionLabel: 'Retry',
      );
    }

    return _DeviceRow(
      device: type.label,
      zone: zone,
      statusLabel: reading.level == SensorLevel.normal
          ? 'Stable'
          : (reading.level == SensorLevel.critical ? 'Critical' : 'Warning'),
      tone: reading.level == SensorLevel.normal
          ? UiBadgeTone.stable
          : (reading.level == SensorLevel.critical
              ? UiBadgeTone.critical
              : UiBadgeTone.warning),
      latestTelemetry: _hhmm(updatedAt),
      actionLabel: 'Retry',
    );
  }

  static String _hhmm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _DeviceRow {
  const _DeviceRow({
    required this.device,
    required this.zone,
    required this.statusLabel,
    required this.tone,
    required this.latestTelemetry,
    required this.actionLabel,
  });

  final String device;
  final String zone;
  final String statusLabel;
  final UiBadgeTone tone;
  final String latestTelemetry;
  final String actionLabel;
}
