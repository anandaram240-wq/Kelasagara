// lib/services/voice/groq_nlu_service.dart
// Groq Llama-3.1-70B Structured Intent Classifier for Kelasagara Voice
// Stage 2 NLU — between FastLocalCommandRouter and Gemini fallback
// Target latency: < 300ms p95

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'voice_api_config.dart';

// ── Intent Types ─────────────────────────────────────────────────────────────
enum VoiceIntentType {
  searchWorkers,
  selectWorker,
  confirmBooking,
  cancelBooking,
  chatWorker,
  callWorker,
  navigateSettings,
  navigateHome,
  navigateProfile,
  navigateBookings,
  navigateChat,
  navigateBack,
  navigateJobs,
  askDistance,
  askAvailability,
  askRating,
  askNearest,
  askDailyRate,
  askJobsDone,
  listApplications,
  voiceHelp,
  unknown,
}

// ── VoiceIntent ───────────────────────────────────────────────────────────────
class VoiceIntent {
  final VoiceIntentType intent;
  final double confidence;
  final String? skill;           // canonical: painter, electrician, etc.
  final String? district;        // Karnataka district name
  final int? workerIndex;        // 1, 2, 3 — from spoken list
  final bool isUrgent;
  final String detectedLanguage; // 'kn', 'en', 'mixed'
  final String rawTranscript;

  const VoiceIntent({
    required this.intent,
    required this.confidence,
    this.skill,
    this.district,
    this.workerIndex,
    this.isUrgent = false,
    this.detectedLanguage = 'kn',
    required this.rawTranscript,
  });

  bool get isNavigationIntent => [
    VoiceIntentType.navigateSettings,
    VoiceIntentType.navigateHome,
    VoiceIntentType.navigateProfile,
    VoiceIntentType.navigateBookings,
    VoiceIntentType.navigateChat,
    VoiceIntentType.navigateBack,
    VoiceIntentType.navigateJobs,
  ].contains(intent);

  String get navScreenName {
    switch (intent) {
      case VoiceIntentType.navigateSettings: return 'settings';
      case VoiceIntentType.navigateHome:     return 'home';
      case VoiceIntentType.navigateProfile:  return 'profile';
      case VoiceIntentType.navigateBookings: return 'bookings';
      case VoiceIntentType.navigateChat:     return 'chat';
      case VoiceIntentType.navigateBack:     return 'back';
      case VoiceIntentType.navigateJobs:     return 'jobs';
      default: return '';
    }
  }

  static VoiceIntent unknownIntent(String transcript) => VoiceIntent(
    intent: VoiceIntentType.unknown,
    confidence: 0.0,
    rawTranscript: transcript,
  );
}

// ── Conversation Turn (for multi-turn NLU context) ────────────────────────────
class ConversationTurn {
  final String role;    // 'user' or 'assistant'
  final String content;
  const ConversationTurn({required this.role, required this.content});
  Map<String, String> toMessage() => {'role': role, 'content': content};
}

// ── GroqNluService ────────────────────────────────────────────────────────────
class GroqNluService {
  static const String _model = 'llama-3.1-70b-versatile';

  // Minimum confidence threshold: below this Gemini takes over
  static const double confidenceThreshold = 0.65;

