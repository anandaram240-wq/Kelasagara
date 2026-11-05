// lib/services/voice/voice_session_manager.dart
// Production Voice Command Center Orchestrator with Realtime Speculative Execution,
// Fast Local Command Routing, Multi-turn Context, and Natural Barge-In

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/voice_session_state.dart';
import 'fast_local_command_router.dart';
import 'voice_intent_parser.dart';
import 'gemini_live_provider.dart';
import 'groq_nlu_service.dart';
import 'sarvam_speech_provider.dart';
import 'sarvam_tts_provider.dart';
import 'speculative_execution_coordinator.dart';
import 'voice_conversation_context.dart';
import 'voice_provider_router.dart';
import 'voice_response_builder.dart';
import 'voice_settings_service.dart';
import 'voice_tool_registry.dart';

class VoiceLatencyMetrics {
  DateTime? t0MicStart;
  DateTime? t1FirstPartial;
  DateTime? t2FinalTranscript;
  DateTime? t3IntentReady;
  DateTime? t4ToolStart;
  DateTime? t5ToolDone;
  DateTime? t6FirstAudio;
  DateTime? t7Complete;

  int get speechToPartialMs => (t1FirstPartial != null && t0MicStart != null)
      ? t1FirstPartial!.difference(t0MicStart!).inMilliseconds
      : 0;

  int get finalToIntentMs => (t3IntentReady != null && t2FinalTranscript != null)
      ? t3IntentReady!.difference(t2FinalTranscript!).inMilliseconds
      : 0;

  int get toolExecutionMs => (t5ToolDone != null && t4ToolStart != null)
      ? t5ToolDone!.difference(t4ToolStart!).inMilliseconds
      : 0;

  int get resultToAudioMs => (t6FirstAudio != null && t5ToolDone != null)
      ? t6FirstAudio!.difference(t5ToolDone!).inMilliseconds
      : 0;

  int get totalLatencyMs => (t7Complete != null && t0MicStart != null)
      ? t7Complete!.difference(t0MicStart!).inMilliseconds
      : 0;

  Map<String, int> toMap() => {
    'speechToPartialMs': speechToPartialMs,
    'finalToIntentMs': finalToIntentMs,
    'toolExecutionMs': toolExecutionMs,
    'resultToAudioMs': resultToAudioMs,
    'totalLatencyMs': totalLatencyMs,
  };
}

class VoiceSessionManager {
  final VoiceStateMachine stateMachine;
  final SarvamSpeechProvider speechProvider;
  final GeminiLiveProvider geminiProvider;
  final SarvamTTSProvider ttsProvider;
  final VoiceToolRegistry toolRegistry;
  final SpeculativeExecutionCoordinator speculativeCoordinator;
  final VoiceSettingsService settingsService;

  // UI Event Callbacks
  void Function(VoiceSessionState state)? onStateChanged;
  void Function(String transcript, bool isFinal)? onTranscriptUpdate;
  void Function(String responseText)? onResponseUpdate;
  void Function(List<WorkerCandidate> candidates)? onCandidatesFound;
  void Function(List<Map<String, dynamic>> applications)? onApplicationsFound;
  void Function(WorkerCandidate worker)? onWorkerSelected;
  void Function(Map<String, dynamic> confirmationDetails)? onConfirmationRequested;
  void Function(String screenName)? onNavigate;
  void Function(String directAction, Map<String, dynamic> args)? onDirectAction;
  void Function(WorkerCandidate worker)? onNavigateToWorker;
  void Function(WorkerCandidate worker)? onOpenBookingForm;
  void Function(VoiceLatencyMetrics metrics)? onMetricsUpdated;
  void Function(VoiceSearchCommand command)? onCommandParsed;

  // Active Multi-Turn Context
  String? currentResultSetId;
  List<WorkerCandidate> activeCandidates = [];
  WorkerCandidate? selectedWorker;
  Map<String, dynamic>? pendingBooking;
  String _currentLanguage = 'kn-IN';

  // Continuous Discovery & Pagination
  bool hasMoreCandidates = false;
  Object? lastDiscoveryCursor;
  String? lastDiscoveryTool;
  Map<String, dynamic>? lastDiscoveryArgs;
  bool isLoadingMore = false;

  // Concurrency & Stale Protection
  int _commandGeneration = 0;
  final VoiceLatencyMetrics metrics = VoiceLatencyMetrics();

  // ── Groq NLU + Multi-Turn Context (Phase 1 upgrade) ──────────────────────
  final GroqNluService _groqNlu = GroqNluService();
  final VoiceConversationContext _voiceContext = VoiceConversationContext();

  VoiceSessionManager({
    VoiceToolRegistry? registry,
    SarvamSpeechProvider? speech,
    GeminiLiveProvider? gemini,
    SarvamTTSProvider? tts,
    SpeculativeExecutionCoordinator? speculative,
    VoiceSettingsService? settings,
  })  : toolRegistry = registry ?? VoiceToolRegistry(),
        speechProvider = speech ?? SarvamSpeechProvider(),
        geminiProvider = gemini ?? GeminiLiveProvider(),
        ttsProvider = tts ?? SarvamTTSProvider(),
        speculativeCoordinator = speculative ?? SpeculativeExecutionCoordinator(registry: registry ?? VoiceToolRegistry()),
        settingsService = settings ?? VoiceSettingsService.instance,
        stateMachine = VoiceStateMachine() {
    stateMachine.transition(VoiceSessionState.idle);
  }

  VoiceSessionState get currentState => stateMachine.current;

  Future<void> initialize() async {
    await settingsService.init();
    await speechProvider.initialize();
    await ttsProvider.initialize();
  }

