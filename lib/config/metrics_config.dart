import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';

const activeSensorTypes = <SensorType>[
  SensorType.waterLevel,
  SensorType.vibration,
  SensorType.temperature,
];

const timeRangeLabels = <String>['1H', '6H', '24H', '7D', '14D', '30D'];

const sensorColors = <SensorType, Color>{
  SensorType.waterLevel: Color(0xFF0A7E8C),
  SensorType.vibration: Color(0xFF385CB8),
  SensorType.temperature: Color(0xFFDA6D1E),
};

Color sensorColorOf(SensorType type) =>
    sensorColors[type] ?? const Color(0xFF0A7E8C);

Duration rangeDurationFor(String range) {
  switch (range) {
    case '1H':
      return const Duration(hours: 1);
    case '6H':
      return const Duration(hours: 6);
    case '24H':
      return const Duration(hours: 24);
    case '7D':
      return const Duration(days: 7);
    case '14D':
      return const Duration(days: 14);
    case '30D':
      return const Duration(days: 30);
    default:
      return const Duration(hours: 1);
  }
}

String rangeWindowLabel(String range) {
  switch (range) {
    case '1H':
      return 'Last 1 hour';
    case '6H':
      return 'Last 6 hours';
    case '24H':
      return 'Last 24 hours';
    case '7D':
      return 'Last 7 days';
    case '14D':
      return 'Last 14 days';
    case '30D':
      return 'Last 30 days';
    default:
      return 'Last 1 hour';
  }
}

List<DateTime> buildSeriesTimestamps({
  required int count,
  required String range,
  required DateTime end,
}) {
  if (count <= 0) return const <DateTime>[];
  if (count == 1) return <DateTime>[end];
  final duration = rangeDurationFor(range);
  final start = end.subtract(duration);
  final stepMs = duration.inMilliseconds / (count - 1);
  return List<DateTime>.generate(
    count,
    (i) => start.add(Duration(milliseconds: (stepMs * i).round())),
    growable: false,
  );
}

List<DateTime> buildXAxisTicks({
  required String range,
  required DateTime end,
}) {
  final alignedEnd = _alignTickEnd(range, end);
  switch (range) {
    case '1H':
      return List<DateTime>.generate(
        6,
        (i) => alignedEnd.subtract(Duration(minutes: (5 - i) * 10)),
        growable: false,
      );
    case '6H':
      return List<DateTime>.generate(
        6,
        (i) => alignedEnd.subtract(Duration(hours: 5 - i)),
        growable: false,
      );
    case '24H':
      return List<DateTime>.generate(
        6,
        (i) => alignedEnd.subtract(Duration(hours: (5 - i) * 4)),
        growable: false,
      );
    case '7D':
      return List<DateTime>.generate(
        7,
        (i) => alignedEnd.subtract(Duration(days: 6 - i)),
        growable: false,
      );
    case '14D':
      return List<DateTime>.generate(
        7,
        (i) => alignedEnd.subtract(Duration(days: (6 - i) * 2)),
        growable: false,
      );
    case '30D':
      return List<DateTime>.generate(
        5,
        (i) => alignedEnd.subtract(Duration(days: (4 - i) * 7)),
        growable: false,
      );
    default:
      return List<DateTime>.generate(
        6,
        (i) => alignedEnd.subtract(Duration(minutes: (5 - i) * 10)),
        growable: false,
      );
  }
}

String formatRangeTickLabel(DateTime dt, String range) {
  switch (range) {
    case '1H':
    case '6H':
    case '24H':
      return formatHm(dt);
    case '7D':
    case '14D':
    case '30D':
      return formatMonthDay(dt);
    default:
      return formatHm(dt);
  }
}

String formatHm(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String formatMonthDay(DateTime dt) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final m = months[(dt.month - 1).clamp(0, 11)];
  final d = dt.day.toString().padLeft(2, '0');
  return '$m $d';
}

String inferSamplingIntervalLabel(List<DateTime> timestamps) {
  if (timestamps.length < 2) return '--';
  final first = timestamps.first;
  final last = timestamps.last;
  if (!last.isAfter(first)) return '--';
  final avgMs = (last.millisecondsSinceEpoch - first.millisecondsSinceEpoch) ~/
      (timestamps.length - 1);
  final avg = Duration(milliseconds: avgMs);
  if (avg.inMinutes < 60) {
    return '${avg.inMinutes} min';
  }
  if (avg.inHours < 24) {
    final hours = (avg.inMinutes / 60);
    if ((hours - hours.round()).abs() < 0.05) {
      return '${hours.round()} h';
    }
    return '${hours.toStringAsFixed(1)} h';
  }
  final days = avg.inHours / 24;
  if ((days - days.round()).abs() < 0.05) {
    return '${days.round()} d';
  }
  return '${days.toStringAsFixed(1)} d';
}

DateTime _alignTickEnd(String range, DateTime end) {
  switch (range) {
    case '1H':
      return DateTime(
        end.year,
        end.month,
        end.day,
        end.hour,
        (end.minute ~/ 10) * 10,
      );
    case '6H':
      return DateTime(end.year, end.month, end.day, end.hour);
    case '24H':
      return DateTime(
        end.year,
        end.month,
        end.day,
        (end.hour ~/ 4) * 4,
      );
    case '7D':
    case '14D':
    case '30D':
      return DateTime(end.year, end.month, end.day);
    default:
      return end;
  }
}

int pointsForRange(String range) {
  switch (range) {
    case '1H':
      return 8;
    case '6H':
      return 16;
    case '24H':
      return 24;
    case '7D':
      return 48;
    case '14D':
      return 84;
    case '30D':
      return 120;
    default:
      return 8;
  }
}

String rangeToApi(String range) {
  switch (range) {
    case '1H':
      return '1h';
    case '6H':
      return '6h';
    case '24H':
      return '24h';
    case '7D':
      return '7d';
    case '14D':
      return '14d';
    case '30D':
      return '30d';
    default:
      return '1h';
  }
}

String metricToApi(SensorType metric) {
  switch (metric) {
    case SensorType.waterLevel:
      return 'water_level';
    case SensorType.vibration:
      return 'vibration';
    case SensorType.temperature:
      return 'temperature';
  }
}

List<double> buildTrendSeries({
  required List<double> source,
  required String range,
  required SensorType metric,
}) {
  if (source.isEmpty) return const <double>[];
  final target = pointsForRange(range);
  if (source.length <= target) {
    return List<double>.from(source, growable: false);
  }
  return source.sublist(source.length - target);
}
