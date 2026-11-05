// lib/models/voice_session_state.dart
// Kelasagara Voice AI V70 — 16-State Formal Voice Session State Machine

import 'package:flutter/foundation.dart';

/// 16 Explicit Discrete States of the Kelasagara Voice Session
enum VoiceSessionState {
  idle,
  listening,
  userSpeaking,
  transcribing,
  understanding,
  toolRequested,
  toolValidating,
  waitingConfirmation,
  executing,
  responding,
  speaking,
  interrupted,
  retrying,
  error,
  cancelled,
  closed;

  String get displayName => switch (this) {
    idle                => 'Idle',
    listening           => 'Listening',
    userSpeaking        => 'User Speaking',
    transcribing        => 'Transcribing',
    understanding       => 'Understanding',
    toolRequested       => 'Tool Requested',
    toolValidating      => 'Validating Tool',
    waitingConfirmation => 'Waiting for Confirmation',
    executing           => 'Executing Action',
    responding          => 'Generating Response',
    speaking            => 'Assistant Speaking',
    interrupted         => 'Interrupted (Barge-In)',
    retrying            => 'Retrying',
    error               => 'Error',
    cancelled           => 'Cancelled',
    closed              => 'Closed',
  };

  String get kannadaDisplayName => switch (this) {
    idle                => 'ಸಿದ್ಧವಾಗಿದೆ',
    listening           => 'ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ...',
    userSpeaking        => 'ನೀವು ಮಾತನಾಡುತ್ತಿದ್ದೀರಿ...',
    transcribing        => 'ಪಠ್ಯಕ್ಕೆ ಪರಿವರ್ತಿಸಲಾಗುತ್ತಿದೆ...',
    understanding       => 'ಆದೇಶ ಅರ್ಥಮಾಡಿಕೊಳ್ಳಲಾಗುತ್ತಿದೆ...',
    toolRequested       => 'ಕಾರ್ಯ ಕೋರಲಾಗಿದೆ...',
    toolValidating      => 'ದೃಢೀಕರಿಸಲಾಗುತ್ತಿದೆ...',
    waitingConfirmation => 'ನಿಮ್ಮ ಒಪ್ಪಿಗೆಗಾಗಿ ಕಾಯಲಾಗುತ್ತಿದೆ...',
    executing           => 'ಕಾರ್ಯಗತಗೊಳಿಸಲಾಗುತ್ತಿದೆ...',
    responding          => 'ಉತ್ತರ ಸಿದ್ಧಪಡಿಸಲಾಗುತ್ತಿದೆ...',
    speaking            => 'ಸಹಾಯಕ ಮಾತನಾಡುತ್ತಿದ್ದಾನೆ...',
    interrupted         => 'ಮಧ್ಯಪ್ರವೇಶಿಸಲಾಗಿದೆ',
    retrying            => 'ಮರುಪ್ರಯತ್ನಿಸಲಾಗುತ್ತಿದೆ...',
    error               => 'ದೋಷ ಸಂಭವಿಸಿದೆ',
    cancelled           => 'ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ',
    closed              => 'ಮುಕ್ತಾಯಗೊಂಡಿದೆ',
  };
}

/// Formal State Machine for Voice Session Transitions
class VoiceStateMachine {
  VoiceSessionState _current;
  final ValueChanged<VoiceSessionState>? onStateChanged;

  VoiceStateMachine({
    VoiceSessionState initialState = VoiceSessionState.idle,
    this.onStateChanged,
  }) : _current = initialState;

  VoiceSessionState get current => _current;

