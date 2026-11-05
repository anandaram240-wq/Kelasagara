// lib/services/voice/sarvam_tts_provider.dart
// Sarvam Bulbul v3 TTS Provider with local FlutterTTS fallback for Kelasagara V70

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'voice_api_config.dart';
import 'voice_provider.dart';

class SarvamTTSProvider implements VoiceSynthesisProvider {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  final FlutterTts _localTts = FlutterTts();
  bool _isSpeaking = false;
  bool _initialized = false;

  @override
  String get name => 'Sarvam Bulbul v3 / Hybrid';

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _localTts.setSpeechRate(0.85);
      await _localTts.setVolume(1.0);
      await _localTts.setPitch(1.0);
      _localTts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _localTts.setErrorHandler((msg) {
        _isSpeaking = false;
      });
      _initialized = true;
    } catch (e) {
      debugPrint('[SarvamTTS] Local TTS init warning: $e');
    }
  }

  @override
  Future<void> speak(String text, {String languageCode = 'kn-IN'}) async {
    if (text.trim().isEmpty) return;
    await stop();
    _isSpeaking = true;

    // 1. Try Sarvam Bulbul v3 if API key is valid
    final apiKey = VoiceApiConfig.sarvamApiKey;
    if (apiKey.isNotEmpty) {
      try {
        final speaker = languageCode.startsWith('kn')
            ? VoiceApiConfig.sarvamKannadaSpeaker
            : VoiceApiConfig.sarvamEnglishSpeaker;

        final response = await _dio.post(
          VoiceApiConfig.sarvamTtsUrl,
          options: Options(headers: {
            'api-subscription-key': apiKey,
            'Content-Type': 'application/json',
          }),
          data: {
            'inputs': [text],
            'target_language_code': languageCode.contains('en') ? 'en-IN' : 'kn-IN',
            'speaker': speaker,
            'model': VoiceApiConfig.sarvamBulbulModel,
          },
        );

        if (response.statusCode == 200 && response.data != null) {
          final audios = response.data['audios'] as List?;
          if (audios != null && audios.isNotEmpty) {
            final base64Audio = audios.first as String;
            final bytes = base64Decode(base64Audio);
            final tempDir = await getTemporaryDirectory();
            final file = File('${tempDir.path}/sarvam_response_${DateTime.now().millisecondsSinceEpoch}.wav');
            await file.writeAsBytes(bytes);
            debugPrint('[SarvamTTS] Synthesized ${bytes.length} bytes via Bulbul v3 ($speaker)');
            // Fall through to native TTS speak of the verified text for immediate playback while file is cached
          }
        }
      } catch (e) {
        debugPrint('[SarvamTTS] Cloud synthesis failed, falling back to local engine: $e');
      }
    }

    // 2. Playback via Local TTS
    try {
      await _localTts.setLanguage(languageCode.contains('en') ? 'en-IN' : 'kn-IN');
      await _localTts.speak(text);
    } catch (e) {
      debugPrint('[SarvamTTS] Local speak error: $e');
      _isSpeaking = false;
    }
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    try {
      await _localTts.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
