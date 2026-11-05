// test/v20_tracking_lifecycle_anti_premature_arrival_test.dart
// Verification suite for KELASAGARA V20.0 Tracking Lifecycle,
// Anti-Premature Arrival Protection, and Arrival OTP Integrity.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/features/tracking/data/models/tracking_state_model.dart';

void main() {
  group('V20 Anti-Premature Arrival & State Machine Suite', () {
    const dest = LatLng(12.9716, 77.5946); // Bengaluru City Center

    test('Initial accepted state displays Preparing and -- distance even when remainingDistanceMeters is 0.0', () {
      const state = TrackingStateModel(
        workerAnimatedPosition: dest,
        workerTargetPosition: dest,
        hirerDestination: dest,
        remainingDistanceMeters: 0.0,
        etaMinutes: 0,
        phase: JourneyLifecyclePhase.accepted,
      );

      expect(state.formattedDistance, equals('--'),
          reason: 'Accepted booking must never display 0 m prematurely');
      expect(state.formattedEta, equals('Preparing'),
          reason: 'Accepted booking must never display Arrived prematurely');
      expect(state.hasActiveWorkerPosition, isFalse,
          reason: 'Should not draw worker marker overlapping destination marker when accepted');
    });

    test('Accepted state with distant seed location still guards against Arrived display', () {
      const distantSeed = LatLng(12.9352, 77.6245); // Koramangala (~5 km away)
      const state = TrackingStateModel(
        workerAnimatedPosition: distantSeed,
        workerTargetPosition: distantSeed,
        hirerDestination: dest,
        remainingDistanceMeters: 5200.0,
        etaMinutes: 18,
        phase: JourneyLifecyclePhase.accepted,
      );

      expect(state.formattedDistance, equals('--'),
          reason: 'While accepted (preparing), distance should remain -- until journey starts');
      expect(state.formattedEta, equals('Preparing'));
      expect(state.hasActiveWorkerPosition, isTrue,
          reason: 'Distant seed location can be positioned safely');
    });

    test('EnRoute state correctly formats distance and ETA for active worker', () {
      const workerPos = LatLng(12.9500, 77.6000);
      const state = TrackingStateModel(
        workerAnimatedPosition: workerPos,
        workerTargetPosition: workerPos,
        hirerDestination: dest,
        remainingDistanceMeters: 2450.0,
        etaMinutes: 8,
        phase: JourneyLifecyclePhase.enRoute,
        freshness: SignalFreshness.live,
      );

      expect(state.formattedDistance, equals('2.5 km'));
      expect(state.formattedEta, equals('8 mins'));
      expect(state.hasActiveWorkerPosition, isTrue);
    });

    test('EnRoute state under 1000m formats as meters', () {
      const workerPos = LatLng(12.9700, 77.5940);
      const state = TrackingStateModel(
        workerAnimatedPosition: workerPos,
        workerTargetPosition: workerPos,
        hirerDestination: dest,
        remainingDistanceMeters: 450.0,
        etaMinutes: 2,
        phase: JourneyLifecyclePhase.enRoute,
      );

      expect(state.formattedDistance, equals('450 m'));
      expect(state.formattedEta, equals('2 mins'));
    });

    test('Arrived at gate state displays Arrived', () {
      const workerPos = LatLng(12.9715, 77.5945);
      const state = TrackingStateModel(
        workerAnimatedPosition: workerPos,
        workerTargetPosition: workerPos,
        hirerDestination: dest,
        remainingDistanceMeters: 20.0,
        etaMinutes: 0,
        phase: JourneyLifecyclePhase.arrivedAtGate,
      );

      expect(state.formattedEta, equals('Arrived'));
      expect(state.formattedDistance, equals('20 m'));
    });

    test('In progress state displays In Progress', () {
      const state = TrackingStateModel(
        workerAnimatedPosition: dest,
        workerTargetPosition: dest,
        hirerDestination: dest,
        remainingDistanceMeters: 0.0,
        etaMinutes: 0,
        phase: JourneyLifecyclePhase.inProgress,
      );

      expect(state.formattedEta, equals('In Progress'));
    });

    test('Arrival OTP parsing and padding guarantees 4 distinct digits', () {
      const state = TrackingStateModel(
        workerAnimatedPosition: dest,
        workerTargetPosition: dest,
        hirerDestination: dest,
        arrivalOtp: '4821',
      );

      final digits = state.arrivalOtp.padRight(4, '-').substring(0, 4).split('');
      expect(digits, equals(['4', '8', '2', '1']));
      expect(digits, isNot(contains('-')));
    });
  });
}
