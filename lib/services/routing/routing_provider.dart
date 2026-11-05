// lib/services/routing/routing_provider.dart
// Abstract routing provider interface for Kelasagara.
// Decouples routing engine implementation (Valhalla, OSRM, Cloudflare Tunnel, Mapbox)
// from application navigation state and business logic.

import 'package:latlong2/latlong.dart';
import '../../models/route_result.dart';

enum PolylineEncoding { polyline5, polyline6 }

enum ProviderPriority { primary, secondary, tertiary }

class ProviderHealth {
  final bool online;
  final int latencyMs;
  final DateTime? lastSuccess;
  final DateTime? lastFailure;
  final int consecutiveFails;

  const ProviderHealth({
    required this.online,
    required this.latencyMs,
    this.lastSuccess,
    this.lastFailure,
    this.consecutiveFails = 0,
  });

  double get errorRate => consecutiveFails > 0 ? (consecutiveFails / 10.0).clamp(0.0, 1.0) : 0.0;
}

class MatrixResult {
  final List<LatLng> sources;
  final List<LatLng> targets;
  final List<List<double?>> distances;
  final List<List<int?>> durations;

  const MatrixResult({
    required this.sources,
    required this.targets,
    required this.distances,
    required this.durations,
  });
}

abstract class RoutingProvider {
  /// Name identifier of the engine (e.g., 'valhalla', 'osrm')
  String get name;

  /// Polyline encoding format used by the provider
  PolylineEncoding get polylineEncoding;

  /// Priority of this provider
  ProviderPriority get priority;

  /// Whether this provider supports matrix calculations
  bool get supportsMatrix;

  /// Check if the routing engine backend is available and responsive.
  /// Default delegates to checkHealthDetailed().
  Future<bool> checkHealth();

  /// Detailed health check
  Future<ProviderHealth> checkHealthDetailed();

  /// Calculate a driving route between [origin] and [destination].
  /// Returns a validated [RouteResult] or null if the provider fails.
  /// Implementations MUST NOT return fake or straight-line geometry.
  Future<RouteResult?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
  });

  /// Calculate a time and distance matrix
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  });
}
