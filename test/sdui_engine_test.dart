// test/sdui_engine_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/core/sdui/sdui_components_registry.dart';
import 'package:kelasagaara/core/sdui/sdui_engine.dart';
import 'package:kelasagaara/screens/voice/sdui_voice_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    registerKelasagaraSduiComponents();
  });

  group('SDUI Protocol & AST Node Parsing Tests', () {
    test('parses basic leaf node from json correctly', () {
      final json = {
        'id': 'card_1',
        'type': 'booking_card',
        'props': {
          'workerId': 'w_101',
          'name': 'ಮಂಜುನಾಥ್ ಆರ್ (Manjunath R)',
          'wage': 750,
        },
      };

      final node = SduiNode.fromJson(json);
      expect(node.id, equals('card_1'));
      expect(node.type, equals('booking_card'));
      expect(node.props['workerId'], equals('w_101'));
      expect(node.props['wage'], equals(750));
      expect(node.children, isEmpty);
    });

    test('parses recursive AST with children containers', () {
      final json = {
        'id': 'col_root',
        'type': 'sdui_column',
        'props': {'spacing': 14.0},
        'children': [
          {
            'id': 'radar_1',
            'type': 'live_radar',
            'props': {'radiusKm': 3.0},
          },
          {
            'id': 'card_1',
            'type': 'booking_card',
            'props': {'name': 'Ramesh'},
          },
        ],
      };

      final root = SduiNode.fromJson(json);
      expect(root.id, equals('col_root'));
      expect(root.type, equals('sdui_column'));
      expect(root.children.length, equals(2));
      expect(root.children[0].type, equals('live_radar'));
      expect(root.children[1].type, equals('booking_card'));
    });

    test('SduiActionEvent serializes to valid JSON envelope', () {
      final event = SduiActionEvent(
        actionId: 'book_worker',
        nodeId: 'card_w_101',
        payload: const {'workerId': 'w_101', 'wage': 750},
      );

      final map = event.toJson();
      expect(map['actionId'], equals('book_worker'));
      expect(map['nodeId'], equals('card_w_101'));
      expect(map['payload']['wage'], equals(750));
      expect(map['timestamp'], isNotEmpty);
    });
  });

  group('SduiStateStore Reactive Delta Patch Tests', () {
    test('applyDeltaPatch updates node props reactively without re-mounting', () {
      final store = SduiStateStore();
      final listenable = store.watchNode('radar_node_1', {'radiusKm': 2.5});

      expect(listenable.value['radiusKm'], equals(2.5));

      // Simulate WebSocket delta patch arriving from backend
      store.applyDeltaPatch('radar_node_1', {'radiusKm': 4.5, 'workersCount': 8});

      expect(listenable.value['radiusKm'], equals(4.5));
      expect(listenable.value['workersCount'], equals(8));

      store.dispose();
    });

    test('separate nodes maintain isolated prop states', () {
      final store = SduiStateStore();
      final nodeA = store.watchNode('node_a', {'val': 10});
      final nodeB = store.watchNode('node_b', {'val': 20});

      store.applyDeltaPatch('node_a', {'val': 15});

      expect(nodeA.value['val'], equals(15));
      expect(nodeB.value['val'], equals(20));

      store.dispose();
    });
  });

  group('SDUI Component Registry & Widget Tests', () {
    testWidgets('renders composite JSON schema (Column + Radar + Carousel + Negotiator)', (tester) async {
      final compositeSchema = {
        'id': 'turn_root_901',
        'type': 'sdui_column',
        'props': {'spacing': 12},
        'children': [
          {
            'id': 'radar_node_1',
            'type': 'live_radar',
            'props': {
              'radiusKm': 2.5,
              'workers': [
                {'workerId': 'w_101', 'distanceKm': 0.8, 'bearingDeg': 35},
                {'workerId': 'w_102', 'distanceKm': 1.4, 'bearingDeg': 160},
              ],
            },
          },
          {
            'id': 'worker_carousel_1',
            'type': 'sdui_carousel',
            'props': {'height': 168},
            'children': [
              {
                'id': 'card_w_101',
                'type': 'booking_card',
                'props': {
                  'workerId': 'w_101',
                  'name': 'ಮಂಜುನಾಥ್ ಆರ್ (Manjunath R)',
                  'skill': 'ಒಳಾಂಗಣ ಪೇಂಟರ್ • Interior Painter',
                  'rating': 4.9,
                  'jobsCompleted': 118,
                  'wage': 750,
                  'wageUnit': 'ದಿನಕ್ಕೆ',
                  'distance': 0.8,
                },
              },
            ],
          },
          {
            'id': 'negotiator_node_1',
            'type': 'wage_negotiator',
            'props': {
              'minWage': 500,
              'maxWage': 1000,
              'defaultWage': 700,
              'workerCounterOffer': 750,
            },
          },
        ],
      };

      final actionsEmitted = <SduiActionEvent>[];
      final deltaStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SduiVoiceMessageCard(
                sduiSchema: compositeSchema,
                onAction: (event) => actionsEmitted.add(event),
                deltaPatchStream: deltaStreamCtrl.stream,
              ),
            ),
          ),
        ),
      );

      // Verify radar rendered
      expect(find.text('ಸಮೀಪದ ಕೆಲಸಗಾರರ ಹುಡುಕಾಟ (Live Radar)'), findsOneWidget);
      expect(find.text('2 workers active within 2.5 km'), findsOneWidget);

      // Verify worker booking card rendered
      expect(find.text('ಮಂಜುನಾಥ್ ಆರ್ (Manjunath R)'), findsOneWidget);
      expect(find.text('₹750/ದಿನಕ್ಕೆ • 0.8 km'), findsOneWidget);

      // Verify wage negotiator rendered
      expect(find.text('ಕೂಲಿ ಮೊತ್ತ ಮಾತುಕತೆ (Wage Negotiation)'), findsOneWidget);
      expect(find.text('Worker Ask: ₹750'), findsOneWidget);

      // Test Booking Action tap
      final bookBtn = find.text('ಈಗ ಬುಕ್ ಮಾಡಿ • Book Now');
      expect(bookBtn, findsOneWidget);
      await tester.tap(bookBtn);
      await tester.pump();

      expect(actionsEmitted.any((e) => e.actionId == 'book_worker'), isTrue);
      expect(actionsEmitted.firstWhere((e) => e.actionId == 'book_worker').payload['workerId'], equals('w_101'));

      // Test WebSocket delta streaming update to radar
      deltaStreamCtrl.add({
        'targetNodeId': 'radar_node_1',
        'patch': {
          'radiusKm': 4.5,
          'workers': [
            {'workerId': 'w_101', 'distanceKm': 0.8, 'bearingDeg': 35},
            {'workerId': 'w_102', 'distanceKm': 1.4, 'bearingDeg': 160},
            {'workerId': 'w_103', 'distanceKm': 3.1, 'bearingDeg': 280},
          ],
        },
      });

      await tester.pump();
      expect(find.text('3 workers active within 4.5 km'), findsOneWidget);

      await deltaStreamCtrl.close();
    });
  });
}
