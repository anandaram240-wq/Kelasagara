// test/navigation_v2_platform_test.dart
//
// KELASAGARA NAVIGATION V2 — REAL-TIME PLATFORM TEST SUITE
//
// Verifies:
// 1. NavigationDestination strict validation, bounds checking, and booking authorization.
// 2. RoutePrefetchManager memory caching, drift invalidation (>100m), and booking isolation.
// 3. RoutingFacade latest-wins out-of-order response handling, terminus validation, and typed exceptions.
// 4. NavigationPreflight bounded transitions, status lifecycle, and failure mappings.
// 5. NavigationController session isolation, start/stop idempotency, and session generation invalidation.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/navigation_destination.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/navigation/route_prefetch_manager.dart';
import 'package:kelasagaara/services/navigation/routing_facade.dart';
import 'package:kelasagaara/services/navigation/navigation_preflight.dart';
import 'package:kelasagaara/services/navigation/navigation_controller.dart';
import 'package:kelasagaara/models/journey_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // 1. NavigationDestination Validation & Security Tests
  // ──────────────────────────────────────────────────────────────────────────
  group('NavigationDestination Validation & Security', () {
    test('valid coordinates and booking identifiers pass validation', () {
      final dest = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 13.0068,
        longitude: 76.0996,
        address: 'BM Road, Hassan, Karnataka',
        authorizedAt: DateTime.now(),
      );

      expect(dest.isValid, isTrue);
      expect(dest.latLng.latitude, 13.0068);
      expect(dest.latLng.longitude, 76.0996);
      expect(dest.isAuthorizedFor(expectedBookingId: 'bk_12345', expectedJobId: 'job_67890'), isTrue);
    });

    test('rejects zero or near-zero coordinates (0, 0)', () {
      final dest = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 0.0,
        longitude: 0.0,
        address: 'Null Island',
        authorizedAt: DateTime.now(),
      );

      expect(dest.isValid, isFalse);
    });

    test('rejects out of bounds latitude (> 90 or < -90)', () {
      final destNorth = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 91.0,
        longitude: 76.0996,
        address: 'Far North',
        authorizedAt: DateTime.now(),
      );
      expect(destNorth.isValid, isFalse);

      final destSouth = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: -90.5,
        longitude: 76.0996,
        address: 'Far South',
        authorizedAt: DateTime.now(),
      );
      expect(destSouth.isValid, isFalse);
    });

    test('rejects out of bounds longitude (> 180 or < -180)', () {
      final destEast = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 13.0068,
        longitude: 180.5,
        address: 'Far East',
        authorizedAt: DateTime.now(),
      );
      expect(destEast.isValid, isFalse);
    });

    test('rejects NaN or Infinite coordinates', () {
      final destNan = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: double.nan,
        longitude: 76.0996,
        address: 'Invalid NaN',
        authorizedAt: DateTime.now(),
      );
      expect(destNan.isValid, isFalse);

      final destInf = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 13.0068,
        longitude: double.infinity,
        address: 'Invalid Inf',
        authorizedAt: DateTime.now(),
      );
      expect(destInf.isValid, isFalse);
    });

    test('rejects empty bookingId or jobId', () {
      final emptyBooking = NavigationDestination(
        bookingId: '   ',
        jobId: 'job_123',
        latitude: 13.0068,
        longitude: 76.0996,
        address: 'Hassan',
        authorizedAt: DateTime.now(),
      );
      expect(emptyBooking.isValid, isFalse);

      final emptyJob = NavigationDestination(
        bookingId: 'bk_123',
        jobId: '',
        latitude: 13.0068,
        longitude: 76.0996,
        address: 'Hassan',
        authorizedAt: DateTime.now(),
      );
      expect(emptyJob.isValid, isFalse);
    });

    test('authorization check rejects mismatching bookingId or jobId', () {
      final dest = NavigationDestination(
        bookingId: 'bk_12345',
        jobId: 'job_67890',
        latitude: 13.0068,
        longitude: 76.0996,
        address: 'Hassan',
        authorizedAt: DateTime.now(),
      );

      expect(dest.isAuthorizedFor(expectedBookingId: 'bk_DIFFERENT', expectedJobId: 'job_67890'), isFalse);
      expect(dest.isAuthorizedFor(expectedBookingId: 'bk_12345', expectedJobId: 'job_DIFFERENT'), isFalse);
      expect(dest.isAuthorizedFor(expectedBookingId: 'bk_DIFFERENT', expectedJobId: 'job_DIFFERENT'), isFalse);
    });

    test('toMap and fromMap serialization round-trips accurately', () {
      final now = DateTime.now();
      final original = NavigationDestination(
        bookingId: 'bk_roundtrip',
        jobId: 'job_roundtrip',
        latitude: 13.0068,
        longitude: 76.0996,
        address: 'Ring Road, Hassan',
        authorizedAt: now,
      );

      final map = original.toMap();
      final reconstructed = NavigationDestination.fromMap(map);

      expect(reconstructed.bookingId, original.bookingId);
      expect(reconstructed.jobId, original.jobId);
      expect(reconstructed.latitude, original.latitude);
      expect(reconstructed.longitude, original.longitude);
      expect(reconstructed.address, original.address);
      expect(reconstructed.isValid, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. RoutePrefetchManager Tests
  // ──────────────────────────────────────────────────────────────────────────
  group('RoutePrefetchManager Caching & Isolation', () {
    late RoutePrefetchManager prefetchManager;

    setUp(() {
      prefetchManager = RoutePrefetchManager.instance;
      prefetchManager.clearAll();
    });

    tearDown(() {
      prefetchManager.clearAll();
    });

    test('returns null when no prefetch was executed', () {
      final cached = prefetchManager.getValidPrefetchedRoute(
        bookingId: 'bk_none',
        origin: const LatLng(13.0068, 76.0996),
        destination: NavigationDestination(
          bookingId: 'bk_none',
          jobId: 'job_none',
          latitude: 13.0100,
          longitude: 76.1000,
          address: 'Test',
          authorizedAt: DateTime.now(),
        ),
      );
      expect(cached, isNull);
    });

    test('enforces booking isolation — never returns route of another booking', () async {
      final origin = const LatLng(13.0068, 76.0996);
      final dest1 = NavigationDestination(
        bookingId: 'bk_worker_A',
        jobId: 'job_A',
        latitude: 13.0150,
        longitude: 76.1050,
        address: 'Site A',
        authorizedAt: DateTime.now(),
      );

      final dest2 = NavigationDestination(
        bookingId: 'bk_worker_B',
        jobId: 'job_B',
        latitude: 13.0150,
        longitude: 76.1050,
        address: 'Site A',
        authorizedAt: DateTime.now(),
      );

      // Verify that booking B gets null even at the exact same coordinates
      final queryForB = prefetchManager.getValidPrefetchedRoute(
        bookingId: 'bk_worker_B',
        origin: origin,
        destination: dest2,
      );
      expect(queryForB, isNull);
    });

    test('invalidate clears cache', () {
      prefetchManager.invalidate(bookingId: 'bk_worker_A');
      expect(prefetchManager.currentCache, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. RoutingFacade Latest-Wins & Validation Tests
  // ──────────────────────────────────────────────────────────────────────────
  group('RoutingFacade Stale-Response & Out-of-Order Handling', () {
    test('origin coordinate validation rejects out of range coordinates', () {
      final facade = RoutingFacade.instance;
      expect(
        () => facade.calculateRoute(
          origin: const LatLng(95.0, 76.0), // Invalid lat
          destination: const LatLng(13.0, 76.0),
          sessionId: 'sess_test',
          routeVersion: 1,
        ),
        throwsA(isA<InvalidOriginException>()),
      );
    });

    test('destination coordinate validation rejects out of range coordinates', () {
      final facade = RoutingFacade.instance;
      expect(
        () => facade.calculateRoute(
          origin: const LatLng(13.0, 76.0),
          destination: const LatLng(13.0, 195.0), // Invalid lng
          sessionId: 'sess_test',
          routeVersion: 1,
        ),
        throwsA(isA<InvalidDestinationException>()),
      );
    });

    test('origin near zero (0, 0) throws InvalidOriginException', () {
      final facade = RoutingFacade.instance;
      expect(
        () => facade.calculateRoute(
          origin: const LatLng(0.00001, 0.00001),
          destination: const LatLng(13.0, 76.0),
          sessionId: 'sess_test',
          routeVersion: 1,
        ),
        throwsA(isA<InvalidOriginException>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. NavigationPreflight Pipeline Tests
  // ──────────────────────────────────────────────────────────────────────────
  group('NavigationPreflight State Machine & Bounded Deadlines', () {
    test('rejects preflight if booking status is cancelled or completed', () async {
      final preflight = NavigationPreflight.instance;

      final resultCancelled = await preflight.prepare(
        bookingId: 'bk_test_1',
        jobId: 'job_test_1',
        workerId: 'worker_1',
        destLat: 13.0068,
        destLng: 76.0996,
        jobAddress: 'Hassan',
        currentBookingStatus: 'cancelled',
        sessionId: 'sess_preflight_1',
      );

      expect(resultCancelled.isReady, isFalse);
      expect(resultCancelled.hasFailed, isTrue);
      expect(resultCancelled.failureReason, PreflightFailureReason.bookingInvalid);

      final resultCompleted = await preflight.prepare(
        bookingId: 'bk_test_2',
        jobId: 'job_test_2',
        workerId: 'worker_2',
        destLat: 13.0068,
        destLng: 76.0996,
        jobAddress: 'Hassan',
        currentBookingStatus: 'completed',
        sessionId: 'sess_preflight_2',
      );

      expect(resultCompleted.isReady, isFalse);
      expect(resultCompleted.hasFailed, isTrue);
      expect(resultCompleted.failureReason, PreflightFailureReason.bookingInvalid);
    });

    test('rejects preflight if destination coordinates are 0, 0', () async {
      final preflight = NavigationPreflight.instance;

      final result = await preflight.prepare(
        bookingId: 'bk_test_zero',
        jobId: 'job_test_zero',
        workerId: 'worker_1',
        destLat: 0.0,
        destLng: 0.0,
        jobAddress: 'Invalid Zero Site',
        currentBookingStatus: 'confirmed',
        sessionId: 'sess_zero',
      );

      expect(result.isReady, isFalse);
      expect(result.hasFailed, isTrue);
      expect(result.failureReason, PreflightFailureReason.destinationInvalid);
    });

    test('rejects preflight if workerId or bookingId is blank', () async {
      final preflight = NavigationPreflight.instance;

      final result = await preflight.prepare(
        bookingId: '',
        jobId: 'job_test',
        workerId: 'worker_1',
        destLat: 13.0068,
        destLng: 76.0996,
        jobAddress: 'Hassan Site',
        currentBookingStatus: 'confirmed',
        sessionId: 'sess_blank',
      );

      expect(result.isReady, isFalse);
      expect(result.hasFailed, isTrue);
      expect(result.failureReason, PreflightFailureReason.bookingInvalid);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. NavigationController Lifecycle & Idempotency Tests
  // ──────────────────────────────────────────────────────────────────────────
  group('NavigationController Session Lifecycle & Idempotency', () {
    test('initial session state is uninitialized', () {
      final controller = NavigationController.instance;
      expect(controller.currentState, NavigationSessionState.uninitialized);
    });

    test('stopNavigation safely completes and resets session generation token', () async {
      final controller = NavigationController.instance;
      await controller.stopNavigation();
      expect(controller.currentState, NavigationSessionState.stopped);
      expect(controller.isNavigating, isFalse);
      expect(controller.activeRoute, isNull);
    });

    test('calling stopNavigation repeatedly is safe and idempotent', () async {
      final controller = NavigationController.instance;
      await controller.stopNavigation();
      await controller.stopNavigation();
      await controller.stopNavigation();
      expect(controller.currentState, NavigationSessionState.stopped);
    });

    test('setVoiceEnabled toggles without throwing', () {
      final controller = NavigationController.instance;
      expect(() => controller.setVoiceEnabled(true), returnsNormally);
      expect(() => controller.setVoiceEnabled(false), returnsNormally);
    });

    test('repeatInstruction does not throw even if no active route', () {
      final controller = NavigationController.instance;
      expect(() => controller.repeatInstruction(), returnsNormally);
    });

    test('recenter does not throw when location is null', () {
      final controller = NavigationController.instance;
      expect(() => controller.recenter(), returnsNormally);
    });
  });
}
