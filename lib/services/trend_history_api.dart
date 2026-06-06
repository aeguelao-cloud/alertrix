import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/metrics_config.dart';
import '../models/monitoring_models.dart';

class TrendHistoryApi {
  TrendHistoryApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<SensorTrendSeries> fetchTrend({
    required SensorType metric,
    required String range,
  }) async {
    final uri = Uri.parse('$baseUrl/api/trends').replace(
      queryParameters: {
        'metric': metricToApi(metric),
        'range': rangeToApi(range),
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final resp = await _client.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Trends API ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return parseTrendPayload(data);
  }

  static SensorTrendSeries parseTrendPayload(Map<String, dynamic> data) {
    final rawSeries = data['series'] ?? data['points'];
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
                  item['capturedAt']?.toString() ??
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

    return SensorTrendSeries(values: values, timestamps: timestamps);
  }

  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    return parsed?.toLocal();
  }
}
