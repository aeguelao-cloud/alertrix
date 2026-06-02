import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/fcm_web_probe_stub.dart'
    if (dart.library.html) '../utils/fcm_web_probe_web.dart' as web_probe;
import '../utils/web_fcm_fallback_stub.dart'
    if (dart.library.html) '../utils/web_fcm_fallback_web.dart'
    as web_fcm_fallback;

const _defaultFirebaseApiKey = 'AIzaSyCdaebCdME_g0QDjFYhysnQUpvEqlcmW3w';
const _defaultFirebaseAppId = '1:509883742045:web:a755fe97ce4aa0c5c99ab4';
const _defaultFirebaseMessagingSenderId = '509883742045';
const _defaultFirebaseProjectId = 'alertrix-eb014';
const _defaultFirebaseStorageBucket = 'alertrix-eb014.firebasestorage.app';
const _defaultFirebaseAuthDomain = 'alertrix-eb014.firebaseapp.com';
const _maxTokenAttempts = 5;
const _defaultFcmWebVapidKey =
    'BNNhmKgShm2p2SYFBymJwGWnrmt_o-i9AKG3weWEll2cfraqH1CgGbimMaaGvI5jodCxC6DGY9ITd2_a2SV3swg';

class PushNotificationService {
  PushNotificationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  String? _lastErrorMessage;
  bool _lastFailureRetryable = true;

  String? get lastErrorMessage => _lastErrorMessage;
  bool get lastFailureRetryable => _lastFailureRetryable;

  Future<String?> initializeAndGetToken({bool userInitiated = false}) async {
    _lastErrorMessage = null;
    _lastFailureRetryable = true;
    final options = _optionsFromEnv();
    const enableWebFcm = bool.fromEnvironment(
      'ENABLE_WEB_FCM',
      defaultValue: true,
    );
    const webVapidKey = String.fromEnvironment(
      'FCM_WEB_VAPID_KEY',
      defaultValue: _defaultFcmWebVapidKey,
    );
    final debugInfo = _buildDebugInfo(options, webVapidKey);
    if (kIsWeb && !enableWebFcm) {
      _lastErrorMessage = 'Push disabled by config (MQTT mode)';
      _lastFailureRetryable = false;
      return null;
    }
    if (options == null) {
      _lastErrorMessage = 'FCM OFF: Firebase options missing ($debugInfo)';
      _lastFailureRetryable = false;
      return null;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
    } catch (initError) {
      final message = 'FCM OFF: Firebase init failed: $initError ($debugInfo)';
      _lastErrorMessage = message;
      debugPrint(message);
      return null;
    }

    if (kIsWeb) {
      final webReady = await _prepareWebMessaging(debugInfo).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          _lastErrorMessage =
              'FCM OFF: service worker readiness timeout ($debugInfo)';
          _lastFailureRetryable = false;
          return false;
        },
      );
      if (!webReady) {
        return null;
      }

