import 'dart:html' as html;

const String _alertBeepDataUri =
    'data:audio/wav;base64,UklGRoQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YWAAAACAgICAgICAgICAgICAf39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIB/f39/f39/f39/f39/f39/f39/f39/f39/gICAgICAgICAgICAgIA=';

html.AudioElement? _audio;

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
  bool announce = true,
}) async {
  try {
    _audio ??= html.AudioElement(_alertBeepDataUri)
      ..preload = 'auto'
      ..volume = 1.0;
    _audio!
      ..muted = false
      ..loop = false
      ..currentTime = 0;
    await _audio!.play();
  } catch (_) {
    // Keep trying speech below.
  }

  // Secondary path: voice cue (helps on some browsers/devices where beep is muted).
  if (announce) {
    try {
      final normalized = severityLabel.toUpperCase() == 'WARNING' ? 'Warning alert' : 'Critical alert';
      final utterance = html.SpeechSynthesisUtterance(normalized);
      utterance
        ..volume = 1.0
        ..rate = 1.0
        ..pitch = 1.0;
      final synth = html.window.speechSynthesis;
      synth?.cancel();
      synth?.speak(utterance);
    } catch (_) {
      // Ignore final fallback failure.
    }
  }
}

Future<void> stopAlertTone() async {
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