  /// Start Listening with Low-Latency Streaming
  Future<void> startListening() async {
    if (!settingsService.isEnabled) {
      debugPrint('[VoiceSessionManager] Voice Command Center is disabled in settings.');
      return;
    }

    if (stateMachine.current == VoiceSessionState.speaking) {
      await interrupt();
    }

    _commandGeneration++;
    final currentGen = _commandGeneration;
    speculativeCoordinator.newUtterance();

    metrics.t0MicStart = DateTime.now();
    metrics.t1FirstPartial = null;
    metrics.t2FinalTranscript = null;
    metrics.t3IntentReady = null;
    metrics.t4ToolStart = null;
    metrics.t5ToolDone = null;
    metrics.t6FirstAudio = null;
    metrics.t7Complete = null;

    if (!stateMachine.transition(VoiceSessionState.listening)) {
      stateMachine.force(VoiceSessionState.listening);
    }
    onStateChanged?.call(stateMachine.current);

    // Apply configured language preference
    final langPref = settingsService.language;
    final locale = switch (langPref) {
      VoiceLanguagePreference.kannada => 'kn_IN',
      VoiceLanguagePreference.english => 'en_IN',
      _                               => 'kn_IN', // auto starts with kn_IN multi-locale
    };

    await speechProvider.startListening(
      locale: locale,
      onResult: (transcript, isFinal) {
        if (currentGen != _commandGeneration) return; // Stale audio frame

        if (stateMachine.current == VoiceSessionState.listening) {
          stateMachine.transition(VoiceSessionState.userSpeaking);
          onStateChanged?.call(stateMachine.current);
        }

        if (!isFinal && metrics.t1FirstPartial == null && transcript.trim().isNotEmpty) {
          metrics.t1FirstPartial = DateTime.now();
          onMetricsUpdated?.call(metrics);
        }

        onTranscriptUpdate?.call(transcript, isFinal);

        // SPEED CRITICAL PATH: Safe Speculative Pre-Search on partial transcript
        if (!isFinal && transcript.trim().length >= 3) {
          speculativeCoordinator.onPartialTranscript(transcript);
        }

        // Final validated transcript processing
        if (isFinal && transcript.trim().isNotEmpty) {
          metrics.t2FinalTranscript = DateTime.now();
          _processUserInput(transcript, currentGen);
        }
      },
      onComplete: () {
        if (currentGen != _commandGeneration) return;
        if (stateMachine.current == VoiceSessionState.userSpeaking) {
          stateMachine.transition(VoiceSessionState.transcribing);
          onStateChanged?.call(stateMachine.current);
        }
      },
      onError: (err) {
        if (currentGen != _commandGeneration) return;
        debugPrint('[VoiceSessionManager] STT Error: $err');
        stateMachine.transition(VoiceSessionState.error);
        onStateChanged?.call(stateMachine.current);
      },
    );
  }

  /// Stop Listening
  Future<void> stopListening() async {
    await speechProvider.stopListening();
    if (stateMachine.current == VoiceSessionState.listening ||
        stateMachine.current == VoiceSessionState.userSpeaking) {
      stateMachine.transition(VoiceSessionState.idle);
      onStateChanged?.call(stateMachine.current);
    }
  }

  /// Natural Barge-in / Interruption
  Future<void> interrupt() async {
    debugPrint('[VoiceSessionManager] ⚡ Barge-in: interrupting audio immediately');
    _commandGeneration++;
    speculativeCoordinator.cancel();

    await ttsProvider.stop();
    stateMachine.transition(VoiceSessionState.interrupted);
    onStateChanged?.call(stateMachine.current);

    // Reset to listening immediately for follow-up speech
    stateMachine.transition(VoiceSessionState.listening);
    onStateChanged?.call(stateMachine.current);
  }

  /// Public entry point to process a simulated or typed text utterance
  Future<void> processTextUtterance(String text) async {
    _commandGeneration++;
    final currentGen = _commandGeneration;
    onTranscriptUpdate?.call(text, true);
    await _processUserInput(text, currentGen);
  }

