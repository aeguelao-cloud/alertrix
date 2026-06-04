Future<void> playAlertTone({
  String severityLabel = 'CRITICAL',
  String? announcementText,
  bool announce = true,
  bool continuous = false,
}) async {}

Future<void> primeAlertAudio() async {}

Future<void> stopAlertTone() async {}

bool isAlertPageVisible() => true;

Future<void> showAlertNotification({
  required String title,
  required String body,
  String? tag,
  String severityLabel = 'CRITICAL',
}) async {}
