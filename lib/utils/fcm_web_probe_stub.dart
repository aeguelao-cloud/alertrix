import 'dart:async';

Future<bool> isWebFcmRuntimeSupported() async => true;

Future<void> waitForWebFcmServiceWorkerReady({
  Duration timeout = const Duration(seconds: 8),
}) async {}

String webNotificationPermission() => 'unknown';