  /// Process Transcribed Input
  Future<void> _processUserInput(String text, int generation) async {
    if (generation != _commandGeneration) return;

    // Reset pagination cursor on new query
    hasMoreCandidates = false;
    lastDiscoveryCursor = null;

    stateMachine.transition(VoiceSessionState.understanding);
    onStateChanged?.call(stateMachine.current);

    // 1. Language determination (Settings preference takes precedence if fixed)
    final detected = VoiceProviderRouter.detectLanguage(text);
    if (settingsService.language == VoiceLanguagePreference.kannada) {
      _currentLanguage = 'kn-IN';
    } else if (settingsService.language == VoiceLanguagePreference.english) {
      _currentLanguage = 'en-IN';
    } else {
      _currentLanguage = VoiceProviderRouter.getTtsLanguageCode(detected);
    }

    // 2. Security Guard: Password Disclosure Prevention
    final tLower = text.toLowerCase();
    if (tLower.contains('password') || tLower.contains('ಪಾಸ್ವರ್ಡ್') || tLower.contains('ಪಾಸ್‌ವರ್ಡ್')) {
      final reply = _currentLanguage.contains('en')
          ? "For security, I can't display your password. You can reset it from Account Security."
          : "ಭದ್ರತೆಯ ಕಾರಣದಿಂದ, ನಾನು ನಿಮ್ಮ ಪಾಸ್‌ವರ್ಡ್ ಅನ್ನು ಪ್ರದರ್ಶಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ. ನೀವು ಖಾತೆ ಭದ್ರತೆಯಿಂದ ಅದನ್ನು ಮರುಹೊಂದಿಸಬಹುದು.";
      await _respondAndSpeak(reply, generation);
      return;
    }

    // 3. FAST LOCAL COMMAND ROUTER (Zero-LLM deterministic path)
    final localRoute = FastLocalCommandRouter.tryRoute(
      utterance: text,
      activeCandidates: activeCandidates,
      pendingBooking: pendingBooking,
    );

    metrics.t3IntentReady = DateTime.now();

    if (localRoute.parsedCommand != null) {
      onCommandParsed?.call(localRoute.parsedCommand!);
    }

    if (localRoute.isHandled) {
      debugPrint('[VoiceSessionManager] 🚀 Handled via Fast Local Router: ${localRoute.toolName}');
      await _handleLocalRoute(localRoute, generation);
      return;
    }

    // 4. Check for speculative match before invoking Gemini
    final specSkill = speculativeCoordinator.activeResult?.skillId;
    if (specSkill != null && _isSearchQuery(text)) {
      final specResult = await speculativeCoordinator.claimSpeculativeResult(specSkill);
      if (specResult != null && specResult['success'] == true) {
        debugPrint('[VoiceSessionManager] ⚡ Reusing speculative result for $specSkill!');
        await _applyCandidateResult(specResult, generation);
        return;
      }
    }

    // 5. GROQ NLU — Structured intent extraction (Stage 2, < 300ms target)
    debugPrint('[VoiceSessionManager] 🤖 Dispatching to Groq NLU: "$text"');
    _voiceContext.addUserTurn(text);
    _voiceContext.detectedLanguage = _currentLanguage.contains('en') ? 'en' : 'kn';

    final groqIntent = await _groqNlu.classify(
      transcript: text,
      history: _voiceContext.history,
    );
    if (generation != _commandGeneration) return;

    metrics.t3IntentReady = DateTime.now();

    // If Groq is confident (≥ 0.65), handle intent directly without Gemini
    if (groqIntent.confidence >= GroqNluService.confidenceThreshold &&
        groqIntent.intent != VoiceIntentType.unknown) {
      debugPrint('[VoiceSessionManager] ✅ Groq confident (${groqIntent.confidence.toStringAsFixed(2)}): ${groqIntent.intent.name}');
      await _handleGroqIntent(groqIntent, generation);
      return;
    }

    // 6. Fallback: Gemini Conversational Engine (low confidence / ambiguous)
    debugPrint('[VoiceSessionManager] 🔄 Groq confidence ${groqIntent.confidence.toStringAsFixed(2)} < threshold, falling back to Gemini.');
    final response = await geminiProvider.processUtterance(prompt: text);
    if (generation != _commandGeneration) return;

    if (response.functionCall != null) {
      final fc = response.functionCall!;
      stateMachine.transition(VoiceSessionState.toolRequested);
      onStateChanged?.call(stateMachine.current);
      stateMachine.transition(VoiceSessionState.toolValidating);
      onStateChanged?.call(stateMachine.current);

      if (fc.name == 'createBooking' && settingsService.requireBookingConfirmation) {
        pendingBooking = fc.arguments;
        stateMachine.transition(VoiceSessionState.waitingConfirmation);
        onStateChanged?.call(stateMachine.current);
        onConfirmationRequested?.call(fc.arguments);
        final promptMsg = _currentLanguage.contains('en')
            ? 'Shall I confirm this booking?'
            : 'ಈ ಬುಕಿಂಗ್ ಅನ್ನು ಖಚಿತಪಡಿಸಬೇಕೇ?';
        await _respondAndSpeak(promptMsg, generation);
        return;
      }
      await _executeToolCall(fc.name, fc.arguments, generation);
    } else {
      final directText = response.textResponse ?? '';
      await _respondAndSpeak(directText, generation);
    }
  }

