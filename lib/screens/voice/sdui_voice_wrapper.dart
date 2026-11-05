// lib/screens/voice/sdui_voice_wrapper.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/sdui/sdui_components_registry.dart';
import '../../core/sdui/sdui_engine.dart';

class SduiVoiceMessageCard extends StatefulWidget {
  final Map<String, dynamic> sduiSchema;
  final SduiActionCallback onAction;
  final Stream<Map<String, dynamic>>? deltaPatchStream;

  const SduiVoiceMessageCard({
    super.key,
    required this.sduiSchema,
    required this.onAction,
    this.deltaPatchStream,
  });

  @override
  State<SduiVoiceMessageCard> createState() => _SduiVoiceMessageCardState();
}

class _SduiVoiceMessageCardState extends State<SduiVoiceMessageCard> {
  late final SduiStateStore _stateStore;
  StreamSubscription<Map<String, dynamic>>? _deltaSub;

  @override
  void initState() {
    super.initState();
    // Register components once outside build()
    registerKelasagaraSduiComponents();
    _stateStore = SduiStateStore();

    // Listen for live WebSocket patches (e.g., {"targetNodeId": "radar_1", "patch": {...}})
    _deltaSub = widget.deltaPatchStream?.listen((deltaEvent) {
      final String? targetId = deltaEvent['targetNodeId'] as String?;
      final Map<String, dynamic>? patch =
          (deltaEvent['patch'] as Map?)?.cast<String, dynamic>();
      if (targetId != null && patch != null && mounted) {
        _stateStore.applyDeltaPatch(targetId, patch);
      }
    });
  }

  @override
  void dispose() {
    _deltaSub?.cancel();
    _stateStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SduiRendererView(
          schema: widget.sduiSchema,
          stateStore: _stateStore,
          onAction: widget.onAction,
        ),
      ),
    );
  }
}
