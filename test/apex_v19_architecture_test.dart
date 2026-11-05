// test/apex_v19_architecture_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/core/performance/apex_native_telemetry.dart';
import 'package:kelasagaara/core/sdui/apex_sdui_stream_controller.dart';
import 'package:kelasagaara/core/sdui/zero_copy_binary_sdui.dart';
import 'package:kelasagaara/widgets/sdui/live_gps_radar_card.dart';

void main() {
  group('Apex v19: Zero-Copy Binary SDUI Protocol Tests', () {
    test('Encodes and decodes flat binary wire frame with bitmask flags and UTF-8 strings', () {
      final Uint8List rawFrame = SduiBinaryView.encodeFrame(
        cardType: 1,
        distanceKm: 2.45,
        rating: 4.85,
        hourlyWageInr: 650,
        workerNorthMeters: 142.5,
        workerEastMeters: -95.0,
        isAvailable: true,
        isFaceRdVerified: true,
        workerId: 'WKR-994',
        workerName: 'ರಮೇಶ್ ಗೌಡ (Ramesh Gowda)',
        skillTitle: 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್ • Master Electrician',
      );

      final SduiBinaryView view = SduiBinaryView(rawFrame);

      expect(view.cardType, equals(1));
      expect(view.distanceKm, closeTo(2.45, 0.001));
      expect(view.rating, closeTo(4.85, 0.001));
      expect(view.hourlyWageInr, equals(650));
      expect(view.workerNorthMeters, closeTo(142.5, 0.001));
      expect(view.workerEastMeters, closeTo(-95.0, 0.001));
      expect(view.isAvailable, isTrue);
      expect(view.isFaceRdVerified, isTrue);

      final (String id, String name, String skill) = view.decodeStrings();
      expect(id, equals('WKR-994'));
      expect(name, equals('ರಮೇಶ್ ಗೌಡ (Ramesh Gowda)'));
      expect(skill, equals('ಎಲೆಕ್ಟ್ರಿಷಿಯನ್ • Master Electrician'));
    });

    test('Validates bitmask flags when worker is unavailable and unverified', () {
      final Uint8List rawFrame = SduiBinaryView.encodeFrame(
        cardType: 2,
        distanceKm: 5.0,
        rating: 4.0,
        hourlyWageInr: 400,
        workerNorthMeters: 0.0,
        workerEastMeters: 0.0,
        isAvailable: false,
        isFaceRdVerified: false,
        workerId: 'WKR-101',
        workerName: 'ಸುರೇಶ್ (Suresh)',
        skillTitle: 'ಕಾರ್ಪೆಂಟರ್ • Carpenter',
      );

      final SduiBinaryView view = SduiBinaryView(rawFrame);
      expect(view.isAvailable, isFalse);
      expect(view.isFaceRdVerified, isFalse);
    });
  });

  group('Apex v19: 120Hz 2D Kinematic Kalman Filter Tests', () {
    test('Dead-reckons worker position based on velocity and dt', () {
      final filter = WorkerKinematicKalmanFilter(
        px: 100.0,
        py: 100.0,
        vx: -2.0,
        vy: -2.0,
      );

      expect(filter.distanceMeters, closeTo(141.42, 0.1));

      // Advance 1 second at 120Hz (120 steps of ~0.00833s)
      const double dt = 1.0 / 120.0;
      for (int i = 0; i < 120; i++) {
        filter.predict(dt);
      }

      // After 1 sec at -2m/s, position should be near (98.0, 98.0)
      expect(filter.px, closeTo(98.0, 0.05));
      expect(filter.py, closeTo(98.0, 0.05));
      expect(filter.distanceMeters, closeTo(138.59, 0.1));
      expect(filter.speedMetersPerSec, closeTo(2.828, 0.05));
    });

    test('Kalman measurement update smoothly corrects position residual', () {
      final filter = WorkerKinematicKalmanFilter(
        px: 50.0,
        py: 50.0,
        vx: 0.0,
        vy: 0.0,
      );

      // GPS ping arrives indicating position is actually (45.0, 48.0)
      filter.updateMeasurement(45.0, 48.0, 1.0);

      // Position should move toward measurement weighted by Kalman gain
      expect(filter.px, lessThan(50.0));
      expect(filter.px, greaterThan(45.0));
      expect(filter.py, lessThan(50.0));
      expect(filter.py, greaterThan(48.0));
    });
  });

  group('Apex v19: Full-Duplex SDUI Stream Controller Tests', () {
    test('Seeds voice turn cards and handles optimistic instant booking with verbal stream sync', () async {
      final controller = ApexSduiStreamController();

      controller.seedVoiceTurnCards(
        workerId: 'WKR-555',
        workerName: 'ಮಂಜುನಾಥ್ ಆರ್. (Manjunath R.)',
        skillTitle: 'ಪ್ಲಂಬರ್ • Master Plumber',
        distanceKm: 1.8,
        baseWageInr: 500,
      );

      expect(controller.binaryCards.length, equals(2));

      // Check card 0 (BookingCard)
      final widget0 = controller.buildBinaryCardAt(0);
      expect(widget0, isA<DirectCanvasBookingCard>());

      // Check card 1 (LiveGpsRadarCard)
      final widget1 = controller.buildBinaryCardAt(1);
      expect(widget1, isA<LiveGpsRadarSduiCard>());

      // Listen for bi-directional verbal feedback
      String? receivedFeedback;
      final sub = controller.voiceFeedbackStream.listen((msg) {
        receivedFeedback = msg;
      });

      // Simulate instant booking callback
      final DirectCanvasBookingCard bookingCard = widget0 as DirectCanvasBookingCard;
      bookingCard.onBookTap();

      await pumpEventQueue();

      expect(receivedFeedback, contains('ಮಂಜುನಾಥ್ ಆರ್. (Manjunath R.)'));
      expect(receivedFeedback, contains('₹500'));
      expect(receivedFeedback, contains('ಲೈವ್ ಜಿಪಿಎಸ್ ರಾಡಾರ್ ಸಕ್ರಿಯವಾಗಿದೆ'));

      // Re-building card 0 should now reflect isBooked = true
      final widget0Updated = controller.buildBinaryCardAt(0) as DirectCanvasBookingCard;
      expect(widget0Updated.isBooked, isTrue);

      await sub.cancel();
      controller.dispose();
    });
  });

  group('Apex v19: Hardware Bridge Fallback Tests', () {
    test('Initializes safely on non-Android platform in pure-Dart fallback mode', () {
      final bridge = ApexHardwareBridge.instance;
      expect(bridge.registers.length, equals(12));
      expect(bridge.rms, equals(0.0));
      expect(bridge.spectralCentroid, equals(0.0));
      expect(bridge.isHumanSpeechActive, isFalse);
      expect(bridge.consumeHardwareBargeIn(), isFalse);

      bridge.setAssistantSpeaking(true);
      bridge.setAssistantSpeaking(false);
    });
  });
}