  /// Handle a classified Groq intent end-to-end
  Future<void> _handleGroqIntent(VoiceIntent intent, int generation) async {
    if (generation != _commandGeneration) return;
    final lang = _voiceContext.detectedLanguage;

    switch (intent.intent) {
      // ── Worker Search ──────────────────────────────────────────────────────
      case VoiceIntentType.searchWorkers:
        final skill = intent.skill ?? 'helper';
        stateMachine.transition(VoiceSessionState.executing);
        onStateChanged?.call(stateMachine.current);
        metrics.t4ToolStart = DateTime.now();

        final toolName = intent.district != null
            ? 'searchWorkersByDistrict'
            : 'searchWorkersNearby';
        final toolArgs = <String, dynamic>{
          'skillId': skill,
          if (intent.district != null) 'district': intent.district,
        };

        final result = await toolRegistry.executeTool(
          toolName: toolName,
          arguments: toolArgs,
          onNavigate: onNavigate,
        );
        metrics.t5ToolDone = DateTime.now();
        if (generation != _commandGeneration) return;

        if (result['success'] == true &&
            (result['candidates'] as List? ?? []).isNotEmpty) {
          await _applyCandidateResult(result, generation);
          // Override generic speech with full bilingual list announcement
          if (activeCandidates.isNotEmpty) {
            final speech = VoiceResponseBuilder.buildWorkerListResponse(
              candidates: activeCandidates,
              skill: skill,
              language: lang,
              district: intent.district,
            );
            await _respondAndSpeak(speech, generation);
            _voiceContext.addAssistantTurn(speech);
          }
        } else {
          final speech = VoiceResponseBuilder.buildNoWorkersResponse(
            skill: skill,
            language: lang,
            district: intent.district,
          );
          await _respondAndSpeak(speech, generation);
          _voiceContext.addAssistantTurn(speech);
        }
        break;

      // ── Worker Selection ───────────────────────────────────────────────────
      case VoiceIntentType.selectWorker:
        final idx = intent.workerIndex ?? 1;
        if (activeCandidates.isNotEmpty && idx <= activeCandidates.length) {
          _voiceContext.selectWorkerByIndex(idx);
          selectedWorker = _voiceContext.selectedWorker;
          if (selectedWorker != null) {
            onWorkerSelected?.call(selectedWorker!);
            final speech = VoiceResponseBuilder.buildWorkerSelectedResponse(
              worker: selectedWorker!,
              language: lang,
            );
            await _respondAndSpeak(speech, generation);
            _voiceContext.addAssistantTurn(speech);
          }
        } else {
          final msg = lang == 'en'
              ? 'Please search for workers first, then select by saying one, two, or three.'
              : 'ಮೊದಲು ಕಾರ್ಮಿಕರನ್ನು ಹುಡುಕಿ, ನಂತರ ಒಂದು, ಎರಡು ಅಥವಾ ಮೂರು ಹೇಳಿ.';
          await _respondAndSpeak(msg, generation);
        }
        break;

      // ── Booking Confirmation / Cancellation ────────────────────────────────
      case VoiceIntentType.confirmBooking:
        await executeConfirmedBooking(generation);
        break;

      case VoiceIntentType.cancelBooking:
        await cancelPendingBooking(generation);
        break;

      // ── Chat with Worker ───────────────────────────────────────────────────
      case VoiceIntentType.chatWorker:
        final worker = selectedWorker ?? _voiceContext.selectedWorker;
        if (worker != null) {
          stateMachine.transition(VoiceSessionState.executing);
          onStateChanged?.call(stateMachine.current);
          final chatResult = await toolRegistry.executeTool(
            toolName: 'initiateChatConversation',
            arguments: {'workerId': worker.workerId, 'workerName': worker.name},
          );
          if (generation != _commandGeneration) return;
          final convId = chatResult['conversationId'] as String?;
          if (convId != null) {
            onNavigate?.call('chat/$convId');
          } else {
            onNavigate?.call('chat');
          }
          final speech = VoiceResponseBuilder.buildChatOpenedResponse(
            worker: worker,
            language: lang,
          );
          await _respondAndSpeak(speech, generation);
          _voiceContext.addAssistantTurn(speech);
        } else {
          final msg = lang == 'en'
              ? 'Please select a worker first before opening chat.'
              : 'ಚಾಟ್ ತೆರೆಯಲು ಮೊದಲು ಒಬ್ಬ ಕಾರ್ಮಿಕರನ್ನು ಆಯ್ಕೆ ಮಾಡಿ.';
          await _respondAndSpeak(msg, generation);
        }
        break;

      // ── Navigation ─────────────────────────────────────────────────────────
      case VoiceIntentType.navigateSettings:
      case VoiceIntentType.navigateHome:
      case VoiceIntentType.navigateProfile:
      case VoiceIntentType.navigateBookings:
      case VoiceIntentType.navigateChat:
      case VoiceIntentType.navigateBack:
      case VoiceIntentType.navigateJobs:
        final screen = intent.navScreenName;
        onNavigate?.call(screen);
        onDirectAction?.call('NAV_${screen.toUpperCase()}', {});
        final navSpeech = VoiceResponseBuilder.buildNavigationResponse(
          screenName: screen,
          language: lang,
        );
        await _respondAndSpeak(navSpeech, generation);
        _voiceContext.addAssistantTurn(navSpeech);
        break;

      // ── List Applications ──────────────────────────────────────────────────
      case VoiceIntentType.listApplications:
        stateMachine.transition(VoiceSessionState.executing);
        onStateChanged?.call(stateMachine.current);
        metrics.t4ToolStart = DateTime.now();

        final result = await toolRegistry.executeTool(
          toolName: 'listMyApplications',
          arguments: {},
          onNavigate: onNavigate,
        );
        metrics.t5ToolDone = DateTime.now();
        if (generation != _commandGeneration) return;

        if (result['success'] == true) {
          final rawApps = (result['applications'] as List? ?? []);
          final apps = rawApps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          onApplicationsFound?.call(apps);
          final speech = lang == 'en'
              ? (result['speechResponseEn'] as String? ?? 'Here are your applications.')
              : (result['speechResponseKn'] as String? ?? 'ಇಲ್ಲಿ ನಿಮ್ಮ ಅರ್ಜಿಗಳಿವೆ.');
          await _respondAndSpeak(speech, generation);
          _voiceContext.addAssistantTurn(speech);
        } else {
          final err = result['error'] as String? ?? 'Could not load applications';
          await _respondAndSpeak(err, generation);
        }
        break;

      // ── Voice Help ─────────────────────────────────────────────────────────
      case VoiceIntentType.voiceHelp:
        final helpSpeech = VoiceResponseBuilder.buildHelpResponse(language: lang);
        await _respondAndSpeak(helpSpeech, generation);
        _voiceContext.addAssistantTurn(helpSpeech);
        break;

      // ── Worker Query Intents ────────────────────────────────────────────────
      case VoiceIntentType.askDistance:
      case VoiceIntentType.askAvailability:
      case VoiceIntentType.askRating:
      case VoiceIntentType.askNearest:
      case VoiceIntentType.askDailyRate:
      case VoiceIntentType.askJobsDone:
        final queryWorker = _resolveQueryWorker(intent);
        if (queryWorker != null) {
          final msg = _buildQueryResponse(intent.intent, queryWorker, lang);
          await _respondAndSpeak(msg, generation);
          _voiceContext.addAssistantTurn(msg);
        } else {
          final msg = lang == 'en'
              ? 'Search for workers first, then ask about them.'
              : 'ಮೊದಲು ಕಾರ್ಮಿಕರನ್ನು ಹುಡುಕಿ, ನಂತರ ಅವರ ಬಗ್ಗೆ ಕೇಳಿ.';
          await _respondAndSpeak(msg, generation);
        }
        break;

      // ── Unknown / Low-confidence → Gemini fallback ─────────────────────────
      case VoiceIntentType.unknown:
      default:
        final response =
            await geminiProvider.processUtterance(prompt: intent.rawTranscript);
        if (generation != _commandGeneration) return;
        final directText = response.textResponse ?? '';
        await _respondAndSpeak(
          directText.isNotEmpty
              ? directText
              : (lang == 'en'
                  ? 'I did not understand. Try: find painter nearby.'
                  : 'ಅರ್ಥವಾಗಲಿಲ್ಲ. ಉದಾ: ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು ಎಂದು ಹೇಳಿ.'),
          generation,
        );
        break;
    }
  }

  /// Resolve which worker to answer a query about
  WorkerCandidate? _resolveQueryWorker(VoiceIntent intent) {
    if (intent.workerIndex != null && activeCandidates.isNotEmpty) {
      final idx = (intent.workerIndex! - 1).clamp(0, activeCandidates.length - 1);
      return activeCandidates[idx];
    }
    return selectedWorker ??
        _voiceContext.selectedWorker ??
        (activeCandidates.isNotEmpty ? activeCandidates.first : null);
  }

