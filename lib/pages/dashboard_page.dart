import 'dart:async';

import 'package:flutter/material.dart';

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import '../services/trend_history_api.dart';
import '../theme/severity_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/alert_card.dart';
import '../widgets/dashboard_layout.dart';
import '../widgets/device_status_card.dart';
import '../widgets/incident_zero_state.dart';
import '../widgets/section_header.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/trend_sparkline.dart';
import '../widgets/ui_kit.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.snapshot,
    required this.isAdminView,
    required this.alertsLabel,
    required this.onOpenAlertDetail,
    required this.onNavigateToAlerts,
    required this.onNavigateToDevices,
    required this.onRetrySync,
    required this.syncBusy,
    this.apiBaseUrl,
  });

  final MonitoringSnapshot snapshot;
  final bool isAdminView;
  final String alertsLabel;
  final ValueChanged<AlertEvent> onOpenAlertDetail;
  final VoidCallback onNavigateToAlerts;
  final VoidCallback onNavigateToDevices;
  final VoidCallback onRetrySync;
  final bool syncBusy;
  final String? apiBaseUrl;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey _deviceSectionKey = GlobalKey();
  final Map<String, SensorTrendSeries> _remoteTrendCache =
      <String, SensorTrendSeries>{};
  SensorType _selectedMetric = SensorType.waterLevel;
  String _selectedRange = '1H';
  bool _loadingRemoteTrend = false;
  String? _remoteTrendError;
  int _trendRequestId = 0;
  DateTime? _lastTrendFetchAt;
  static const Duration _minRemoteTrendFetchGap = Duration(seconds: 2);

  bool get _useRemoteTrend => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_useRemoteTrend) {
      unawaited(_fetchSelectedTrend(force: true));
    }
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final apiChanged = oldWidget.apiBaseUrl != widget.apiBaseUrl;
    final snapshotUpdated =
        oldWidget.snapshot.updatedAt != widget.snapshot.updatedAt;
    if (apiChanged) {
      _remoteTrendCache.clear();
      _remoteTrendError = null;
    }
    if (_useRemoteTrend && (apiChanged || snapshotUpdated)) {
      unawaited(_fetchSelectedTrend(force: apiChanged));
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final sectionSpace = uiSectionSpacing(context);
    final snapshot = widget.snapshot;
    final alerts = snapshot.alerts;
    final readings = snapshot.readings;
    final incidentGroups = _aggregateIncidentGroups(alerts);
    final overview = snapshot.overview;

    final incident = _topIncident(alerts);
    final fallbackCriticalCount = incidentGroups
        .where((e) => e.source.severity == SensorLevel.critical)
        .length;
    final fallbackWarningCount = incidentGroups
        .where((e) => e.source.severity == SensorLevel.warning)
        .length;
    final fallbackOpenAlerts = incidentGroups.length;
    final totalAssets = 1 + activeSensorTypes.length;
    final unavailableSensors = activeSensorTypes
        .where((t) => _readingByType(readings, t) == null)
        .length;
    final unavailableAssets =
        readings.isEmpty ? totalAssets : unavailableSensors;
    final availableAssets = totalAssets - unavailableAssets;
    final telemetryCoverage = totalAssets == 0
        ? 0
        : ((availableAssets / totalAssets) * 100).round().clamp(0, 100);
    final fallbackTelemetryStatus = unavailableAssets == 0
        ? 'Normal'
        : (unavailableAssets < totalAssets
            ? 'Partial / Degraded'
            : 'No Telemetry');
    final fallbackRiskLabel = incident == null
        ? 'Stable'
        : (incident.severity == SensorLevel.critical ? 'Critical' : 'Warning');
    final fallbackRiskTone = incident == null
        ? UiBadgeTone.healthy
        : (incident.severity == SensorLevel.critical
            ? UiBadgeTone.critical
            : UiBadgeTone.warning);
    final criticalCount = overview?.criticalQueue ?? fallbackCriticalCount;
    final warningCount = overview?.warningQueue ?? fallbackWarningCount;
    final openAlerts = overview?.activeIncidents ?? fallbackOpenAlerts;
    final telemetryCoverageValue =
        overview?.telemetryCoverage ?? telemetryCoverage;
    final telemetryStatus =
        _telemetryStatusLabel(overview, fallbackTelemetryStatus);
    final riskLabel = overview?.currentRiskLabel ?? fallbackRiskLabel;
    final riskTone = _riskTone(overview, fallbackRiskTone);
    final systemStatusLabel = _systemStatusLabel(overview, riskLabel);
    final systemStatusTone = _systemTone(overview, riskTone);
    final systemStatusIcon = _systemIcon(overview, incident);
    final fallbackSeries =
        _seriesFor(_selectedMetric, snapshot.history, _selectedRange);
    final remoteSeries = _remoteTrendCache[
        _trendCacheKey(metric: _selectedMetric, range: _selectedRange)];
    final usingRemoteSeries = remoteSeries != null;
    final series = usingRemoteSeries ? remoteSeries.values : fallbackSeries;
    final trendTimestamps = remoteSeries?.hasTimedValues == true
        ? remoteSeries!.timestamps
        : const <DateTime>[];
    final trendSource = usingRemoteSeries
        ? 'Cloud history API'
        : (_useRemoteTrend ? 'Local snapshot fallback' : 'Local snapshot');

    final incidentCard = _IncidentCard(
      incident: incident,
      onOpenIncident: incident == null
          ? widget.onNavigateToAlerts
          : () => widget.onOpenAlertDetail(incident),
      onNavigateToAlerts: widget.onNavigateToAlerts,
      alertsLabel: widget.alertsLabel,
    );
    final readingsCard = _RecentReadingsCard(
      readings: readings,
      updatedAt: snapshot.updatedAt,
    );
    final alertsCard = _RecentAlertsCard(
      alerts: alerts,
      onOpen: widget.onOpenAlertDetail,
    );
    final devicesCard = _DeviceOverviewCard(
      key: _deviceSectionKey,
      siteName: snapshot.siteName,
      readings: readings,
      updatedAt: snapshot.updatedAt,
      onRetrySync: widget.onRetrySync,
      onOpenIncidentQueue: widget.onNavigateToAlerts,
      alertsLabel: widget.alertsLabel,
    );
    final emergencyBanner = _EmergencyBanner(
      overview: overview,
      incident: incident,
      criticalCount: criticalCount,
      warningCount: warningCount,
      alertsLabel: widget.alertsLabel,
      onOpenDeviceManagement: widget.onNavigateToDevices,
      onRetrySync: widget.onRetrySync,
      onOpenIncident: incident == null
          ? widget.onNavigateToAlerts
          : () => widget.onOpenAlertDetail(incident),
      onOpenQueue: widget.onNavigateToAlerts,
    );
    final trendsCard = _TrendsCard(
      selectedMetric: _selectedMetric,
      selectedRange: _selectedRange,
      values: series,
      timestamps: trendTimestamps,
      syncedAt: snapshot.updatedAt,
      syncBusy: widget.syncBusy,
      loadingRemoteTrend: _loadingRemoteTrend,
      remoteTrendError: _remoteTrendError,
      trendSource: trendSource,
      onRetrySync: widget.onRetrySync,
      onViewDeviceStatus: _scrollToDeviceSection,
      onMetricChanged: _handleMetricChanged,
      onRangeChanged: _handleRangeChanged,
    );
    final sensorSummary = _SensorSummaryGrid(
      readings: readings,
      updatedAt: snapshot.updatedAt,
      siteName: snapshot.siteName,
      history: snapshot.history,
      lastSeenBySensor: snapshot.lastSeenBySensor,
      overview: overview,
    );

    return DashboardLayout(
      title: widget.isAdminView ? 'Response Overview' : 'Dashboard',
      subtitle: widget.isAdminView
          ? 'Cloud-assisted IoT disaster response command center.'
          : 'Your alerts, sensors, and emergency guidance at a glance.',
      trailing: StatusBadge(
        label: 'System: $systemStatusLabel',
        tone: systemStatusTone,
        icon: systemStatusIcon,
        prominent: true,
      ),
      children: compact
          ? [
              _CompactInfoFeed(
                emergencyBanner: emergencyBanner,
                incidentCard: incidentCard,
                readingsCard: readingsCard,
                alertsCard: alertsCard,
                devicesCard: devicesCard,
                trendsCard: trendsCard,
                sensorSummary: sensorSummary,
                riskLabel: riskLabel,
                riskTone: riskTone,
                openAlerts: openAlerts,
                criticalCount: criticalCount,
                warningCount: warningCount,
                telemetryCoverage: telemetryCoverageValue,
                telemetryStatus: telemetryStatus,
                latestSync: overview?.latestSync ?? _hhmm(snapshot.updatedAt),
                telemetryOnline: readings.isNotEmpty,
              ),
            ]
          : [
              emergencyBanner,
              SizedBox(height: sectionSpace),
              _SummaryGrid(
                cards: [
                  _SummaryData(
                    title: 'Current Risk',
                    value: riskLabel,
                    helper: overview?.systemStatus ==
                            DashboardSystemStatus.noTelemetry
                        ? 'Status: No live telemetry'
                        : (incident == null
                            ? 'No active critical incident'
                            : '${incident.zone} requires attention'),
                    tone: riskTone,
                  ),
                  _SummaryData(
                    title: 'Active Incidents',
                    value: '$openAlerts',
                    helper: '$openAlerts requires acknowledgment',
                    tone: openAlerts == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.warning,
                  ),
                  _SummaryData(
                    title: 'Critical Queue',
                    value: '$criticalCount',
                    helper: 'Requires immediate response',
                    tone: criticalCount == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.critical,
                  ),
                  _SummaryData(
                    title: 'Warning Queue',
                    value: '$warningCount',
                    helper: 'Monitor and assess impact',
                    tone: warningCount == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.warning,
                  ),
                  _SummaryData(
                    title: 'Telemetry Coverage',
                    value: '$telemetryCoverageValue%',
                    helper: '$availableAssets/$totalAssets assets reporting',
                    tone: overview?.systemStatus ==
                            DashboardSystemStatus.noTelemetry
                        ? UiBadgeTone.noTelemetry
                        : (unavailableAssets == 0
                            ? UiBadgeTone.healthy
                            : (unavailableAssets < totalAssets
                                ? UiBadgeTone.warning
                                : UiBadgeTone.offline)),
                  ),
                  _SummaryData(
                    title: 'Latest Sync',
                    value: overview?.latestSync ?? _hhmm(snapshot.updatedAt),
                    helper: 'Cloud status: $telemetryStatus',
                    tone: systemStatusTone,
                  ),
                ],
              ),
              SizedBox(height: sectionSpace),
              SectionHeader(
                title: 'Sensor Summary',
                subtitle:
                    'Latest water level, vibration, and temperature readings.',
                icon: Icons.sensors_rounded,
                trailing: StatusBadge.online(
                  online: readings.isNotEmpty,
                  label: readings.isEmpty ? 'No telemetry' : 'Telemetry online',
                ),
              ),
              const SizedBox(height: UiSpace.gap),
              sensorSummary,
              SizedBox(height: sectionSpace),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 12, child: incidentCard),
                  const SizedBox(width: UiSpace.gap),
                  Expanded(flex: 10, child: readingsCard),
                ],
              ),
              SizedBox(height: sectionSpace),
              trendsCard,
              SizedBox(height: sectionSpace),
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

  void _handleMetricChanged(SensorType value) {
    setState(() => _selectedMetric = value);
    if (_useRemoteTrend) {
      unawaited(_fetchSelectedTrend(force: true));
    }
  }

  void _handleRangeChanged(String value) {
    setState(() => _selectedRange = value);
    if (_useRemoteTrend) {
      unawaited(_fetchSelectedTrend(force: true));
    }
  }

  Future<void> _fetchSelectedTrend({bool force = false}) async {
    final baseUrl = (widget.apiBaseUrl ?? '').trim();
    if (baseUrl.isEmpty) return;
    if (!force && _loadingRemoteTrend) return;

    final now = DateTime.now();
    final lastFetch = _lastTrendFetchAt;
    if (!force &&
        lastFetch != null &&
        now.difference(lastFetch) < _minRemoteTrendFetchGap) {
      return;
    }
    _lastTrendFetchAt = now;

    final metric = _selectedMetric;
    final range = _selectedRange;
    final requestId = ++_trendRequestId;
    setState(() {
      _loadingRemoteTrend = true;
      _remoteTrendError = null;
    });

    try {
      final series = await TrendHistoryApi(baseUrl: baseUrl).fetchTrend(
        metric: metric,
        range: range,
      );
      if (!mounted || requestId != _trendRequestId) return;
      setState(() {
        _remoteTrendCache[_trendCacheKey(metric: metric, range: range)] =
            series;
        _loadingRemoteTrend = false;
        _remoteTrendError = null;
      });
    } catch (_) {
      if (!mounted || requestId != _trendRequestId) return;
      setState(() {
        _remoteTrendCache.remove(_trendCacheKey(metric: metric, range: range));
        _loadingRemoteTrend = false;
        _remoteTrendError =
            'Cloud trend history unavailable; showing latest snapshot cache.';
      });
    }
  }

  static String _trendCacheKey({
    required SensorType metric,
    required String range,
  }) {
    return '${metric.name}|$range';
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

  static String _telemetryStatusLabel(
    DashboardOverview? overview,
    String fallback,
  ) {
    if (overview == null) return fallback;
    return switch (overview.systemStatus) {
      DashboardSystemStatus.noTelemetry => 'No Telemetry',
      DashboardSystemStatus.critical => 'Critical',
      DashboardSystemStatus.warning => 'Warning',
      DashboardSystemStatus.normal => 'Normal',
    };
  }

  static UiBadgeTone _riskTone(
    DashboardOverview? overview,
    UiBadgeTone fallback,
  ) {
    if (overview == null) return fallback;
    return switch (overview.currentRisk.toUpperCase()) {
      'CRITICAL' => UiBadgeTone.critical,
      'WARNING' => UiBadgeTone.warning,
      'NORMAL' => UiBadgeTone.healthy,
      'UNKNOWN' => UiBadgeTone.noTelemetry,
      _ => fallback,
    };
  }

  static String _systemStatusLabel(
    DashboardOverview? overview,
    String riskLabel,
  ) {
    if (overview == null) return riskLabel;
    return overview.systemStatus.label;
  }

  static UiBadgeTone _systemTone(
    DashboardOverview? overview,
    UiBadgeTone fallback,
  ) {
    if (overview == null) return fallback;
    return switch (overview.systemStatus) {
      DashboardSystemStatus.noTelemetry => UiBadgeTone.noTelemetry,
      DashboardSystemStatus.critical => UiBadgeTone.critical,
      DashboardSystemStatus.warning => UiBadgeTone.warning,
      DashboardSystemStatus.normal => UiBadgeTone.healthy,
    };
  }

  static IconData _systemIcon(
      DashboardOverview? overview, AlertEvent? incident) {
    if (overview == null) {
      if (incident == null) return Icons.verified_rounded;
      return incident.severity == SensorLevel.critical
          ? Icons.crisis_alert_rounded
          : Icons.warning_amber_rounded;
    }
    return switch (overview.systemStatus) {
      DashboardSystemStatus.noTelemetry => Icons.cloud_off_rounded,
      DashboardSystemStatus.critical => Icons.crisis_alert_rounded,
      DashboardSystemStatus.warning => Icons.warning_amber_rounded,
      DashboardSystemStatus.normal => Icons.verified_rounded,
    };
  }
}

