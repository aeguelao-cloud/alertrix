import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';
import '../widgets/trend_sparkline.dart';
import '../widgets/ui_kit.dart';

class TrendsPage extends StatefulWidget {
  const TrendsPage({
    super.key,
    required this.snapshot,
    this.apiBaseUrl,
    this.refreshToken = 0,
  });

  final MonitoringSnapshot snapshot;
  final String? apiBaseUrl;
  final int refreshToken;

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  SensorType _selectedMetric = SensorType.waterLevel;
  String _selectedRange = '1H';
  bool _loadingRemote = false;
  String? _remoteError;
  int _requestId = 0;
  DateTime? _lastRemoteFetchAt;
  static const Duration _minRemoteFetchGap = Duration(seconds: 2);
  final Map<SensorType, List<double>> _remoteSeries =
      <SensorType, List<double>>{};
  final Map<SensorType, List<DateTime>> _remoteTimestamps =
      <SensorType, List<DateTime>>{};

  bool get _useRemote => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_useRemote) {
      _fetchMetricAndRange(force: true);
    }
  }

  @override
  void didUpdateWidget(covariant TrendsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final refreshClicked = oldWidget.refreshToken != widget.refreshToken;
    final snapshotUpdated =
        oldWidget.snapshot.updatedAt != widget.snapshot.updatedAt;
    final apiChanged = oldWidget.apiBaseUrl != widget.apiBaseUrl;

    if (_useRemote && (refreshClicked || apiChanged)) {
      _fetchMetricAndRange(force: true);
      return;
    }

    if (_useRemote && snapshotUpdated) {
      _fetchMetricAndRange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionSpace = uiSectionSpacing(context);
    final selectedSeries = _seriesFor(_selectedMetric);
    final selectedTimestamps =
        _timestampsFor(_selectedMetric, selectedSeries.length);
    final selectedReading = _readingFor(_selectedMetric, selectedSeries);
    final hasData = selectedSeries.isNotEmpty;
    final latestIndex = selectedSeries.isEmpty ? -1 : selectedSeries.length - 1;
    final peakIndex = _indexOfMax(selectedSeries);
    final minIndex = _indexOfMin(selectedSeries);

    final latest = hasData ? selectedSeries.last : selectedReading?.value;
    final average = hasData
        ? selectedSeries.reduce((a, b) => a + b) / selectedSeries.length
        : selectedReading?.value;
    final peak = hasData
        ? selectedSeries.reduce((a, b) => a > b ? a : b)
        : selectedReading?.value;
    final min = hasData
        ? selectedSeries.reduce((a, b) => a < b ? a : b)
        : selectedReading?.value;
    final latestTime =
        latestIndex >= 0 && latestIndex < selectedTimestamps.length
            ? selectedTimestamps[latestIndex]
            : null;
    final peakTime = peakIndex >= 0 && peakIndex < selectedTimestamps.length
        ? selectedTimestamps[peakIndex]
        : null;
    final minTime = minIndex >= 0 && minIndex < selectedTimestamps.length
        ? selectedTimestamps[minIndex]
        : null;
    final xTicks = buildXAxisTicks(
      range: _selectedRange,
      end: selectedTimestamps.isNotEmpty
          ? selectedTimestamps.last
          : widget.snapshot.updatedAt,
    );

    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertrix',
          title: 'Situation Trends',
          subtitle: 'Cloud telemetry trend view by metric and time range.',
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final metricField = _FilterDropdown<SensorType>(
                title: 'Metric',
                value: _selectedMetric,
                items: activeSensorTypes,
                labelBuilder: (v) => v.label,
                onChanged: (value) {
                  setState(() => _selectedMetric = value);
                  if (_useRemote) _fetchMetricAndRange(force: true);
                },
              );
              final rangeField = _FilterDropdown<String>(
                title: 'Time Range',
                value: _selectedRange,
                items: timeRangeLabels,
                onChanged: (value) {
                  setState(() => _selectedRange = value);
                  if (_useRemote) _fetchMetricAndRange(force: true);
                },
              );

              if (stacked) {
                return Column(
                  children: [
                    metricField,
                    const SizedBox(height: 12),
                    rangeField,
                  ],
                );
              }
              return Row(
                children: [
                  const Expanded(child: SizedBox()),
                  Expanded(flex: 5, child: metricField),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: rangeField),
                  const Expanded(child: SizedBox()),
                ],
              );
            },
          ),
        ),
        SizedBox(height: sectionSpace),
        UiCard(
          big: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_selectedMetric.icon,
                      color: sensorColorOf(_selectedMetric)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${_selectedMetric.label} Trend',
                        style: UiText.sectionTitle),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_thresholdText(_selectedMetric), style: UiText.helper),
              const SizedBox(height: 2),
              Text(
                'Time window: ${rangeWindowLabel(_selectedRange)} | Sampling interval: ${inferSamplingIntervalLabel(selectedTimestamps)}',
                style: UiText.helper,
              ),
              if (_loadingRemote) ...[
                const SizedBox(height: 8),
                const Text('Syncing latest cloud trend...',
                    style: UiText.helper),
              ],
              if (_remoteError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E7),
                    borderRadius: BorderRadius.circular(UiRadius.input),
                  ),
                  child: Text(_remoteError!, style: UiText.helper),
                ),
              ],
              if (_remoteError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF5F7),
                    borderRadius: BorderRadius.circular(UiRadius.input),
                  ),
                  child: const Text(
                    'Latest cloud data may be stale due to device communication loss.',
                    style: UiText.helper,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: hasData ? 284 : 214,
                child: hasData
                    ? Column(
                        children: [
                          Expanded(
                            child: TrendSparkline(
                              values: selectedSeries,
                              timestamps: selectedTimestamps,
                              xTicks: xTicks,
                              color: sensorColorOf(_selectedMetric),
                              warningThreshold: _warning(_selectedMetric),
                              criticalThreshold: _critical(_selectedMetric),
                              metricLabel: _selectedMetric.label,
                              yAxisUnit: _selectedMetric.unit,
                              minY: _selectedMetric == SensorType.waterLevel
                                  ? 0
                                  : null,
                              maxY: _selectedMetric == SensorType.waterLevel
                                  ? 100
                                  : null,
                              timeLabelBuilder: (dt) =>
                                  formatRangeTickLabel(dt, _selectedRange),
                              valueLabelBuilder: (v) =>
                                  _formatSensorValue(v, _selectedMetric),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatChip(
                                  label: 'Latest',
                                  value: _statWithTime(
                                    latest,
                                    latestTime,
                                    _selectedMetric,
                                    includeTime: true,
                                  )),
                              _StatChip(
                                  label: 'Average',
                                  value: _statWithTime(
                                    average,
                                    null,
                                    _selectedMetric,
                                    timeHint:
                                        'over ${rangeWindowLabel(_selectedRange)}',
                                  )),
                              _StatChip(
                                  label: 'Peak',
                                  value: _statWithTime(
                                    peak,
                                    peakTime,
                                    _selectedMetric,
                                    includeTime: true,
                                  )),
                              _StatChip(
                                  label: 'Min',
                                  value: _statWithTime(
                                    min,
                                    minTime,
                                    _selectedMetric,
                                    includeTime: true,
                                  )),
                            ],
                          ),
                        ],
                      )
                    : UiEmptyState(
                        icon: Icons.show_chart_outlined,
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
                          onPressed: _loadingRemote ? null : _handleRetry,
                          style: uiPrimaryButton(),
                          child: const Text('Retry Sync'),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                'Latest reading: ${_statWithTime(latest, latestTime, _selectedMetric, includeTime: latestTime != null)}',
                style: UiText.helper,
              ),
              const SizedBox(height: 4),
              Text('Last sync: ${_hhmm(widget.snapshot.updatedAt)}',
                  style: UiText.helper),
            ],
          ),
        ),
        SizedBox(height: sectionSpace),
        const Text('Other Sensor Trends', style: UiText.sectionTitle),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 1200
                ? (constraints.maxWidth - UiSpace.gap * 2) / 3
                : constraints.maxWidth >= 760
                    ? (constraints.maxWidth - UiSpace.gap) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: UiSpace.gap,
              runSpacing: UiSpace.gap,
              children: activeSensorTypes.map((type) {
                final series = _seriesFor(type);
                final reading = _readingFor(type, series);
                final value = series.isNotEmpty ? series.last : reading?.value;
                final level = reading?.level;
                final tone = _toneForReading(level, value, type);
                return SizedBox(
                  width: cardWidth,
                  child: UiCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(UiRadius.card),
                      onTap: () {
                        setState(() => _selectedMetric = type);
                        if (_useRemote) _fetchMetricAndRange(force: true);
                      },
                      child: SizedBox(
                        height: 146,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(type.icon, color: sensorColorOf(type)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child:
                                      Text(type.label, style: UiText.cardTitle),
                                ),
                                UiBadge(
                                  label: _statusLabel(level, value, type),
                                  tone: tone,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Last reading: ${value == null ? '-' : _formatSensorValue(value, type)}',
                              style: UiText.body,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Threshold state: ${_thresholdState(value, type)}',
                              style: UiText.helper,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleRetry() async {
    if (_useRemote) {
      await _fetchMetricAndRange(force: true);
      return;
    }
    if (!mounted) return;
    setState(() {});
  }

  List<double> _seriesFor(SensorType type) {
    final remote = _remoteSeries[type];
    if (remote != null && remote.isNotEmpty) return remote;
    return buildTrendSeries(
      source: widget.snapshot.history[type] ?? const <double>[],
      range: _selectedRange,
      metric: type,
    );
  }

  List<DateTime> _timestampsFor(SensorType type, int count) {
    if (count <= 0) return const <DateTime>[];
    final remote = _remoteTimestamps[type];
    if (remote != null && remote.length == count) {
      return remote;
    }
    return buildSeriesTimestamps(
      count: count,
      range: _selectedRange,
      end: widget.snapshot.updatedAt,
    );
  }

  int _indexOfMax(List<double> values) {
    if (values.isEmpty) return -1;
    var idx = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[idx]) idx = i;
    }
    return idx;
  }

  int _indexOfMin(List<double> values) {
    if (values.isEmpty) return -1;
    var idx = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[idx]) idx = i;
    }
    return idx;
  }

  String _statWithTime(
    double? value,
    DateTime? time,
    SensorType type, {
    bool includeTime = false,
    String? timeHint,
  }) {
    if (value == null) return '-';
    final valueText = _formatSensorValue(value, type);
    if (timeHint != null && timeHint.isNotEmpty) {
      return '$valueText ($timeHint)';
    }
    if (includeTime && time != null) {
      return '$valueText at ${formatHm(time)}';
    }
    return valueText;
  }

  SensorReading? _readingFor(SensorType type, List<double> series) {
    SensorReading? base;
    for (final reading in widget.snapshot.readings) {
      if (reading.type == type) {
        base = reading;
        break;
      }
    }
    if (series.isEmpty) return base;
    final value = series.last;
    return SensorReading(
      type: type,
      value: value,
      level: _levelFor(type, value),
      delta: base?.delta ?? 0,
    );
  }

  Future<void> _fetchMetricAndRange({bool force = false}) async {
    final baseUrl = (widget.apiBaseUrl ?? '').trim();
    if (baseUrl.isEmpty) return;
    if (!force && _loadingRemote) return;

    final now = DateTime.now();
    final lastFetch = _lastRemoteFetchAt;
    if (!force &&
        lastFetch != null &&
        now.difference(lastFetch) < _minRemoteFetchGap) {
      return;
    }
    _lastRemoteFetchAt = now;

    final requestId = ++_requestId;
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });

    try {
      final responses = await Future.wait(
        activeSensorTypes.map((metric) async {
          final uri = Uri.parse('$baseUrl/api/trends').replace(
            queryParameters: {
              'metric': metricToApi(metric),
              'range': rangeToApi(_selectedRange),
              '_': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
          final resp = await http.get(uri);
          if (resp.statusCode < 200 || resp.statusCode >= 300) {
            throw Exception('Trends API ${resp.statusCode}');
          }
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final parsed = _parseTrendPayload(data);
          return MapEntry(metric, parsed);
        }),
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _remoteSeries.clear();
        _remoteTimestamps.clear();
        for (final item in responses) {
          _remoteSeries[item.key] = item.value.values;
          if (item.value.timestamps.isNotEmpty) {
            _remoteTimestamps[item.key] = item.value.timestamps;
          }
        }
        _loadingRemote = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingRemote = false;
        _remoteError = 'Remote trends unavailable.';
      });
    }
  }

  _TrendPayload _parseTrendPayload(Map<String, dynamic> data) {
    final rawSeries = data['series'];
    final values = <double>[];
    final timestamps = <DateTime>[];

    if (rawSeries is List) {
      if (rawSeries.isNotEmpty && rawSeries.first is Map) {
        for (final item in rawSeries.whereType<Map>()) {
          final rawValue = item['value'];
          if (rawValue is num) {
            values.add(rawValue.toDouble());
            final parsed = _parseTime(
              item['timestamp']?.toString() ??
                  item['time']?.toString() ??
                  item['ts']?.toString(),
            );
            if (parsed != null) {
              timestamps.add(parsed);
            }
          }
        }
      } else {
        values.addAll(
          rawSeries.whereType<num>().map((e) => e.toDouble()),
        );
      }
    }

    final rawTimestamps = data['timestamps'];
    if (rawTimestamps is List && rawTimestamps.length == values.length) {
      timestamps
        ..clear()
        ..addAll(
          rawTimestamps
              .map((e) => _parseTime(e?.toString()))
              .whereType<DateTime>(),
        );
      if (timestamps.length != values.length) {
        timestamps.clear();
      }
    } else if (timestamps.length != values.length) {
      timestamps.clear();
    }

    return _TrendPayload(values: values, timestamps: timestamps);
  }

  DateTime? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    return parsed?.toLocal();
  }

  static SensorLevel _levelFor(SensorType type, double value) {
    if (value >= _critical(type)) return SensorLevel.critical;
    if (value >= _warning(type)) return SensorLevel.warning;
    return SensorLevel.normal;
  }

  static double _warning(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 70;
      case SensorType.vibration:
        return 2.8;
      case SensorType.temperature:
        return 35;
    }
  }

  static double _critical(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 85;
      case SensorType.vibration:
        return 4.0;
      case SensorType.temperature:
        return 40;
    }
  }

  static String _thresholdText(SensorType type) {
    switch (type) {
      case SensorType.waterLevel:
        return 'Warning threshold: 70% | Critical threshold: 85%';
      case SensorType.vibration:
        return 'Warning threshold: 2.8 mm/s RMS | Critical threshold: 4.0 mm/s RMS';
      case SensorType.temperature:
        return 'Warning threshold: 35°C | Critical threshold: 40°C';
    }
  }

  static String _thresholdState(double? value, SensorType type) {
    if (value == null) return 'No telemetry';
    if (value >= _critical(type)) return 'Critical';
    if (value >= _warning(type)) return 'Warning';
    return 'Stable';
  }

  static UiBadgeTone _toneForReading(
      SensorLevel? level, double? value, SensorType type) {
    if (value == null && level == null) return UiBadgeTone.noTelemetry;
    final resolved = level ?? _levelFor(type, value!);
    switch (resolved) {
      case SensorLevel.critical:
        return UiBadgeTone.critical;
      case SensorLevel.warning:
        return UiBadgeTone.warning;
      case SensorLevel.normal:
        return UiBadgeTone.stable;
    }
  }

  static String _statusLabel(
      SensorLevel? level, double? value, SensorType type) {
    if (value == null && level == null) return 'No telemetry';
    final resolved = level ?? _levelFor(type, value!);
    switch (resolved) {
      case SensorLevel.critical:
        return 'Critical';
      case SensorLevel.warning:
        return 'Warning';
      case SensorLevel.normal:
        return 'Stable';
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

class _TrendPayload {
  const _TrendPayload({
    required this.values,
    required this.timestamps,
  });

  final List<double> values;
  final List<DateTime> timestamps;
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelBuilder,
  });

  final String title;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: UiText.helper.copyWith(
            fontSize: 11,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          value: value,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelBuilder?.call(item) ?? item.toString()),
                ),
              )
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5F7),
        borderRadius: BorderRadius.circular(UiRadius.input),
        border: Border.all(color: const Color(0xFFE0E9ED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: UiText.helper),
          const SizedBox(width: 6),
          Text(value, style: UiText.cardTitle),
        ],
      ),
    );
  }
}