  /// Build follow-up query response (distance, rating, availability, etc.)
  String _buildQueryResponse(
      VoiceIntentType q, WorkerCandidate w, String lang) {
    switch (q) {
      case VoiceIntentType.askDistance:
        return lang == 'en'
            ? '${w.name} is ${w.distanceDisplay} away.'
            : '${w.name} ಅವರು ${w.distanceDisplay} ದೂರದಲ್ಲಿದ್ದಾರೆ.';
      case VoiceIntentType.askAvailability:
        return lang == 'en'
            ? '${w.name} is ${w.isAvailable ? "available now" : "currently busy"}.'
            : '${w.name} ಅವರು ${w.isAvailable ? "ಈಗ ಲಭ್ಯ ಇದ್ದಾರೆ" : "ಪ್ರಸ್ತುತ ಕೆಲಸದಲ್ಲಿದ್ದಾರೆ"}.';
      case VoiceIntentType.askRating:
        return lang == 'en'
            ? '${w.name} is rated ${w.rating.toStringAsFixed(1)} out of 5 stars.'
            : '${w.name} ಅವರ ರೇಟಿಂಗ್ ${w.rating.toStringAsFixed(1)} ಸ್ಟಾರ್ ಆಗಿದೆ.';
      case VoiceIntentType.askNearest:
        return lang == 'en'
            ? '${w.name} is the closest, at ${w.distanceDisplay}.'
            : '${w.name} ಅತ್ಯಂತ ಹತ್ತಿರ, ${w.distanceDisplay} ದೂರ.';
      case VoiceIntentType.askJobsDone:
        return lang == 'en'
            ? '${w.name} has completed ${w.completedJobs} jobs.'
            : '${w.name} ಅವರು ${w.completedJobs} ಕೆಲಸ ಮಾಡಿದ್ದಾರೆ.';
      default:
        return lang == 'en'
            ? 'Information not available.'
            : 'ಮಾಹಿತಿ ಲಭ್ಯವಿಲ್ಲ.';
    }
  }