class _SummaryData {
  const _SummaryData({
    required this.title,
    required this.value,
    required this.helper,
    required this.tone,
  });

  final String title;
  final String value;
  final String helper;
  final UiBadgeTone tone;
}

class _CompactInfoFeed extends StatelessWidget {
  const _CompactInfoFeed({
    required this.emergencyBanner,
    required this.incidentCard,
    required this.readingsCard,
    required this.alertsCard,
    required this.devicesCard,
    required this.trendsCard,
    required this.sensorSummary,
    required this.riskLabel,
    required this.riskTone,
    required this.openAlerts,
    required this.criticalCount,
    required this.warningCount,
    required this.telemetryCoverage,
    required this.telemetryStatus,
    required this.latestSync,
    required this.telemetryOnline,
  });

  final Widget emergencyBanner;
  final Widget incidentCard;
  final Widget readingsCard;
  final Widget alertsCard;
  final Widget devicesCard;
  final Widget trendsCard;
  final Widget sensorSummary;
  final String riskLabel;
  final UiBadgeTone riskTone;
  final int openAlerts;
  final int criticalCount;
  final int warningCount;
  final int telemetryCoverage;
  final String telemetryStatus;
  final String latestSync;
  final bool telemetryOnline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        UiCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.view_stream_rounded,
                    size: 18,
                    color: UiColors.brandDark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mobile Information Feed',
                    style: UiText.cardTitle.copyWith(fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompactMetricPill(
                    label: 'Risk',
                    value: riskLabel,
                    tone: riskTone,
                    icon: Icons.health_and_safety_rounded,
                  ),
                  _CompactMetricPill(
                    label: 'Incidents',
                    value: '$openAlerts',
                    tone: openAlerts == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.warning,
                    icon: Icons.notification_important_rounded,
                  ),
                  _CompactMetricPill(
                    label: 'Critical',
                    value: '$criticalCount',
                    tone: criticalCount == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.critical,
                    icon: Icons.warning_amber_rounded,
                  ),
                  _CompactMetricPill(
                    label: 'Warnings',
                    value: '$warningCount',
                    tone: warningCount == 0
                        ? UiBadgeTone.stable
                        : UiBadgeTone.warning,
                    icon: Icons.report_problem_rounded,
                  ),
                  _CompactMetricPill(
                    label: 'Coverage',
                    value: '$telemetryCoverage%',
                    tone: telemetryCoverage >= 90
                        ? UiBadgeTone.healthy
                        : (telemetryCoverage >= 55
                            ? UiBadgeTone.warning
                            : UiBadgeTone.offline),
                    icon: Icons.cloud_done_rounded,
                  ),
                  _CompactMetricPill(
                    label: 'Sync',
                    value: latestSync,
                    tone: telemetryOnline
                        ? UiBadgeTone.healthy
                        : UiBadgeTone.noTelemetry,
                    icon: Icons.sync_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Telemetry: $telemetryStatus',
                style: UiText.helper,
              ),
            ],
          ),
        ),
        const SizedBox(height: UiSpace.gap),
        emergencyBanner,
        const SizedBox(height: UiSpace.gap),
        SectionHeader(
          title: 'Sensor Summary',
          subtitle: 'Card-based stream for core sensor updates.',
          icon: Icons.sensors_rounded,
          trailing: StatusBadge.online(
            online: telemetryOnline,
            label: telemetryOnline ? 'Telemetry online' : 'No telemetry',
          ),
        ),
        const SizedBox(height: UiSpace.gap),
        sensorSummary,
        const SizedBox(height: UiSpace.gap),
        incidentCard,
        const SizedBox(height: UiSpace.gap),
        readingsCard,
        const SizedBox(height: UiSpace.gap),
        trendsCard,
        const SizedBox(height: UiSpace.gap),
        alertsCard,
        const SizedBox(height: UiSpace.gap),
        devicesCard,
      ],
    );
  }
}

