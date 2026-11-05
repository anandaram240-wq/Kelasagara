// lib/services/route_service.dart
// Canonical route service for Kelasagara.
// Primary engine: Valhalla (self-hosted via Docker).
// Fallback: HERE API (if HERE_API_KEY is set).
//
// Requires --dart-define=VALHALLA_URL=http://192.168.x.x:8002
// to activate routing. Without it, all calls return null immediately
// and log the error clearly — NO silent failure.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/journey_state.dart';
import 'valhalla_service.dart';
import 'routing/routing_orchestrator.dart';

// Routing state exposed to UI
enum RouteState {
  idle,
  loading,
  ready,
  stale,
  recalculating,
  failed,        // server returned error
  unavailable,   // server not configured / offline
}

class RouteService {
  RouteService._();
  static final RouteService instance = RouteService._();

  // ── Cache ─────────────────────────────────────────────────────────────────
  RouteResult? _cached;
  LatLng?      _cachedOriginSegment;   // coarse origin bucket (±0.01°)
  LatLng?      _cachedDest;
  DateTime?    _lastCalcTime;

  // V700 Fix D2: single-flight Future replaces _isFetching bool.
  // Concurrent callers for the same request await the shared Future.
  Future<RouteResult?>? _inFlight;
  LatLng?               _inFlightOriginBucket;
  LatLng?               _inFlightDest;

  RouteState   _state = RouteState.idle;
  RouteState   get state => _state;
  String       _lastError = '';
  String       get lastError => _lastError;

  RouteResult? get cached => _cached;

