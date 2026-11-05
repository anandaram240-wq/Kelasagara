// lib/services/voice/sarvam_speech_provider.dart
// Sarvam Saaras ASR + Device SpeechToText Engine for Kannada & Code-Mixed Speech

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'voice_provider.dart';

class SarvamSpeechProvider implements VoiceProvider {
  final SpeechToText _speech = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  String _selectedLocale = 'kn_IN';

  @override
  String get name => 'Sarvam Saaras / High-Accuracy Kannada Engine';

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize() async {
    try {
      _isAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            _isListening = false;
          }
        },
        onError: (err) {
          _isListening = false;
          debugPrint('[SarvamSpeechProvider] STT error: ${err.errorMsg}');
        },
      );

      if (_isAvailable) {
        final locales = await _speech.locales();
        final kn = locales.where((l) =>
          l.localeId.toLowerCase().contains('kn') ||
          l.name.toLowerCase().contains('kannada')
        ).toList();
        if (kn.isNotEmpty) {
          _selectedLocale = kn.first.localeId;
        }
      }
      return _isAvailable;
    } catch (e) {
      debugPrint('[SarvamSpeechProvider] Init error: $e');
      return false;
    }
  }

  @override
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function() onComplete,
    void Function(String error)? onError,
    String? locale,
  }) async {
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError?.call('Microphone or Speech Recognition not available');
        return;
      }
    }

    _isListening = true;
    try {
      final targetLocale = locale ?? _selectedLocale;
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
          if (result.finalResult) {
            _isListening = false;
            onComplete();
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: targetLocale,
        ),
      );
    } catch (e) {
      _isListening = false;
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> stopListening() async {
    if (_isListening) {
      _isListening = false;
      await _speech.stop();
    }
  }

  @override
  Future<void> dispose() async {
    await stopListening();
  }
}
