// lib/services/voice/fast_local_command_router.dart
// Deterministic Fast-Path Command Router for Kelasagara Voice Command Center
// Sub-2ms, zero-network. Covers all 30 Karnataka districts + code-mixed pronunciations.

import 'voice_tool_registry.dart';
import 'voice_intent_parser.dart';

class LocalRouteResult {
  final bool isHandled;
  final String? toolName;
  final Map<String, dynamic> arguments;
  final String? speechResponseKn;
  final String? speechResponseEn;
  final String? directAction; // 'NAV_SETTINGS', 'NAV_HOME', 'NAV_BACK', etc.
  final VoiceSearchCommand? parsedCommand;

  const LocalRouteResult({
    required this.isHandled,
    this.toolName,
    this.arguments = const {},
    this.speechResponseKn,
    this.speechResponseEn,
    this.directAction,
    this.parsedCommand,
  });

  static const unhandled = LocalRouteResult(isHandled: false);
}

class FastLocalCommandRouter {
  static LocalRouteResult tryRoute({
    required String utterance,
    List<WorkerCandidate> activeCandidates = const [],
    Map<String, dynamic>? pendingBooking,
  }) {
    final text = utterance.trim().toLowerCase();
    if (text.isEmpty) return LocalRouteResult.unhandled;

    // ── 0. Security Guard: Sensitive Password Inquiry ─────────────────────
    if (text.contains('password') || text.contains('ಪಾಸ್ವರ್ಡ್') || text.contains('ಪಾಸ್‌ವರ್ಡ್')) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'securityGuardPassword',
        speechResponseEn: "For security, I cannot display your password. You can reset it from Account Security.",
        speechResponseKn: "ಭದ್ರತೆಯ ಕಾರಣದಿಂದ, ನಾನು ನಿಮ್ಮ ಪಾಸ್‌ವರ್ಡ್ ಅನ್ನು ಪ್ರದರ್ಶಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ. ನೀವು ಖಾತೆ ಭದ್ರತೆಯಿಂದ ಅದನ್ನು ಮರುಹೊಂದಿಸಬಹುದು.",
      );
    }

    // ── 1. Stop / Cancel / Pause Control ──────────────────────────────────
    if (_matches(text, ['stop', 'ನಿಲ್ಲಿಸು', 'ನಿಲ್ಲಿಸಿ', 'ಸಾಕು', 'stop it', 'pause', 'stop listening'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'stop',
        directAction: 'STOP',
        speechResponseEn: 'Stopped.',
        speechResponseKn: 'ನಿಲ್ಲಿಸಲಾಗಿದೆ.',
      );
    }

    // Repeat Command
    if (_matches(text, ['repeat', 'ಮತ್ತೊಮ್ಮೆ ಹೇಳಿ', 'ಮತ್ತೆ ಹೇಳಿ', 'repeat that', 'say again', 'once more', 'innondu sala repeat'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'repeat',
        speechResponseEn: 'Repeating last response.',
        speechResponseKn: 'ಹಿಂದಿನ ಉತ್ತರವನ್ನು ಪುನರಾವರ್ತಿಸಲಾಗುತ್ತಿದೆ.',
      );
    }

    if (_matches(text, ['cancel', 'cancel that', 'ರದ್ದು', 'ರದ್ದು ಮಾಡು', 'ರದ್ದು ಮಾಡಿ', 'ಬೇಡ', 'cancel maadi', 'cancel booking'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'cancelBooking',
        directAction: 'CANCEL_BOOKING',
        speechResponseEn: 'Booking cancelled.',
        speechResponseKn: 'ಬುಕಿಂಗ್ ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ.',
      );
    }

    // ── 2. Direct Booking Confirmation ───────────────────────────────────
    if (_matches(text, ['confirm', 'yes', 'ಹೌದು', 'ಖಚಿತ', 'ಖಚಿತಪಡಿಸಿ', 'confirm ಮಾಡು', 'book him', 'book her', 'proceed', 'yes confirm', 'confirm booking', 'okay confirm'])) {
      return LocalRouteResult(
        isHandled: true,
        toolName: 'confirmBooking',
        arguments: pendingBooking ?? const {},
        directAction: 'CONFIRM_BOOKING',
        speechResponseEn: 'Confirmed.',
        speechResponseKn: 'ಖಚಿತಪಡಿಸಲಾಗಿದೆ.',
      );
    }

    // ── 3. App Navigation ─────────────────────────────────────────────────
    // Settings
    if (_matches(text, [
      'open settings', 'go to settings', 'settings', 'ಸೆಟ್ಟಿಂಗ್ಸ್', 'ಸೆಟ್ಟಿಂಗ್ಸ್ ಓಪನ್ ಮಾಡಿ',
      'settings open madu', 'open setting'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openSettings',
        directAction: 'NAV_SETTINGS',
        speechResponseEn: 'Opening Settings.',
        speechResponseKn: 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಲಾಗುತ್ತಿದೆ.',
      );
    }

    // Voice & Accessibility Settings
    if (_matches(text, [
      'open voice settings', 'voice settings', 'ಧ್ವನಿ ಸೆಟ್ಟಿಂಗ್ಸ್', 'accessibility settings',
      'voice command settings'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openVoiceSettings',
        directAction: 'NAV_VOICE_SETTINGS',
        speechResponseEn: 'Opening Voice & Accessibility Settings.',
        speechResponseKn: 'ಧ್ವನಿ ಮತ್ತು ಪ್ರವೇಶಿಸುವಿಕೆ ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಲಾಗುತ್ತಿದೆ.',
      );
    }

    // Bookings
    if (_matches(text, [
      'open my bookings', 'open bookings', 'my bookings', 'show bookings',
      'ನನ್ನ ಬುಕಿಂಗ್ಸ್', 'ನನ್ನ ಬುಕಿಂಗ್ ತೋರಿಸಿ', 'ಬುಕಿಂಗ್ಸ್', 'bookings open madu'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openBookings',
        directAction: 'NAV_BOOKINGS',
        speechResponseEn: 'Opening your bookings.',
        speechResponseKn: 'ನಿಮ್ಮ ಬುಕಿಂಗ್‌ಗಳನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ.',
      );
    }

    // ── 3B. Applicants (Hirer Context) & Applications (Worker Context) ──
    // Hirer: Show my applicants / ಅರ್ಜಿದಾರರು
    if (_matches(text, [
      'show my applicants', 'show applicants', 'my applicants', 'applicants',
      'check my applicants', 'view applicants', 'view my applicants', 'find my applicants',
      'list applicants', 'applicant list',
      'ನನ್ನ ಅರ್ಜಿದಾರರು', 'ಅರ್ಜಿದಾರರು', 'ಅರ್ಜಿದಾರರನ್ನು ತೋರಿಸಿ', 'ಅರ್ಜಿದಾರರ ಪಟ್ಟಿ',
      'applicant torisi', 'applicants torisi', 'applicants nodi'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'listMyApplications',
        arguments: {'roleFilter': 'hirer'},
        directAction: 'SHOW_APPLICANTS',
        speechResponseEn: 'Showing applicants for your posted jobs.',
        speechResponseKn: 'ನಿಮ್ಮ ಕೆಲಸಗಳಿಗೆ ಬಂದಿರುವ ಅರ್ಜಿದಾರರನ್ನು ತೋರಿಸಲಾಗುತ್ತಿದೆ.',
      );
    }

    // Worker / General: My applications / ನನ್ನ ಅರ್ಜಿಗಳು
    if (_matches(text, [
      'my applications', 'my application', 'applications', 'show applications',
      'show my applications', 'open applications', 'check applications',
      'view applications', 'my apps', 'apps', 'find my applications', 'find applications',
      'ನನ್ನ ಅರ್ಜಿಗಳು', 'ನನ್ನ ಅರ್ಜಿ', 'ಅರ್ಜಿಗಳು', 'ಅರ್ಜಿ', 'ನನ್ನ ಕೆಲಸದ ಅರ್ಜಿಗಳು',
      'ಅರ್ಜಿಗಳನ್ನು ತೋರಿಸಿ', 'ಅರ್ಜಿ ತೋರಿಸಿ', 'ಅರ್ಜಿ ಓಪನ್ ಮಾಡಿ',
      'my work', 'my works', 'show my work', 'show my works', 'list of work',
      'show work list', 'works', 'ಕೆಲಸದ ಪಟ್ಟಿ', 'ನನ್ನ ಕೆಲಸಗಳು', 'ನನ್ನ ಕೆಲಸ',
      'ಮಾಡಬೇಕಾದ ಕೆಲಸ', 'application nodu', 'application torisi',
      'kelasa torisi', 'kelasa list'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'listMyApplications',
        arguments: {'roleFilter': 'worker'},
        directAction: 'SHOW_APPLICATIONS',
        speechResponseEn: 'Showing your job applications.',
        speechResponseKn: 'ನಿಮ್ಮ ಅರ್ಜಿಗಳನ್ನು ತೋರಿಸಲಾಗುತ್ತಿದೆ.',
      );
    }

    // ── 3C. Profile Navigation ────────────────────────────────────────────
    if (_matches(text, [
      'my profile', 'profile', 'open profile', 'account', 'my account',
      'ಪ್ರೊಫೈಲ್', 'ನನ್ನ ಅಕೌಂಟ್', 'ಖಾತೆ', 'ನನ್ನ ಪ್ರೊಫೈಲ್',
      'profile tereyi', 'profile terey', 'profile open maadi',
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openProfile',
        directAction: 'NAV_PROFILE',
        speechResponseEn: 'Opening your profile.',
        speechResponseKn: 'ನಿಮ್ಮ ಪ್ರೊಫೈಲ್ ತೆರೆಯಲಾಗಿದೆ.',
      );
    }

    // ── 3D. Jobs / Job List Navigation ───────────────────────────────────
    if (_matches(text, [
      'jobs', 'job list', 'available jobs', 'show jobs', 'open jobs',
      'find jobs', 'show my posted jobs', 'my posted jobs', 'posted jobs',
      'my jobs', 'show my jobs',
      'ಕೆಲಸಗಳು', 'ಜಾಬ್ ಲಿಸ್ಟ್', 'ಕೆಲಸ ಪಟ್ಟಿ', 'ಲಭ್ಯ ಕೆಲಸ',
      'ನನ್ನ ಪೋಸ್ಟ್ ಮಾಡಿದ ಕೆಲಸಗಳು', 'ನಾನು ಹಾಕಿದ ಕೆಲಸಗಳು',
      'jobs tereyi', 'kelasagalu torisi', 'kelasagalu nodri',
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openJobs',
        directAction: 'NAV_JOBS',
        speechResponseEn: 'Opening jobs list.',
        speechResponseKn: 'ಕೆಲಸಗಳ ಪಟ್ಟಿ ತೆರೆಯಲಾಗಿದೆ.',
      );
    }

    // ── 3E. Chat List Navigation ──────────────────────────────────────────
    if (_matches(text, [
      'open chat', 'messages', 'my messages', 'inbox', 'chat list',
      'ಚಾಟ್', 'ಸಂದೇಶ', 'ಮೆಸೇಜ್', 'ಮೆಸೇಜ್ ಪಟ್ಟಿ', 'ಚಾಟ್ ಪಟ್ಟಿ',
      'chat tereyi', 'message tereyi', 'open messages',
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'openChatList',
        directAction: 'NAV_CHAT',
        speechResponseEn: 'Opening chat.',
        speechResponseKn: 'ಚಾಟ್ ತೆರೆಯಲಾಗಿದೆ.',
      );
    }

    // ── Book currently selected or active worker ───────────────────────────
    if (_matches(text, [
      'book this worker', 'book him', 'book her', 'hire this worker', 'hire him', 'hire her',
      'ಈ ಕಾರ್ಮಿಕರನ್ನು ಬುಕ್ ಮಾಡು', 'ಇವರನ್ನು ಬುಕ್ ಮಾಡು', 'ಇವರನ್ನೇ ಬುಕ್ ಮಾಡು', 'ಬುಕ್ ಮಾಡಿ',
      'book maadi', 'hire maadi', 'book karo', 'hire karo',
    ])) {
      if (activeCandidates.isNotEmpty) {
        final targetWorker = activeCandidates.first;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'openBookingForm',
          arguments: {
            'workerIndex': 1,
            'targetIndex': 1,
            'workerId': targetWorker.workerId,
            'worker': targetWorker.toMap(),
          },
          directAction: 'OPEN_BOOKING_FORM',
          speechResponseEn:
              'Opening booking form for ${targetWorker.name}. Please confirm job details.',
          speechResponseKn:
              '${targetWorker.name} ಅವರ ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.',
        );
      }
    }

    // ── 3C. Structured Voice Intelligence Parser (Kannada, English, Mixed) ───
    final parsedCmd = VoiceIntentParser.parse(
      utterance: text,
      hasActiveCandidates: activeCandidates.isNotEmpty,
      activeCandidateCount: activeCandidates.length,
    );

    if (parsedCmd.intent == ParsedIntentType.openBookingForm && parsedCmd.selectedWorkerIndex != null) {
      final targetIdx = parsedCmd.selectedWorkerIndex!;
      final worker = activeCandidates.isNotEmpty
          ? activeCandidates[(targetIdx - 1).clamp(0, activeCandidates.length - 1)]
          : null;
      return LocalRouteResult(
        isHandled: true,
        toolName: 'openBookingForm',
        arguments: {
          'targetIndex': targetIdx,
          'workerIndex': targetIdx,
          if (worker != null) 'workerId': worker.workerId,
          if (worker != null) 'worker': worker.toMap(),
        },
        directAction: 'OPEN_BOOKING_FORM',
        speechResponseEn: worker != null
            ? 'Opening booking form for ${worker.name}. Please confirm job details.'
            : 'Opening booking form for candidate $targetIdx. Please confirm job details.',
        speechResponseKn: worker != null
            ? '${worker.name} ಅವರ ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.'
            : 'ಅಭ್ಯರ್ಥಿ $targetIdx ಅವರ ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.',
        parsedCommand: parsedCmd,
      );
    }

    if (parsedCmd.intent == ParsedIntentType.workerSearch) {
      if (parsedCmd.requiresClarification) {
        return LocalRouteResult(
          isHandled: true,
          toolName: 'clarificationPrompt',
          speechResponseEn: parsedCmd.clarificationPromptEn,
          speechResponseKn: parsedCmd.clarificationPromptKn,
          parsedCommand: parsedCmd,
        );
      }

      final skillId = parsedCmd.trade?.categoryId ?? 'all';
      final skillDisplayEn = parsedCmd.trade?.canonicalName ?? 'workers';
      final skillDisplayKn = parsedCmd.trade?.kannadaName ?? 'ಕಾರ್ಮಿಕರನ್ನು';

      if ((parsedCmd.geography.isDistrictWide || parsedCmd.geography.mode == 'taluk_scope') &&
          parsedCmd.geography.district != null) {
        final district = parsedCmd.geography.district!;
        final districtKn = parsedCmd.geography.districtKn ?? district;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'searchWorkersByDistrict',
          arguments: {
            'skillId': skillId,
            'trade': skillDisplayEn,
            'district': district,
            if (parsedCmd.geography.taluk != null) 'taluk': parsedCmd.geography.taluk,
            'specializationMode': parsedCmd.trade?.specializationMode ?? 'standard',
          },
          directAction: 'SEARCH_WORKERS_DISTRICT',
          speechResponseEn: 'Searching for $skillDisplayEn across $district district...',
          speechResponseKn: '$districtKn ಜಿಲ್ಲೆಯಲ್ಲಿ $skillDisplayKn ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
          parsedCommand: parsedCmd,
        );
      } else if (parsedCmd.geography.mode == 'landmark_radius') {
        final landmark = parsedCmd.geography.landmark ?? 'landmark';
        final radiusKm = parsedCmd.geography.radiusKm ?? 10.0;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'searchWorkersNearby',
          arguments: {
            'skillId': skillId,
            'trade': skillDisplayEn,
            'radiusMeters': parsedCmd.geography.radiusMeters,
            'latitude': parsedCmd.geography.latitude,
            'longitude': parsedCmd.geography.longitude,
            'landmark': landmark,
          },
          directAction: 'SEARCH_WORKERS_NEARBY',
          speechResponseEn: 'Searching for $skillDisplayEn within ${radiusKm.round()} km of $landmark...',
          speechResponseKn: '$landmark ಹತ್ತಿರ ${radiusKm.round()} ಕಿಲೋಮೀಟರ್ ಒಳಗೆ $skillDisplayKn ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
          parsedCommand: parsedCmd,
        );
      } else {
        final radiusKm = parsedCmd.geography.radiusKm ?? 10.0;
        final radiusMeters = parsedCmd.geography.radiusMeters ?? 10000.0;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'searchWorkersNearby',
          arguments: {
            'skillId': skillId,
            'trade': skillDisplayEn,
            'radiusMeters': radiusMeters,
            'specializationMode': parsedCmd.trade?.specializationMode ?? 'standard',
          },
          directAction: 'SEARCH_WORKERS_NEARBY',
          speechResponseEn: 'Searching for $skillDisplayEn within ${radiusKm.round()} km...',
          speechResponseKn: '${radiusKm.round()} ಕಿಲೋಮೀಟರ್ ಒಳಗೆ $skillDisplayKn ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
          parsedCommand: parsedCmd,
        );
      }
    }

    // Home
    if (_matches(text, ['go home', 'home', 'ಮುಖಪುಟ', 'home ge hogi', 'open home', 'home screen'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'goHome',
        directAction: 'NAV_HOME',
        speechResponseEn: 'Navigating to Home.',
        speechResponseKn: 'ಮುಖಪುಟಕ್ಕೆ ಹೋಗಲಾಗುತ್ತಿದೆ.',
      );
    }

    // Back
    if (_matches(text, ['go back', 'back', 'ಹಿಂದೆ ಹೋಗಿ', 'back hogi', 'return'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'goBack',
        directAction: 'NAV_BACK',
        speechResponseEn: 'Going back.',
        speechResponseKn: 'ಹಿಂದೆ ಹೋಗಲಾಗುತ್ತಿದೆ.',
      );
    }

    // Recenter Map
    if (_matches(text, ['recenter', 'recenter map', 'ನಕ್ಷೆ ಮರುಕೇಂದ್ರೀಕರಿಸಿ', 'center map', 'map recenter'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'recenter',
        directAction: 'MAP_RECENTER',
        speechResponseEn: 'Map re-centered on your location.',
        speechResponseKn: 'ನಕ್ಷೆಯನ್ನು ಮರುಕೇಂದ್ರೀಕರಿಸಲಾಗಿದೆ.',
      );
    }

    // Help
    if (_matches(text, [
      'help', 'what can you do', 'ಏನು ಮಾಡಬಹುದು', 'ಸಹಾಯ', 'help me', 'features', 'ಯಾವ ಕೆಲಸ ಮಾಡುತ್ತೀರಿ'
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'voiceHelp',
        speechResponseEn: 'You can find nearby workers, check availability, view bookings, navigate to a worker, or prepare a booking.',
        speechResponseKn: 'ನೀವು ಹತ್ತಿರದ ಕಾರ್ಮಿಕರನ್ನು ಹುಡುಕಬಹುದು, ಲಭ್ಯತೆ ಪರಿಶೀಲಿಸಬಹುದು, ಬುಕಿಂಗ್‌ಗಳನ್ನು ನೋಡಬಹುದು ಅಥವಾ ಮಾರ್ಗದರ್ಶನ ಪಡೆಯಬಹುದು.',
      );
    }

    // ── 4. Candidate List Selection & Follow-up Queries ──────────────────
    if (activeCandidates.isNotEmpty) {
      final selectedIdx = _extractWorkerIndex(text);
      if (selectedIdx != null && selectedIdx < activeCandidates.length) {
        final worker = activeCandidates[selectedIdx];

        // A0. "Book worker X" / "Hire worker X" / "ಬುಕ್ ಮಾಡು"
        if (_matches(text, [
          'book', 'hire', 'ಬುಕ್', 'ಆಯ್ಕೆ ಮಾಡಿ ಬುಕ್', 'ನೇಮಿಸಿ', 'ಬುಕ್ ಮಾಡಿ',
          'book him', 'book her', 'hire him', 'hire her', 'bulao', 'hire karo',
        ])) {
          return LocalRouteResult(
            isHandled: true,
            toolName: 'openBookingForm',
            arguments: {
              'workerIndex': selectedIdx + 1,
              'workerId': worker.workerId,
              'worker': worker.toMap(),
            },
            directAction: 'OPEN_BOOKING_FORM',
            speechResponseEn:
                'Opening booking form for ${worker.name}. Please confirm job details.',
            speechResponseKn:
                '${worker.name} ಅವರ ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.',
          );
        }

        // A. "Navigate to painter number X" / "Take me to him"
        if (_matches(text, ['navigate', 'take me', 'ದಾರಿ ತೋರಿಸು', 'navigation', 'ಹೋಗೋಣ', 'ಹೋಗು'])) {
          return LocalRouteResult(
            isHandled: true,
            toolName: 'navigateToWorker',
            arguments: {
              'workerId': worker.workerId,
              'workerName': worker.name,
              'latitude': worker.latitude,
              'longitude': worker.longitude,
            },
            directAction: 'NAVIGATE_WORKER',
            speechResponseEn: 'Starting navigation to ${worker.name}.',
            speechResponseKn: '${worker.name} ಅವರ ಸ್ಥಳಕ್ಕೆ ಮಾರ್ಗದರ್ಶನ ಪ್ರಾರಂಭಿಸಲಾಗುತ್ತಿದೆ.',
          );
        }

        // B. "How far is painter number X?"
        if (_matches(text, ['how far', 'distance', 'ಎಷ್ಟು ದೂರ', 'dura', 'km'])) {
          return LocalRouteResult(
            isHandled: true,
            toolName: 'getWorkerDistance',
            arguments: {'workerId': worker.workerId},
            speechResponseEn: '${worker.name} is ${worker.distanceDisplay} away.',
            speechResponseKn: '${worker.name} ಅವರು ${worker.distanceDisplay} ದೂರದಲ್ಲಿದ್ದಾರೆ.',
          );
        }

        // C. "When is number X available?"
        if (_matches(text, ['when is', 'available', 'ಲಭ್ಯ', 'ಯಾವಾಗ', 'free'])) {
          final availStr = worker.isAvailable
              ? 'available now'
              : 'currently on a job';
          final availStrKn = worker.isAvailable
              ? 'ಈಗ ಲಭ್ಯವಿದ್ದಾರೆ'
              : 'ಪ್ರಸ್ತುತ ಕೆಲಸದಲ್ಲಿದ್ದಾರೆ';
          return LocalRouteResult(
            isHandled: true,
            toolName: 'getWorkerAvailability',
            arguments: {'workerId': worker.workerId},
            speechResponseEn: '${worker.name} is $availStr.',
            speechResponseKn: '${worker.name} ಅವರು $availStrKn.',
          );
        }

        // D. "Show number X" / Select worker
        return LocalRouteResult(
          isHandled: true,
          toolName: 'selectWorker',
          arguments: {
            'workerIndex': selectedIdx + 1,
            'workerId': worker.workerId,
            'worker': worker.toMap(),
          },
          speechResponseEn: '${worker.name}, ${worker.distanceDisplay} away, rated ${worker.rating.toStringAsFixed(1)} stars.',
          speechResponseKn: '${worker.name}, ${worker.distanceDisplay} ದೂರ, ${worker.rating.toStringAsFixed(1)} ಸ್ಟಾರ್ ರೇಟಿಂಗ್.',
        );
      }

      // "Who is closest?"
      if (_matches(text, ['who is closest', 'nearest', 'ಹತ್ತಿರದವರು ಯಾರು', 'closest', 'ಯಾರು ಹತ್ತಿರ'])) {
        final closest = activeCandidates.first;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'selectWorker',
          arguments: {'workerIndex': 1, 'workerId': closest.workerId, 'worker': closest.toMap()},
          speechResponseEn: '${closest.name} is closest, ${closest.distanceDisplay} away.',
          speechResponseKn: '${closest.name} ಅತ್ಯಂತ ಹತ್ತಿರವಿದ್ದಾರೆ, ${closest.distanceDisplay} ದೂರ.',
        );
      }
    }

    // ── NEW: Chat with selected worker ─────────────────────────────────────
    if (_matches(text, [
      'chat with him', 'chat with her', 'message him', 'message her',
      'talk to him', 'talk to her', 'open chat with',
      'ಚಾಟ್ ಮಾಡಿ', 'ಚಾಟ್ ಮಾಡ್ರಿ', 'ಮಾತಾಡಿ', 'ಸಂದೇಶ ಕಳಿಸಿ', 'ಮಾತಾಡ್ರಿ',
      'chat maadi', 'chat maadri', 'message maadi', 'chat with worker',
    ])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'chatWithWorker',
        directAction: 'CHAT_WORKER',
        speechResponseEn: 'Opening chat with selected worker.',
        speechResponseKn: 'ಆಯ್ಕೆ ಮಾಡಿದ ಕಾರ್ಮಿಕರೊಂದಿಗೆ ಚಾಟ್ ತೆರೆಯಲಾಗಿದೆ.',
      );
    }

    // ── Book currently selected or active worker ───────────────────────────
    if (_matches(text, [
      'book this worker', 'book him', 'book her', 'hire this worker', 'hire him', 'hire her',
      'ಈ ಕಾರ್ಮಿಕರನ್ನು ಬುಕ್ ಮಾಡು', 'ಇವರನ್ನು ಬುಕ್ ಮಾಡು', 'ಇವರನ್ನೇ ಬುಕ್ ಮಾಡು', 'ಬುಕ್ ಮಾಡಿ',
      'book maadi', 'hire maadi', 'book karo', 'hire karo',
    ])) {
      if (activeCandidates.isNotEmpty) {
        final targetWorker = activeCandidates.first;
        return LocalRouteResult(
          isHandled: true,
          toolName: 'openBookingForm',
          arguments: {
            'workerIndex': 1,
            'workerId': targetWorker.workerId,
            'worker': targetWorker.toMap(),
          },
          directAction: 'OPEN_BOOKING_FORM',
          speechResponseEn:
              'Opening booking form for ${targetWorker.name}. Please confirm job details.',
          speechResponseKn:
              '${targetWorker.name} ಅವರ ಬುಕಿಂಗ್ ನಮೂನೆಯನ್ನು ತೆರೆಯಲಾಗುತ್ತಿದೆ. ಕೆಲಸದ ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ.',
        );
      }
    }

    // ── NEW: Extended worker index selection (4 and 5) ────────────────────
    if (activeCandidates.isNotEmpty) {
      if (text.contains('number 4') || text.contains('fourth') ||
          text.contains('4th') || text.contains('ನಾಲ್ಕು') ||
          text.contains('ನಂಬರ್ 4') || text == '4' || text == 'four') {
        if (activeCandidates.length >= 4) {
          final worker = activeCandidates[3];
          return LocalRouteResult(
            isHandled: true,
            toolName: 'selectWorker',
            arguments: {
              'workerIndex': 4,
              'workerId': worker.workerId,
              'worker': worker.toMap(),
            },
            speechResponseEn:
                '${worker.name}, ${worker.distanceDisplay} away, ${worker.rating.toStringAsFixed(1)} stars.',
            speechResponseKn:
                '${worker.name}, ${worker.distanceDisplay} ದೂರ, ${worker.rating.toStringAsFixed(1)} ಸ್ಟಾರ್.',
          );
        }
      }

      if (text.contains('number 5') || text.contains('fifth') ||
          text.contains('5th') || text.contains('ಐದು') ||
          text.contains('ನಂಬರ್ 5') || text == '5' || text == 'five') {
        if (activeCandidates.length >= 5) {
          final worker = activeCandidates[4];
          return LocalRouteResult(
            isHandled: true,
            toolName: 'selectWorker',
            arguments: {
              'workerIndex': 5,
              'workerId': worker.workerId,
              'worker': worker.toMap(),
            },
            speechResponseEn:
                '${worker.name}, ${worker.distanceDisplay} away, ${worker.rating.toStringAsFixed(1)} stars.',
            speechResponseKn:
                '${worker.name}, ${worker.distanceDisplay} ದೂರ, ${worker.rating.toStringAsFixed(1)} ಸ್ಟಾರ್.',
          );
        }
      }

      // ── Repeat the worker list ─────────────────────────────────────────
      if (_matches(text, [
        'show list again', 'repeat list', 'list again', 'show again',
        'ಮತ್ತೆ ಹೇಳಿ', 'ಪಟ್ಟಿ ಮತ್ತೆ', 'ಇನ್ನೊಮ್ಮೆ ಹೇಳಿ', 'list torisi',
        'mattomme heli', 'matte heli', 'again heli',
      ])) {
        return const LocalRouteResult(
          isHandled: true,
          toolName: 'repeatList',
          directAction: 'REPEAT_LIST',
          speechResponseEn: 'Repeating the worker list.',
          speechResponseKn: 'ಕಾರ್ಮಿಕರ ಪಟ್ಟಿ ಮತ್ತೆ ಹೇಳಲಾಗುತ್ತಿದೆ.',
        );
      }
    }

    // ── NEW: Kalyana Karnataka — Urdu/Hindi skill searches (Zone 3) ───────────
    // These are the MOST COMMON ways laborers in Kalaburagi/Bidar say skill names.
    // Fast-path them here so Groq isn't needed for these common patterns.
    {
      String? dialectSkill;
      if (_matchesAny(text, ['mazdoor', 'mazdur', 'mazadoor', 'kaam wala', 'kaamwala', 'beldar'])) {
        dialectSkill = 'helper';
      } else if (_matchesAny(text, ['bijli wala', 'bijliwala', 'bejli wala', 'bijli'])) {
        dialectSkill = 'electrician';
      } else if (_matchesAny(text, ['rang wala', 'rangwala', 'rang karne wala'])) {
        dialectSkill = 'painter';
      } else if (_matchesAny(text, ['nal mestri', 'nal mistri', 'pani mistri', 'pipe wala'])) {
        dialectSkill = 'plumber';
      } else if (_matchesAny(text, ['raj mistri', 'raj mistry', 'rajmistri', 'cement wala'])) {
        dialectSkill = 'mason';
      } else if (_matchesAny(text, ['darji', 'darji wala', 'silai wala', 'kapada silai'])) {
        dialectSkill = 'tailor';
      } else if (_matchesAny(text, ['chaukidaar', 'chaukidar', 'chowkidaar', 'chowkidar'])) {
        dialectSkill = 'security';
      } else if (_matchesAny(text, ['loha kaam', 'loha kaam wala', 'lohaar'])) {
        dialectSkill = 'welder';
      } else if (_matchesAny(text, ['baagban', 'baaghbaan', 'garden wala'])) {
        dialectSkill = 'gardener';
      } else if (_matchesAny(text, ['khet kaam', 'khetiwala', 'fasal'])) {
        dialectSkill = 'agriculture';
      } else if (_matchesAny(text, ['bawarchi', 'khaana banaane', 'khansama'])) {
        dialectSkill = 'cook';
      }
      if (dialectSkill != null) {
        final isUrgent = _matchesAny(text, ['abhi', 'jaldi', 'turant', 'urgent', 'lavkar']);
        return LocalRouteResult(
          isHandled: true,
          toolName: 'searchWorkersNearby',
          arguments: {'skillId': dialectSkill, 'isUrgent': isUrgent},
          directAction: 'SEARCH_WORKERS_NEARBY',
          speechResponseEn: 'Searching for $dialectSkill near you...',
          speechResponseKn: '$dialectSkill ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
        );
      }
    }

    // ── NEW: Kalyana Karnataka confirm/cancel (Urdu/Hindi Zone 3) ─────────────
    if (_matchesAny(text, ['haan', 'hanji', 'theek hai', 'thik hai', 'hoy'])) {
      return LocalRouteResult(
        isHandled: true,
        toolName: 'confirmBooking',
        arguments: pendingBooking ?? const {},
        directAction: 'CONFIRM_BOOKING',
        speechResponseEn: 'Confirmed.',
        speechResponseKn: 'ಖಚಿತಪಡಿಸಲಾಗಿದೆ.',
      );
    }
    if (_matchesAny(text, ['nahi chahiye', 'nahi', 'nako', 'rehne do'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'cancelBooking',
        directAction: 'CANCEL_BOOKING',
        speechResponseEn: 'Booking cancelled.',
        speechResponseKn: 'ಬುಕಿಂಗ್ ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ.',
      );
    }

    // ── NEW: Coastal / Kundagannada (Tulu-influenced Zone 4) ──────────────────
    {
      String? coastalSkill;
      if (_matchesAny(text, ['adiga beku', 'adiga bekka', 'adiga'])) {
        coastalSkill = 'cook';
      } else if (_matchesAny(text, ['badiga beku', 'badiga bekka', 'badiga'])) {
        coastalSkill = 'carpenter';
      } else if (_matchesAny(text, ['kaavalgar beku', 'kaavalgaraa beku', 'kaavalgar'])) {
        coastalSkill = 'security';
      }
      if (coastalSkill != null) {
        return LocalRouteResult(
          isHandled: true,
          toolName: 'searchWorkersNearby',
          arguments: {'skillId': coastalSkill, 'isUrgent': false},
          directAction: 'SEARCH_WORKERS_NEARBY',
          speechResponseEn: 'Searching for $coastalSkill near you...',
          speechResponseKn: '$coastalSkill ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
        );
      }
    }
    // Coastal: barpira + skill = availability check
    if (_matchesAny(text, ['barpira', 'barpodu'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'askAvailability',
        directAction: 'ASK_AVAILABILITY',
        speechResponseEn: 'Checking worker availability...',
        speechResponseKn: 'ಕಾರ್ಮಿಕರ ಲಭ್ಯತೆ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...',
      );
    }

    // ── NEW: Dharwad / North Karnataka (Zone 2) ───────────────────────────────
    if (_matchesAny(text, ['mandi bekri', 'mandi bekaagbaar', 'aLu bekri', 'mandi kaLsi'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'searchWorkersNearby',
        arguments: {'skillId': 'helper'},
        directAction: 'SEARCH_WORKERS_NEARBY',
        speechResponseEn: 'Searching for helpers near you...',
        speechResponseKn: 'ಸಹಾಯಕರನ್ನು ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
      );
    }
    if (_matchesAny(text, ['agaiti', 'aagaiti', 'agaitti', 'khare confirm'])) {
      return LocalRouteResult(
        isHandled: true,
        toolName: 'confirmBooking',
        arguments: pendingBooking ?? const {},
        directAction: 'CONFIRM_BOOKING',
        speechResponseEn: 'Confirmed.',
        speechResponseKn: 'ಖಚಿತಪಡಿಸಲಾಗಿದೆ.',
      );
    }
    if (_matchesAny(text, ['byada', 'byaad', 'beda cancel'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'cancelBooking',
        directAction: 'CANCEL_BOOKING',
        speechResponseEn: 'Booking cancelled.',
        speechResponseKn: 'ಬುಕಿಂಗ್ ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ.',
      );
    }

    // ── NEW: Belagavi Border / Malenadu (Zones 5/7) ───────────────────────────
    if (_matchesAny(text, ['dagada kelasa', 'dagada wala', 'raj mistri beka'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'searchWorkersNearby',
        arguments: {'skillId': 'mason'},
        directAction: 'SEARCH_WORKERS_NEARBY',
        speechResponseEn: 'Searching for masons near you...',
        speechResponseKn: 'ಮೇಸ್ತ್ರಿಗಳನ್ನು ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
      );
    }
    if (_matchesAny(text, ['pahije', 'pahije maaNus'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'searchWorkersNearby',
        arguments: {'skillId': 'helper'},
        directAction: 'SEARCH_WORKERS_NEARBY',
        speechResponseEn: 'Searching for workers near you...',
        speechResponseKn: 'ಕಾರ್ಮಿಕರನ್ನು ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
      );
    }
    // Malenadu: estate / agriculture workers
    if (_matchesAny(text, ['aalu beku', 'aaLu beku', 'thotada aalu', 'katavu aalu', 'estate kelasa', 'coffee tota'])) {
      return const LocalRouteResult(
        isHandled: true,
        toolName: 'searchWorkersNearby',
        arguments: {'skillId': 'agriculture'},
        directAction: 'SEARCH_WORKERS_NEARBY',
        speechResponseEn: 'Searching for agriculture workers near you...',
        speechResponseKn: 'ಕೃಷಿ ಕಾರ್ಮಿಕರನ್ನು ಹತ್ತಿರದಲ್ಲಿ ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
      );
    }

    return LocalRouteResult.unhandled;
  }

  static bool _matches(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text == p || text.startsWith('$p ') || text.endsWith(' $p') || text.contains(' $p ') || text.contains(p)) {
        return true;
      }
    }
    return false;
  }

  // Substring-only match (faster for dialect token checks)
  static bool _matchesAny(String text, List<String> tokens) {
    for (final t in tokens) {
      if (text.contains(t)) return true;
    }
    return false;
  }

  static int? _extractWorkerIndex(String text) {
    if (text.contains('number 1') || text.contains('worker 1') || text.contains('first') || text.contains('1st') ||
        text.contains('ಮೊದಲನೆ') || text.contains('ಒಂದನೆ') || text.contains('ನಂಬರ್ 1') || text.contains('ಕಾರ್ಮಿಕ 1') ||
        text.contains('number one') || text.contains('worker one') || text.contains('select 1') || text == '1' || text == 'one') {
      return 0;
    }
    if (text.contains('number 2') || text.contains('worker 2') || text.contains('second') || text.contains('2nd') ||
        text.contains('ಎರಡನೆ') || text.contains('ನಂಬರ್ 2') || text.contains('ಕಾರ್ಮಿಕ 2') ||
        text.contains('number two') || text.contains('worker two') || text.contains('select 2') || text == '2' || text == 'two') {
      return 1;
    }
    if (text.contains('number 3') || text.contains('worker 3') || text.contains('third') || text.contains('3rd') ||
        text.contains('ಮೂರನೆ') || text.contains('ನಂಬರ್ 3') || text.contains('ಕಾರ್ಮಿಕ 3') ||
        text.contains('number three') || text.contains('worker three') || text.contains('select 3') || text == '3' || text == 'three') {
      return 2;
    }
    return null;
  }
}