  /// Handle Fast Local Command Router Result
  Future<void> _handleLocalRoute(LocalRouteResult route, int generation) async {
    if (generation != _commandGeneration) return;

    if (route.directAction != null) {
      onDirectAction?.call(route.directAction!, route.arguments);

      if (route.directAction == 'NAVIGATE_WORKER') {
        final workerId = route.arguments['workerId'] as String?;
        final worker = activeCandidates.where((w) => w.workerId == workerId).firstOrNull;
        if (worker != null) {
          onNavigateToWorker?.call(worker);
        }
      }
    }

    if (route.toolName == 'confirmBooking') {
      await executeConfirmedBooking(generation);
      return;
    }

    if (route.toolName == 'cancelBooking') {
      await cancelPendingBooking(generation);
      return;
    }

    if (route.toolName == 'openBookingForm' || route.directAction == 'OPEN_BOOKING_FORM') {
      final workerId = route.arguments['workerId'] as String?;
      final worker = activeCandidates.where((w) => w.workerId == workerId).firstOrNull ?? selectedWorker;
      if (worker != null) {
        selectedWorker = worker;
        onOpenBookingForm?.call(worker);
      }
      final speech = _currentLanguage.contains('en')
          ? (route.speechResponseEn ?? 'Opening booking form for ${worker?.name ?? 'worker'}. Please confirm job details.')
          : (route.speechResponseKn ?? '${worker?.name ?? 'ಕಾರ್ಮಿಕರ'} ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.');
      await _respondAndSpeak(speech, generation);
      return;
    }

    if (route.toolName == 'selectWorker') {
      final workerId = route.arguments['workerId'] as String?;
      final worker = activeCandidates.where((w) => w.workerId == workerId).firstOrNull;
      if (worker != null) {
        selectedWorker = worker;
        onWorkerSelected?.call(worker);
      }
    }

    // ── Execute Clarification Prompt ──────────────────────────────────────
    if (route.toolName == 'clarificationPrompt') {
      final msg = _currentLanguage.contains('en')
          ? (route.speechResponseEn ?? 'Could you please clarify your request?')
          : (route.speechResponseKn ?? 'ದಯವಿಟ್ಟು ನಿಮ್ಮ ವಿನಂತಿಯನ್ನು ಸ್ಪಷ್ಟಪಡಿಸಿ.');
      await _respondAndSpeak(msg, generation);
      return;
    }

    // ── Execute Real District Worker Search via Local Router ──────────────
    if (route.toolName == 'searchWorkersByDistrict') {
      final skill = route.arguments['skillId'] as String? ?? 'helper';
      final district = route.arguments['district'] as String? ?? '';
      lastDiscoveryTool = 'searchWorkersByDistrict';
      lastDiscoveryArgs = Map<String, dynamic>.from(route.arguments);
      stateMachine.transition(VoiceSessionState.executing);
      onStateChanged?.call(stateMachine.current);
      metrics.t4ToolStart = DateTime.now();

      final result = await toolRegistry.executeTool(
        toolName: 'searchWorkersByDistrict',
        arguments: route.arguments,
        onNavigate: onNavigate,
      );
      metrics.t5ToolDone = DateTime.now();
      if (generation != _commandGeneration) return;

      if (result['success'] == true &&
          (result['candidates'] as List? ?? []).isNotEmpty) {
        await _applyCandidateResult(result, generation);
        final lang = _currentLanguage.contains('en') ? 'en' : 'kn';
        final speech = VoiceResponseBuilder.buildWorkerListResponse(
          candidates: activeCandidates,
          skill: skill,
          language: lang,
          district: district,
        );
        await _respondAndSpeak(speech, generation);
      } else {
        final speech = VoiceResponseBuilder.buildNoWorkersResponse(
          skill: skill,
          language: _currentLanguage.contains('en') ? 'en' : 'kn',
          district: district,
        );
        await _respondAndSpeak(speech, generation);
      }
      return;
    }

    // ── Execute Real Nearby Worker Search via Local Router ────────────────
    if (route.toolName == 'searchWorkersNearby') {
      final skill = route.arguments['skillId'] as String? ?? 'helper';
      lastDiscoveryTool = 'searchWorkersNearby';
      lastDiscoveryArgs = Map<String, dynamic>.from(route.arguments);
      stateMachine.transition(VoiceSessionState.executing);
      onStateChanged?.call(stateMachine.current);
      metrics.t4ToolStart = DateTime.now();

      final result = await toolRegistry.executeTool(
        toolName: 'searchWorkersNearby',
        arguments: route.arguments,
        onNavigate: onNavigate,
      );
      metrics.t5ToolDone = DateTime.now();
      if (generation != _commandGeneration) return;

      if (result['success'] == true &&
          (result['candidates'] as List? ?? []).isNotEmpty) {
        await _applyCandidateResult(result, generation);
        final lang = _currentLanguage.contains('en') ? 'en' : 'kn';
        final speech = VoiceResponseBuilder.buildWorkerListResponse(
          candidates: activeCandidates,
          skill: skill,
          language: lang,
        );
        await _respondAndSpeak(speech, generation);
      } else {
        final rawErr = result['error'] as String?;
        final isTechnicalError = rawErr != null && (rawErr.contains('console.firebase') || rawErr.contains('requires an index'));
        final cleanErr = isTechnicalError
            ? (_currentLanguage.contains('en')
                ? 'Worker search is temporarily unavailable. Please try again.'
                : 'ಕೆಲಸಗಾರರ ಹುಡುಕಾಟ ತಾತ್ಕಾಲಿಕವಾಗಿ ಲಭ್ಯವಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.')
            : rawErr;
        final msg = _currentLanguage.contains('en')
            ? (cleanErr != null ? 'Note: $cleanErr' : 'No available ${skill}s found nearby right now.')
            : (cleanErr != null ? 'ಮಾಹಿತಿ: $cleanErr' : 'ನಿಮ್ಮ ಹತ್ತಿರ ಯಾವುದೇ $skill ಸದ್ಯಕ್ಕೆ ಲಭ್ಯವಿಲ್ಲ.');
        await _respondAndSpeak(msg, generation);
      }
      return;
    }

    // ── Execute Book Nearby Worker (now search + prompt selection) ───────────
    if (route.toolName == 'bookNearbyWorker') {
      final skill = route.arguments['skillId'] as String? ?? 'worker';
      stateMachine.transition(VoiceSessionState.executing);
      onStateChanged?.call(stateMachine.current);
      metrics.t4ToolStart = DateTime.now();

      final result = await toolRegistry.executeTool(
        toolName: 'bookNearbyWorker',
        arguments: route.arguments,
        onNavigate: onNavigate,
      );
      metrics.t5ToolDone = DateTime.now();
      if (generation != _commandGeneration) return;

      final lang = _currentLanguage.contains('en') ? 'en' : 'kn';
      if (result['success'] == true && (result['candidates'] as List? ?? []).isNotEmpty) {
        await _applyCandidateResult(result, generation);
        final speech = lang == 'en'
            ? 'Found ${activeCandidates.length} nearby $skill workers. Say "Book worker 1" or select a worker to enter job details.'
            : 'ಹತ್ತಿರದ ${activeCandidates.length} $skill ಕಾರ್ಮಿಕರು ಸಿಕ್ಕಿದ್ದಾರೆ. ಬುಕ್ ಮಾಡಲು ಕಾರ್ಮಿಕರನ್ನು ಆಯ್ಕೆಮಾಡಿ.';
        await _respondAndSpeak(speech, generation);
      } else if (result['success'] == true && result['bookingId'] != null) {
        final workerName = result['workerName'] as String? ?? 'Worker';
        final dist = result['distanceDisplay'] as String? ?? '';
        final bookingId = result['bookingId'] as String? ?? '';
        final speech = lang == 'en'
            ? 'Booking confirmed! $workerName${dist.isNotEmpty ? ", $dist away," : ""} '
              'has been booked for $skill work. Booking ID: $bookingId'
            : '$workerName${dist.isNotEmpty ? " ($dist)" : ""} ಅವರನ್ನು $skill ಕೆಲಸಕ್ಕೆ ಬುಕ್ ಮಾಡಲಾಗಿದೆ. '
              'ಬುಕಿಂಗ್ ಐಡಿ: $bookingId';
        await _respondAndSpeak(speech, generation);
      } else {
        final err = result['error'] as String? ?? 'Booking failed. Please try again.';
        final speech = lang == 'en' ? err : 'ಬುಕಿಂಗ್ ವಿಫಲವಾಯಿತು: $err';
        await _respondAndSpeak(speech, generation);
      }
      return;
    }

    // ── Execute List My Applications via Local Router ─────────────────────
    if (route.toolName == 'listMyApplications') {
      stateMachine.transition(VoiceSessionState.executing);
      onStateChanged?.call(stateMachine.current);
      metrics.t4ToolStart = DateTime.now();

      final result = await toolRegistry.executeTool(
        toolName: 'listMyApplications',
        arguments: route.arguments,
        onNavigate: onNavigate,
      );
      metrics.t5ToolDone = DateTime.now();
      if (generation != _commandGeneration) return;

      if (result['success'] == true) {
        final rawApps = (result['applications'] as List? ?? []);
        final apps = rawApps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        onApplicationsFound?.call(apps);
        final lang = _currentLanguage.contains('en') ? 'en' : 'kn';
        final speech = lang == 'en'
            ? (result['speechResponseEn'] as String? ?? 'Here are your applications.')
            : (result['speechResponseKn'] as String? ?? 'ಇಲ್ಲಿ ನಿಮ್ಮ ಅರ್ಜಿಗಳಿವೆ.');
        await _respondAndSpeak(speech, generation);
      } else {
        final err = result['error'] as String? ?? 'Failed to load applications';
        await _respondAndSpeak(err, generation);
      }
      return;
    }

    final speech = _currentLanguage.contains('en')
        ? (route.speechResponseEn ?? 'Action completed.')
        : (route.speechResponseKn ?? 'ಕಾರ್ಯ ಪೂರ್ಣಗೊಂಡಿದೆ.');
    await _respondAndSpeak(speech, generation);
  }

