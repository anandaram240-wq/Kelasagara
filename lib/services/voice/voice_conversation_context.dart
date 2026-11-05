// lib/services/voice/voice_conversation_context.dart
// Multi-turn conversation context for Kelasagara Voice Command Center
// Maintains state across speech turns: worker list, selected worker,
// pending booking, conversation history, and detected language.

import 'groq_nlu_service.dart';
import 'voice_tool_registry.dart';

class VoiceConversationContext {
  // ── Active State ──────────────────────────────────────────────────────────

  /// Workers from the most recent SEARCH_WORKERS result
  List<WorkerCandidate> activeCandidates = [];

  /// Worker selected from the list (by voice "number one" or tap)
  WorkerCandidate? selectedWorker;

  /// Pending booking args — populated when waiting for confirm/cancel
  Map<String, dynamic>? pendingBookingArgs;

  /// Conversation history for Groq multi-turn NLU (kept to last 10 turns)
  final List<ConversationTurn> history = [];

  /// Last TTS response text — for "repeat" command
  String? lastSpokenResponse;

  /// Detected language from last utterance: 'kn', 'en', 'mixed'
  String detectedLanguage = 'kn';

  /// Unique ID for current candidate result set (stale detection)
  String? resultSetId;

  // ── Accessors ─────────────────────────────────────────────────────────────

  bool get hasCandidates => activeCandidates.isNotEmpty;
  bool get hasSelectedWorker => selectedWorker != null;
  bool get hasPendingBooking => pendingBookingArgs != null;

  /// TTS language code for Sarvam / FlutterTTS
  String get ttsLanguageCode =>
      detectedLanguage == 'en' ? 'en-IN' : 'kn-IN';

  // ── Candidate Management ──────────────────────────────────────────────────

  void setCandidates(List<WorkerCandidate> candidates) {
    activeCandidates = List.of(candidates);
    resultSetId = 'res_${DateTime.now().millisecondsSinceEpoch}';
    // A new search clears the previous selection
    selectedWorker = null;
    pendingBookingArgs = null;
  }

  /// Select worker by 1-based index (from voice: "one", "two", "three")
  bool selectWorkerByIndex(int oneBasedIndex) {
    if (oneBasedIndex >= 1 && oneBasedIndex <= activeCandidates.length) {
      selectedWorker = activeCandidates[oneBasedIndex - 1];
      return true;
    }
    return false;
  }

  /// Select worker by Firestore document ID
  bool selectWorkerById(String workerId) {
    try {
      selectedWorker =
          activeCandidates.firstWhere((w) => w.workerId == workerId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Booking Management ────────────────────────────────────────────────────

  void setPendingBooking(WorkerCandidate worker) {
    selectedWorker = worker;
    pendingBookingArgs = {
      'workerId': worker.workerId,
      'skillId': worker.skill,
      'workerName': worker.name,
    };
  }

  void clearPendingBooking() {
    pendingBookingArgs = null;
  }

  // ── Full Reset ────────────────────────────────────────────────────────────

  void clearAll() {
    activeCandidates = [];
    selectedWorker = null;
    pendingBookingArgs = null;
    history.clear();
    lastSpokenResponse = null;
    resultSetId = null;
  }

  // ── Conversation History ──────────────────────────────────────────────────

  void addUserTurn(String text) {
    history.add(ConversationTurn(role: 'user', content: text));
    _trimHistory();
  }

  void addAssistantTurn(String text) {
    history.add(ConversationTurn(role: 'assistant', content: text));
    lastSpokenResponse = text;
    _trimHistory();
  }

  /// Keep at most 10 turns (5 exchanges) to avoid bloating Groq prompt
  void _trimHistory() {
    if (history.length > 10) {
      history.removeRange(0, history.length - 10);
    }
  }

  // ── Debug ─────────────────────────────────────────────────────────────────

  @override
  String toString() => 'VoiceConversationContext('
      'candidates=${activeCandidates.length}, '
      'selected=${selectedWorker?.name}, '
      'pending=${pendingBookingArgs != null}, '
      'history=${history.length}, '
      'lang=$detectedLanguage)';
}
