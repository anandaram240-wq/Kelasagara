// lib/services/voice/voice_settings_service.dart
// Persistent Settings for Voice Command Center & Accessibility

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VoiceLanguagePreference {
  auto('auto', 'Automatic / ಸ್ವಯಂಚಾಲಿತ'),
  kannada('kannada', 'Kannada / ಕನ್ನಡ'),
  english('english', 'English / ಇಂಗ್ಲಿಷ್');

  final String code;
  final String label;
  const VoiceLanguagePreference(this.code, this.label);

  static VoiceLanguagePreference fromCode(String? c) => switch (c) {
    'kannada' => VoiceLanguagePreference.kannada,
    'english' => VoiceLanguagePreference.english,
    _         => VoiceLanguagePreference.auto,
  };
}

class VoiceSettingsService extends ChangeNotifier {
  static final VoiceSettingsService instance = VoiceSettingsService._();
  VoiceSettingsService._();

  static const String _keyEnabled       = 'vcc_enabled';
  static const String _keyLanguage      = 'vcc_language';
  static const String _keyVoiceReplies  = 'vcc_voice_replies';
  static const String _keySpeaker       = 'vcc_speaker';
  static const String _keySpeed         = 'vcc_speed';
  static const String _keyHaptic        = 'vcc_haptic';
  static const String _keyTranscript    = 'vcc_transcript';
  static const String _keyConfirmBook   = 'vcc_confirm_booking';

  bool _enabled = true;
  VoiceLanguagePreference _language = VoiceLanguagePreference.auto;
  bool _voiceReplies = true;
  String _speaker = 'priya';
  double _speed = 1.0;
  bool _haptic = true;
  bool _showTranscript = true;
  bool _confirmBooking = true;
  bool _initialized = false;

  bool get isEnabled => _enabled;
  VoiceLanguagePreference get language => _language;
  bool get voiceReplies => _voiceReplies;
  String get speaker => _speaker;
  double get speed => _speed;
  bool get hapticEnabled => _haptic;
  bool get showLiveTranscript => _showTranscript;
  bool get requireBookingConfirmation => _confirmBooking;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_keyEnabled) ?? true;
      _language = VoiceLanguagePreference.fromCode(prefs.getString(_keyLanguage));
      _voiceReplies = prefs.getBool(_keyVoiceReplies) ?? true;
      _speaker = prefs.getString(_keySpeaker) ?? 'priya';
      _speed = prefs.getDouble(_keySpeed) ?? 1.0;
      _haptic = prefs.getBool(_keyHaptic) ?? true;
      _showTranscript = prefs.getBool(_keyTranscript) ?? true;
      _confirmBooking = prefs.getBool(_keyConfirmBook) ?? true;
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceSettings] Error loading preferences: $e');
    }
  }

  Future<void> setEnabled(bool val) async {
    _enabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, val);
  }

  Future<void> setLanguage(VoiceLanguagePreference pref) async {
    _language = pref;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, pref.code);
  }

  Future<void> setVoiceReplies(bool val) async {
    _voiceReplies = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoiceReplies, val);
  }

  Future<void> setSpeaker(String s) async {
    _speaker = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpeaker, s);
  }

  Future<void> setSpeed(double s) async {
    _speed = s.clamp(0.5, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySpeed, _speed);
  }

  Future<void> setHaptic(bool val) async {
    _haptic = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHaptic, val);
  }

  Future<void> setShowTranscript(bool val) async {
    _showTranscript = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTranscript, val);
  }

  Future<void> setConfirmBooking(bool val) async {
    _confirmBooking = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyConfirmBook, val);
  }
}
