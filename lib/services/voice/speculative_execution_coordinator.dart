// lib/services/voice/speculative_execution_coordinator.dart
// Realtime Safe Speculative Search Execution Coordinator for Kelasagara Voice

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'regional_kannada_normalizer.dart';
import 'voice_tool_registry.dart';

class SpeculativeResult {
  final String skillId;
  final String query;
  final DateTime startTime;
  final Future<Map<String, dynamic>> future;

  const SpeculativeResult({
    required this.skillId,
    required this.query,
    required this.startTime,
    required this.future,
  });

  bool get isConsequential => false;
}

class SpeculativeExecutionCoordinator {
  final VoiceToolRegistry toolRegistry;
  int _currentGeneration = 0;
  String? _activeSkill;
  SpeculativeResult? _activeResult;

  SpeculativeExecutionCoordinator({VoiceToolRegistry? registry})
      : toolRegistry = registry ?? VoiceToolRegistry();

  int get currentGeneration => _currentGeneration;
  SpeculativeResult? get activeResult => _activeResult;

  /// Resets speculative state for a new turn/utterance
  void newUtterance() {
    _currentGeneration++;
    _activeSkill = null;
    _activeResult = null;
  }

  /// Inspect partial speech transcript and start SAFE speculative candidate retrieval
  SpeculativeResult? onPartialTranscript(String partialText) {
    final text = partialText.trim();
    if (text.length < 3) return null;

    // Consequential action guard: Consequential actions (booking, cancelling, messaging) are strictly blocked from speculative execution
    final lower = text.toLowerCase();
    if (lower.contains('book') || lower.contains('ಬುಕ್') ||
        lower.contains('cancel') || lower.contains('ರದ್ದು') ||
        lower.contains('pay') || lower.contains('ಹಣ')) {
      return null;
    }

    // Detect skill and search intent from partial text
    final detectedSkill = _detectSkill(text);
    if (detectedSkill == null) return null;

    // If already speculating for this skill in current generation, return active
    if (_activeSkill == detectedSkill && _activeResult != null) {
      return _activeResult;
    }

    _activeSkill = detectedSkill;
    final generation = _currentGeneration;
    final startTime = DateTime.now();

    debugPrint('[Speculative] ⚡ Starting SAFE speculative search for "$detectedSkill" from partial: "$text" (Gen $generation)');

    final future = () async {
      final res = await toolRegistry.searchWorkersNearby({
        'skillId': detectedSkill,
      });

      // Verify generation has not expired while search was in flight
      if (generation != _currentGeneration) {
        debugPrint('[Speculative] ⚠️ Discarding stale speculative result for Gen $generation (Current: $_currentGeneration)');
        return {'success': false, 'stale': true};
      }
      return res;
    }();

    _activeResult = SpeculativeResult(
      skillId: detectedSkill,
      query: text,
      startTime: startTime,
      future: future,
    );

    return _activeResult;
  }

  /// Match candidate skill against lexicon
  String? _detectSkill(String text) {
    final lower = text.toLowerCase();
    for (final entry in KelasagaraKannadaDomainLexicon.skillSynonyms.entries) {
      for (final synonym in entry.value) {
        if (lower.contains(synonym.toLowerCase())) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Retrieve speculative result if it matches final validated skill
  Future<Map<String, dynamic>?> claimSpeculativeResult(String finalSkill) async {
    if (_activeResult == null || _activeSkill != finalSkill) {
      return null;
    }
    try {
      final res = await _activeResult!.future;
      if (res['stale'] == true) return null;
      debugPrint('[Speculative] ✅ Claimed ready speculative result for $finalSkill '
          '(Elapsed: ${DateTime.now().difference(_activeResult!.startTime).inMilliseconds}ms)');
      return res;
    } catch (e) {
      debugPrint('[Speculative] Speculative search failed: $e');
      return null;
    }
  }

  void cancel() {
    _currentGeneration++;
    _activeSkill = null;
    _activeResult = null;
  }
}