class _CompactMetricPill extends StatelessWidget {
  const _CompactMetricPill({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final UiBadgeTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: uiToneSoftColor(tone),
        borderRadius: BorderRadius.circular(UiRadius.input),
        border:
            Border.all(color: uiToneBorderColor(tone).withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: uiToneColor(tone)),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: uiToneColor(tone),
            ),
          ),
        ],
      ),
    );
  }
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
        final singleColumn = uiIsCompactLayout(context);
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - (UiSpace.gap * 3)) / 4
            : !singleColumn && constraints.maxWidth >= 760
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
                          Row(
                            children: [
                              _SeverityDot(tone: card.tone),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(card.title, style: UiText.helper),
                              ),
                            ],
                          ),
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

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.tone});

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

class _SensorSummaryGrid extends StatelessWidget {
  const _SensorSummaryGrid({
    required this.readings,
    required this.updatedAt,
    required this.siteName,
    required this.history,
    required this.lastSeenBySensor,
    required this.overview,
  });

  final List<SensorReading> readings;
  final DateTime updatedAt;
  final String siteName;
  final Map<SensorType, List<double>> history;
  final Map<SensorType, DateTime?> lastSeenBySensor;
  final DashboardOverview? overview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = uiIsCompactLayout(context);
        final width = constraints.maxWidth >= 1180
            ? (constraints.maxWidth - UiSpace.gap * 2) / 3
            : (!compact && constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth);

        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: activeSensorTypes.map((type) {
            final reading = _find(readings, type);
            return SizedBox(
              width: width,
              child: reading == null
                  ? _SensorNoTelemetryCard(
                      type: type,
                      siteName: siteName,
                      lastKnownSeries: history[type] ?? const <double>[],
                      lastSeenAt: lastSeenBySensor[type] ??
                          overview?.sensorStatus[type]?.lastSeenAt,
                    )
                  : SensorCard(
                      sensor: reading,
                      updatedAt: updatedAt,
                      deviceId: _deviceIdForSensor(type),
                      zone: siteName,
                    ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  static SensorReading? _find(List<SensorReading> readings, SensorType type) {
    for (final reading in readings) {
      if (reading.type == type) return reading;
    }
    return null;
  }
}

class _SensorNoTelemetryCard extends StatelessWidget {
  const _SensorNoTelemetryCard({
    required this.type,
    required this.siteName,
    required this.lastKnownSeries,
    required this.lastSeenAt,
  });

  final SensorType type;
  final String siteName;
  final List<double> lastKnownSeries;
  final DateTime? lastSeenAt;

  @override
  Widget build(BuildContext context) {
    final color = sensorColorOf(type);
    final lastKnownReading =
        lastKnownSeries.isEmpty ? null : lastKnownSeries.last;
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(UiRadius.input),
                ),
                child: Icon(type.icon, color: color),
              ),
              const Spacer(),
              const StatusBadge(
                label: 'No live telemetry',
                tone: UiBadgeTone.noTelemetry,
                icon: Icons.cloud_off_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(type.label, style: UiText.cardTitle),
          const SizedBox(height: 2),
          Text('${_deviceIdForSensor(type)} | $siteName', style: UiText.helper),
          const SizedBox(height: 16),
          Text(
            lastKnownReading == null
                ? '--'
                : _formatLastKnownValue(lastKnownReading, type),
            style: UiText.bigNumber.copyWith(fontSize: 34),
          ),
          if (lastKnownReading != null) ...[
            const SizedBox(height: 2),
            Text(type.unit, style: UiText.helper),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: UiColors.surfaceAlt,
              borderRadius: BorderRadius.circular(UiRadius.input),
              border: Border.all(color: UiColors.border),
            ),
            child: Text(
              lastKnownReading == null
                  ? 'Status: No live telemetry\nLast seen: ${_formatLastSeen(lastSeenAt)}'
                  : 'Status: No live telemetry\nLast known reading: ${_formatLastKnownValue(lastKnownReading, type)}\nLast seen: ${_formatLastSeen(lastSeenAt)}',
              style: UiText.helper,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatLastKnownValue(double value, SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return '${value.toStringAsFixed(2)}%';
      case SensorType.vibration:
        return '${value.toStringAsFixed(2)} mm/s RMS';
      case SensorType.temperature:
        return '${value.toStringAsFixed(2)}deg C';
    }
  }

  static String _formatLastSeen(DateTime? lastSeenAt) {
    if (lastSeenAt == null) return 'Never';
    final diff = DateTime.now().difference(lastSeenAt);
    if (diff.isNegative) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({
    required this.overview,
    required this.incident,
    required this.criticalCount,
    required this.warningCount,
    required this.alertsLabel,
    required this.onOpenDeviceManagement,
    required this.onRetrySync,
    required this.onOpenIncident,
    required this.onOpenQueue,
  });

  final DashboardOverview? overview;
  final AlertEvent? incident;
  final int criticalCount;
  final int warningCount;
  final String alertsLabel;
  final VoidCallback onOpenDeviceManagement;
  final VoidCallback onRetrySync;
  final VoidCallback onOpenIncident;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final systemStatus = overview?.systemStatus;
    final noTelemetry = systemStatus == DashboardSystemStatus.noTelemetry;
    final critical = systemStatus == DashboardSystemStatus.critical ||
        (systemStatus == null && criticalCount > 0);
    final warningOnly = systemStatus == DashboardSystemStatus.warning ||
        (systemStatus == null && !critical && warningCount > 0);
    final tone = noTelemetry
        ? UiBadgeTone.noTelemetry
        : (critical
            ? UiBadgeTone.critical
            : (warningOnly ? UiBadgeTone.warning : UiBadgeTone.healthy));
    final bannerColor = switch (tone) {
      UiBadgeTone.critical => SeverityColors.criticalSoft,
      UiBadgeTone.warning => SeverityColors.warningSoft,
      UiBadgeTone.noTelemetry => const Color(0xFFF2F6F8),
      _ => SeverityColors.normalSoft,
    };
    final borderColor = switch (tone) {
      UiBadgeTone.critical => SeverityColors.criticalBorder,
      UiBadgeTone.warning => SeverityColors.warningBorder,
      UiBadgeTone.noTelemetry => const Color(0xFFCBD8DF),
      _ => SeverityColors.normalBorder,
    };
    final banner = overview?.banner;
    final title = banner?.title ??
        (critical
            ? 'Critical incident response required'
            : (warningOnly
                ? 'Warning condition detected'
                : 'System operating normally'));
    final detail = banner?.message ??
        (incident == null
            ? 'No high-priority incident in the queue.'
            : '${_formatAlertTitle(incident!.title)} in ${incident!.zone} - ${formatIncidentRelativeTime(incident!.timestamp)}');
    final icon = noTelemetry
        ? Icons.cloud_off_rounded
        : (critical
            ? Icons.crisis_alert_rounded
            : (warningOnly
                ? Icons.warning_amber_rounded
                : Icons.check_circle_rounded));
    final iconColor = switch (tone) {
      UiBadgeTone.critical => UiColors.danger,
      UiBadgeTone.warning => UiColors.warning,
      UiBadgeTone.noTelemetry => UiColors.neutral,
      _ => UiColors.healthy,
    };

    Widget messageBlock() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UiText.cardTitle),
                const SizedBox(height: 2),
                Text(detail, style: UiText.helper),
              ],
            ),
          ),
        ],
      );
    }

    Widget actionButtons() {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (noTelemetry) ...[
            OutlinedButton(
              onPressed: onOpenDeviceManagement,
              style: uiSecondaryButton(),
              child: const Text('Open Device Management'),
            ),
            FilledButton(
              onPressed: onRetrySync,
              style: uiPrimaryButton(),
              child: const Text('Retry Sync'),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: onOpenQueue,
              style: uiSecondaryButton(),
              child: Text('Open $alertsLabel'),
            ),
            FilledButton(
              onPressed: onOpenIncident,
              style: uiPrimaryButton(),
              child: Text(
                incident == null ? 'Review Status' : 'Open Incident',
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(UiRadius.card),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                messageBlock(),
                const SizedBox(height: 10),
                actionButtons(),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: messageBlock()),
              const SizedBox(width: 10),
              actionButtons(),
            ],
          );
        },
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.onOpenIncident,
    required this.onNavigateToAlerts,
    required this.alertsLabel,
  });

  final AlertEvent? incident;
  final VoidCallback onOpenIncident;
  final VoidCallback onNavigateToAlerts;
  final String alertsLabel;

  @override
  Widget build(BuildContext context) {
    final hasIncident = incident != null;
    final isCritical =
        hasIncident && incident!.severity == SensorLevel.critical;
    final now = DateTime.now();
    final stripColor = isCritical
        ? SeverityColors.criticalSoft
        : (hasIncident
            ? SeverityColors.warningSoft
            : SeverityColors.normalSoft);
    final stripIcon = isCritical
        ? Icons.crisis_alert_rounded
        : (hasIncident
            ? Icons.warning_amber_rounded
            : Icons.check_circle_outline_rounded);
    final stripIconColor = isCritical
        ? UiColors.danger
        : (hasIncident ? UiColors.warning : UiColors.healthy);
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
                        ? (isCritical
                            ? 'Critical incident requires immediate response.'
                            : 'Warning-level incident requires operator action.')
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
                    ? (isCritical ? 'Critical' : 'Warning')
                    : 'None',
              ),
              _IncidentMetaChip(
                label: alertsLabel,
                value: hasIncident ? 'Active' : 'Clear',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Incident Summary', style: UiText.cardTitle),
          const SizedBox(height: 6),
          Text(
            hasIncident
                ? '${_formatAlertTitle(incident!.title)} in ${incident!.zone} - ${formatIncidentRelativeTime(incident!.timestamp)}'
                : 'No active incident to summarize.',
            style: UiText.body,
          ),
          const SizedBox(height: 10),
          Text(
            'Recommended Action: ${_recommendedAction(incident)}',
            style: UiText.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: onOpenIncident,
                  style: uiPrimaryButton(),
                  child: Text(isCritical
                      ? 'Engage Critical Response'
                      : 'Open Incident'),
                ),
              ),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: onNavigateToAlerts,
                  style: uiSecondaryButton(),
                  child: Text('Open $alertsLabel'),
                ),
              ),
              SizedBox(
                height: 46,
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

  static String _recommendedAction(AlertEvent? incident) {
    if (incident == null) {
      return 'Continue monitoring. No emergency action is required.';
    }
    final title = incident.title.toLowerCase();
    if (incident.severity == SensorLevel.critical && title.contains('water')) {
      return 'Avoid ${incident.zone} and wait for further instructions.';
    }
    if (incident.severity == SensorLevel.critical) {
      return 'Move away from the affected area immediately.';
    }
    return 'Review the alert details and avoid ${incident.zone} until it clears.';
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

class _RecentReadingsCard extends StatelessWidget {
  const _RecentReadingsCard({
    required this.readings,
    required this.updatedAt,
  });

  final List<SensorReading> readings;
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final rows = activeSensorTypes.map((type) {
      final reading = _find(readings, type);
      if (reading == null) {
        return _ReadingRow(
          sensor: type.label,
          deviceId: _deviceIdForSensor(type),
          value: '-- ${type.unit}',
          delta: '--',
          statusLabel: 'No telemetry',
          tone: UiBadgeTone.noTelemetry,
          lastUpdate: '--',
        );
      }
      return _ReadingRow(
        sensor: type.label,
        deviceId: _deviceIdForSensor(type),
        value: _formatSensorValue(reading.value, type),
        delta: reading.trendText,
        statusLabel: _levelLabel(reading.level),
        tone: _toneFromLevel(reading.level),
        lastUpdate: _hhmm(updatedAt),
      );
    }).toList(growable: false);

    return UiCard(
      big: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Recent Readings',
            subtitle: 'Latest sensor values with units and 1-hour movement.',
            icon: Icons.receipt_long_rounded,
            trailing: StatusBadge(
              label: readings.isEmpty ? 'No telemetry' : '${rows.length} live',
              tone: readings.isEmpty
                  ? UiBadgeTone.noTelemetry
                  : UiBadgeTone.healthy,
              icon: readings.isEmpty
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_done_rounded,
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: UiColors.tableRow,
                borderRadius: BorderRadius.circular(UiRadius.input),
                border:
                    Border.all(color: UiColors.border.withValues(alpha: 0.5)),
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.sensor, style: UiText.cardTitle),
                        const SizedBox(height: 4),
                        Text('${row.deviceId} | Updated ${row.lastUpdate}',
                            style: UiText.helper),
                        const SizedBox(height: 4),
                        Text(row.value, style: UiText.body),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusBadge(
                              label: row.statusLabel,
                              tone: row.tone,
                            ),
                            Text(row.delta, style: UiText.helper),
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
                              Text(row.sensor, style: UiText.cardTitle),
                              const SizedBox(height: 4),
                              Text(
                                  '${row.deviceId} | Updated ${row.lastUpdate}',
                                  style: UiText.helper),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: Text(row.value, style: UiText.body),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(row.delta, style: UiText.helper),
                        ),
                        StatusBadge(label: row.statusLabel, tone: row.tone),
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

  static String _formatSensorValue(double value, SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return '${value.toStringAsFixed(0)}%';
      case SensorType.vibration:
        return '${value.toStringAsFixed(1)} mm/s RMS';
      case SensorType.temperature:
        return '${value.toStringAsFixed(1)}deg C';
    }
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

class _ReadingRow {
  const _ReadingRow({
    required this.sensor,
    required this.deviceId,
    required this.value,
    required this.delta,
    required this.statusLabel,
    required this.tone,
    required this.lastUpdate,
  });

  final String sensor;
  final String deviceId;
  final String value;
  final String delta;
  final String statusLabel;
  final UiBadgeTone tone;
  final String lastUpdate;
}

class _TrendsCard extends StatelessWidget {
  const _TrendsCard({
    required this.selectedMetric,
    required this.selectedRange,
    required this.values,
    required this.timestamps,
    required this.syncedAt,
    required this.syncBusy,
    required this.loadingRemoteTrend,
    required this.remoteTrendError,
    required this.trendSource,
    required this.onMetricChanged,
    required this.onRangeChanged,
    required this.onRetrySync,
    required this.onViewDeviceStatus,
  });

  final SensorType selectedMetric;
  final String selectedRange;
  final List<double> values;
  final List<DateTime> timestamps;
  final DateTime syncedAt;
  final bool syncBusy;
  final bool loadingRemoteTrend;
  final String? remoteTrendError;
  final String trendSource;
  final ValueChanged<SensorType> onMetricChanged;
  final ValueChanged<String> onRangeChanged;
  final VoidCallback onRetrySync;
  final VoidCallback onViewDeviceStatus;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final hasData = values.isNotEmpty;
    final chartTimestamps = timestamps.length == values.length
        ? timestamps
        : buildSeriesTimestamps(
            count: values.length,
            range: selectedRange,
            end: syncedAt,
          );
    final xTicks = buildXAxisTicks(
      range: selectedRange,
      end: chartTimestamps.isNotEmpty ? chartTimestamps.last : syncedAt,
    );
    final latestValue = hasData ? values.last : null;
    final latestTime = chartTimestamps.isNotEmpty ? chartTimestamps.last : null;
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Source: $trendSource', style: UiText.helper),
              if (loadingRemoteTrend)
                const Text('Syncing cloud trend...', style: UiText.helper),
              if (remoteTrendError != null)
                Text(remoteTrendError!, style: UiText.helper),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: hasData ? 222 : (compact ? 350 : 336),
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
                        'Time window: ${rangeWindowLabel(selectedRange)} | Sampling interval: ${inferSamplingIntervalLabel(chartTimestamps)}',
                        style: UiText.helper,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TrendSparkline(
                          values: values,
                          timestamps: chartTimestamps,
                          xTicks: xTicks,
                          color: sensorColorOf(selectedMetric),
                          warningThreshold: _warning(selectedMetric),
                          criticalThreshold: _critical(selectedMetric),
                          metricLabel: selectedMetric.label,
                          yAxisUnit: selectedMetric.unit,
                          minY: selectedMetric == SensorType.waterLevel
                              ? 0
                              : null,
                          maxY: selectedMetric == SensorType.waterLevel
                              ? 100
                              : null,
                          timeLabelBuilder: (dt) =>
                              formatRangeTickLabel(dt, selectedRange),
                          valueLabelBuilder: (v) =>
                              _formatSensorValue(v, selectedMetric),
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Center(
                            child: UiEmptyState(
                              icon: Icons.cloud_off_outlined,
                              title:
                                  'No telemetry data received for the selected time range',
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
                                    : const Text('Retry Sync'),
                              ),
                              secondaryAction: OutlinedButton(
                                onPressed: onViewDeviceStatus,
                                style: uiSecondaryButton(),
                                child: const Text('View device status'),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
        return 'Warning threshold: 35deg C | Critical threshold: 40deg C';
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
        return '${value.toStringAsFixed(1)}deg C';
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
  });

  final List<AlertEvent> alerts;
  final ValueChanged<AlertEvent> onOpen;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final items = _aggregateRecentAlertLog(alerts);
    final hasCritical =
        items.any((alert) => alert.severity == SensorLevel.critical);
    final hasWarning =
        items.any((alert) => alert.severity == SensorLevel.warning);
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Active Incidents',
            subtitle: 'Open warning and critical incidents awaiting review.',
            icon: Icons.notification_important_rounded,
            trailing: StatusBadge(
              label: items.isEmpty ? 'Clear' : '${items.length} active',
              tone: hasCritical
                  ? UiBadgeTone.critical
                  : (hasWarning ? UiBadgeTone.warning : UiBadgeTone.healthy),
              icon: items.isEmpty
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const SizedBox(
              height: 240,
              child: IncidentZeroState(minHeight: 220),
            )
          else
            ...items.take(8).map(
                  (alert) => AlertCard(
                    alertType: _formatAlertTitle(alert.title),
                    deviceId: _sensorIdForAlert(alert),
                    zone: alert.zone,
                    measuredValue: _measuredValueForAlert(alert),
                    threshold: _thresholdForAlert(alert.title, alert.severity),
                    timestamp: formatIncidentRelativeTime(alert.timestamp),
                    status: alert.status.label,
                    severity: alert.severity,
                    occurrences: alert.eventCount,
                    onOpen: () => onOpen(alert),
                    compact: compact,
                  ),
                ),
        ],
      ),
    );
  }
}

class _DeviceOverviewCard extends StatelessWidget {
  const _DeviceOverviewCard({
    super.key,
    required this.siteName,
    required this.readings,
    required this.updatedAt,
    required this.onRetrySync,
    required this.onOpenIncidentQueue,
    required this.alertsLabel,
  });

  final String siteName;
  final List<SensorReading> readings;
  final DateTime updatedAt;
  final VoidCallback onRetrySync;
  final VoidCallback onOpenIncidentQueue;
  final String alertsLabel;

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
          SectionHeader(
            title: 'Device Status Overview',
            subtitle: 'Desktop table, mobile cards, and clear connectivity.',
            icon: Icons.router_rounded,
            trailing: StatusBadge.online(
              online: readings.isNotEmpty,
              label: readings.isEmpty ? 'Offline' : 'Online',
            ),
          ),
          const SizedBox(height: 10),
          if (compact)
            ...rows.map(
              (row) => DeviceStatusCard(
                deviceName: row.device,
                deviceId: row.deviceId,
                zone: row.zone,
                statusLabel: row.statusLabel,
                statusTone: row.tone,
                latestTelemetry: row.latestTelemetry,
                readingSummary: row.readingSummary,
                icon: row.icon,
                primaryActionLabel: row.actionLabel,
                onPrimaryAction: onRetrySync,
                secondaryActionLabel: 'Open $alertsLabel',
                onSecondaryAction: onOpenIncidentQueue,
              ),
            )
          else
            UiResponsiveTable(
              minWidth: 920,
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
                          child: Text('Latest', style: UiText.cardTitle)),
                      Expanded(
                          flex: 2,
                          child: Text('Status', style: UiText.cardTitle)),
                      Expanded(
                          flex: 2,
                          child: Text('Action', style: UiText.cardTitle)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...rows.map(
                    (row) => UiTableBodyRow(
                      height: 62,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(row.icon,
                                  size: 18, color: uiToneColor(row.tone)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  row.device,
                                  style: UiText.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
                            child: Text(row.zone, style: UiText.helper)),
                        Expanded(
                            flex: 2,
                            child: Text(row.latestTelemetry,
                                style: UiText.helper)),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StatusBadge(
                              label: row.statusLabel,
                              tone: row.tone,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextButton(
                            onPressed: onRetrySync,
                            style: uiLinkButton(),
                            child: Text(row.actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      deviceId: 'ESP32-01',
      zone: zone,
      statusLabel: online ? 'Normal' : 'Offline / Communication Lost',
      tone: online ? UiBadgeTone.healthy : UiBadgeTone.offline,
      latestTelemetry: online ? _hhmm(updatedAt) : '--',
      readingSummary: online ? 'Gateway reporting' : 'No cloud heartbeat',
      actionLabel: 'Retry Sync',
      icon: Icons.memory_rounded,
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
        deviceId: _deviceIdForSensor(type),
        zone: zone,
        statusLabel: 'No telemetry',
        tone: UiBadgeTone.noTelemetry,
        latestTelemetry: '--',
        readingSummary: '-- ${type.unit}',
        actionLabel: 'Retry Sync',
        icon: type.icon,
      );
    }

    return _DeviceRow(
      device: type.label,
      deviceId: _deviceIdForSensor(type),
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
      readingSummary: _formatSensorValue(reading.value, type),
      actionLabel: 'Retry Sync',
      icon: type.icon,
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
    required this.deviceId,
    required this.zone,
    required this.statusLabel,
    required this.tone,
    required this.latestTelemetry,
    required this.readingSummary,
    required this.actionLabel,
    required this.icon,
  });

  final String device;
  final String deviceId;
  final String zone;
  final String statusLabel;
  final UiBadgeTone tone;
  final String latestTelemetry;
  final String readingSummary;
  final String actionLabel;
  final IconData icon;
}

List<_IncidentGroup> _aggregateIncidentGroups(List<AlertEvent> events) {
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
            return '${event.zone}|${event.severity.name}|${bucketStart.toIso8601String()}|${_sensorKeyFromTitle(event.title)}';
          })();
    buckets.putIfAbsent(key, () => <AlertEvent>[]).add(event);
  }

  final groups = buckets.values.map((group) {
    group.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final occurrences = group.fold<int>(
      0,
      (sum, item) => sum + (item.eventCount < 1 ? 1 : item.eventCount),
    );
    return _IncidentGroup(
      source: group.first,
      occurrences: occurrences,
      latestTimestamp: group.first.timestamp,
    );
  }).toList(growable: false);

  groups.sort((a, b) {
    final sev = b.source.severity.index.compareTo(a.source.severity.index);
    if (sev != 0) return sev;
    return b.latestTimestamp.compareTo(a.latestTimestamp);
  });
  return groups;
}

List<AlertEvent> _aggregateRecentAlertLog(List<AlertEvent> events) {
  return _aggregateIncidentGroups(events)
      .map((group) => group.source)
      .toList(growable: false);
}

String _deviceIdForSensor(SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return 'WL-01';
    case SensorType.vibration:
      return 'VB-01';
    case SensorType.temperature:
      return 'TP-01';
  }
}

