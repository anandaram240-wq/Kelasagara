// lib/core/sdui/sdui_engine.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Structured action event emitted from SDUI components back to the Sarvam AI WebSocket pipeline
@immutable
class SduiActionEvent {
  final String actionId;
  final String nodeId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  SduiActionEvent({
    required this.actionId,
    required this.nodeId,
    required this.payload,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'actionId': actionId,
        'nodeId': nodeId,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };
}

typedef SduiActionCallback = void Function(SduiActionEvent event);

typedef SduiWidgetBuilder = Widget Function(
  BuildContext context,
  SduiNode node,
  SduiStateStore stateStore,
  SduiActionCallback onAction,
);

/// Parsed immutable AST Node representing a single Server-Driven UI element
@immutable
class SduiNode {
  final String id;
  final String type;
  final Map<String, dynamic> props;
  final List<SduiNode> children;

  const SduiNode({
    required this.id,
    required this.type,
    required this.props,
    this.children = const [],
  });

  factory SduiNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? const [];
    return SduiNode(
      id: json['id'] as String? ?? UniqueKey().toString(),
      type: json['type'] as String? ?? 'unknown',
      props: (json['props'] as Map?)?.cast<String, dynamic>() ?? const {},
      children: rawChildren
          .whereType<Map>()
          .map((e) => SduiNode.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// Fine-grained reactive store for WebSocket delta patches (e.g., live GPS ticks or counter-offers)
/// Prevents rebuilding the entire SDUI tree on high-frequency stream updates.
class SduiStateStore {
  final Map<String, ValueNotifier<Map<String, dynamic>>> _nodeProps = {};

  ValueListenable<Map<String, dynamic>> watchNode(String nodeId, Map<String, dynamic> initialProps) {
    return _nodeProps.putIfAbsent(
      nodeId,
      () => ValueNotifier<Map<String, dynamic>>(Map<String, dynamic>.from(initialProps)),
    );
  }

  /// Apply partial JSON patch from WebSocket without re-mounting the widget tree
  void applyDeltaPatch(String nodeId, Map<String, dynamic> patch) {
    final notifier = _nodeProps[nodeId];
    if (notifier != null) {
      notifier.value = {...notifier.value, ...patch};
    }
  }

  void dispose() {
    for (final notifier in _nodeProps.values) {
      notifier.dispose();
    }
    _nodeProps.clear();
  }
}

/// Singleton Registry with O(1) builder lookup and recursive layout support
class SduiRegistry {
  static final SduiRegistry instance = SduiRegistry._();
  SduiRegistry._();

  final Map<String, SduiWidgetBuilder> _builders = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  void markInitialized() => _isInitialized = true;

  void register(String type, SduiWidgetBuilder builder) {
    _builders[type] = builder;
  }

  Widget buildNode(
    BuildContext context,
    SduiNode node,
    SduiStateStore stateStore,
    SduiActionCallback onAction,
  ) {
    final builder = _builders[node.type];
    if (builder == null) {
      return const SizedBox.shrink();
    }

    // Wrap each dynamic node in a keyed RepaintBoundary for 120 FPS raster layer isolation
    return RepaintBoundary(
      key: ValueKey<String>('sdui_boundary_${node.id}'),
      child: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: stateStore.watchNode(node.id, node.props),
        builder: (ctx, liveProps, _) {
          final updatedNode = SduiNode(
            id: node.id,
            type: node.type,
            props: liveProps,
            children: node.children,
          );
          return builder(ctx, updatedNode, stateStore, onAction);
        },
      ),
    );
  }
}

/// Fault-tolerant root renderer with error boundary isolation
class SduiRendererView extends StatelessWidget {
  final Map<String, dynamic> schema;
  final SduiStateStore stateStore;
  final SduiActionCallback onAction;

  const SduiRendererView({
    super.key,
    required this.schema,
    required this.stateStore,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final rootNode = SduiNode.fromJson(schema);
      return SduiRegistry.instance.buildNode(context, rootNode, stateStore, onAction);
    } catch (e, stack) {
      debugPrint('SDUI Render Exception: $e\n$stack');
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
            SizedBox(width: 8),
            Text(
              'UI ಸಿಂಕ್ರೊನೈಸೇಷನ್ ದೋಷ (SDUI Fallback)',
              style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
  }
}
