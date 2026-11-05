// lib/services/voice/voice_response_builder.dart
// Bilingual (Kannada + English) TTS Response Builder for Kelasagara Voice
// Builds natural speech from tool results — Kannada primary, English fallback.
// All worker list, booking, chat, and navigation responses live here.

import 'voice_tool_registry.dart';

class VoiceResponseBuilder {
  // ── Worker List ───────────────────────────────────────────────────────────

  /// Full worker list announcement (after SEARCH_WORKERS).
  /// Kannada: "3 ಪೇಂಟರ್ ಸಿಕ್ಕಿದ್ದಾರೆ. ಒಂದು — ರಮೇಶ್, 1.2 ಕಿಮೀ ..."
  /// English: "Found 3 painters. One — Ramesh, 1.2 km away ..."
  static String buildWorkerListResponse({
    required List<WorkerCandidate> candidates,
    required String skill,
    required String language,
    String? district,
  }) {
    if (candidates.isEmpty) {
      return buildNoWorkersResponse(
          skill: skill, language: language, district: district);
    }

    final count = candidates.length;
    final skillKn = _skillKn(skill);
    final skillEn = _skillEn(skill);
    final districtPartKn =
        district != null ? ' $district ಜಿಲ್ಲೆಯಲ್ಲಿ' : '';
    final districtPartEn =
        district != null ? ' in $district' : '';

    final buf = StringBuffer();

    if (language == 'en') {
      buf.write('Found $count $skillEn$districtPartEn. ');
      for (int i = 0; i < candidates.length; i++) {
        final w = candidates[i];
        final ord = _ordinalEn(i + 1);
        final dist = w.roadDurationDisplay != null
            ? '${w.distanceDisplay}, ${w.roadDurationDisplay} by road'
            : w.distanceDisplay;
        buf.write('$ord — ${w.name}, $dist away, '
            'rated ${w.rating.toStringAsFixed(1)} stars');
        if (w.completedJobs > 0) buf.write(', ${w.completedJobs} jobs done');
        buf.write('. ');
      }
      buf.write('Which one? Say one, two, or three.');
    } else {
      // Kannada (default)
      buf.write('$count $skillKn$districtPartKn ಸಿಕ್ಕಿದ್ದಾರೆ. ');
      for (int i = 0; i < candidates.length; i++) {
        final w = candidates[i];
        final ord = _ordinalKn(i + 1);
        final dist = w.roadDurationDisplay != null
            ? '${w.distanceDisplay}, ${w.roadDurationDisplay} ರಸ್ತೆಯಲ್ಲಿ'
            : w.distanceDisplay;
        buf.write('$ord — ${w.name}, $dist ದೂರ, '
            '${w.rating.toStringAsFixed(1)} ಸ್ಟಾರ್');
        if (w.completedJobs > 0) {
          buf.write(', ${w.completedJobs} ಕೆಲಸ ಮಾಡಿದ್ದಾರೆ');
        }
        buf.write('. ');
      }
      buf.write('ಯಾರನ್ನು ಆಯ್ಕೆ ಮಾಡಬೇಕು? ಒಂದು, ಎರಡು ಅಥವಾ ಮೂರು ಹೇಳಿ.');
    }

    return buf.toString();
  }

  // ── Worker Selected ───────────────────────────────────────────────────────

  /// Response after user selects a specific worker from the list.
  /// Prompts: "Book or chat?"
  static String buildWorkerSelectedResponse({
    required WorkerCandidate worker,
    required String language,
  }) {
    final dist = worker.roadDurationDisplay != null
        ? '${worker.distanceDisplay} (${worker.roadDurationDisplay})'
        : worker.distanceDisplay;
    final rating = worker.rating.toStringAsFixed(1);
    final skill =
        language == 'en' ? _skillEn(worker.skill) : _skillKn(worker.skill);

    if (language == 'en') {
      return '${worker.name} — $skill, $dist away, rated $rating stars. '
          'Shall I book them, or would you like to chat first?';
    } else {
      return '${worker.name} — $skill, $dist ದೂರ, $rating ಸ್ಟಾರ್. '
          'ಬುಕ್ ಮಾಡಬೇಕೇ ಅಥವಾ ಚಾಟ್ ಮಾಡಬೇಕೇ?';
    }
  }

  // ── Booking ───────────────────────────────────────────────────────────────

