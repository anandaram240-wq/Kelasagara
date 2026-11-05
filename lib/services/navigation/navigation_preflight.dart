// lib/services/navigation/navigation_preflight.dart
// ============================================================================
// KELASAGARA — Deterministic Navigation Preflight Engine (Phase 6, 8, 10, 13)
//
// Responsibilities:
//   - Strict sequential or safe concurrent preflight operations:
//       1. Booking authorization & status check
//       2. Destination coordinate validation
//       3. Hardware GPS staged acquisition (service, permission, cached, active)
//       4. GPS validation
//       5. Route prefetch check or calculation via RoutingFacade
//       6. Route validation
//   - Bounded deadlines on all asynchronous stages.
//   - Decoupled error taxonomy: maps failures to exact subsystem reasons.
//   - Absolute zero infinite loading spinners.
// ============================================================================

import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../../models/navigation_destination.dart';
import '../../models/navigation_health.dart';
import '../../models/route_result.dart';
import '../../models/live_location.dart';
import 'navigation_location_provider.dart';
import 'routing_facade.dart';
import 'route_prefetch_manager.dart';

enum PreflightStatus {
  idle,
  bookingValidating,
  destinationValidating,
  permissionChecking,
  locationServiceChecking,
  gpsAcquiring,
  gpsValidating,
  routeFetching,
  routeValidating,
  ready,
  failed,
}

enum PreflightFailureReason {
  none,
  bookingInvalid,
  destinationInvalid,
  permissionDenied,
  locationServiceDisabled,
  locationTimeout,
  locationAccuracyLow,
  routingConfigurationMissing,
  routeAuthenticationError,
  routeNoRoute,
  routeTimeout,
  routeUnavailable,
  routeMalformed,
  unknown,
}

class PreflightResult {
  final PreflightStatus status;
  final PreflightFailureReason failureReason;
  final String? errorMessage;
  final LiveLocation? initialLocation;
  final RouteResult? initialRoute;
  final NavigationDestination? destination;

  const PreflightResult({
    required this.status,
    this.failureReason = PreflightFailureReason.none,
    this.errorMessage,
    this.initialLocation,
    this.initialRoute,
    this.destination,
  });

  bool get isReady =>
      status == PreflightStatus.ready &&
      initialLocation != null &&
      initialRoute != null;
  bool get hasFailed => status == PreflightStatus.failed;
}

class NavigationPreflight {
  NavigationPreflight._();
  static final NavigationPreflight instance = NavigationPreflight._();

  final StreamController<PreflightStatus> _statusController =
      StreamController<PreflightStatus>.broadcast();
  Stream<PreflightStatus> get statusStream => _statusController.stream;

  PreflightStatus _currentStatus = PreflightStatus.idle;
  PreflightStatus get currentStatus => _currentStatus;

