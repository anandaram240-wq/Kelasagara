// lib/services/navigation/routing_facade.dart
// ============================================================================
// KELASAGARA — Production Routing Facade & Request Manager (Phase 8-12)
//
// Responsibilities:
//   - Exclusive routing authority via Valhalla (no silent demo fallback).
//   - Strict provider selection and validation: fails explicitly with
//     ROUTING_CONFIGURATION_MISSING if production provider URL is not set.
//   - Single-Flight Request Management & True HTTP Request Cancellation via Dio
//   - Circuit Breaker (CLOSED / OPEN / HALF_OPEN) with cooldown & health probe
//   - Stale-While-Revalidate In-Memory Route Cache (TTL 45s, origin proximity)
//   - Specific typed exceptions:
//       * RoutingConfigurationException
//       * AuthenticationException
//       * NoRouteFoundException
//       * RouteTimeoutException
//       * MalformedRouteException
//       * RouteUnavailableException
//       * InvalidOriginException / InvalidDestinationException
//       * StaleRouteException (superseded requests cleanly discarded)
//   - Diagnostic logging:
//       ROUTE_PROVIDER_SELECTED, ROUTE_REQUEST_STARTED, ROUTE_HTTP_STATUS,
//       ROUTE_RESPONSE_RECEIVED, ROUTE_PROVIDER_ERROR, ROUTE_NO_ROUTE,
//       ROUTE_TIMEOUT, ROUTE_DECODE_ERROR, ROUTE_SUCCESS
// ============================================================================

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/route_result.dart';
import '../routing/valhalla_route_provider.dart';
import '../routing/routing_provider.dart';

sealed class RoutingException implements Exception {
  final String message;
  const RoutingException(this.message);
  @override
  String toString() => message;
}

class RoutingConfigurationException extends RoutingException {
  const RoutingConfigurationException([
    String msg =
        'ROUTING_CONFIGURATION_MISSING: Valhalla routing URL is not configured.',
  ]) : super(msg);
}

class AuthenticationException extends RoutingException {
  const AuthenticationException([
    String msg = 'Routing service authentication failed (HTTP 401/403).',
  ]) : super(msg);
}

class RouteTimeoutException extends RoutingException {
  const RouteTimeoutException([
    String msg = "Couldn't calculate the route within the time limit.",
  ]) : super(msg);
}

class RouteUnavailableException extends RoutingException {
  const RouteUnavailableException([
    String msg = 'Navigation routing service is currently unavailable.',
  ]) : super(msg);
}

class InvalidOriginException extends RoutingException {
  const InvalidOriginException([
    String msg = 'Invalid current location coordinates for routing.',
  ]) : super(msg);
}

class InvalidDestinationException extends RoutingException {
  const InvalidDestinationException([
    String msg = 'Invalid job destination coordinates.',
  ]) : super(msg);
}

class MalformedRouteException extends RoutingException {
  const MalformedRouteException([
    String msg = 'Routing server returned an invalid or incomplete route.',
  ]) : super(msg);
}

class NoRouteFoundException extends RoutingException {
  const NoRouteFoundException([
    String msg =
        'No drivable route found between your location and the destination.',
  ]) : super(msg);
}

class StaleRouteException extends RoutingException {
  const StaleRouteException([
    String msg = 'Stale route request was superseded by a newer request.',
  ]) : super(msg);
}

enum CircuitBreakerState { closed, open, halfOpen }

class _CachedRouteEntry {
  final RouteResult route;
  final LatLng origin;
  final LatLng destination;
  final String costing;
  final DateTime cachedAt;

  _CachedRouteEntry({
    required this.route,
    required this.origin,
    required this.destination,
    required this.costing,
    required this.cachedAt,
  });

  bool isValid(Duration ttl) => DateTime.now().difference(cachedAt) < ttl;
}

class RoutingFacade {
  RoutingFacade._();
  static final RoutingFacade instance = RoutingFacade._();

  final ValhallaRouteProvider _valhalla = ValhallaRouteProvider();

  // Single-Flight and Cancellation state
  int _activeRequestGeneration = 0;
  String _activeSessionId = '';
  CancelToken? _activeCancelToken;