  /// Prompt user to confirm before booking
  static String buildBookingConfirmationPrompt({
    required WorkerCandidate worker,
    required String language,
  }) {
    if (language == 'en') {
      return 'Confirm booking ${worker.name} for ${_skillEn(worker.skill)}? '
          'Say yes to confirm or no to cancel.';
    } else {
      return '${worker.name} ಅವರನ್ನು ${_skillKn(worker.skill)} ಕೆಲಸಕ್ಕೆ ಬುಕ್ ಮಾಡಬೇಕೇ? '
          'ಹೌದು ಅಂದ್ರೆ ಖಚಿತ, ಬೇಡ ಅಂದ್ರೆ ರದ್ದು.';
    }
  }

  /// Booking confirmed success
  static String buildBookingConfirmedResponse({
    required WorkerCandidate worker,
    required String bookingId,
    required String language,
  }) {
    if (language == 'en') {
      return 'Booking confirmed with ${worker.name}! '
          'Booking ID: $bookingId. They will be notified.';
    } else {
      return '${worker.name} ಅವರ ಬುಕಿಂಗ್ ಖಚಿತಪಡಿಸಲಾಗಿದೆ! '
          'ಬುಕಿಂಗ್ ಐಡಿ: $bookingId. ಅವರಿಗೆ ತಿಳಿಸಲಾಗುವುದು.';
    }
  }

  /// Booking cancelled
  static String buildBookingCancelledResponse({required String language}) =>
      language == 'en'
          ? 'Booking cancelled.'
          : 'ಬುಕಿಂಗ್ ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ.';

  // ── Chat ──────────────────────────────────────────────────────────────────

  static String buildChatOpenedResponse({
    required WorkerCandidate worker,
    required String language,
  }) =>
      language == 'en'
          ? 'Opening chat with ${worker.name}.'
          : '${worker.name} ಅವರೊಂದಿಗೆ ಚಾಟ್ ತೆರೆಯಲಾಗಿದೆ.';

  // ── Navigation ────────────────────────────────────────────────────────────

