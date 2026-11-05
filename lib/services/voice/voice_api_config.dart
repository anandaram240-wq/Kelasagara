// lib/services/voice/voice_api_config.dart
// Secure API Configuration for Kelasagara Voice Engine V70

class VoiceApiConfig {
  // Configured via --dart-define or fallback
  static const String _envSarvam = String.fromEnvironment('SARVAM_API_KEY');
  static const String _envGemini = String.fromEnvironment('GEMINI_API_KEY');
  static const String _envGroq   = String.fromEnvironment('GROQ_API_KEY');

  // Hardened fallback keys provided securely via --dart-define or runtime environment
  static const String _defaultSarvam = String.fromEnvironment('DEFAULT_SARVAM_KEY', defaultValue: '');
  static const String _defaultGemini = String.fromEnvironment('DEFAULT_GEMINI_KEY', defaultValue: '');
  static const String _defaultGroq   = String.fromEnvironment('DEFAULT_GROQ_KEY', defaultValue: '');

  static String get sarvamApiKey =>
      _envSarvam.isNotEmpty ? _envSarvam : _defaultSarvam;

  static String get geminiApiKey =>
      _envGemini.isNotEmpty ? _envGemini : _defaultGemini;

  static String get groqApiKey =>
      _envGroq.isNotEmpty ? _envGroq : _defaultGroq;

  // Endpoint URIs
  static const String sarvamTtsUrl = 'https://api.sarvam.ai/text-to-speech';
  static const String sarvamAsrUrl = 'https://api.sarvam.ai/speech-to-text';
  static const String geminiLiveWsUrl = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent';
  static const String groqChatUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String groqAudioUrl = 'https://api.groq.com/openai/v1/audio/transcriptions';

  // Sarvam Bulbul v3 configuration
  static const String sarvamBulbulModel = 'bulbul:v3';
  static const String sarvamKannadaSpeaker = 'priya'; // measured high-naturalness female Kannada speaker
  static const String sarvamEnglishSpeaker = 'aditya'; // measured clear Indian English speaker

  // Gemini Live configuration
  static const String geminiLiveModel = 'models/gemini-2.0-flash-exp';
}