  static const String _systemPrompt = r'''
You are the voice intent classifier for Kelasagara — a Karnataka, India blue-collar worker hiring app.
Users speak in Kannada (ಕನ್ನಡ), English, Urdu-influenced Kannada, Tulu-mixed Kannada, Marathi-mixed Kannada, or code-mixed.
There are 8 dialect zones across Karnataka — you must understand ALL of them.

YOUR JOB: Extract intent and entities. Return ONLY valid JSON. No explanation. No markdown. No code blocks.

════════════════════════════════════════════════
AVAILABLE INTENTS:
════════════════════════════════════════════════
SEARCH_WORKERS  — find workers for a skill (nearby or in district)
SELECT_WORKER   — pick from list (workerIndex 1–5)
CONFIRM_BOOKING — confirm a pending booking
CANCEL_BOOKING  — cancel a booking
CHAT_WORKER     — open chat with selected worker
CALL_WORKER     — call worker by phone
NAV_SETTINGS    — open settings
NAV_HOME        — go to home/dashboard
NAV_PROFILE     — open profile/account
NAV_BOOKINGS    — open my bookings
NAV_CHAT        — open chat/messages tab
NAV_BACK        — go back
NAV_JOBS        — open jobs list
ASK_DISTANCE    — how far is a specific worker
ASK_AVAILABILITY — is worker available now
ASK_RATING      — worker star rating
ASK_NEAREST     — who is closest
ASK_DAILY_RATE  — worker's daily wage
ASK_JOBS_DONE   — how many jobs worker completed
VOICE_HELP      — what can this voice assistant do
UNKNOWN         — cannot determine

════════════════════════════════════════════════
SKILL CANONICAL IDs — map ALL dialect forms to EXACTLY these:
painter | electrician | plumber | carpenter | mason | cleaner | driver |
cook | gardener | mechanic | welder | tailor | security | helper | agriculture
════════════════════════════════════════════════

── ZONE 1 — Southern Standard (Bengaluru, Mysuru, Mandya) ──
ಪೇಂಟರ್, ಬಣ್ಣ ಹಚ್ಚೋರು, ಬಣ್ಣದ ಆಳು, ಬಣ್ಣದವ್ರು, paint madooru → painter
ಕರೆಂಟ್ ಮೇಸ್ತ್ರಿ, ಎಲೆಕ್ಟ್ರಿಷಿಯನ್, ಕರೆಂಟ್ ಕೆಲಸ, ವೈರ್ ಮ್ಯಾನ್ → electrician
ಪ್ಲಂಬರ್, ಪೈಪ್ ಕೆಲಸ, ನಲ್ಲಿ ರಿಪೇರಿ, ನಲ್ಲಿ ಮ್ಯಾನ್ → plumber
ಬಡಗಿ, ಮರಗೆಲಸ, ಕಾರ್ಪೆಂಟರ್ → carpenter
ಮೇಸ್ತ್ರಿ, ಗಾರೆ ಕೆಲಸ, ಕಟ್ಟಡ ಕೆಲಸ → mason
ಕ್ಲೀನರ್, ಮನೆ ಕೆಲಸ, ಕಸ ಗುಡಿಸೋರು, ಸ್ವಚ್ಛ ಮಾಡೋರು → cleaner
ಡ್ರೈವರ್, ಕಾರ್ ಡ್ರೈವರ್, ಗಾಡಿ ಹೊಡಿಯೋರು → driver
ಅಡಿಗೆ ಮಾಡೋರು, ಅಡಿಗೆ ಮ್ಯಾನ್ → cook
ತೋಟಗಾರ, ಮಾಲಿ, ಹೂದೋಟ ಮ್ಯಾನ್ → gardener
ಮೆಕ್ಯಾನಿಕ್, ಗಾಡಿ ರಿಪೇರಿ → mechanic
ವೆಲ್ಡರ್, ಕಬ್ಬಿಣ ಕೆಲಸ, ವೆಲ್ಡಿಂಗ್ → welder
ದರ್ಜಿ, ಹೊಲಿಗೆ, ಟೈಲರ್ → tailor
ವಾಚ್‌ಮನ್, ಭದ್ರತಾ ಸಿಬ್ಬಂದಿ, ಕಾವಲ್ಗಾರ, guard → security
ಸಹಾಯಕ, ಹೆಲ್ಪರ್, ಕೆಲಸದ ಆಳು → helper
ಕೃಷಿ ಕೆಲಸ, ತೋಟದ ಕೆಲಸ, ಆಳುಗಳು, coffee estate → agriculture

── ZONE 2 — Dharwad / North Karnataka (Dharwad, Haveri, Gadag) ──
ಮಿಸ್ತ್ರಿ (mistri) — same as mason (not to be confused with mestri)
ಮಂದಿ ಬೇಕ್ರಿ, ಮಂದಿ ಬೇಕಾಗ್ಯಾರ → SEARCH_WORKERS: helper
ಬೇಕ್ರಿ = ಬೇಕು (need) — suffix -ri is honorific
ಆಗೈತಿ, agaiti = ಆಗಿದೆ (done/okay) — in booking context = CONFIRM_BOOKING
ಖರೇ, khare = verified/confirmed/real
ರೊಕ್ಕ, rokka = money (in "ರೊಕ್ಕ ಎಷ್ಟು" context → ASK_DAILY_RATE)
ಸಿಗ್ತಾರ್ರಿ, sigtaarri = ಸಿಗುತ್ತಾರೆ (will be found/available)
ಬ್ಯಾಡ, byada = ಬೇಡ (cancel)
ಹೋಗ್ರಿ = ಹೋಗಿ (go) → navigation intent

── ZONE 3 — Kalyana Karnataka URDU-INFLUENCED (Kalaburagi, Bidar, Raichur, Yadgir) ──
CRITICAL: These Urdu/Hindi words ARE Kannada for these users. Map them directly:
mazdoor, mazdur, mazadoor → helper  ⚠️ MOST COMMON LABORER TERM
kaam wala, kaamwala → helper
beldar, bheldar → helper (earthwork laborer)
bijli wala, bijliwala, bejli wala → electrician  ⚠️ CRITICAL
rang wala, rangwala, rang karne wala → painter  ⚠️ CRITICAL
nal mestri, nal mistri → plumber  ⚠️ CRITICAL
raj mistri, raj mistry, rajmistri → mason  ⚠️ CRITICAL
darji, darji wala, silai wala → tailor
chaukidaar, chaukidar, chowkidaar → security  ⚠️ CRITICAL
loha kaam, loha kaam wala → welder
baagban, baaghbaan → gardener
khet kaam, khetiwala → agriculture
bawarchi, khaana banaane wala → cook
thekedar = employer/hirer (not a skill)
haajri = daily attendance/wage (in query context → ASK_DAILY_RATE)
chahiye, chaaiye = ಬೇಕು (need) — always maps to SEARCH_WORKERS intent
haan, hanji = ಹೌದು (yes/confirm) → CONFIRM_BOOKING
nahi = ಬೇಡ (no) → CANCEL_BOOKING
theek hai, thik hai = ಆಯ್ತು (okay/confirm) → CONFIRM_BOOKING
abhi = ಈಗಲೇ (right now) → isUrgent=true

── ZONE 4 — Coastal / Kundagannada (Mangaluru, Udupi — Tulu-influenced) ──
barpira, barpodu → asking if worker will come → ASK_AVAILABILITY
adiga → cook (Tulu word used as Kannada)
badiga → carpenter (Tulu word)
kaavalgar, kaavalgaraa → security
ulleer = ಇದ್ದಾರೆ (are there people)
yaan = ನಾನು (I/me)
bajji = ಬೇಗ (quickly) → isUrgent=true
barpira + skill = ASK_AVAILABILITY for that skill

── ZONE 5 — Malenadu (Hassan, Chikkamagaluru, Shivamogga) ──
aaLu beku, aalu beku, ಆಳು ಬೇಕು → SEARCH_WORKERS: helper or agriculture
thotada aalu, thotada kelasa → agriculture
katavu, adike katavu → agriculture
coffee tota, coffee estate → agriculture
estate kelasa → agriculture

── ZONE 6 — Havyaka (coastal Brahmin communities) ──
toti, ತೊಟಿ = water tap → plumber context
adiga = cook (same as Zone 4)
begane = ಬೇಗ (quickly) → isUrgent=true

── ZONE 7 — Belagavi Border (Kannada + Marathi mix) ──
dagada, dagada wala → mason (stone work)
pahije = ಬೇಕು (need) → SEARCH_WORKERS
nako = ಬೇಡ (don't want) → CANCEL_BOOKING
hoy = ಹೌದು (yes) → CONFIRM_BOOKING
lavkar, lagech = ಬೇಗ (quickly/urgently) → isUrgent=true
beka (without -u ending) = ಬೇಕು → SEARCH_WORKERS

── ZONE 8 — Code-Mixed Urban (Any city) ──
English nouns + Kannada verbs: "electrician beku maadi" → SEARCH_WORKERS: electrician
"painter send maadi" → SEARCH_WORKERS: painter + isUrgent potentially
"1 number select maadi" → SELECT_WORKER: workerIndex=1
"chat tereyi / open maadi" → CHAT_WORKER
"confirm maadi" → CONFIRM_BOOKING
"cancel maadi" → CANCEL_BOOKING

════════════════════════════════════════════════
NUMBER WORDS → workerIndex (ALL dialect forms):
════════════════════════════════════════════════
ಒಂದು / ondu / one / first / 1st / 1 / ond → 1
ಎರಡು / eradu / two / second / 2nd / 2 → 2
ಮೂರು / mooru / three / third / 3rd / 3 → 3
ನಾಲ್ಕು / naLku / naaku / four / fourth / 4 → 4
ಐದು / aidu / five / fifth / 5 → 5
ಆರು / aaru / six / 6 → 6
ಏಳು / yelu / seven / 7 → 7
ಎಂಟು / entu / eight / 8 → 8

════════════════════════════════════════════════
KARNATAKA DISTRICTS (old names → new names):
════════════════════════════════════════════════
Bengaluru/Bangalore → Bengaluru Urban | Mysuru/Mysore | Mangaluru/Mangalore
Hubballi/Hubli → Dharwad | Belagavi/Belgaum | Kalaburagi/Gulbarga
Shivamogga/Shimoga | Tumakuru/Tumkur | Hassan | Davanagere | Ballari/Bellary
Bidar | Raichur | Vijayapura/Bijapur | Chitradurga | Dakshina Kannada/DK
Uttara Kannada | Kodagu/Coorg | Udupi | Chikkamagaluru/Chickmagalur | Kolar
Koppal | Mandya | Ramanagara | Bagalkot | Yadgir | Gadag | Haveri
Chamarajanagar | Chikkaballapur | Bengaluru Rural

HAASAN → Hassan (common misspelling)
HASSAN DISTRICT PAINTER → SEARCH_WORKERS: painter, district: Hassan

════════════════════════════════════════════════
URGENCY WORDS (all zones):
isUrgent=true when: ಅರ್ಜೆಂಟ್ / ತುರ್ತು / ಜಲ್ದಿ / ಬೇಗ / ಈಗಲೇ / urgent / emergency /
                     asap / jaldi / abhi / lavkar / lagech / bajji / ಬಜ್ಜಿ
════════════════════════════════════════════════

OUTPUT FORMAT (strict JSON, nothing else):
{
  "intent": "SEARCH_WORKERS",
  "confidence": 0.95,
  "skill": "painter",
  "district": null,
  "workerIndex": null,
  "isUrgent": false,
  "language": "kn"
}

LANGUAGE DETECTION:
- Only Kannada script → "kn"
- Only English → "en"  
- Urdu/Hindi words with Kannada (Zone 3) → "mixed"
- Any mix → "mixed"
''';

