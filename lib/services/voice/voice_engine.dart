// lib/services/voice/voice_engine.dart
// Clean Abstract Interface for Realtime Voice Engines in Kelasagara

import 'dart:async';
import 'package:flutter/foundation.dart';

enum VoiceEngineEventType {
  sessionStarted,
  speechStarted,
  partialTranscript,
  finalTranscript,
  speculativeTriggered,
  toolRequested,
  toolExecuted,
  responseStarted,
  audioChunk,
  interrupted,
  generationComplete,
  error,
  sessionEnded,
}

class VoiceEngineEvent {
  final VoiceEngineEventType type;
  final String? text;
  final double? confidence;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final Map<String, dynamic>? toolResult;
  final Uint8List? audioData;
  final String? errorMessage;
  final String? errorCode;
  final DateTime timestamp;

  VoiceEngineEvent({
    required this.type,
    this.text,
    this.confidence,
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.audioData,
    this.errorMessage,
    this.errorCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'VoiceEngineEvent($type, text: $text, tool: $toolName, err: $errorMessage)';
}

/// Abstract contract for all Voice Engine implementations (Sarvam, Gemini Live, Mock)
abstract class VoiceEngine {
  String get providerName;
  bool get isSessionActive;
  bool get isSpeaking;

  Stream<VoiceEngineEvent> get events;

  Future<bool> initialize();
  Future<void> startSession({String languageCode = 'kn-IN'});
  Future<void> stopSession();
  Future<void> interrupt();
  Future<void> reconnect();
  Future<void> dispose();

  /// Feed audio frame to the engine (PCM 16-bit, 16kHz mono)
  void sendAudio(Uint8List audioPcm);

  /// Allows direct transcript injection for testing or fallback
  void feedTranscript(String text, {bool isFinal = true});
}