  // ── Get route ─────────────────────────────────────────────────────────────
  // Returns null when routing unavailable — caller must show error state.
  // Never returns fake/stub data.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    bool forceRefresh = false,
  }) async {
    final originBucket = _bucketize(origin);

    // Guard: in-flight — if concurrent request is for the exact same O/D bucket, await the same Future
    if (_inFlight != null) {
      if (_inFlightOriginBucket?.latitude == originBucket.latitude &&
          _inFlightOriginBucket?.longitude == originBucket.longitude &&
          _inFlightDest?.latitude == destination.latitude &&
          _inFlightDest?.longitude == destination.longitude) {
        debugPrint('[RouteService] D2: identical request in flight — awaiting same Future');
        return _inFlight;
      }
      // If in flight for a different O/D pair, await its completion first to avoid race conditions
      try {
        await _inFlight;
      } catch (_) {}
    }

    // Guard: cooldown
    if (!forceRefresh && _cached != null && _lastCalcTime != null) {
      final elapsedSec = DateTime.now().difference(_lastCalcTime!).inSeconds;
      if (elapsedSec < TrackingConfig.minRouteRecalcIntervalSec) {
        debugPrint('[RouteService] Cooldown (${elapsedSec}s) — returning cached');
        return _cached;
      }
    }

    // Guard: same origin bucket + same dest → return valid cache
    if (!forceRefresh && _cached != null && !_cached!.isStale &&
        _cachedDest?.latitude  == destination.latitude &&
        _cachedDest?.longitude == destination.longitude &&
        _cachedOriginSegment?.latitude  == originBucket.latitude &&
        _cachedOriginSegment?.longitude == originBucket.longitude) {
      debugPrint('[RouteService] Cache hit — returning cached route');
      return _cached;
    }

    _state = RouteState.loading;

    // Create the shared Future and store it for concurrent callers
    _inFlightOriginBucket = originBucket;
    _inFlightDest = destination;
    final future = _doFetch(origin: origin, destination: destination,
        forceRefresh: forceRefresh, originBucket: originBucket);
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
      _inFlightOriginBucket = null;
      _inFlightDest = null;
    }
  }

  Future<RouteResult?> _doFetch({
    required LatLng origin,
    required LatLng destination,
    required bool forceRefresh,
    required LatLng originBucket,
  }) async {
    try {
      // V600 FIX: Route via RoutingOrchestrator — Valhalla → OSRM → ORS failover.
      final result = await RoutingOrchestrator.instance.getRoute(
        origin:      origin,
        destination: destination,
        forceRefresh: forceRefresh,
      );

      if (result != null) {
        _cached              = result;
        _cachedDest          = destination;
        _cachedOriginSegment = originBucket;
        _lastCalcTime        = DateTime.now();
        _state               = RouteState.ready;
        _lastError           = '';
        debugPrint('[RouteService] ✅ Route cached: ${result.distanceText} / ${result.etaText} '
            '(via ${result.provider})');
        return result;
      }

      // V400 FIX: Route failed — NEVER return stale cache.
      _state     = ValhallaService.instance.lastKnownStatus == RoutingStatus.offline
          ? RouteState.unavailable
          : RouteState.failed;
      _lastError = _state == RouteState.unavailable
          ? 'All routing providers offline (Valhalla+OSRM+ORS)'
          : 'Route not found between these points';
      debugPrint('[RouteService] ❌ $_lastError');
      return null;
    } catch (e) {
      _state     = RouteState.failed;
      _lastError = 'Route request threw: $e';
      debugPrint('[RouteService] ❌ Exception: $e');
      return null;
    }
  }

  // ── Reroute if off course ─────────────────────────────────────────────────
  // NOTE (V600): This is called ONLY from JourneyProvider for route display
  // updates on the HIRER side. NavigationEngine is the single rerouting
  // authority for the worker side. Double-reroute race is fixed in
  // JourneyProvider._onWorkerLocationUpdate().
  Future<RouteResult?> rerouteIfNeeded({
    required LatLng workerPos,
    required LatLng destination,
  }) async {
    if (_cached == null) {
      return getRoute(origin: workerPos, destination: destination);
    }
    // D2 Fix: Do NOT apply the 120s cooldown guard here.
    // rerouteIfNeeded() is only called when NavigationEngine has already
    // confirmed an off-route condition (3 consecutive fixes > 50m deviation).
    // Blocking the reroute for 120s after the PREVIOUS route fetch causes the
    // worker to navigate on a stale/wrong route. The deviation check below is
    // the correct throttle: if not actually off-route, the cached route is returned.

    final deviation = _minDistFromPolyline(workerPos, _cached!.polyline);
    debugPrint('[RouteService] Deviation: ${deviation.toStringAsFixed(0)}m '
        '(threshold: ${TrackingConfig.routeDeviationM}m)');

    if (deviation > TrackingConfig.routeDeviationM) {
      _state = RouteState.recalculating;
      debugPrint('[RouteService] Off-route → rerouting via Orchestrator');
      return getRoute(origin: workerPos, destination: destination, forceRefresh: true);
    }
    return _cached;
  }

  void clearCache() {
    _cached              = null;
    _cachedDest          = null;
    _cachedOriginSegment = null;
    _lastCalcTime        = null;
    _inFlightOriginBucket = null;
    _inFlightDest         = null;
    _state               = RouteState.idle;
    _lastError           = '';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  // Bucket origin to ±0.01° (~1 km) to avoid cache misses on GPS jitter
  LatLng _bucketize(LatLng pos) => LatLng(
    (pos.latitude  * 100).round() / 100,
    (pos.longitude * 100).round() / 100,
  );

  // V400 FIX: Use perpendicular distance to polyline SEGMENTS, not just
  // vertices. The old vertex-only check caused false off-route triggers on
  // long highway segments (e.g. 500m between vertices).
  double _minDistFromPolyline(LatLng pos, List<LatLng> poly) {
    if (poly.isEmpty) return double.infinity;
    if (poly.length == 1) {
      return Geolocator.distanceBetween(
          pos.latitude, pos.longitude, poly[0].latitude, poly[0].longitude);
    }
    double minD = double.infinity;
    for (int i = 0; i < poly.length - 1; i++) {
      final d = _ptSegDist(pos, poly[i], poly[i + 1]);
      if (d < minD) minD = d;
    }
    return minD;
  }

  /// Perpendicular distance from point P to line segment AB.
  /// Uses flat-Earth approximation (accurate enough for < 1km distances).
  static double _ptSegDist(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude  - a.latitude;
    if (dx == 0 && dy == 0) {
      return Geolocator.distanceBetween(
          p.latitude, p.longitude, a.latitude, a.longitude);
    }
    var t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy)
        / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);
    final projLat = a.latitude  + t * dy;
    final projLng = a.longitude + t * dx;
    return Geolocator.distanceBetween(
        p.latitude, p.longitude, projLat, projLng);
  }
}
