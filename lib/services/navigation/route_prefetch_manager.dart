// lib/services/navigation/route_prefetch_manager.dart
// Kelasagara Navigation V2: Route Prefetch & Caching Engine.
//
// Responsibilities:
//   - Pre-fetches Valhalla route when Work Detail screen opens.
//   - Caches validated routes strictly keyed by bookingId + destination + origin bucket.
//   - Zero cross-booking cache leakage.
//   - Provides instant (0ms network) transition to navigation if origin hasn't drifted.
//   - Invalidation on drift (> 100m) or staleness (> 5 minutes).

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/route_result.dart';
import '../../models/navigation_destination.dart';
import 'routing_facade.dart';

class CachedRouteEntry {
  final String bookingId;
  final LatLng origin;
  final NavigationDestination destination;
  final RouteResult route;
  final DateTime cachedAt;
  final int routeVersion;

  CachedRouteEntry({
    required this.bookingId,
    required this.origin,
    required this.destination,
    required this.route,
    required this.cachedAt,
    required this.routeVersion,
  });

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes >= 5;

  bool isValidFor({
    required String currentBookingId,
    required LatLng currentOrigin,
    required NavigationDestination currentDest,
    double maxDriftMeters = 100.0,
  }) {
    if (bookingId != currentBookingId) return false;
    if (isExpired) return false;
    if (destination.latitude != currentDest.latitude || destination.longitude != currentDest.longitude) {
      return false;
    }

    final drift = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      currentOrigin.latitude,
      currentOrigin.longitude,
    );

    return drift <= maxDriftMeters;
  }
}

class RoutePrefetchManager {
  RoutePrefetchManager._();
  static final RoutePrefetchManager instance = RoutePrefetchManager._();

  CachedRouteEntry? _currentCache;
  bool _isPrefetching = false;

  CachedRouteEntry? get currentCache => _currentCache;
  bool get isPrefetching => _isPrefetching;

  /// Attempts to prefetch a route for the given booking and destination.
  /// Deduplicates identical requests and updates the cache upon completion.
  Future<RouteResult?> prefetchRoute({
    required String bookingId,
    required LatLng origin,
    required NavigationDestination destination,
    required String sessionId,
    int routeVersion = 1,
  }) async {
    // 1. Check existing valid cache
    if (_currentCache != null &&
        _currentCache!.isValidFor(
          currentBookingId: bookingId,
          currentOrigin: origin,
          currentDest: destination,
        )) {
      debugPrint('[RoutePrefetch] Cache hit for booking $bookingId — reusing valid prefetched route');
      return _currentCache!.route;
    }

    if (_isPrefetching) {
      debugPrint('[RoutePrefetch] Prefetch already in progress — skipping duplicate');
      return null;
    }

    _isPrefetching = true;
    try {
      final route = await RoutingFacade.instance.calculateRoute(
        origin: origin,
        destination: destination.latLng,
        sessionId: sessionId,
        routeVersion: routeVersion,
      );

      _currentCache = CachedRouteEntry(
        bookingId: bookingId,
        origin: origin,
        destination: destination,
        route: route,
        cachedAt: DateTime.now(),
        routeVersion: routeVersion,
      );

      debugPrint('[RoutePrefetch] Successfully cached route for booking $bookingId');
      return route;
    } catch (e) {
      debugPrint('[RoutePrefetch] Prefetch non-fatal error: $e');
      return null;
    } finally {
      _isPrefetching = false;
    }
  }

  /// Checks if a valid prefetched route exists for the given booking, origin, and destination.
  RouteResult? getValidPrefetchedRoute({
    required String bookingId,
    required LatLng origin,
    required NavigationDestination destination,
  }) {
    if (_currentCache != null &&
        _currentCache!.isValidFor(
          currentBookingId: bookingId,
          currentOrigin: origin,
          currentDest: destination,
        )) {
      return _currentCache!.route;
    }
    return null;
  }

  /// Invalidate cache when booking changes, cancels, or completes.
  void invalidate({String? bookingId}) {
    if (bookingId == null || _currentCache?.bookingId == bookingId) {
      _currentCache = null;
      debugPrint('[RoutePrefetch] Cache invalidated');
    }
  }

  /// Clears the entire prefetch cache.
  void clearAll() => invalidate();
}