      final permission = web_probe.webNotificationPermission().toLowerCase();
      if (!userInitiated &&
          (permission == 'default' || permission == 'unknown')) {
        _lastErrorMessage =
            'FCM waiting for user action: allow browser notifications';
        _lastFailureRetryable = false;
        return null;
      }
    }

    try {
      NotificationSettings settings;
      try {
        settings = await FirebaseMessaging.instance
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        _lastErrorMessage =
            'FCM OFF: notification permission request timeout (${web_probe.webNotificationPermission()})';
        _lastFailureRetryable = false;
        return null;
      }
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _lastErrorMessage =
            'FCM OFF: notification permission denied ($debugInfo)';
        _lastFailureRetryable = false;
        return null;
      }
      if (kIsWeb &&
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        _lastErrorMessage =
            'FCM OFF: notification permission not granted (${web_probe.webNotificationPermission()})';
        _lastFailureRetryable = false;
        return null;
      }
      if (kIsWeb) {
        // Give service worker a short warm-up window on first launch.
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }

      String? lastError;
      if (kIsWeb) {
        final fallbackToken = await _tryWebFallbackToken(
          options: options,
          webVapidKey: webVapidKey,
          debugInfo: debugInfo,
          reason: 'preflight',
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            _lastErrorMessage = 'FCM web fallback timeout [preflight]';
            _lastFailureRetryable = false;
            return null;
          },
        );
        if (fallbackToken != null && fallbackToken.isNotEmpty) {
          return fallbackToken;
        }
        if (_lastErrorMessage != null && _lastErrorMessage!.isNotEmpty) {
          lastError = _lastErrorMessage;
        }
      }

      for (var i = 0; i < _maxTokenAttempts; i++) {
        try {
          if (i > 0 && kIsWeb) {
            await Future<void>.delayed(Duration(milliseconds: 1100 * i));
            try {
              await FirebaseMessaging.instance.deleteToken();
            } catch (_) {}
          }

          String? token;
          if (kIsWeb && webVapidKey.isNotEmpty) {
            try {
              token = await FirebaseMessaging.instance
                  .getToken(vapidKey: webVapidKey)
                  .timeout(const Duration(seconds: 10));
            } catch (_) {
              token = await FirebaseMessaging.instance
                  .getToken()
                  .timeout(const Duration(seconds: 10));
            }
          } else {
            token = await FirebaseMessaging.instance
                .getToken()
                .timeout(const Duration(seconds: 10));
          }

          if (token != null && token.trim().isNotEmpty) {
            return token;
          }
          lastError =
              'FCM OFF: token empty after attempt ${i + 1}/$_maxTokenAttempts ($debugInfo)';
        } catch (error) {
          lastError =
              'FCM token error on attempt ${i + 1}/$_maxTokenAttempts: $error ($debugInfo)';
          debugPrint(lastError);
          if (kIsWeb &&
              error
                  .toString()
                  .toLowerCase()
                  .contains('token-subscribe-failed')) {
            final fallbackToken = await _tryWebFallbackToken(
              options: options,
              webVapidKey: webVapidKey,
              debugInfo: debugInfo,
              reason: 'token-subscribe-failed',
            ).timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                _lastErrorMessage =
                    'FCM web fallback timeout [token-subscribe-failed]';
                _lastFailureRetryable = false;
                return null;
              },
            );
            if (fallbackToken != null && fallbackToken.isNotEmpty) {
              return fallbackToken;
            }
          }
        }
      }

      _lastErrorMessage =
          lastError ?? _lastErrorMessage ?? 'FCM OFF: token unavailable';
      return null;
    } catch (error) {
      final message = 'FCM token error: $error ($debugInfo)';
      _lastErrorMessage = message;
      debugPrint(message);
      return null;
    }
  }

  Future<String?> _tryWebFallbackToken({
    required FirebaseOptions options,
    required String webVapidKey,
    required String debugInfo,
    required String reason,
  }) async {
    final fallbackResult = await web_fcm_fallback.tryAcquireWebFcmToken(
      apiKey: options.apiKey,
      appId: options.appId,
      projectId: options.projectId,
      messagingSenderId: options.messagingSenderId,
      vapidKey: webVapidKey,
    );

    if (fallbackResult.token != null && fallbackResult.token!.isNotEmpty) {
      final message = 'FCM token ready (web fallback: $reason)';
      _lastErrorMessage = message;
      debugPrint(message);
      return fallbackResult.token;
    }

    if (fallbackResult.attempted) {
      final reasonText = fallbackResult.error ?? 'unknown error';
      final message =
          'FCM web fallback failed [$reason]: $reasonText ($debugInfo)';
      _lastErrorMessage = message;
      debugPrint(message);
    } else if (fallbackResult.error != null &&
        fallbackResult.error!.isNotEmpty) {
      final message =
          'FCM web fallback skipped [$reason]: ${fallbackResult.error} ($debugInfo)';
      debugPrint(message);
    }
    return null;
  }

  Future<bool> _prepareWebMessaging(String debugInfo) async {
    try {
      final supported = await FirebaseMessaging.instance.isSupported();
      if (!supported) {
        _lastErrorMessage =
            'FCM OFF: browser does not support Firebase Messaging ($debugInfo)';
        _lastFailureRetryable = false;
        return false;
      }
    } catch (error) {
      final message =
          'FCM OFF: failed to detect browser messaging support: $error ($debugInfo)';
      _lastErrorMessage = message;
      _lastFailureRetryable = false;
      debugPrint(message);
      return false;
    }

    final runtimeSupported = await web_probe.isWebFcmRuntimeSupported();
    if (!runtimeSupported) {
      _lastErrorMessage =
          'FCM OFF: browser missing required Web Push APIs ($debugInfo)';
      _lastFailureRetryable = false;
      return false;
    }

    await web_probe.waitForWebFcmServiceWorkerReady(
      timeout: const Duration(seconds: 8),
    );
    return true;
  }

  Future<void> registerToken({
    required String apiBaseUrl,
    required String token,
    required String userId,
  }) async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/api/push/register-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'userId': userId,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to register FCM token: ${resp.statusCode}');
    }
  }

  FirebaseOptions? _optionsFromEnv() {
    const apiKey = String.fromEnvironment(
      'FIREBASE_API_KEY',
      defaultValue: _defaultFirebaseApiKey,
    );
    const appId = String.fromEnvironment(
      'FIREBASE_APP_ID',
      defaultValue: _defaultFirebaseAppId,
    );
    const messagingSenderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: _defaultFirebaseMessagingSenderId,
    );
    const projectId = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: _defaultFirebaseProjectId,
    );
    const storageBucket = String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: _defaultFirebaseStorageBucket,
    );
    const authDomain = String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: _defaultFirebaseAuthDomain,
    );

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
      authDomain: authDomain,
    );
  }

  String _buildDebugInfo(FirebaseOptions? options, String vapidKey) {
    final apiKey = options?.apiKey ?? '';
    final apiKeyPrefix = apiKey.length >= 8 ? apiKey.substring(0, 8) : apiKey;
    final appId = options?.appId ?? '';
    final appSuffix =
        appId.length >= 8 ? appId.substring(appId.length - 8) : appId;
    final projectId = options?.projectId ?? '';
    return 'project=$projectId apiKey=$apiKeyPrefix*** app=***$appSuffix vapidLen=${vapidKey.length}';
  }
}
