import 'dart:async';
import 'dart:html' as html;

Future<bool> isWebFcmRuntimeSupported() async {
  final hasServiceWorker = html.window.navigator.serviceWorker != null;
  final hasNotification = html.Notification.permission != null;
  return hasServiceWorker && hasNotification;
}

Future<void> waitForWebFcmServiceWorkerReady({
  Duration timeout = const Duration(seconds: 8),
}) async {
  final serviceWorker = html.window.navigator.serviceWorker;
  if (serviceWorker == null) {
    return;
  }

  try {
    await serviceWorker.ready.timeout(timeout);
  } catch (_) {
    // Best effort only.
  }
}

String webNotificationPermission() {
  try {
    return html.Notification.permission ?? 'unknown';
  } catch (_) {
    return 'unknown';
  }
}
