// lib/services/voice/voice_provider_router.dart
// Intelligent Multi-Language Voice Provider Router for Kelasagara V70

import 'voice_provider.dart';

class VoiceProviderRouter {
  /// Detect language: Kannada, English, or Code-Mixed
  static DetectedLanguage detectLanguage(String text) {
    if (text.trim().isEmpty) return DetectedLanguage.kannada;

    // Check for Kannada Unicode range: 0x0C80 to 0x0CFF
    final hasKannada = text.codeUnits.any((c) => c >= 0x0C80 && c <= 0x0CFF);
    // Check for Latin/English letters: a-z, A-Z
    final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(text);

    if (hasKannada && hasEnglish) {
      return DetectedLanguage.codeMixed;
    } else if (hasKannada) {
      return DetectedLanguage.kannada;
    } else if (hasEnglish) {
      return DetectedLanguage.english;
    }
    return DetectedLanguage.kannada;
  }

  /// Get preferred TTS language code for speech output
  static String getTtsLanguageCode(DetectedLanguage lang) {
    return switch (lang) {
      DetectedLanguage.kannada   => 'kn-IN',
      DetectedLanguage.english   => 'en-IN',
      DetectedLanguage.codeMixed => 'kn-IN', // Bulbul v3 handles code-mixed with kn-IN
      DetectedLanguage.unknown   => 'kn-IN',
    };
  }
}
