// lib/services/routing/routing_orchestrator.dart
// V400 Multi-Provider Routing Orchestrator for Kelasagara.
//
// Manages Valhalla (PRIMARY), OSRM (SECONDARY), and OpenRouteService (TERTIARY).
// Features:
//   - Provider health tracking with error rate and latency
//   - Automatic failover: PRIMARY → SECONDARY → TERTIARY
//   - Route versioning: stale async responses are discarded
//   - Route validation: polyline integrity, India bbox, endpoint proximity
//   - Route scoring when multiple providers return results
//   - Intelligent caching with origin/dest bucket keys and TTL
//   - Cancellation: in-flight requests cancelled on new request
//   - Telemetry: emits RoutingTelemetryEvent for diagnostics
//
// ABSOLUTE RULES:
//   - NEVER fake GPS, route, ETA, or road distance
//   - NEVER use AI/LLM to generate route geometry
//   - If ALL providers fail → return null, show honest error
//   - Valhalla = PRIMARY, OSRM = SECONDARY, ORS = TERTIARY

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/route_result.dart';
import 'routing_provider.dart';
import 'valhalla_route_provider.dart';
import 'osrm_route_provider.dart';
import 'ors_route_provider.dart';
import 'mapbox_route_provider.dart';
import 'route_consensus_engine.dart';

/// Telemetry event emitted on every route request for diagnostics.
class RoutingTelemetryEvent {
  final String provider;
  final int latencyMs;
  final bool success;
  final String? errorReason;
  final int routeVersion;
  final DateTime timestamp;

  const RoutingTelemetryEvent({
    required this.provider,
    required this.latencyMs,
    required this.success,
    this.errorReason,
    required this.routeVersion,
    required this.timestamp,
  });
}

/// Route cache entry with TTL.
class _CachedRoute {
  final RouteResult route;
  final LatLng originBucket;
  final LatLng destBucket;
  final DateTime cachedAt;

