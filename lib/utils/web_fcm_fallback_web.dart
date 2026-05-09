import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class WebFcmFallbackResult {
  const WebFcmFallbackResult({
    required this.token,
    required this.error,
    required this.attempted,
  });

  final String? token;
  final String? error;
  final bool attempted;
}

Future<WebFcmFallbackResult> tryAcquireWebFcmToken({
  required String apiKey,
  required String appId,
  required String projectId,
  required String messagingSenderId,
  required String vapidKey,
}) async {
  if (html.Notification.permission != 'granted') {
    return const WebFcmFallbackResult(
      token: null,
      error: 'Web fallback skipped: notification permission is not granted',
      attempted: false,
    );
  }

  if (vapidKey.trim().isEmpty) {
    return const WebFcmFallbackResult(
      token: null,
      error: 'Web fallback skipped: empty VAPID key',
      attempted: false,
    );
  }

  try {
    final registration = await _resolveMessagingServiceWorkerRegistration();
    if (registration == null) {
      return const WebFcmFallbackResult(
        token: null,
        error: 'Web fallback failed: messaging service worker unavailable',
        attempted: true,
      );
    }

    html.PushSubscription? subscription;
    try {
      subscription = await _resolvePushSubscription(
        registration: registration,
        vapidKey: vapidKey,
      );
    } catch (error) {
      return WebFcmFallbackResult(
        token: null,
        error: 'Web fallback failed: push subscribe error: $error',
        attempted: true,
      );
    }
    if (subscription == null) {
      return const WebFcmFallbackResult(
        token: null,
        error:
            'Web fallback failed: unable to create browser push subscription',
        attempted: true,
      );
    }

    final auth = _subscriptionKeyBase64Url(subscription, 'auth');
    final p256dh = _subscriptionKeyBase64Url(subscription, 'p256dh');
    final endpoint = subscription.endpoint ?? '';
    if (endpoint.isEmpty ||
        auth == null ||
        auth.isEmpty ||
        p256dh == null ||
        p256dh.isEmpty) {
      return const WebFcmFallbackResult(
        token: null,
        error: 'Web fallback failed: push subscription keys are incomplete',
        attempted: true,
      );
    }

    final client = http.Client();
    try {
      final installationsResp = await client.post(
        Uri.parse(
            'https://firebaseinstallations.googleapis.com/v1/projects/$projectId/installations'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: jsonEncode({
          'appId': appId,
          'authVersion': 'FIS_v2',
          'sdkVersion': 'w:0.6.6',
        }),
      );

      if (installationsResp.statusCode < 200 ||
          installationsResp.statusCode >= 300) {
        return WebFcmFallbackResult(
          token: null,
          error: _buildApiFailure(
            'installations',
            installationsResp.statusCode,
            installationsResp.body,
          ),
          attempted: true,
        );
      }

      final installJson =
          jsonDecode(installationsResp.body) as Map<String, dynamic>;
      final authTokenObj = installJson['authToken'];
      final fisToken = authTokenObj is Map<String, dynamic>
          ? authTokenObj['token']?.toString()
          : null;
      if (fisToken == null || fisToken.isEmpty) {
        return const WebFcmFallbackResult(
          token: null,
          error: 'Web fallback failed: installations auth token missing',
          attempted: true,
        );
      }

      final registrationResp = await client.post(
        Uri.parse(
            'https://fcmregistrations.googleapis.com/v1/projects/$messagingSenderId/registrations'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
          'x-goog-firebase-installations-auth': fisToken,
        },
        body: jsonEncode({
          'web': {
            'endpoint': endpoint,
            'auth': auth,
            'p256dh': p256dh,
          },
        }),
      );

      if (registrationResp.statusCode < 200 ||
          registrationResp.statusCode >= 300) {
        return WebFcmFallbackResult(
          token: null,
          error: _buildApiFailure(
            'fcm registrations',
            registrationResp.statusCode,
            registrationResp.body,
          ),
          attempted: true,
        );
      }

      final registrationJson =
          jsonDecode(registrationResp.body) as Map<String, dynamic>;
      final token = registrationJson['token']?.toString();
      if (token == null || token.isEmpty) {
        return const WebFcmFallbackResult(
          token: null,
          error: 'Web fallback failed: registration token missing',
          attempted: true,
        );
      }

      return WebFcmFallbackResult(
        token: token,
        error: null,
        attempted: true,
      );
    } finally {
      client.close();
    }
  } catch (error) {
    return WebFcmFallbackResult(
      token: null,
      error: 'Web fallback failed: $error',
      attempted: true,
    );
  }
}

Future<html.ServiceWorkerRegistration?>
    _resolveMessagingServiceWorkerRegistration() async {
  final sw = html.window.navigator.serviceWorker;
  if (sw == null) return null;

  try {
    return await sw
        .getRegistration('/firebase-cloud-messaging-push-scope')
        .timeout(const Duration(seconds: 6));
  } catch (_) {}

  try {
    final reg = await sw.register(
      '/firebase-messaging-sw.js',
      {'scope': '/firebase-cloud-messaging-push-scope'},
    ).timeout(const Duration(seconds: 8));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return reg;
  } catch (_) {
    // Continue to enumerate registrations as a final fallback.
  }

  try {
    final regs =
        await sw.getRegistrations().timeout(const Duration(seconds: 6));
    for (final reg in regs) {
      final scopePath = Uri.parse(reg.scope).path;
      if (scopePath == '/firebase-cloud-messaging-push-scope' ||
          scopePath == '/firebase-cloud-messaging-push-scope/') {
        return reg;
      }
    }
  } catch (_) {}

  return null;
}

Future<html.PushSubscription?> _resolvePushSubscription({
  required html.ServiceWorkerRegistration registration,
  required String vapidKey,
}) async {
  final pushManager = registration.pushManager;
  if (pushManager == null) return null;

  final keyBytes = _decodeBase64Url(vapidKey);
  if (keyBytes == null || keyBytes.isEmpty) return null;

  Object? lastError;
  try {
    return await pushManager.subscribe({
      'userVisibleOnly': true,
      'applicationServerKey': keyBytes,
    }).timeout(const Duration(seconds: 8));
  } catch (error) {
    lastError = error;
  }

  // Some browsers are stricter about BufferSource and prefer ByteBuffer.
  try {
    return await pushManager.subscribe({
      'userVisibleOnly': true,
      'applicationServerKey': keyBytes.buffer,
    }).timeout(const Duration(seconds: 8));
  } catch (error) {
    lastError = error;
  }

  throw StateError('subscribe failed: $lastError');
}

String _trimBody(String text, {int max = 260}) {
  if (text.length <= max) return text;
  return text.substring(0, max);
}

String _normalizeGoogleApiErrorBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    }
  } catch (_) {}
  return _trimBody(body);
}

