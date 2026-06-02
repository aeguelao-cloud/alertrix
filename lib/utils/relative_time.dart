import 'package:timeago/timeago.dart' as timeago;

import '../config/time_display_config.dart';

String formatIncidentRelativeTime(DateTime timestamp, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final diff = clock.difference(timestamp);

  if (!diff.isNegative && diff >= kIncidentRelativeCutoff) {
    return _formatMonthDay(timestamp);
  }

  if (!diff.isNegative && diff.inSeconds < 45) {
    return 'Just now';
  }

  final value = timeago.format(timestamp, clock: clock);
  if (value == 'a moment ago' || value == 'just now') {
    return 'Just now';
  }
  return value;
}

String _formatMonthDay(DateTime dt) {
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
  final month = months[dt.month - 1];
  return '$month ${dt.day}';
}
