// test/phase6_navigation_platform_test.dart
//
// KELASAGARA PHASE 6 — ADVANCED PRODUCTION NAVIGATION & ROUTING PLATFORM TEST SUITE
//
// Tests comprehensive navigation engine mechanics, destination authorization gates,
// GPS quality engine classification, off-route detection, auto-rerouting versioning,
// arrival candidate stability, and session lifecycle teardown.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';
import 'package:kelasagaara/services/routing/gps_quality_engine.dart';
import 'package:kelasagaara/screens/tracking/journey_navigator.dart';
import 'package:kelasagaara/services/routing/osrm_route_provider.dart';
import 'package:kelasagaara/services/navigation_engine.dart';
import 'package:kelasagaara/models/journey_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 6 — Section 1: GPS Quality Engine & Hardware Validation', () {
    late GpsQualityEngine engine;

    setUp(() {
      engine = GpsQualityEngine.instance;
      engine.reset();
    });

    test('valid GPS fix within Karnataka produces GOOD or LIVE classification', () {
      final pos = Position(
        latitude: 13.0068,
        longitude: 76.0996,
        timestamp: DateTime.now(),
        accuracy: 8.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 45.0,
        headingAccuracy: 5.0,
        speed: 8.5, // ~30.6 km/h
        speedAccuracy: 1.0,
      );

      final classified = engine.classify(pos);
      expect(classified.isUsable, isTrue);
      expect(
        classified.classification == GpsClassification.GOOD ||
            classified.classification == GpsClassification.LIVE,
        isTrue,
      );
    });

    test('rejects zero or out-of-bounds coordinates as INVALID', () {
      final zeroPos = Position(
        latitude: 0.0,
        longitude: 0.0,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      final classifiedZero = engine.classify(zeroPos);
      expect(classifiedZero.isUsable, isFalse);
      expect(classifiedZero.classification, GpsClassification.INVALID);

      final outOfBoundsPos = Position(
        latitude: 95.0, // Invalid latitude > 90
        longitude: 76.0,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      final classifiedOob = engine.classify(outOfBoundsPos);
      expect(classifiedOob.isUsable, isFalse);
      expect(classifiedOob.classification, GpsClassification.INVALID);
    });

    test('flags fixes with accuracy 50-100m as LOW_ACCURACY', () {
      final lowAccPos = Position(
        latitude: 13.0068,
        longitude: 76.0996,
        timestamp: DateTime.now(),
        accuracy: 75.0, // 50m - 100m is LOW_ACCURACY
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 5.0,
        speedAccuracy: 1.0,
      );

      final classified = engine.classify(lowAccPos);
      expect(classified.classification, GpsClassification.LOW_ACCURACY);
    });

    test('detects impossible teleports as GPS_JUMP', () {
      final now = DateTime.now();
      final pos1 = Position(
        latitude: 13.0000,
        longitude: 76.0000,
        timestamp: now,
        accuracy: 10.0,
        altitude: 800.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );
      engine.classify(pos1);

      // Jump 50 km in 1 second (180,000 km/h)
      final posJump = Position(
        latitude: 13.4500,
        longitude: 76.0000,
        timestamp: now.add(const Duration(seconds: 1)),
        accuracy: 10.0,
        altitude: 800.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );

      final classifiedJump = engine.classify(posJump);
      expect(classifiedJump.classification, GpsClassification.GPS_JUMP);
      expect(classifiedJump.isUsable, isFalse);
    });
  });

  group('Phase 6 — Section 2: Destination Authorization & Location Privacy Gates', () {
    test('isValidCoord strictly validates geographical coordinate boundaries', () {
      // Valid Karnataka locations
      expect(JourneyNavigator.isValidCoord(13.0068, 76.0996), isTrue); // Hassan
      expect(JourneyNavigator.isValidCoord(12.9716, 77.5946), isTrue); // Bengaluru
      expect(JourneyNavigator.isValidCoord(15.3647, 75.1240), isTrue); // Hubli

      // Invalid: Null Island (0, 0)
      expect(JourneyNavigator.isValidCoord(0.0, 0.0), isFalse);

      // Invalid: Out of latitude range
      expect(JourneyNavigator.isValidCoord(90.1, 76.0), isFalse);
      expect(JourneyNavigator.isValidCoord(-90.1, 76.0), isFalse);

      // Invalid: Out of longitude range
      expect(JourneyNavigator.isValidCoord(13.0, 180.1), isFalse);
      expect(JourneyNavigator.isValidCoord(13.0, -180.1), isFalse);

      // Invalid: NaN or Infinity
      expect(JourneyNavigator.isValidCoord(double.nan, 76.0), isFalse);
      expect(JourneyNavigator.isValidCoord(13.0, double.infinity), isFalse);
    });
  });

  group('Phase 6 — Section 3: OSRM Production Configuration & Demo Server Purge', () {
    test('OsrmRouteProvider correctly reports production configuration status', () {
      final provider = OsrmRouteProvider();
      expect(provider.name, 'osrm');
      expect(provider.polylineEncoding, PolylineEncoding.polyline5);
      expect(provider.supportsMatrix, isTrue);

      // Verify configured status corresponds to OSRM_URL environment variable
      const configuredEnv = String.fromEnvironment('OSRM_URL', defaultValue: '');
      expect(provider.isProductionConfigured, configuredEnv.isNotEmpty);
    });

    test('OsrmRouteProvider rejects invalid or zero coordinates before network request', () async {
      final provider = OsrmRouteProvider();
      final route = await provider.calculateRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(13.0, 76.0),
      );
      expect(route, isNull);
    });
  });

  group('Phase 6 — Section 4: Polyline Projection, Maneuvers & Route Progress', () {
    // Construct a canonical test route in Hassan
    final testPoints = [
      const LatLng(13.0000, 76.0000), // start
      const LatLng(13.0050, 76.0000), // point 1
      const LatLng(13.0100, 76.0000), // point 2 (turn right)
      const LatLng(13.0100, 76.0050), // point 3
      const LatLng(13.0100, 76.0100), // destination
    ];

    final testSteps = [
      RouteStep.simple(
        instruction: 'Head north on Main Road',
        distanceM: 1113,
        durationSec: 120,
        action: 'depart',
      ),
      RouteStep.simple(
        instruction: 'Turn right onto Market Street',
        distanceM: 1085,
        durationSec: 100,
        action: 'turn_right',
      ),
    ];

    final sampleRoute = RouteResult.withCumulativeDistances(
      polyline: testPoints,
      distanceM: 2198,
      durationSec: 220,
      steps: testSteps,
      calculatedAt: DateTime.now(),
      provider: 'valhalla',
    );

    test('RouteResult builds cumulative distances accurately', () {
      expect(sampleRoute.cumulativeDistances.length, testPoints.length);
      expect(sampleRoute.cumulativeDistances[0], 0.0);
      expect(sampleRoute.totalPolylineLength, greaterThan(2000.0));
    });

    test('RouteResult formats distance and ETA strings clearly', () {
      expect(sampleRoute.distanceText, contains('km'));
      expect(sampleRoute.etaText, contains('min'));
    });
  });

  group('Phase 6 — Section 5: Session Lifecycle, Teardown & Zombie Prevention', () {
    test('NavigationEngine singleton starts and cleanly stops session', () async {
      final engine = NavigationEngine.instance;
      expect(engine.isRunning, isFalse);

      final dummyRoute = RouteResult(
        polyline: const [
          LatLng(13.0000, 76.0000),
          LatLng(13.0010, 76.0010),
        ],
        distanceM: 150,
        durationSec: 30,
        steps: const [],
        calculatedAt: DateTime.now(),
        provider: 'test',
      );

      await engine.start(
        route: dummyRoute,
        destination: const LatLng(13.0010, 76.0010),
        bookingId: 'booking_phase6_test_001',
        voiceEnabled: false,
        manageGpsStream: false,
      );

      expect(engine.isRunning, isTrue);

      // Clean teardown
      await engine.stop();
      expect(engine.isRunning, isFalse);
      expect(engine.current, isNull);
    });

    test('Rapid start/stop cycles do not leak active sessions or timers', () async {
      final engine = NavigationEngine.instance;

      for (int i = 0; i < 3; i++) {
        final dummyRoute = RouteResult(
          polyline: const [
            LatLng(13.0000, 76.0000),
            LatLng(13.0020, 76.0020),
          ],
          distanceM: 300,
          durationSec: 60,
          steps: const [],
          calculatedAt: DateTime.now(),
          provider: 'test',
        );

        await engine.start(
          route: dummyRoute,
          destination: const LatLng(13.0020, 76.0020),
          bookingId: 'booking_phase6_cycle_$i',
          voiceEnabled: false,
          manageGpsStream: false,
        );

        expect(engine.isRunning, isTrue);
        await engine.stop();
        expect(engine.isRunning, isFalse);
      }
    });
  });

  group('Phase 6 — Section 6: In-Flight Off-Route Detection & Auto-Reroute Gating', () {
    test('feeding on-route GPS updates maintains isOffRoute false', () async {
      final engine = NavigationEngine.instance;

      final route = RouteResult(
        polyline: const [
          LatLng(13.0000, 76.0000),
          LatLng(13.0100, 76.0000),
        ],
        distanceM: 1113,
        durationSec: 120,
        steps: const [],
        calculatedAt: DateTime.now(),
        provider: 'test',
      );

      await engine.start(
        route: route,
        destination: const LatLng(13.0100, 76.0000),
        bookingId: 'booking_phase6_offroute_001',
        voiceEnabled: false,
        manageGpsStream: false,
      );

      // Feed position exactly on the route polyline
      final onRoutePos = Position(
        latitude: 13.0050,
        longitude: 76.0000,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );

      engine.feedGpsPosition(onRoutePos);
      expect(engine.current, isNotNull);
      expect(engine.current!.isOffRoute, isFalse);
      expect(engine.current!.isSnapped, isTrue);

      await engine.stop();
    });

    test('single jitter fix beyond 50m does not prematurely trigger reroute due to grace count', () async {
      final engine = NavigationEngine.instance;

      final route = RouteResult(
        polyline: const [
          LatLng(13.0000, 76.0000),
          LatLng(13.0100, 76.0000),
        ],
        distanceM: 1113,
        durationSec: 120,
        steps: const [],
        calculatedAt: DateTime.now(),
        provider: 'test',
      );

      await engine.start(
        route: route,
        destination: const LatLng(13.0100, 76.0000),
        bookingId: 'booking_phase6_jitter_001',
        voiceEnabled: false,
        manageGpsStream: false,
      );

      // Single fix 60m away
      // 1 degree longitude ≈ 108 km in southern India → 0.0006 deg ≈ 65m
      final jitterPos = Position(
        latitude: 13.0050,
        longitude: 76.0006,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );

      engine.feedGpsPosition(jitterPos);
      expect(engine.current, isNotNull);
      // isRerouting should still be false after only 1 tick (grace count is 3)
      expect(engine.current!.isRerouting, isFalse);

      await engine.stop();
    });
  });

  group('Phase 6 — Section 7: Arrival Stability & Proximity Detection', () {
    test('detects arrival when within 30m of destination while stopped', () async {
      final engine = NavigationEngine.instance;
      const dest = LatLng(13.0100, 76.0000);

      final route = RouteResult(
        polyline: const [
          LatLng(13.0090, 76.0000),
          dest,
        ],
        distanceM: 110,
        durationSec: 15,
        steps: const [],
        calculatedAt: DateTime.now(),
        provider: 'test',
      );

      await engine.start(
        route: route,
        destination: dest,
        bookingId: 'booking_phase6_arrival_001',
        voiceEnabled: false,
        manageGpsStream: false,
      );

      final now = DateTime.now();
      // Position 10 metres from destination, speed 0 km/h
      final arrivalPos1 = Position(
        latitude: 13.0099,
        longitude: 76.0000,
        timestamp: now,
        accuracy: 8.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 0.0, // stopped
        speedAccuracy: 0.0,
      );

      final arrivalPos2 = Position(
        latitude: 13.0099,
        longitude: 76.0000,
        timestamp: now.add(const Duration(seconds: 1)),
        accuracy: 8.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 0.0, // stopped
        speedAccuracy: 0.0,
      );

      // Two consecutive stable 1Hz fixes within arrival zone
      engine.feedGpsPosition(arrivalPos1);
      expect(engine.current, isNotNull);
      // First fix is registered as arrival candidate #1
      engine.feedGpsPosition(arrivalPos2);
      // Second consecutive stable fix triggers confirmed arrival
      expect(engine.current!.hasArrived, isTrue);

      await engine.stop();
    });
  });

  group('Phase 6 — Section 8: Navigation Bootstrap State Machine & Session Safety', () {
    test('NavigationBootstrapState correctly categorizes loading, failure, ready, and navigating states', () {
      // Loading states
      expect(NavigationBootstrapState.checkingBooking.isLoading, isTrue);
      expect(NavigationBootstrapState.checkingDestination.isLoading, isTrue);
      expect(NavigationBootstrapState.checkingPermission.isLoading, isTrue);
      expect(NavigationBootstrapState.checkingLocationService.isLoading, isTrue);
      expect(NavigationBootstrapState.requestingLocation.isLoading, isTrue);
      expect(NavigationBootstrapState.routing.isLoading, isTrue);
      expect(NavigationBootstrapState.startingGuidance.isLoading, isTrue);

      // Non-loading states
      expect(NavigationBootstrapState.idle.isLoading, isFalse);
      expect(NavigationBootstrapState.ready.isLoading, isFalse);
      expect(NavigationBootstrapState.navigating.isLoading, isFalse);

      // Failure states
      expect(NavigationBootstrapState.bookingInvalid.isFailure, isTrue);
      expect(NavigationBootstrapState.destinationInvalid.isFailure, isTrue);
      expect(NavigationBootstrapState.permissionDenied.isFailure, isTrue);
      expect(NavigationBootstrapState.locationServiceDisabled.isFailure, isTrue);
      expect(NavigationBootstrapState.locationTimeout.isFailure, isTrue);
      expect(NavigationBootstrapState.locationUnavailable.isFailure, isTrue);
      expect(NavigationBootstrapState.locationAccuracyTooLow.isFailure, isTrue);
      expect(NavigationBootstrapState.routeTimeout.isFailure, isTrue);
      expect(NavigationBootstrapState.routeUnavailable.isFailure, isTrue);
      expect(NavigationBootstrapState.routeInvalid.isFailure, isTrue);
      expect(NavigationBootstrapState.navigationInitializationFailed.isFailure, isTrue);

      // Terminal status check
      expect(NavigationBootstrapState.ready.isReady, isTrue);
      expect(NavigationBootstrapState.navigating.isNavigating, isTrue);
    });

    test('BookingDestinationContract strictly enforces non-empty IDs and valid geographic bounds', () {
      // Valid contract
      const valid = BookingDestinationContract(
        bookingId: 'booking_123',
        jobLat: 13.0068,
        jobLng: 76.0996,
        jobAddress: 'Hassan Work Site',
        workerId: 'worker_001',
        hirerId: 'hirer_001',
      );
      expect(valid.isValid(), isTrue);

      // Empty bookingId
      const emptyBooking = BookingDestinationContract(
        bookingId: '',
        jobLat: 13.0068,
        jobLng: 76.0996,
        jobAddress: 'Hassan',
        workerId: 'worker_001',
        hirerId: 'hirer_001',
      );
      expect(emptyBooking.isValid(), isFalse);

      // Out-of-bounds latitude (outside India)
      const outOfBoundsLat = BookingDestinationContract(
        bookingId: 'booking_123',
        jobLat: 50.0, // outside India (6 to 37)
        jobLng: 76.0996,
        jobAddress: 'Abroad',
        workerId: 'worker_001',
        hirerId: 'hirer_001',
      );
      expect(outOfBoundsLat.isValid(), isFalse);

      // Missing workerId
      const missingWorker = BookingDestinationContract(
        bookingId: 'booking_123',
        jobLat: 13.0068,
        jobLng: 76.0996,
        jobAddress: 'Site',
        workerId: '',
        hirerId: 'hirer_001',
      );
      expect(missingWorker.isValid(), isFalse);
    });

    test('NavigationSession maintains single-booking ownership and isolates route versions', () {
      final session = NavigationSession(
        navigationSessionId: 'nav_sess_001',
        bookingId: 'booking_001',
        jobId: 'job_001',
        workerId: 'worker_001',
        hirerId: 'hirer_001',
        origin: const LatLng(13.0068, 76.0996),
        destination: const LatLng(13.0100, 76.1050),
        state: NavigationBootstrapState.ready,
        routeVersion: 1,
        activeRequestId: 'req_001',
        startedAt: DateTime.now(),
      );

      expect(session.bookingId, 'booking_001');
      expect(session.routeVersion, 1);
      expect(session.state, NavigationBootstrapState.ready);

      // Update session via copyWith
      final updatedSession = session.copyWith(
        routeVersion: 2,
        activeRequestId: 'req_002',
        state: NavigationBootstrapState.navigating,
      );

      expect(updatedSession.routeVersion, 2);
      expect(updatedSession.activeRequestId, 'req_002');
      expect(updatedSession.state, NavigationBootstrapState.navigating);
      expect(updatedSession.navigationSessionId, session.navigationSessionId);
      expect(updatedSession.bookingId, session.bookingId);
    });

    test('NavigationStateMachine allows transition from requestingLocation to locationTimeout', () {
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.locationAcquiring,
          NavigationState.error,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.locationAcquiring,
          NavigationState.permissionDenied,
        ),
        isTrue,
      );
      expect(
        NavigationStateMachine.canTransition(
          NavigationState.locationAcquiring,
          NavigationState.gpsDisabled,
        ),
        isTrue,
      );
    });
  });
}