  static String buildNavigationResponse({
    required String screenName,
    required String language,
  }) {
    const screens = {
      'settings': ('Opening Settings.', 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಲಾಗಿದೆ.'),
      'home':     ('Going to Home.', 'ಮುಖಪುಟಕ್ಕೆ ಹೋಗಲಾಗುತ್ತಿದೆ.'),
      'profile':  ('Opening your Profile.', 'ನಿಮ್ಮ ಪ್ರೊಫೈಲ್ ತೆರೆಯಲಾಗಿದೆ.'),
      'bookings': ('Opening your Bookings.', 'ನಿಮ್ಮ ಬುಕಿಂಗ್‌ಗಳನ್ನು ತೆರೆಯಲಾಗಿದೆ.'),
      'chat':     ('Opening Chat.', 'ಚಾಟ್ ತೆರೆಯಲಾಗಿದೆ.'),
      'jobs':     ('Opening Jobs list.', 'ಕೆಲಸಗಳ ಪಟ್ಟಿ ತೆರೆಯಲಾಗಿದೆ.'),
      'back':     ('Going back.', 'ಹಿಂದೆ ಹೋಗಲಾಗುತ್ತಿದೆ.'),
    };
    final pair = screens[screenName] ?? ('Done.', 'ಆಯ್ತು.');
    return language == 'en' ? pair.$1 : pair.$2;
  }

  // ── No Workers Found ──────────────────────────────────────────────────────

  static String buildNoWorkersResponse({
    required String skill,
    required String language,
    String? district,
  }) {
    final skillKn = _skillKn(skill);
    final skillEn = _skillEn(skill);
    final isGeneralSearch = skill.isEmpty || skill.toLowerCase() == 'all' || skill.toLowerCase() == 'worker';
    if (language == 'en') {
      return district != null
          ? (isGeneralSearch
              ? 'No workers found in $district. Want to search in a different district?'
              : 'No $skillEn found in $district. Want to search in a different district?')
          : (isGeneralSearch
              ? 'No workers available nearby right now. Try expanding the search area?'
              : 'No $skillEn available nearby right now. Try expanding the search area?');
    } else {
      return district != null
          ? (isGeneralSearch
              ? '$district ಜಿಲ್ಲೆಯಲ್ಲಿ ಯಾವುದೇ ಕೆಲಸಗಾರರು ಸಿಕ್ಕಿಲ್ಲ. ಬೇರೆ ಜಿಲ್ಲೆ ಹುಡುಕಲಾ?'
              : '$district ಜಿಲ್ಲೆಯಲ್ಲಿ $skillKn ಸಿಕ್ಕಿಲ್ಲ. ಬೇರೆ ಜಿಲ್ಲೆ ಹುಡುಕಲಾ?')
          : (isGeneralSearch
              ? 'ಹತ್ತಿರದಲ್ಲಿ ಯಾವುದೇ ಕೆಲಸಗಾರರು ಸಿಕ್ಕಿಲ್ಲ. ಶೋಧನೆ ವ್ಯಾಪ್ತಿ ಹೆಚ್ಚಿಸಲಾ?'
              : 'ಹತ್ತಿರದಲ್ಲಿ $skillKn ಕಾರ್ಮಿಕರು ಸಿಕ್ಕಿಲ್ಲ. ಶೋಧನೆ ವ್ಯಾಪ್ತಿ ಹೆಚ್ಚಿಸಲಾ?');
    }
  }

  // ── Voice Help ────────────────────────────────────────────────────────────

  static String buildHelpResponse({required String language}) {
    if (language == 'en') {
      return 'I can find nearby workers like painters, electricians, or plumbers. '
          'I can book a worker, open chat, check availability, or navigate to any screen. '
          'Examples: "find electrician in Hassan", "book him", "open settings".';
    } else {
      return 'ನಾನು ಹತ್ತಿರದ ಕಾರ್ಮಿಕರನ್ನು ಹುಡುಕಬಲ್ಲೆ, ಉದಾ: ಪೇಂಟರ್, ಕರೆಂಟ್ ಮೇಸ್ತ್ರಿ, ಬಡಗಿ. '
          'ಬುಕ್ ಮಾಡಬಲ್ಲೆ, ಚಾಟ್ ತೆರೆಯಬಲ್ಲೆ, ಲಭ್ಯತೆ ಪರಿಶೀಲಿಸಬಲ್ಲೆ, ಯಾವ ಪರದೆಗೂ ಹೋಗಬಲ್ಲೆ. '
          'ಉದಾ: ಹಾಸನದಲ್ಲಿ ಪೇಂಟರ್ ಬೇಕು, ಬುಕ್ ಮಾಡು, ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ.';
    }
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  static String _ordinalEn(int n) {
    const words = ['', 'One', 'Two', 'Three', 'Four', 'Five'];
    return n < words.length ? words[n] : 'Number $n';
  }

  static String _ordinalKn(int n) {
    const words = ['', 'ಒಂದು', 'ಎರಡು', 'ಮೂರು', 'ನಾಲ್ಕು', 'ಐದು'];
    return n < words.length ? words[n] : 'ನಂಬರ್ $n';
  }

  static String _skillKn(String id) {
    const names = {
      'painter': 'ಪೇಂಟರ್',
      'electrician': 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
      'plumber': 'ಪ್ಲಂಬರ್',
      'carpenter': 'ಬಡಗಿ',
      'mason': 'ಮೇಸ್ತ್ರಿ',
      'cleaner': 'ಕ್ಲೀನರ್',
      'driver': 'ಚಾಲಕ',
      'cook': 'ಅಡುಗೆಯವರು',
      'gardener': 'ತೋಟಗಾರ',
      'mechanic': 'ಮೆಕ್ಯಾನಿಕ್',
      'welder': 'ವೆಲ್ಡರ್',
      'tailor': 'ದರ್ಜಿ',
      'security': 'ಭದ್ರತಾ ಸಿಬ್ಬಂದಿ',
      'helper': 'ಸಹಾಯಕ',
      'agriculture': 'ಕೃಷಿ ಕಾರ್ಮಿಕ',
    };
    return names[id] ?? id;
  }

  static String _skillEn(String id) {
    const names = {
      'painter': 'painter',
      'electrician': 'electrician',
      'plumber': 'plumber',
      'carpenter': 'carpenter',
      'mason': 'mason',
      'cleaner': 'cleaner',
      'driver': 'driver',
      'cook': 'cook',
      'gardener': 'gardener',
      'mechanic': 'mechanic',
      'welder': 'welder',
      'tailor': 'tailor',
      'security': 'security guard',
      'helper': 'helper',
      'agriculture': 'agriculture worker',
    };
    return names[id] ?? id;
  }
}