  /// Execute Tool Call via Registry
  Future<void> _executeToolCall(String toolName, Map<String, dynamic> arguments, int generation) async {
    if (generation != _commandGeneration) return;

    stateMachine.transition(VoiceSessionState.executing);
    onStateChanged?.call(stateMachine.current);

    metrics.t4ToolStart = DateTime.now();

    final result = await toolRegistry.executeTool(
      toolName: toolName,
      arguments: arguments,
      onNavigate: onNavigate,
    );

    metrics.t5ToolDone = DateTime.now();
    if (generation != _commandGeneration) return;

    if (toolName == 'searchWorkersNearby' || toolName == 'searchWorkersByDistrict') {
      lastDiscoveryTool = toolName;
      lastDiscoveryArgs = Map<String, dynamic>.from(arguments);
    }

    if ((toolName == 'searchWorkersNearby' || toolName == 'searchWorkersByDistrict') &&
        result['candidates'] != null) {
      await _applyCandidateResult(result, generation);
      return;
    }

    if (toolName == 'listMyApplications' && result['applications'] != null) {
      final rawApps = (result['applications'] as List? ?? []);
      final apps = rawApps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      onApplicationsFound?.call(apps);
      final lang = _currentLanguage.contains('en') ? 'en' : 'kn';
      final speech = lang == 'en'
          ? (result['speechResponseEn'] as String? ?? 'Here are your applications.')
          : (result['speechResponseKn'] as String? ?? 'ಇಲ್ಲಿ ನಿಮ್ಮ ಅರ್ಜಿಗಳಿವೆ.');
      await _respondAndSpeak(speech, generation);
      return;
    }

    stateMachine.transition(VoiceSessionState.responding);
    onStateChanged?.call(stateMachine.current);

    final summary = await geminiProvider.summarizeToolResult(
      toolName: toolName,
      toolResult: result,
      userLanguage: _currentLanguage,
    );

    await _respondAndSpeak(summary, generation);
  }

  /// Apply Candidate Result to Multi-turn Context and Speak Results
  Future<void> _applyCandidateResult(Map<String, dynamic> result, int generation) async {
    if (generation != _commandGeneration) return;

    final rawList = result['candidates'] as List? ?? [];
    activeCandidates = rawList.map((m) {
      final map = m as Map<String, dynamic>;
      return WorkerCandidate(
        workerId: map['workerId'] ?? '',
        name: map['name'] ?? 'Worker',
        skill: map['skill'] ?? '',
        distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0.0,
        distanceDisplay: map['distanceDisplay'] ?? '',
        latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
        isAvailable: map['isAvailable'] ?? true,
        verificationLevel: map['verificationLevel'] ?? 'practicalVerified',
        completedJobs: map['completedJobs'] ?? 0,
        rating: (map['rating'] as num?)?.toDouble() ?? 4.5,
        rankingScore: (map['rankingScore'] as num?)?.toDouble() ?? 0.0,
        selectionReason: map['selectionReason'] ?? '',
        roadDistanceMeters: (map['roadDistanceMeters'] as num?)?.toDouble(),
        roadDurationSeconds: (map['roadDurationSeconds'] as num?)?.toInt(),
        roadDurationDisplay: map['roadDurationDisplay'],
        isRoadDistance: map['isRoadDistance'] ?? false,
        locationFreshness: map['locationFreshness'] ?? 'UNKNOWN',
      );
    }).toList();

    currentResultSetId = 'res_${DateTime.now().millisecondsSinceEpoch}';
    hasMoreCandidates = result['hasMore'] == true;
    lastDiscoveryCursor = result['nextCursor'];
    _voiceContext.setCandidates(activeCandidates); // sync multi-turn context
    onCandidatesFound?.call(activeCandidates);

    stateMachine.transition(VoiceSessionState.responding);
    onStateChanged?.call(stateMachine.current);

    // Build concise progressive speech response
    final count = activeCandidates.length;
    final String speech;
    if (count == 0) {
      speech = _currentLanguage.contains('en')
          ? "I couldn't find an available worker nearby."
          : "ನಿಮ್ಮ ಹತ್ತಿರ ಯಾವುದೇ ಲಭ್ಯವಿರುವ ಕಾರ್ಮಿಕರು ಕಂಡುಬಂದಿಲ್ಲ.";
    } else {
      final first = activeCandidates.first;
      final distText = first.roadDurationDisplay != null
          ? '${first.distanceDisplay} (${first.roadDurationDisplay})'
          : first.distanceDisplay;

      if (_currentLanguage.contains('en')) {
        speech = count == 1
            ? "I found one worker nearby. ${first.name} is $distText away."
            : "I found $count workers nearby. ${first.name} is closest, $distText away.";
      } else {
        speech = count == 1
            ? "ಹತ್ತಿರದಲ್ಲಿ ಒಬ್ಬ ಕಾರ್ಮಿಕರು ಕಂಡುಬಂದಿದ್ದಾರೆ. ${first.name} $distText ದೂರದಲ್ಲಿದ್ದಾರೆ."
            : "ಹತ್ತಿರದಲ್ಲಿ $count ಕಾರ್ಮಿಕರು ಕಂಡುಬಂದಿದ್ದಾರೆ. ${first.name} ಅತ್ಯಂತ ಹತ್ತಿರ, $distText ದೂರ.";
      }
    }

    await _respondAndSpeak(speech, generation);
  }