  _CachedRoute({
    required this.route,
    required this.originBucket,
    required this.destBucket,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMinutes > 5;
}

/// V800 Multi-Provider Routing Orchestrator.
///
/// Singleton that manages all routing providers and selects the best route
/// using Hedged Concurrent Racing, health tracking, failover, validation, and consensus.
class RoutingOrchestrator {
  RoutingOrchestrator._();
  static final RoutingOrchestrator instance = RoutingOrchestrator._();

  // ── Providers ──────────────────────────────────────────────────────────────
  late final MapboxRouteProvider _mapbox = MapboxRouteProvider();
  late final ValhallaRouteProvider _valhalla = ValhallaRouteProvider();
  late final OsrmRouteProvider _osrm = OsrmRouteProvider();
  late final OrsRouteProvider _ors = OrsRouteProvider();

  List<RoutingProvider> get _providers => [_mapbox, _valhalla, _osrm, _ors];

  /// The providers in priority order: Mapbox → Valhalla → OSRM → ORS.
  List<RoutingProvider> get _orderedProviders {
    final available = <RoutingProvider>[];
    if (_mapbox.isConfigured) available.add(_mapbox);
    if (_valhalla.isConfigured) available.add(_valhalla);
    available.add(_osrm); // OSRM always available (public)
    if (_ors.isConfigured) available.add(_ors);
    return available;
  }

  // ── Route versioning ───────────────────────────────────────────────────────
  int _routeVersion = 0;
  int get routeVersion => _routeVersion;

  // ── Cache ──────────────────────────────────────────────────────────────────
  _CachedRoute? _cache;

  // ── Single-flight in-flight request (V700 Fix D2) ─────────────────────────
  // Replaces the old boolean _isFetching guard that returned null to concurrent
  // callers. Now all callers for the same request await the same Future.
  Completer<RouteResult?>? _inFlight;
  // The origin/destination for the current in-flight request (for identity check).
  LatLng? _inFlightOriginBucket;
  LatLng? _inFlightDestBucket;

  // ── Telemetry ──────────────────────────────────────────────────────────────
  final StreamController<RoutingTelemetryEvent> _telemetryCtrl =
      StreamController<RoutingTelemetryEvent>.broadcast();
  Stream<RoutingTelemetryEvent> get telemetry => _telemetryCtrl.stream;

  final List<RoutingTelemetryEvent> _recentEvents = [];
  List<RoutingTelemetryEvent> get recentEvents =>
      List.unmodifiable(_recentEvents);

  // ── Last known source ─────────────────────────────────────────────────────
  String _lastRoutingSource = 'none';
  String get lastRoutingSource => _lastRoutingSource;

  // ── Get route (main entry point) ──────────────────────────────────────────
  /// Requests a route from providers in priority order.
  ///
  /// Returns a validated [RouteResult] or null if all providers fail.
  /// Never returns fake geometry. Never returns a straight-line fallback.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
    bool forceRefresh = false,
  }) async {
    // Validate inputs
    if (!_isValidCoord(origin) || !_isValidCoord(destination)) {
      debugPrint('[Orchestrator] Invalid coordinates: $origin → $destination');
      return null;
    }

    // Same position guard
    if ((origin.latitude - destination.latitude).abs() < 0.0001 &&
        (origin.longitude - destination.longitude).abs() < 0.0001) {
      debugPrint('[Orchestrator] Origin ≈ destination — no route needed');
      return null;
    }

    // Cache check
    if (!forceRefresh && _cache != null && !_cache!.isExpired) {
      final ob = _bucketize(origin);
      final db = _bucketize(destination);
      if (ob.latitude == _cache!.originBucket.latitude &&
          ob.longitude == _cache!.originBucket.longitude &&
          db.latitude == _cache!.destBucket.latitude &&
          db.longitude == _cache!.destBucket.longitude) {
        debugPrint('[Orchestrator] Cache hit');
        return _cache!.route;
      }
    }

    // V700 Fix D2: Single-flight guard using Completer.
    // If a request for the SAME origin+destination bucket is already in flight,
    // await it instead of starting a duplicate or returning null.
    final ob = _bucketize(origin);
    final db = _bucketize(destination);
    if (_inFlight != null && !forceRefresh) {
      // Check if in-flight request is for the same O/D bucket
      if (_inFlightOriginBucket?.latitude == ob.latitude &&
          _inFlightOriginBucket?.longitude == ob.longitude &&
          _inFlightDestBucket?.latitude == db.latitude &&
          _inFlightDestBucket?.longitude == db.longitude) {
        debugPrint('[Orchestrator] D2: request in flight — awaiting same Future');
        return _inFlight!.future;
      } else {
        // Different destination — do NOT reuse; fall through to start new request.
        // The old request will complete normally; its result will go to the old callers.
        debugPrint('[Orchestrator] D2: different destination — starting new request');
      }
    }

    final completer = Completer<RouteResult?>();
    _inFlight = completer;
    _inFlightOriginBucket = ob;
    _inFlightDestBucket = db;
    final requestVersion = ++_routeVersion;

    try {
      final providers = _orderedProviders;
      if (providers.isEmpty) {
        debugPrint('[Orchestrator] No providers configured');
        completer.complete(null);
        return null;
      }

      // Try each provider using Hedged Concurrent Racing (V800.2)
      final results = <RouteResult>[];
      String? lastProvider;

      Future<RouteResult?> fetchProvider(RoutingProvider provider) async {
        final sw = Stopwatch()..start();
        try {
          final route = await provider.calculateRoute(
            origin: origin,
            destination: destination,
            costing: costing,
          ).timeout(
            _timeoutFor(provider),
            onTimeout: () {
              debugPrint('[Orchestrator] ${provider.name} TIMEOUT');
              return null;
            },
          );
          sw.stop();

          _emitTelemetry(
            provider: provider.name,
            latencyMs: sw.elapsedMilliseconds,
            success: route != null,
            routeVersion: requestVersion,
          );

          if (requestVersion < _routeVersion) {
            debugPrint('[Orchestrator] Discarding stale response v$requestVersion');
            return null;
          }

          if (route != null && _validateRoute(route, origin, destination)) {
            debugPrint('[Orchestrator] ✅ ${provider.name}: ${route.distanceText}');
            return route;
          }
        } catch (e) {
          sw.stop();
          _emitTelemetry(
            provider: provider.name,
            latencyMs: sw.elapsedMilliseconds,
            success: false,
            errorReason: e.toString(),
            routeVersion: requestVersion,
          );
          debugPrint('[Orchestrator] ❌ ${provider.name} error: $e');
        }
        return null;
      }

      // T=0ms: Launch Primary
      final primary = providers[0];
      final primaryFuture = fetchProvider(primary);
      bool primaryDone = false;
      primaryFuture.whenComplete(() => primaryDone = true);

      RouteResult? winner;

      try {
        winner = await primaryFuture.timeout(const Duration(milliseconds: 600));
        if (winner != null) {
          lastProvider = primary.name;
        }
      } on TimeoutException {
        // T=600ms: Primary pending, Hedged Race triggered
        debugPrint('[Orchestrator] ⚡ Hedged Race Triggered: Primary ${primary.name} > 600ms');
      }

      if (winner == null && !primaryDone) {
        // Race primary against fallback providers sequentially
        for (int i = 1; i < providers.length; i++) {
          final fallback = providers[i];
          final fallbackFuture = fetchProvider(fallback);
          
          // Wait for either the primary (still running) or the new fallback
          final raceResult = await Future.any([
            primaryFuture.then((r) => r != null ? {'route': r, 'name': primary.name} : null),
            fallbackFuture.then((r) => r != null ? {'route': r, 'name': fallback.name} : null),
          ]);
          
          if (raceResult != null) {
             winner = raceResult['route'] as RouteResult;
             lastProvider = raceResult['name'] as String;
             break;
          }
          
          // If Future.any returned null, it means whichever finished first was null (failed).
          // Wait for the fallback explicitly just in case primary failed.
          final fRoute = await fallbackFuture;
          if (fRoute != null) {
            winner = fRoute;
            lastProvider = fallback.name;
            break;
          }
          
          // Check if primary finished in the meantime with success
          if (primaryDone) {
             final pRoute = await primaryFuture;
             if (pRoute != null) {
               winner = pRoute;
               lastProvider = primary.name;
               break;
             }
          }
        }
      } else if (winner == null && primaryDone) {
        // Primary failed within 600ms, iterate normally
        for (int i = 1; i < providers.length; i++) {
          final fallback = providers[i];
          winner = await fetchProvider(fallback);
          if (winner != null) {
            lastProvider = fallback.name;
            break;
          }
        }
      }

      if (winner != null) {
         results.add(winner);
      }

      if (results.isEmpty) {
        debugPrint('[Orchestrator] ALL providers failed — no route');
        _lastRoutingSource = 'none';
        completer.complete(null);
        return null;
      }

      // Select best route via consensus engine
      final consensus = RouteConsensusEngine.instance.evaluate(results);
      final selectedRoute = RouteResult(
        polyline: consensus.selectedRoute.polyline,
        durationSec: consensus.selectedRoute.durationSec,
        distanceM: consensus.selectedRoute.distanceM,
        steps: consensus.selectedRoute.steps,
        calculatedAt: consensus.selectedRoute.calculatedAt,
        routingEngine: consensus.selectedRoute.routingEngine,
        cumulativeDistances: consensus.selectedRoute.cumulativeDistances,
        routeVersion: requestVersion,
        confidence: consensus.confidence,
        provider: lastProvider ?? 'unknown',
      );

      // Cache
      _cache = _CachedRoute(
        route: selectedRoute,
        originBucket: ob,
        destBucket: db,
        cachedAt: DateTime.now(),
      );

      _lastRoutingSource = lastProvider ?? 'none';
      debugPrint('[Orchestrator] ✅ Route selected: ${selectedRoute.distanceText} '
          'via $lastProvider (confidence: ${(consensus.confidence * 100).toStringAsFixed(0)}%)');

      completer.complete(selectedRoute);
      return selectedRoute;
    } catch (e, st) {
      debugPrint('[Orchestrator] Unexpected error: $e\n$st');
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      // Always clear in-flight state so no future request is blocked.
      _inFlight = null;
      _inFlightOriginBucket = null;
      _inFlightDestBucket = null;
    }
  }

