import 'package:flutter_test/flutter_test.dart';

import 'package:alertrix_frontend/services/trend_history_api.dart';

void main() {
  test('parseTrendPayload keeps real timestamps from trend points', () {
    final series = TrendHistoryApi.parseTrendPayload({
      'series': [
        {'timestamp': '2026-06-04T14:00:00Z', 'value': 32.5},
        {'capturedAt': '2026-06-04T14:08:00Z', 'value': 33.1},
      ],
    });

    expect(series.values, <double>[32.5, 33.1]);
    expect(series.hasTimedValues, isTrue);
    expect(
      series.timestamps.map((time) => time.toUtc().toIso8601String()),
      <String>[
        '2026-06-04T14:00:00.000Z',
        '2026-06-04T14:08:00.000Z',
      ],
    );
  });

  test('parseTrendPayload clears incomplete timestamps', () {
    final series = TrendHistoryApi.parseTrendPayload({
      'series': <num>[38, 39, 40],
      'timestamps': ['2026-06-04T14:00:00Z'],
    });

    expect(series.values, <double>[38, 39, 40]);
    expect(series.timestamps, isEmpty);
    expect(series.hasTimedValues, isFalse);
  });
}