  /// Deterministic Legal Transition Matrix
  static const Map<VoiceSessionState, Set<VoiceSessionState>> _allowedTransitions = {
    VoiceSessionState.idle: {
      VoiceSessionState.listening,
      VoiceSessionState.closed,
    },
    VoiceSessionState.listening: {
      VoiceSessionState.userSpeaking,
      VoiceSessionState.transcribing,
      VoiceSessionState.idle,
      VoiceSessionState.interrupted,
      VoiceSessionState.error,
      VoiceSessionState.closed,
    },
    VoiceSessionState.userSpeaking: {
      VoiceSessionState.transcribing,
      VoiceSessionState.understanding,
      VoiceSessionState.interrupted,
      VoiceSessionState.listening,
      VoiceSessionState.error,
      VoiceSessionState.closed,
    },
    VoiceSessionState.transcribing: {
      VoiceSessionState.understanding,
      VoiceSessionState.responding,
      VoiceSessionState.interrupted,
      VoiceSessionState.listening,
      VoiceSessionState.error,
    },
    VoiceSessionState.understanding: {
      VoiceSessionState.toolRequested,
      VoiceSessionState.responding,
      VoiceSessionState.interrupted,
      VoiceSessionState.listening,
      VoiceSessionState.error,
    },
    VoiceSessionState.toolRequested: {
      VoiceSessionState.toolValidating,
      VoiceSessionState.interrupted,
      VoiceSessionState.error,
      VoiceSessionState.cancelled,
    },
    VoiceSessionState.toolValidating: {
      VoiceSessionState.waitingConfirmation,
      VoiceSessionState.executing,
      VoiceSessionState.error,
      VoiceSessionState.cancelled,
      VoiceSessionState.interrupted,
    },
    VoiceSessionState.waitingConfirmation: {
      VoiceSessionState.executing,
      VoiceSessionState.cancelled,
      VoiceSessionState.listening,
      VoiceSessionState.speaking,
      VoiceSessionState.interrupted,
      VoiceSessionState.error,
    },
    VoiceSessionState.executing: {
      VoiceSessionState.responding,
      VoiceSessionState.retrying,
      VoiceSessionState.error,
      VoiceSessionState.cancelled,
    },
    VoiceSessionState.responding: {
      VoiceSessionState.speaking,
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
    VoiceSessionState.speaking: {
      VoiceSessionState.listening,
      VoiceSessionState.interrupted,
      VoiceSessionState.idle,
      VoiceSessionState.closed,
      VoiceSessionState.error,
    },
    VoiceSessionState.interrupted: {
      VoiceSessionState.listening,
      VoiceSessionState.userSpeaking,
      VoiceSessionState.idle,
    },
    VoiceSessionState.retrying: {
      VoiceSessionState.executing,
      VoiceSessionState.error,
      VoiceSessionState.idle,
    },
    VoiceSessionState.error: {
      VoiceSessionState.idle,
      VoiceSessionState.listening,
      VoiceSessionState.closed,
    },
    VoiceSessionState.cancelled: {
      VoiceSessionState.idle,
      VoiceSessionState.listening,
      VoiceSessionState.closed,
    },
    VoiceSessionState.closed: {
      VoiceSessionState.idle,
    },
  };

  /// Checks if a transition from `from` to `to` is legally permitted
  static bool canTransition(VoiceSessionState from, VoiceSessionState to) {
    if (from == to) return true; // Self transition is always legal
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  /// Attempts transition to `next`. Returns true if successful, false if rejected.
  bool transition(VoiceSessionState next) {
    if (!canTransition(_current, next)) {
      debugPrint('[VoiceStateMachine] REJECTED illegal transition: $_current -> $next');
      return false;
    }
    final prev = _current;
    _current = next;
    if (prev != next) {
      onStateChanged?.call(_current);
    }
    return true;
  }

  /// Force transition for fatal error handling or shutdown
  void force(VoiceSessionState state) {
    _current = state;
    onStateChanged?.call(_current);
  }
}

/// Domain Event Log for Voice Session Observability
class VoiceSessionEvent {
  final DateTime timestamp;
  final VoiceSessionState state;
  final String eventType;
  final Map<String, dynamic>? data;

  VoiceSessionEvent({
    required this.state,
    required this.eventType,
    this.data,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'state': state.name,
    'eventType': eventType,
    if (data != null) 'data': data,
  };
}