  /// Load next page of worker candidates continuously via cursor pagination
  Future<void> loadMoreCandidates() async {
    if (isLoadingMore || !hasMoreCandidates || lastDiscoveryCursor == null || lastDiscoveryTool == null) return;
    isLoadingMore = true;
    onStateChanged?.call(stateMachine.current);

    try {
      final args = Map<String, dynamic>.from(lastDiscoveryArgs ?? {});
      args['cursor'] = lastDiscoveryCursor;
      args['excludeUids'] = activeCandidates.map((c) => c.workerId).toList();

      final result = await toolRegistry.executeTool(
        toolName: lastDiscoveryTool!,
        arguments: args,
        onNavigate: onNavigate,
      );

      if (result['success'] == true && result['candidates'] is List) {
        final rawList = result['candidates'] as List;
        final newCandidates = rawList.map((m) {
          final map = m as Map<String, dynamic>;
          return WorkerCandidate(
            workerId: map['workerId'] ?? '',
            name: map['name'] ?? 'Worker',
            skill: map['skill'] ?? '',
            distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0.0,
            distanceDisplay: map['distanceDisplay'] ?? '',
            latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
            isAvailable: map['isAvailable'] ?? true,
            verificationLevel: map['verificationLevel'] ?? 'practicalVerified',
            completedJobs: map['completedJobs'] ?? 0,
            rating: (map['rating'] as num?)?.toDouble() ?? 4.5,
            rankingScore: (map['rankingScore'] as num?)?.toDouble() ?? 0.0,
            selectionReason: map['selectionReason'] ?? '',
            roadDistanceMeters: (map['roadDistanceMeters'] as num?)?.toDouble(),
            roadDurationSeconds: (map['roadDurationSeconds'] as num?)?.toInt(),
            roadDurationDisplay: map['roadDurationDisplay'],
            isRoadDistance: map['isRoadDistance'] ?? false,
            locationFreshness: map['locationFreshness'] ?? 'UNKNOWN',
          );
        }).toList();

        // Deduplicate against activeCandidates by workerId
        final existingIds = activeCandidates.map((c) => c.workerId).toSet();
        for (final cand in newCandidates) {
          if (!existingIds.contains(cand.workerId)) {
            activeCandidates.add(cand);
            existingIds.add(cand.workerId);
          }
        }

        hasMoreCandidates = result['hasMore'] == true;
        lastDiscoveryCursor = result['nextCursor'];
        _voiceContext.setCandidates(activeCandidates);
        onCandidatesFound?.call(activeCandidates);
      } else {
        hasMoreCandidates = false;
      }
    } catch (e) {
      debugPrint('[VoiceSessionManager] loadMoreCandidates error: $e');
    } finally {
      isLoadingMore = false;
      onStateChanged?.call(stateMachine.current);
    }
  }

  /// Execute Confirmed Booking Transaction
  Future<void> executeConfirmedBooking([int? generation]) async {
    final gen = generation ?? _commandGeneration;
    if (pendingBooking == null || gen != _commandGeneration) return;

    stateMachine.transition(VoiceSessionState.executing);
    onStateChanged?.call(stateMachine.current);

    final bookingArgs = Map<String, dynamic>.from(pendingBooking!);
    pendingBooking = null;

    final result = await toolRegistry.executeTool(
      toolName: 'createBooking',
      arguments: bookingArgs,
    );

    if (gen != _commandGeneration) return;

    stateMachine.transition(VoiceSessionState.responding);
    onStateChanged?.call(stateMachine.current);

    final isSuccess = result['success'] == true;
    final speech = isSuccess
        ? (_currentLanguage.contains('en') ? 'Booking confirmed successfully!' : 'ಬುಕಿಂಗ್ ಯಶಸ್ವಿಯಾಗಿ ಖಚಿತಗೊಂಡಿದೆ!')
        : (_currentLanguage.contains('en') ? 'Booking failed: ${result['error']}' : 'ಬುಕಿಂಗ್ ವಿಫಲವಾಗಿದೆ: ${result['error']}');

    await _respondAndSpeak(speech, gen);
  }

  /// Cancel Pending Booking
  Future<void> cancelPendingBooking([int? generation]) async {
    final gen = generation ?? _commandGeneration;
    pendingBooking = null;

    stateMachine.transition(VoiceSessionState.cancelled);
    onStateChanged?.call(stateMachine.current);

    final cancelMsg = _currentLanguage.contains('en')
        ? 'Booking cancelled.'
        : 'ಬುಕಿಂಗ್ ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ.';
    await _respondAndSpeak(cancelMsg, gen);
  }

  /// Backwards compatibility alias
  Future<void> executeConfirmedAction([int? generation]) => executeConfirmedBooking(generation);

  /// Backwards compatibility alias
  Future<void> cancelPendingAction([int? generation]) => cancelPendingBooking(generation);

  /// Speak Response and manage speaking states
  Future<void> _respondAndSpeak(String text, int generation) async {
    if (generation != _commandGeneration) return;

    onResponseUpdate?.call(text);

    // If voice replies are disabled in settings, return to idle
    if (!settingsService.voiceReplies) {
      metrics.t7Complete = DateTime.now();
      onMetricsUpdated?.call(metrics);
      stateMachine.transition(VoiceSessionState.idle);
      onStateChanged?.call(stateMachine.current);
      return;
    }

    stateMachine.transition(VoiceSessionState.speaking);
    onStateChanged?.call(stateMachine.current);

    metrics.t6FirstAudio = DateTime.now();
    onMetricsUpdated?.call(metrics);

    await ttsProvider.speak(text, languageCode: _currentLanguage);

    if (generation == _commandGeneration && stateMachine.current == VoiceSessionState.speaking) {
      metrics.t7Complete = DateTime.now();
      onMetricsUpdated?.call(metrics);

      stateMachine.transition(VoiceSessionState.idle);
      onStateChanged?.call(stateMachine.current);
    }
  }

  bool _isSearchQuery(String text) {
    final t = text.toLowerCase();
    return t.contains('find') || t.contains('search') || t.contains('show') ||
        t.contains('ಹುಡುಕು') || t.contains('ತೋರಿಸು') || t.contains('ಬೇಕು');
  }

  Future<void> dispose() async {
    _commandGeneration++;
    speculativeCoordinator.cancel();
    await speechProvider.dispose();
    await ttsProvider.dispose();
    stateMachine.force(VoiceSessionState.closed);
    onStateChanged?.call(stateMachine.current);
  }
}