String _sensorIdForAlert(AlertEvent alert) {
  final lower = alert.title.toLowerCase();
  if (lower.contains('water')) return 'WL-01';
  if (lower.contains('vibration')) return 'VB-01';
  if (lower.contains('temp')) return 'TP-01';
  return 'SN-01';
}

String _measuredValueForAlert(AlertEvent alert) {
  final value = alert.triggerValue?.trim();
  if (value == null || value.isEmpty) return 'Not reported';
  return value;
}

String _thresholdForAlert(String title, SensorLevel severity) {
  final lower = title.toLowerCase();
  final critical = severity == SensorLevel.critical;
  if (lower.contains('water')) {
    return critical ? 'Critical 85%' : 'Warning 70%';
  }
  if (lower.contains('vibration')) {
    return critical ? 'Critical 4.0 mm/s RMS' : 'Warning 2.8 mm/s RMS';
  }
  if (lower.contains('temp')) {
    return critical ? 'Critical 40deg C' : 'Warning 35deg C';
  }
  return critical ? 'Critical threshold' : 'Warning threshold';
}

String _formatSensorValue(double value, SensorType type) {
  switch (type) {
    case SensorType.waterLevel:
      return '${value.toStringAsFixed(0)}%';
    case SensorType.vibration:
      return '${value.toStringAsFixed(1)} mm/s RMS';
    case SensorType.temperature:
      return '${value.toStringAsFixed(1)}deg C';
  }
}

String _sensorKeyFromTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('water')) return 'water';
  if (lower.contains('vibration')) return 'vibration';
  if (lower.contains('temp')) return 'temperature';
  return 'misc';
}

String _formatAlertTitle(String raw) {
  if (raw.trim().isEmpty) return 'Alert Triggered';
  final normalized = raw
      .replaceAll('waterLevel', 'Water level')
      .replaceAll('water level', 'Water level')
      .replaceAll('temperature', 'Temperature')
      .replaceAll('vibration', 'Vibration')
      .replaceAll('threshold exceeded', 'threshold exceeded')
      .trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

class _IncidentGroup {
  const _IncidentGroup({
    required this.source,
    required this.occurrences,
    required this.latestTimestamp,
  });

  final AlertEvent source;
  final int occurrences;
  final DateTime latestTimestamp;
}
