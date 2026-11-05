import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum VoiceIntent {
  bookPlumber, bookElectrician, bookMason, bookCarpenter,
  bookPainter, bookDriver, bookCook, bookCleaner,
  findJob, postJob, checkApplications, checkBookings,
  goHome, unknown
}

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isAvailable = false;
  String _selectedLocale = 'kn_IN';

  Future<bool> initialize() async {
    _isAvailable = await _speech.initialize(
      onStatus: (s) {},
      onError: (e) {},
    );
    // Find Kannada locale
    if (_isAvailable) {
      final locales = await _speech.locales();
      final kn = locales.where((l) =>
        l.localeId.toLowerCase().contains('kn') ||
        l.name.toLowerCase().contains('kannada')
      ).toList();
      if (kn.isNotEmpty) _selectedLocale = kn.first.localeId;
    }
    // Configure TTS for Kannada
    await _tts.setLanguage('kn-IN');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String transcript, bool isFinal) onResult,
    required Function() onListeningComplete,
  }) async {
    if (!_isAvailable) return;
    await _speech.listen(
      localeId: _selectedLocale,
      onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenMode: ListenMode.confirmation,
    );
  }

  Future<void> stopListening() async => _speech.stop();
  bool get isListening => _speech.isListening;

  // ── Intent Detection (Kannada + English + Hinglish) ─────────────
  VoiceIntent parseIntent(String text) {
    final t = text.toLowerCase().trim();
    if (_matches(t, ['plumber', 'ಪ್ಲಂಬರ್', 'plambar', 'pipe', 'ಪೈಪ್'])) return VoiceIntent.bookPlumber;
    if (_matches(t, ['electrician', 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್', 'electric', 'light', 'ವಿದ್ಯುತ್'])) return VoiceIntent.bookElectrician;
    if (_matches(t, ['mason', 'ಕಟ್ಟಡ', 'cement', 'brick', 'ಇಟ್ಟಿಗೆ'])) return VoiceIntent.bookMason;
    if (_matches(t, ['carpenter', 'ಮರಗೆಲಸ', 'wood', 'ಮರ'])) return VoiceIntent.bookCarpenter;
    if (_matches(t, ['painter', 'ಬಣ್ಣ', 'paint', 'color'])) return VoiceIntent.bookPainter;
    if (_matches(t, ['driver', 'ಚಾಲಕ', 'drive', 'car', 'ಕಾರು'])) return VoiceIntent.bookDriver;
    if (_matches(t, ['cook', 'ಅಡುಗೆ', 'chef', 'food', 'ಊಟ'])) return VoiceIntent.bookCook;
    if (_matches(t, ['cleaner', 'ಸ್ವಚ್ಛ', 'clean', 'sweep', 'ಗುಡಿಸು'])) return VoiceIntent.bookCleaner;
    if (_matches(t, ['job', 'ಕೆಲಸ', 'kelsa', 'work', 'ಕೆಲ್ಸ'])) return VoiceIntent.findJob;
    if (_matches(t, ['post job', 'job post', 'ಕೆಲಸ ಪೋಸ್ಟ್', 'hire'])) return VoiceIntent.postJob;
    if (_matches(t, ['applications', 'ಅರ್ಜಿ', 'applied', 'status'])) return VoiceIntent.checkApplications;
    if (_matches(t, ['home', 'back', 'ಹೋಮ್', 'ಹಿಂದೆ'])) return VoiceIntent.goHome;
    return VoiceIntent.unknown;
  }

  bool _matches(String text, List<String> keywords) =>
    keywords.any((k) => text.contains(k.toLowerCase()));

  // ── Speak in Kannada ─────────────────────────────────────────────
  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async => _tts.stop();

  // ── Kannada responses for intents ────────────────────────────────
  String getKannadaResponse(VoiceIntent intent) {
    switch (intent) {
      case VoiceIntent.bookPlumber:   return 'ಪ್ಲಂಬರ್ ಹುಡುಕುತ್ತಿದ್ದೇನೆ. ನಿಮ್ಮ ಹತ್ತಿರದ ಪ್ಲಂಬರ್ ತೋರಿಸುತ್ತೇನೆ';
      case VoiceIntent.bookElectrician: return 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್ ಹುಡುಕುತ್ತಿದ್ದೇನೆ';
      case VoiceIntent.findJob:       return 'ನಿಮಗಾಗಿ ಕೆಲಸ ಹುಡುಕುತ್ತಿದ್ದೇನೆ';
      case VoiceIntent.postJob:       return 'ಕೆಲಸ ಪೋಸ್ಟ್ ಮಾಡಲು ಹೋಗುತ್ತಿದ್ದೇನೆ';
      case VoiceIntent.checkApplications: return 'ನಿಮ್ಮ ಅರ್ಜಿಗಳನ್ನು ತೋರಿಸುತ್ತೇನೆ';
      default: return 'ನಿಮ್ಮ ಆದೇಶ ಅರ್ಥವಾಗಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಹೇಳಿ';
    }
  }
}
