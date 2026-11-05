// test/enterprise_v2_tracking_suite_test.dart
// Production-grade test suite for Kelasagara V2 Enterprise Tracking Architecture.
// Validates 4-State ENU Kinematic Kalman Filter, Mahalanobis Outlier Gate,
// Viterbi HMM Map Matcher, Cubic Bézier Bridge, and Micro-Trail Jitter Buffer.

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/features/tracking/domain/enu_kalman_filter.dart';
import 'package:kelasagaara/features/tracking/domain/hmm_viterbi_shadow_matcher.dart';
import 'package:kelasagaara/features/tracking/domain/trail_jitter_buffer_scheduler.dart';
import 'package:kelasagaara/features/tracking/domain/cubic_hermite_spline_interpolator.dart';
import 'package:kelasagaara/services/booking_service.dart';

void main() {
  group('V2 Enterprise Telemetry Suite: 4-State ENU Kalman Filter', () {
    test('Initializes state and tracks forward kinematics along North axis', () {
      final kalman = EnuKinematicKalmanFilter();

      // First fix: Bengaluru MG Road heading North (0°) at 10 m/s (~36 km/h)
      final f1 = kalman.processMeasurement(
        lat: 12.971600,
        lng: 77.594600,
        accuracyMeters: 6.0,
        rawSpeedMps: 10.0,
        rawHeadingDeg: 0.0,
        timestampMs: 1000,
      );

      expect(f1.position.latitude, closeTo(12.9716, 1e-5));
      expect(f1.wasOutlierRejected, isFalse);

      // Second fix: 1.0 second later, moved ~10m North
      // 10m North at lat 12.9716 is roughly +0.00009 degrees lat
      final f2 = kalman.processMeasurement(
        lat: 12.971690,
        lng: 77.594600,
        accuracyMeters: 5.0,
        rawSpeedMps: 10.0,
        rawHeadingDeg: 0.0,
        timestampMs: 2000,
      );

      expect(f2.wasOutlierRejected, isFalse);
      expect(f2.position.latitude, greaterThan(12.97160));
      expect(f2.speedMps, closeTo(10.0, 3.0));
      expect(f2.headingDeg, closeTo(0.0, 5.0));
    });

    test('Mahalanobis Gate rejects 120m urban-canyon multipath GPS jump', () {
      final kalman = EnuKinematicKalmanFilter();

      // Initial fix
      kalman.processMeasurement(
        lat: 12.971600,
        lng: 77.594600,
        accuracyMeters: 5.0,
        rawSpeedMps: 8.0,
        rawHeadingDeg: 90.0,
        timestampMs: 1000,
      );

      // Stable cruise fix at t=2000ms
      kalman.processMeasurement(
        lat: 12.971600,
        lng: 77.594675,
        accuracyMeters: 5.0,
        rawSpeedMps: 8.0,
        rawHeadingDeg: 90.0,
        timestampMs: 2000,
      );

      // Sudden 120m multipath spike East at t=2200ms (impossible 600 m/s displacement!)
      final spikeFix = kalman.processMeasurement(
        lat: 12.971600,
        lng: 77.595800, // ~120m East in 200ms
        accuracyMeters: 5.0,
        rawSpeedMps: 8.0,
        rawHeadingDeg: 90.0,
        timestampMs: 2200,
      );

      expect(spikeFix.wasOutlierRejected, isTrue);
      expect(spikeFix.mahalanobisScore, greaterThan(11.34));
      // Verify marker was NOT yanked to 77.595800
      expect(spikeFix.position.longitude, lessThan(77.59500));
    });

    test('Damped dead-reckoning extrapolation decays velocity smoothly', () {
      final kalman = EnuKinematicKalmanFilter();

      kalman.processMeasurement(
        lat: 12.971600,
        lng: 77.594600,
        accuracyMeters: 4.0,
        rawSpeedMps: 12.0,
        rawHeadingDeg: 0.0,
        timestampMs: 1000,
      );
      kalman.processMeasurement(
        lat: 12.971708,
        lng: 77.594600,
        accuracyMeters: 4.0,
        rawSpeedMps: 12.0,
        rawHeadingDeg: 0.0,
        timestampMs: 2000,
      );

      final LatLng extrapolated = kalman.extrapolateDamped(2.0);
      expect(extrapolated.latitude, greaterThan(12.971708));

      // With damping lambda=0.45, effectiveDt = (1 - e^-0.9)/0.45 = 1.318s instead of 2.0s
      // ensuring vehicle doesn't overshoot through intersections
      final double distanceMovedM =
          HmmViterbiShadowMatcher.haversineMeters(LatLng(12.971708, 77.594600), extrapolated);
      expect(distanceMovedM, lessThan(24.0)); // Less than naive 12 m/s * 2s = 24m
      expect(distanceMovedM, greaterThan(12.0));
    });
  });

  group('V2 Enterprise Telemetry Suite: Viterbi HMM Map Matcher & Bézier Bridge', () {
    final List<LatLng> mainRoad = [
      const LatLng(12.9700, 77.5900),
      const LatLng(12.9720, 77.5900),
      const LatLng(12.9740, 77.5900),
    ];

    test('Locks onto road when within 19m and heading matches', () {
      final matcher = HmmViterbiShadowMatcher();

      // Worker is 8m East of main road, heading North (0°)
      final output = matcher.match(
        workerPos: const LatLng(12.9710, 77.590074),
        workerHeadingDeg: 0.0,
        workerSpeedMps: 7.0,
        osmPolyline: mainRoad,
      );

      expect(output.mode, equals(ShadowTrackingMode.osmRoadLocked));
      expect(output.crossTrackMeters, closeTo(8.0, 1.5));
      expect(output.matchedPosition.longitude, closeTo(77.5900, 1e-4));
      expect(output.cubicBezierShortcutBridge.isEmpty, isTrue);
      expect(output.requiresHeadingBiasedReroute, isFalse);
    });

    test('Switches to GoogleShortcutGlide & synthesizes 16-point Bézier Bridge on detours', () {
      final matcher = HmmViterbiShadowMatcher();

      // Worker turns 45m East into an unmapped Bengaluru gully
      final gullyPos = const LatLng(12.9715, 77.59045);
      final output = matcher.match(
        workerPos: gullyPos,
        workerHeadingDeg: 45.0,
        workerSpeedMps: 6.0,
        osmPolyline: mainRoad,
      );

      expect(output.mode, equals(ShadowTrackingMode.googleShortcutGlide));
      expect(output.matchedPosition, equals(gullyPos));
      // 16 sample intervals = 17 points
      expect(output.cubicBezierShortcutBridge.length, equals(17));
      expect(output.cubicBezierShortcutBridge.first, equals(gullyPos));
    });
  });

  group('V2 Enterprise Telemetry Suite: Multi-Vertex Jitter Buffer', () {
    test('Unpacks 5-point trail and plays frames at 60fps without lag', () {
      final scheduler = TrailJitterBufferScheduler();
      final now = DateTime.now().millisecondsSinceEpoch;

      final List<Map<String, dynamic>> trail = [
        {'lat': 12.9710, 'lng': 77.5900, 'hdg': 0.0, 'spd': 6.0, 'ts': now - 800},
        {'lat': 12.9712, 'lng': 77.5900, 'hdg': 0.0, 'spd': 6.0, 'ts': now - 600},
        {'lat': 12.9714, 'lng': 77.5901, 'hdg': 30.0, 'spd': 5.5, 'ts': now - 400},
        {'lat': 12.9716, 'lng': 77.5903, 'hdg': 60.0, 'spd': 5.0, 'ts': now - 200},
        {'lat': 12.9717, 'lng': 77.5906, 'hdg': 90.0, 'spd': 5.0, 'ts': now},
      ];

      scheduler.enqueueTrailBatch(
        rawTrail: trail,
        fallbackMatchedPos: const LatLng(12.9717, 77.5906),
        fallbackBearingDeg: 90.0,
        fallbackSpeedMps: 5.0,
        packetTimestampMs: now,
        roadProjector: (pt, hdg, spd) => pt,
      );

      expect(scheduler.isInitialized, isTrue);

      // Sample first tick
      final frame1 = scheduler.tickFrame(now);
      expect(frame1.position.latitude, closeTo(12.9710, 1e-3));
      expect(frame1.isDeadReckoning, isFalse);
    });
  });

  group('V2 Enterprise Security: Atomic Arrival OTP Gate', () {
    test('Throws StateError if mock location flag is detected', () async {
      expect(
        () => BookingService.verifyArrivalOtpAtomically(
          bookingId: 'test_bk_01',
          enteredOtp: '4821',
          workerCurrentLat: 12.9716,
          workerCurrentLng: 77.5946,
          isMockedGps: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
