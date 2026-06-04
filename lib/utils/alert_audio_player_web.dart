// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

const String _alertBeepDataUri =
    'data:audio/wav;base64,UklGRoQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YWAAAACAgICAgICAgICAgICAf39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIA=';

html.AudioElement? _audio;
Timer? _speechRepeatTimer;

Future<void> primeAlertAudio() async {
  try {
    _audio ??= html.AudioElement(_alertBeepDataUri)
      ..preload = 'auto'
      ..volume = 1.0;
    _audio!
      ..muted = true
      ..currentTime = 0;
    await _audio!.play();
    _audio!
      ..pause()
      ..muted = false
      ..currentTime = 0;
  } catch (_) {
    // Best effort only.
  }
}

Future<void> playAlertTone({
  String severityLabel = 'CRITICAL',
  String? announcementText,
  bool announce = true,
  bool continuous = false,
}) async {
  try {
    _audio ??= html.AudioElement(_alertBeepDataUri)
      ..preload = 'auto'
      ..volume = 1.0;
    _audio!
      ..muted = false
      ..loop = continuous
      ..currentTime = 0;
    await _audio!.play();
  } catch (_) {
    // Keep trying speech below.
  }

  // Secondary path: voice cue (helps on some browsers/devices where beep is muted).
  if (announce) {
    try {
      _speechRepeatTimer?.cancel();
      final text = (announcementText ?? '').trim().isNotEmpty
          ? announcementText!.trim()
          : (severityLabel.toUpperCase() == 'WARNING'
              ? 'Warning alert. Please check the Alertrix dashboard.'
              : 'Critical alert. Immediate response is required.');
      final repeatEvery = severityLabel.toUpperCase() == 'WARNING'
          ? const Duration(seconds: 8)
          : const Duration(seconds: 5);

      void speak() {
        final utterance = html.SpeechSynthesisUtterance(text);
        utterance
          ..volume = 1.0
          ..rate = 0.95
          ..pitch = 1.0;
        final synth = html.window.speechSynthesis;
        synth?.cancel();
        synth?.speak(utterance);
      }

      speak();
      if (continuous) {
        _speechRepeatTimer = Timer.periodic(repeatEvery, (_) => speak());
      }
    } catch (_) {
      // Ignore final fallback failure.
    }
  }
}

Future<void> stopAlertTone() async {
  _speechRepeatTimer?.cancel();
  _speechRepeatTimer = null;

  try {
    html.window.speechSynthesis?.cancel();
  } catch (_) {
    // Ignore stop failures.
  }

  try {
    _audio
      ?..pause()
      ..loop = false
      ..currentTime = 0;
  } catch (_) {
    // Ignore stop failures.
  }
}

bool isAlertPageVisible() {
  try {
    return html.document.visibilityState == 'visible';
  } catch (_) {
    return true;
  }
}

Future<void> showAlertNotification({
  required String title,
  required String body,
  String? tag,
  String severityLabel = 'CRITICAL',
}) async {
  try {
    if (html.Notification.permission != 'granted') return;
    html.Notification(
      title,
      body: body,
      icon: '/icons/Icon-192.png',
      tag: tag,
    );
  } catch (_) {
    // Browser notifications are best effort and browser-policy dependent.
  }
}
