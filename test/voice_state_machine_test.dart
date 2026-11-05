// test/voice_state_machine_test.dart
// Automated Unit Tests for the 16-State Voice Session State Machine & Transition Matrix

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/voice_session_state.dart';

void main() {
  group('VoiceStateMachine 16-State Transition Matrix Tests', () {
    test('State machine initializes to idle', () {
      final sm = VoiceStateMachine();
      expect(sm.current, equals(VoiceSessionState.idle));
    });

    test('Legal standard conversational loop transitions', () {
      final sm = VoiceStateMachine();

      // idle -> listening
      expect(sm.transition(VoiceSessionState.listening), isTrue);
      expect(sm.current, equals(VoiceSessionState.listening));

      // listening -> userSpeaking
      expect(sm.transition(VoiceSessionState.userSpeaking), isTrue);
      expect(sm.current, equals(VoiceSessionState.userSpeaking));

      // userSpeaking -> transcribing
      expect(sm.transition(VoiceSessionState.transcribing), isTrue);
      expect(sm.current, equals(VoiceSessionState.transcribing));

      // transcribing -> understanding
      expect(sm.transition(VoiceSessionState.understanding), isTrue);
      expect(sm.current, equals(VoiceSessionState.understanding));

      // understanding -> toolRequested
      expect(sm.transition(VoiceSessionState.toolRequested), isTrue);
      expect(sm.current, equals(VoiceSessionState.toolRequested));

      // toolRequested -> toolValidating
      expect(sm.transition(VoiceSessionState.toolValidating), isTrue);
      expect(sm.current, equals(VoiceSessionState.toolValidating));

      // toolValidating -> executing
      expect(sm.transition(VoiceSessionState.executing), isTrue);
      expect(sm.current, equals(VoiceSessionState.executing));

      // executing -> responding
      expect(sm.transition(VoiceSessionState.responding), isTrue);
      expect(sm.current, equals(VoiceSessionState.responding));

      // responding -> speaking
      expect(sm.transition(VoiceSessionState.speaking), isTrue);
      expect(sm.current, equals(VoiceSessionState.speaking));

      // speaking -> idle
      expect(sm.transition(VoiceSessionState.idle), isTrue);
      expect(sm.current, equals(VoiceSessionState.idle));
    });

    test('Legal barge-in / interruption transition: speaking -> interrupted -> listening', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.speaking);
      expect(sm.transition(VoiceSessionState.interrupted), isTrue);
      expect(sm.current, equals(VoiceSessionState.interrupted));

      expect(sm.transition(VoiceSessionState.listening), isTrue);
      expect(sm.current, equals(VoiceSessionState.listening));
    });

    test('Legal high-risk confirmation transition: toolValidating -> waitingConfirmation -> executing', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.toolValidating);
      expect(sm.transition(VoiceSessionState.waitingConfirmation), isTrue);
      expect(sm.current, equals(VoiceSessionState.waitingConfirmation));

      expect(sm.transition(VoiceSessionState.executing), isTrue);
      expect(sm.current, equals(VoiceSessionState.executing));
    });

    test('Legal decline transition: waitingConfirmation -> cancelled -> idle', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.waitingConfirmation);
      expect(sm.transition(VoiceSessionState.cancelled), isTrue);
      expect(sm.current, equals(VoiceSessionState.cancelled));

      expect(sm.transition(VoiceSessionState.idle), isTrue);
      expect(sm.current, equals(VoiceSessionState.idle));
    });

    test('ILLEGAL transition: idle -> executing directly (MUST BE REJECTED)', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.idle);
      expect(sm.transition(VoiceSessionState.executing), isFalse);
      expect(sm.current, equals(VoiceSessionState.idle));
    });

    test('ILLEGAL transition: closed -> speaking (MUST BE REJECTED)', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.closed);
      expect(sm.transition(VoiceSessionState.speaking), isFalse);
      expect(sm.current, equals(VoiceSessionState.closed));
    });

    test('Self-transition is always legal', () {
      final sm = VoiceStateMachine(initialState: VoiceSessionState.listening);
      expect(sm.transition(VoiceSessionState.listening), isTrue);
      expect(sm.current, equals(VoiceSessionState.listening));
    });
  });
}