  // Circuit Breaker state
  CircuitBreakerState _circuitState = CircuitBreakerState.closed;
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTime;
  static const int _failureThreshold = 3;
  static const Duration _cooldownDuration = Duration(seconds: 15);

  // In-Memory Route Cache
  final List<_CachedRouteEntry> _cache = [];
  static const int _maxCacheSize = 10;
  static const Duration _cacheTtl = Duration(seconds: 45);

  bool get isValhallaConfigured => _valhalla.isConfigured;
  String? get valhallaVersion => _valhalla.version;
  String get valhallaUrlSanitized => _valhalla.baseUrlSanitized;
  CircuitBreakerState get circuitState => _circuitState;

  /// Checks Valhalla server health and status.
  Future<ProviderHealth> checkHealth() => _valhalla.checkHealthDetailed();

  /// Calculates a canonical route between [origin] and [destination] with strict timeout,
  /// Single-Flight concurrency control, CancelToken, Circuit Breaker, and in-memory cache.
  Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required String sessionId,
    required int routeVersion,
    String costing = 'auto',
    Duration timeout = const Duration(seconds: 8),
    String requestId = '',
  }) async {
    // 1. Origin & Destination Boundary Checks
    if (!_isValidCoord(origin)) {
      debugPrint('[ROUTE_PROVIDER_ERROR] provider=valhalla requestId=$requestId reason=invalid_origin');
      throw const InvalidOriginException();
    }
    if (!_isValidCoord(destination)) {
      debugPrint('[ROUTE_PROVIDER_ERROR] provider=valhalla requestId=$requestId reason=invalid_destination');
      throw const InvalidDestinationException();
    }

    // 2. Provider Availability Check
    if (!_valhalla.isConfigured) {
      debugPrint(
          '[ROUTE_PROVIDER_SELECTED] provider=valhalla configured=false reason=ROUTING_CONFIGURATION_MISSING');
      debugPrint('[RoutingFacade] Valhalla is not configured. (VALHALLA_URL missing)');
      throw const RoutingConfigurationException();
    }

    // 3. Circuit Breaker Check
    final now = DateTime.now();
    if (_circuitState == CircuitBreakerState.open) {
      if (_lastFailureTime != null && now.difference(_lastFailureTime!) >= _cooldownDuration) {
        debugPrint('[RoutingFacade] Circuit Breaker: OPEN -> HALF_OPEN (probing)');
        _circuitState = CircuitBreakerState.halfOpen;
      } else {
        debugPrint('[RoutingFacade] Circuit Breaker: OPEN (cooldown active)');
        final cached = _getCachedRoute(origin, destination, costing);
        if (cached != null) {
          debugPrint('[RoutingFacade] Returning cached route during Circuit Breaker OPEN');
          return cached;
        }
        throw const RouteUnavailableException(
          'Routing service temporarily unavailable. Cooldown active.',
        );
      }
    }

    // 4. Single-Flight Management: Cancel any previous in-flight HTTP request
    _activeCancelToken?.cancel('superseded_by_newer_request');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final thisGeneration = ++_activeRequestGeneration;
    _activeSessionId = sessionId;
    final reqId = requestId.isNotEmpty
        ? requestId
        : 'req_${DateTime.now().millisecondsSinceEpoch % 10000}';

    debugPrint(
        '[ROUTE_PROVIDER_SELECTED] provider=valhalla configured=true url=${_valhalla.baseUrlSanitized}');
    debugPrint('[ROUTE_REQUEST_STARTED] provider=valhalla requestId=$reqId sessionId=$sessionId gen=$thisGeneration '
        'origin=(${origin.latitude.toStringAsFixed(5)}, ${origin.longitude.toStringAsFixed(5)}) '
        'dest=(${destination.latitude.toStringAsFixed(5)}, ${destination.longitude.toStringAsFixed(5)})');

    final sw = Stopwatch()..start();

    try {
      final detailedFuture = _valhalla.calculateRouteDetailed(
        origin: origin,
        destination: destination,
        costing: costing,
        cancelToken: cancelToken,
      );

      final detailedResult = await detailedFuture.timeout(timeout);
      final elapsedMs = sw.elapsedMilliseconds;

      debugPrint(
          '[ROUTE_HTTP_STATUS] provider=valhalla requestId=$reqId httpStatus=${detailedResult.httpStatus} elapsedMs=${elapsedMs}ms');

      // Latest-Wins Guard: verify this request is still the active generation and session
      if (thisGeneration != _activeRequestGeneration || _activeSessionId != sessionId) {
        debugPrint(
            '[RoutingFacade] Discarding stale route response (gen $thisGeneration < $_activeRequestGeneration)');
        throw const StaleRouteException();
      }

      if (detailedResult.isCancelled) {
        debugPrint('[RoutingFacade] Route request was cancelled (gen $thisGeneration)');
        throw const StaleRouteException('Routing request cancelled.');
      }

      if (!detailedResult.isSuccess || detailedResult.route == null) {
        final errCode = detailedResult.errorCode ?? 'UNKNOWN';
        debugPrint(
            '[ROUTE_PROVIDER_ERROR] provider=valhalla requestId=$reqId errorCode=$errCode elapsedMs=${elapsedMs}ms msg=${detailedResult.errorMessage}');

        _onFailure();

        if (errCode == 'AUTH_ERROR') {
          throw AuthenticationException(
              detailedResult.errorMessage ?? 'Authentication failed');
        } else if (errCode == 'NO_ROUTE') {
          debugPrint('[ROUTE_NO_ROUTE] provider=valhalla requestId=$reqId');
          throw NoRouteFoundException(
              detailedResult.errorMessage ?? 'No road route found');
        } else if (errCode == 'TIMEOUT') {
          debugPrint('[ROUTE_TIMEOUT] provider=valhalla requestId=$reqId');
          final cached = _getCachedRoute(origin, destination, costing);
          if (cached != null) {
            debugPrint('[RoutingFacade] Returning cached route on TIMEOUT fallback');
            return cached;
          }
          throw const RouteTimeoutException();
        } else if (errCode == 'DECODE_ERROR') {
          debugPrint('[ROUTE_DECODE_ERROR] provider=valhalla requestId=$reqId');
          throw MalformedRouteException(
              detailedResult.errorMessage ?? 'Failed to decode route');
        } else {
          final cached = _getCachedRoute(origin, destination, costing);
          if (cached != null) {
            debugPrint('[RoutingFacade] Returning cached route on SERVER_ERROR fallback');
            return cached;
          }
          throw RouteUnavailableException(
              detailedResult.errorMessage ?? 'Routing service unavailable');
        }
      }

      final result = detailedResult.route!;

      // 5. Strict Route Contract Validation
      _validateRouteContract(result, origin, destination);

      // Success: update Circuit Breaker and Cache
      _onSuccess();
      _cacheRoute(result, origin, destination, costing);

      debugPrint(
          '[ROUTE_RESPONSE_RECEIVED] provider=valhalla requestId=$reqId elapsedMs=${elapsedMs}ms');
      debugPrint('[ROUTE_SUCCESS] provider=valhalla requestId=$reqId elapsedMs=${elapsedMs}ms '
          'dist=${result.distanceM}m dur=${result.durationSec}s maneuvers=${result.steps.length}');

      return result;
    } on TimeoutException {
      final elapsedMs = sw.elapsedMilliseconds;
      _onFailure();
      cancelToken.cancel('timeout');

      final cached = _getCachedRoute(origin, destination, costing);
      if (cached != null) {
        debugPrint('[RoutingFacade] Returning cached route on 8s future TimeoutException');
        return cached;
      }

      debugPrint(
          '[ROUTE_TIMEOUT] provider=valhalla requestId=$reqId elapsedMs=${elapsedMs}ms (limit ${timeout.inSeconds}s)');
      throw const RouteTimeoutException();
    } on RoutingException {
      rethrow;
    } catch (e) {
      final elapsedMs = sw.elapsedMilliseconds;
      _onFailure();
      debugPrint(
          '[ROUTE_PROVIDER_ERROR] provider=valhalla requestId=$reqId elapsedMs=${elapsedMs}ms unexpected: $e');

      final cached = _getCachedRoute(origin, destination, costing);
      if (cached != null) {
        debugPrint('[RoutingFacade] Returning cached route on unexpected exception fallback');
        return cached;
      }

      throw RouteUnavailableException('Routing error: $e');
    } finally {
      if (_activeCancelToken == cancelToken) {
        _activeCancelToken = null;
      }
    }
  }

  void _onSuccess() {
    _consecutiveFailures = 0;
    _circuitState = CircuitBreakerState.closed;
  }

  void _onFailure() {
    _consecutiveFailures++;
    _lastFailureTime = DateTime.now();
    if (_consecutiveFailures >= _failureThreshold) {
      _circuitState = CircuitBreakerState.open;
      debugPrint('[RoutingFacade] Circuit Breaker: OPEN ($_consecutiveFailures consecutive failures)');
    }
  }

  void _cacheRoute(RouteResult route, LatLng origin, LatLng destination, String costing) {
    if (_cache.length >= _maxCacheSize) {
      _cache.removeAt(0);
    }
    _cache.add(_CachedRouteEntry(
      route: route,
      origin: origin,
      destination: destination,
      costing: costing,
      cachedAt: DateTime.now(),
    ));
  }

  RouteResult? _getCachedRoute(LatLng origin, LatLng destination, String costing) {
    for (int i = _cache.length - 1; i >= 0; i--) {
      final entry = _cache[i];
      if (!entry.isValid(_cacheTtl)) continue;
      if (entry.costing != costing) continue;

      final destDist = Geolocator.distanceBetween(
        entry.destination.latitude,
        entry.destination.longitude,
        destination.latitude,
        destination.longitude,
      );
      if (destDist > 50.0) continue;

      final originDist = Geolocator.distanceBetween(
        entry.origin.latitude,
        entry.origin.longitude,
        origin.latitude,
        origin.longitude,
      );
      if (originDist <= 120.0) {
        return entry.route;
      }
    }
    return null;
  }

  void _validateRouteContract(
      RouteResult route, LatLng origin, LatLng destination) {
    if (route.polyline.isEmpty) {
      throw const MalformedRouteException('Route polyline geometry is empty.');
    }
    if (route.distanceM <= 0) {
      throw const MalformedRouteException(
          'Route distance must be greater than zero.');
    }
    if (route.durationSec <= 0) {
      throw const MalformedRouteException(
          'Route duration must be greater than zero.');
    }

    final lastPoint = route.polyline.last;
    final endDistMeters = Geolocator.distanceBetween(
      lastPoint.latitude,
      lastPoint.longitude,
      destination.latitude,
      destination.longitude,
    );

    if (endDistMeters > 1000.0) {
      throw MalformedRouteException(
        'Route endpoint does not match job destination (${endDistMeters.toStringAsFixed(0)}m deviation).',
      );
    }
  }

  bool _isValidCoord(LatLng coord) {
    if (coord.latitude.abs() < 0.0001 && coord.longitude.abs() < 0.0001) {
      return false;
    }
    return coord.latitude.isFinite &&
        !coord.latitude.isNaN &&
        coord.longitude.isFinite &&
        !coord.longitude.isNaN &&
        coord.latitude >= -90.0 &&
        coord.latitude <= 90.0 &&
        coord.longitude >= -180.0 &&
        coord.longitude <= 180.0;
  }

  /// Cancels in-flight route requests immediately via CancelToken.
  void cancelActiveRequests() {
    _activeCancelToken?.cancel('cancelled_by_user');
    _activeCancelToken = null;
    _activeRequestGeneration++;
    _activeSessionId = '';
  }

  /// Clears cache and resets circuit breaker (for testing).
  @visibleForTesting
  void resetState() {
    _activeCancelToken?.cancel('reset');
    _activeCancelToken = null;
    _activeRequestGeneration = 0;
    _activeSessionId = '';
    _circuitState = CircuitBreakerState.closed;
    _consecutiveFailures = 0;
    _lastFailureTime = null;
    _cache.clear();
  }
}