  // ── Matrix routing ────────────────────────────────────────────────────────
  /// Calculate a distance/duration matrix for multi-worker ranking.
  Future<MatrixResult?> getMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    for (final provider in _orderedProviders) {
      if (!provider.supportsMatrix) continue;
      try {
        final result = await provider.calculateMatrix(
          sources: sources,
          targets: targets,
        ).timeout(const Duration(seconds: 15));
        if (result != null) {
          debugPrint('[Orchestrator] Matrix from ${provider.name}: '
              '${sources.length}×${targets.length}');
          return result;
        }
      } catch (e) {
        debugPrint('[Orchestrator] Matrix error (${provider.name}): $e');
      }
    }
    return null;
  }

  // ── Health check all providers ────────────────────────────────────────────
  Future<Map<String, ProviderHealth>> checkAllProviders() async {
    final results = <String, ProviderHealth>{};
    for (final provider in _providers) {
      try {
        results[provider.name] = await provider.checkHealthDetailed()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        results[provider.name] = ProviderHealth(
          online: false,
          latencyMs: -1,
          lastFailure: DateTime.now(),
          consecutiveFails: 999,
        );
      }
    }
    return results;
  }

  // ── Clear cache ────────────────────────────────────────────────────────────
  void clearCache() {
    _cache = null;
    debugPrint('[Orchestrator] Cache cleared');
  }

  /// Clear cache if user has deviated significantly from the cached route.
  void clearCacheOnDeviation(LatLng currentPos) {
    if (_cache == null) return;
    final route = _cache!.route;
    if (route.polyline.isEmpty) return;

    // Check min distance to cached route
    double minDist = double.infinity;
    for (int i = 0; i < route.polyline.length - 1; i++) {
      final d = _ptSegDist(currentPos, route.polyline[i], route.polyline[i + 1]);
      if (d < minDist) minDist = d;
    }

    if (minDist > 200.0) {
      debugPrint('[Orchestrator] Deviation ${minDist.toStringAsFixed(0)}m > 200m — clearing cache');
      clearCache();
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────
  bool _validateRoute(RouteResult route, LatLng origin, LatLng dest) {
    // Polyline minimum
    if (route.polyline.length < 2) {
      debugPrint('[Orchestrator] Validation fail: <2 polyline points');
      return false;
    }

    // Non-zero distance and duration
    if (route.distanceM <= 0 || route.durationSec <= 0) {
      debugPrint('[Orchestrator] Validation fail: zero distance/duration');
      return false;
    }

    // Origin proximity (first polyline point within 500m)
    final originDist = Geolocator.distanceBetween(
      origin.latitude, origin.longitude,
      route.polyline.first.latitude, route.polyline.first.longitude,
    );
    if (originDist > 500) {
      debugPrint('[Orchestrator] Validation fail: origin ${originDist.toStringAsFixed(0)}m from polyline start');
      return false;
    }

    // Destination proximity (last polyline point within 500m)
    final destDist = Geolocator.distanceBetween(
      dest.latitude, dest.longitude,
      route.polyline.last.latitude, route.polyline.last.longitude,
    );
    if (destDist > 500) {
      debugPrint('[Orchestrator] Validation fail: dest ${destDist.toStringAsFixed(0)}m from polyline end');
      return false;
    }

    // India bounding box
    for (final pt in route.polyline) {
      if (pt.latitude < 6.0 || pt.latitude > 37.0 ||
          pt.longitude < 68.0 || pt.longitude > 97.0) {
        debugPrint('[Orchestrator] Validation fail: point outside India');
        return false;
      }
    }

    // No single-segment jump > 50km
    for (int i = 0; i < route.polyline.length - 1; i++) {
      final d = Geolocator.distanceBetween(
        route.polyline[i].latitude, route.polyline[i].longitude,
        route.polyline[i + 1].latitude, route.polyline[i + 1].longitude,
      );
      if (d > 50000) {
        debugPrint('[Orchestrator] Validation fail: ${(d / 1000).toStringAsFixed(1)}km jump');
        return false;
      }
    }

    return true;
  }

  bool _isValidCoord(LatLng coord) {
    if (coord.latitude.isNaN || coord.longitude.isNaN) return false;
    if (coord.latitude.isInfinite || coord.longitude.isInfinite) return false;
    if (coord.latitude == 0 && coord.longitude == 0) return false;
    if (coord.latitude.abs() > 90 || coord.longitude.abs() > 180) return false;
    return true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Bucket origin/dest to ±0.005° (~500m) for cache key.
  LatLng _bucketize(LatLng pos) => LatLng(
    (pos.latitude  * 200).round() / 200,
    (pos.longitude * 200).round() / 200,
  );

  /// Provider-specific timeouts (V700 Fix D4).
  /// Bounded timeouts prevent the 30+ second spinner on offline/unresponsive providers.
  Duration _timeoutFor(RoutingProvider provider) {
    switch (provider.name) {
      case 'valhalla':
        return const Duration(seconds: 5);
      case 'osrm':
        return const Duration(seconds: 6);
      case 'openrouteservice':
        return const Duration(seconds: 8);
      default:
        return const Duration(seconds: 6);
    }
  }

  void _emitTelemetry({
    required String provider,
    required int latencyMs,
    required bool success,
    String? errorReason,
    required int routeVersion,
  }) {
    final event = RoutingTelemetryEvent(
      provider: provider,
      latencyMs: latencyMs,
      success: success,
      errorReason: errorReason,
      routeVersion: routeVersion,
      timestamp: DateTime.now(),
    );
    _telemetryCtrl.add(event);
    _recentEvents.add(event);
    if (_recentEvents.length > 100) _recentEvents.removeAt(0);
  }

  /// Perpendicular distance from point P to segment AB.
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
