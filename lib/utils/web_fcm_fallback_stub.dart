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
  return const WebFcmFallbackResult(
    token: null,
    error: null,
    attempted: false,
  );
}