String _buildApiFailure(String stage, int statusCode, String body) {
  final normalized = _normalizeGoogleApiErrorBody(body);
  return 'Web fallback failed: $stage API $statusCode message=$normalized';
}

String? _subscriptionKeyBase64Url(
    html.PushSubscription subscription, String key) {
  // Primary path: browser native key bytes.
  try {
    final raw = subscription.getKey(key);
    final bytes = _toUint8List(raw);
    if (bytes == null || bytes.isEmpty) return null;
    return _encodeBase64Url(bytes);
  } catch (_) {
    // Fallback path: PushSubscription#toJson().keys.<key>
  }

  try {
    final dynamic dynamicSub = subscription;
    final jsonObject = dynamicSub.toJson();
    if (jsonObject is Map) {
      final keys = jsonObject['keys'];
      if (keys is Map) {
        final raw = keys[key];
        if (raw != null) {
          final str = raw.toString().trim();
          if (str.isNotEmpty) {
            return str;
          }
        }
      }
    }
  } catch (_) {
    // Continue to final JSON serialization fallback.
  }

  try {
    final encoded = jsonEncode(subscription);
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      final keys = decoded['keys'];
      if (keys is Map) {
        final raw = keys[key];
        if (raw != null) {
          final str = raw.toString().trim();
          if (str.isNotEmpty) {
            return str;
          }
        }
      }
    }
  } catch (_) {}

  return null;
}

Uint8List? _toUint8List(Object? value) {
  if (value == null) return null;
  if (value is Uint8List) return value;
  if (value is ByteBuffer) return Uint8List.view(value);
  return null;
}

Uint8List? _decodeBase64Url(String input) {
  try {
    final normalized = base64Url.normalize(input);
    return Uint8List.fromList(base64Url.decode(normalized));
  } catch (_) {
    return null;
  }
}

String _encodeBase64Url(Uint8List bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