  final Dio _dio;

  GroqNluService()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.groq.com',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Authorization': 'Bearer ${VoiceApiConfig.groqApiKey}',
            'Content-Type': 'application/json',
          },
        ));

  /// Classify user intent from transcript + conversation history.
  /// Returns unknownIntent if Groq fails or confidence is below threshold.
  Future<VoiceIntent> classify({
    required String transcript,
    List<ConversationTurn> history = const [],
  }) async {
    if (transcript.trim().isEmpty) {
      return VoiceIntent.unknownIntent(transcript);
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
    ];

    // Include last 6 turns of history for multi-turn resolution
    // (so "book him" after a worker list understands who "him" is)
    final recentHistory =
        history.length > 6 ? history.sublist(history.length - 6) : history;
    for (final turn in recentHistory) {
      messages.add(turn.toMessage());
    }
    messages.add({'role': 'user', 'content': transcript});

    try {
      final response = await _dio.post(
        '/openai/v1/chat/completions',
        data: {
          'model': _model,
          'messages': messages,
          'temperature': 0.0,
          'max_tokens': 150,
          'response_format': {'type': 'json_object'},
        },
      );

      final content =
          response.data['choices'][0]['message']['content'] as String? ?? '';
      return _parse(content, transcript);
    } on DioException catch (e) {
      debugPrint('[GroqNLU] API error: ${e.type} — ${e.message}');
      return VoiceIntent.unknownIntent(transcript);
    } catch (e) {
      debugPrint('[GroqNLU] Unexpected: $e');
      return VoiceIntent.unknownIntent(transcript);
    }
  }

  VoiceIntent _parse(String json, String transcript) {
    try {
      final Map<String, dynamic> data = jsonDecode(json);
      final intentStr = (data['intent'] as String? ?? 'UNKNOWN').toUpperCase();
      final confidence = (data['confidence'] as num? ?? 0.5).toDouble();
      final skill = data['skill'] as String?;
      final district = data['district'] as String?;
      final workerIndex = (data['workerIndex'] as num?)?.toInt();
      final isUrgent = data['isUrgent'] as bool? ?? false;
      final language = data['language'] as String? ?? 'kn';

      return VoiceIntent(
        intent: _parseType(intentStr),
        confidence: confidence,
        skill: skill,
        district: district,
        workerIndex: workerIndex,
        isUrgent: isUrgent,
        detectedLanguage: language,
        rawTranscript: transcript,
      );
    } catch (e) {
      debugPrint('[GroqNLU] JSON parse error: $e — raw: $json');
      return VoiceIntent.unknownIntent(transcript);
    }
  }

  VoiceIntentType _parseType(String s) {
    switch (s) {
      case 'SEARCH_WORKERS':  return VoiceIntentType.searchWorkers;
      case 'SELECT_WORKER':   return VoiceIntentType.selectWorker;
      case 'CONFIRM_BOOKING': return VoiceIntentType.confirmBooking;
      case 'CANCEL_BOOKING':  return VoiceIntentType.cancelBooking;
      case 'CHAT_WORKER':     return VoiceIntentType.chatWorker;
      case 'CALL_WORKER':     return VoiceIntentType.callWorker;
      case 'NAV_SETTINGS':    return VoiceIntentType.navigateSettings;
      case 'NAV_HOME':        return VoiceIntentType.navigateHome;
      case 'NAV_PROFILE':     return VoiceIntentType.navigateProfile;
      case 'NAV_BOOKINGS':    return VoiceIntentType.navigateBookings;
      case 'NAV_CHAT':        return VoiceIntentType.navigateChat;
      case 'NAV_BACK':        return VoiceIntentType.navigateBack;
      case 'NAV_JOBS':        return VoiceIntentType.navigateJobs;
      case 'ASK_DISTANCE':    return VoiceIntentType.askDistance;
      case 'ASK_AVAILABILITY':return VoiceIntentType.askAvailability;
      case 'ASK_RATING':      return VoiceIntentType.askRating;
      case 'ASK_NEAREST':     return VoiceIntentType.askNearest;
      case 'ASK_DAILY_RATE':  return VoiceIntentType.askDailyRate;
      case 'ASK_JOBS_DONE':   return VoiceIntentType.askJobsDone;
      case 'LIST_APPLICATIONS':
      case 'NAV_APPLICATIONS':return VoiceIntentType.listApplications;
      case 'VOICE_HELP':      return VoiceIntentType.voiceHelp;
      default:                return VoiceIntentType.unknown;
    }
  }
}
