// lib/services/voice/voice_provider.dart
// Abstract Voice Provider and Speech Synthesis Interfaces for Kelasagara V70

import 'dart:async';

enum DetectedLanguage {
  kannada('kn-IN'),
  english('en-IN'),
  codeMixed('kn-en-IN'),
  unknown('auto');

  final String code;
  const DetectedLanguage(this.code);

  static DetectedLanguage fromCode(String code) {
    if (code.contains('kn')) return DetectedLanguage.kannada;
    if (code.contains('en')) return DetectedLanguage.english;
    return DetectedLanguage.codeMixed;
  }
}

/// Abstract contract for Speech-to-Text / Bidirectional Voice Providers
abstract class VoiceProvider {
  String get name;
  Future<bool> initialize();
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function() onComplete,
    void Function(String error)? onError,
  });
  Future<void> stopListening();
  bool get isListening;
  Future<void> dispose();
}

/// Abstract contract for Text-to-Speech / Audio Synthesis Providers
abstract class VoiceSynthesisProvider {
  String get name;
  Future<void> initialize();
  Future<void> speak(String text, {String languageCode = 'kn-IN'});
  Future<void> stop();
  bool get isSpeaking;
  Future<void> dispose();
}