  /// Executes the bounded preflight verification and acquisition pipeline.
  Future<PreflightResult> prepare({
    required String bookingId,
    required String jobId,
    required String workerId,
    required double destLat,
    required double destLng,
    required String jobAddress,
    required String currentBookingStatus,
    String? sessionId,
  }) async {
    final activeSessionId = sessionId ??
        'pre_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Booking Authorization & Status Whitelist Check
    _updateStatus(PreflightStatus.bookingValidating);
    final allowedStatuses = {
      'confirmed',
      'tracking',
      'in_progress',
      'working',
      'arrived',
      'completion_requested',
      'payment_pending',
    };

    if (bookingId.trim().isEmpty || workerId.trim().isEmpty) {
      return _fail(
        PreflightFailureReason.bookingInvalid,
        'Booking or worker authorization identity is missing.',
      );
    }

    if (!allowedStatuses.contains(currentBookingStatus.toLowerCase())) {
      return _fail(
        PreflightFailureReason.bookingInvalid,
        'Navigation is only available for active work bookings (Status: $currentBookingStatus).',
      );
    }

    // 2. Destination Validation
    _updateStatus(PreflightStatus.destinationValidating);
    final destination = NavigationDestination(
      bookingId: bookingId,
      jobId: jobId,
      latitude: destLat,
      longitude: destLng,
      address: jobAddress,
      authorizedAt: DateTime.now(),
    );

    if (!destination.isValid) {
      return _fail(
        PreflightFailureReason.destinationInvalid,
        'Authorized work site location coordinates are missing or invalid.',
      );
    }

    // 3. Staged GPS Bootstrap (Step 1-6 via NavigationLocationProvider)
    _updateStatus(PreflightStatus.gpsAcquiring);
    final gpsResult =
        await NavigationLocationProvider.instance.acquireInitialPosition(
      sessionId: activeSessionId,
      requestId: 'req_preflight',
      timeout: const Duration(seconds: 12),
    );

    if (!gpsResult.isSuccess || gpsResult.location == null) {
      if (gpsResult.status == GpsStatus.serviceDisabled) {
        return _fail(
          PreflightFailureReason.locationServiceDisabled,
          gpsResult.errorMessage ??
              'Turn on device location to continue navigation.',
        );
      }
      if (gpsResult.status == GpsStatus.permissionDenied) {
        return _fail(
          PreflightFailureReason.permissionDenied,
          gpsResult.errorMessage ??
              'Location permission is required for Kelasagara navigation.',
        );
      }
      return _fail(
        PreflightFailureReason.locationTimeout,
        gpsResult.errorMessage ??
            "Unable to obtain a usable device location. Move to an area with clear sky view.",
      );
    }

    final freshFix = gpsResult.location!;
    _updateStatus(PreflightStatus.gpsValidating);
    final origin = LatLng(freshFix.latitude, freshFix.longitude);

    // 4. Check Prefetched Route Cache
    RouteResult? route = RoutePrefetchManager.instance.getValidPrefetchedRoute(
      bookingId: bookingId,
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      // 5. Route Fetching (Bounded 8s timeout via RoutingFacade)
      _updateStatus(PreflightStatus.routeFetching);
      try {
        route = await RoutingFacade.instance.calculateRoute(
          origin: origin,
          destination: destination.latLng,
          sessionId: activeSessionId,
          routeVersion: 1,
          timeout: const Duration(seconds: 8),
          requestId: 'req_preflight',
        );

        // Cache the newly acquired route
        RoutePrefetchManager.instance.prefetchRoute(
          bookingId: bookingId,
          origin: origin,
          destination: destination,
          sessionId: activeSessionId,
          routeVersion: 1,
        );
      } on RoutingConfigurationException catch (e) {
        return _fail(
            PreflightFailureReason.routingConfigurationMissing, e.message);
      } on AuthenticationException catch (e) {
        return _fail(
            PreflightFailureReason.routeAuthenticationError, e.message);
      } on NoRouteFoundException catch (e) {
        return _fail(PreflightFailureReason.routeNoRoute, e.message);
      } on RouteTimeoutException catch (e) {
        return _fail(PreflightFailureReason.routeTimeout, e.message);
      } on RouteUnavailableException catch (e) {
        return _fail(PreflightFailureReason.routeUnavailable, e.message);
      } on MalformedRouteException catch (e) {
        return _fail(PreflightFailureReason.routeMalformed, e.message);
      } catch (e) {
        return _fail(
            PreflightFailureReason.routeUnavailable, 'Failed to calculate route: $e');
      }
    }

    // 6. Route Validation
    _updateStatus(PreflightStatus.routeValidating);
    if (route.polyline.isEmpty || route.distanceM <= 0) {
      return _fail(PreflightFailureReason.routeMalformed,
          'Generated route has invalid geometry.');
    }

    // 7. Preflight Complete -> READY
    _updateStatus(PreflightStatus.ready);
    return PreflightResult(
      status: PreflightStatus.ready,
      initialLocation: freshFix,
      initialRoute: route,
      destination: destination,
    );
  }

  PreflightResult _fail(PreflightFailureReason reason, String message) {
    _updateStatus(PreflightStatus.failed);
    return PreflightResult(
      status: PreflightStatus.failed,
      failureReason: reason,
      errorMessage: message,
    );
  }

  void _updateStatus(PreflightStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void reset() {
    _currentStatus = PreflightStatus.idle;
    _statusController.add(PreflightStatus.idle);
  }
}
