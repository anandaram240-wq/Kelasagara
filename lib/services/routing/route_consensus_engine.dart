import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';

/// Route Consensus Engine for Kelasagara V400.
/// Validates routes from multiple providers WITHOUT using LLM/AI.
/// Pure algorithmic comparison of distance, duration, and geometry.

/// Contains the evaluation result of multiple route providers.
class ConsensusResult {
  final RouteResult selectedRoute;
  final double confidence;
  final List<String> anomalies;
  final String selectionReason;

  const ConsensusResult({
    required this.selectedRoute,
    required this.confidence,
    required this.anomalies,
    required this.selectionReason,
  });
}

/// Singleton engine to validate and agree on the best route algorithmically.
class RouteConsensusEngine {
  RouteConsensusEngine._();
  
  /// Singleton instance
  static final RouteConsensusEngine instance = RouteConsensusEngine._();

  /// Evaluates multiple candidate routes and selects the most optimal/correct one.
  ConsensusResult evaluate(List<RouteResult> routes) {
    if (routes.isEmpty) {
      throw ArgumentError('Cannot evaluate empty route list');
    }

    if (routes.length == 1) {
      final route = routes.first;
      _validateRoute(route);
      return ConsensusResult(
        selectedRoute: route,
        confidence: 0.6,
        anomalies: ['Only one route provided, no cross-validation possible'],
        selectionReason: 'Single route fallback',
      );
    }

    if (routes.length == 2) {
      return _evaluateTwo(routes[0], routes[1]);
    }

    return _evaluateThree(routes);
  }

  ConsensusResult _evaluateTwo(RouteResult r1, RouteResult r2) {
    double confidence = 0.9;
    List<String> anomalies = [];

    // Compare distances
    final distDiff = (r1.distanceM - r2.distanceM).abs();
    final maxDist = (r1.distanceM > r2.distanceM ? r1.distanceM : r2.distanceM);
    if (maxDist > 0 && (distDiff / maxDist) > 0.4) {
      anomalies.add('Distance difference > 40%');
      confidence -= 0.2;
    }

    // Compare durations
    final durDiff = (r1.durationSec - r2.durationSec).abs();
    final maxDur = (r1.durationSec > r2.durationSec ? r1.durationSec : r2.durationSec);
    if (maxDur > 0 && (durDiff / maxDur) > 0.5) {
      anomalies.add('Duration difference > 50%');
      confidence -= 0.1;
    }
    
    // Compare endpoint matching
    const d = Distance();
    if (r1.polyline.isNotEmpty && r2.polyline.isNotEmpty) {
      final startDist = d.as(LengthUnit.Meter, r1.polyline.first, r2.polyline.first);
      final endDist = d.as(LengthUnit.Meter, r1.polyline.last, r2.polyline.last);
      if (startDist > 500) {
        anomalies.add('Start endpoints > 500m apart');
      }
      if (endDist > 500) {
        anomalies.add('Destination endpoints > 500m apart');
      }
    }

    final selected = r1.polyline.length >= r2.polyline.length ? r1 : r2;
    _validateRoute(selected);

    return ConsensusResult(
      selectedRoute: selected,
      confidence: confidence,
      anomalies: anomalies,
      selectionReason: 'Selected route with higher resolution (${selected.polyline.length} pts vs ${r1.polyline.length >= r2.polyline.length ? r2.polyline.length : r1.polyline.length})',
    );
  }

  ConsensusResult _evaluateThree(List<RouteResult> routes) {
    double confidence = 0.95;
    List<String> anomalies = [];
    
    bool allAgreeDist = true;
    for (int i = 0; i < routes.length; i++) {
      for (int j = i + 1; j < routes.length; j++) {
        final distDiff = (routes[i].distanceM - routes[j].distanceM).abs();
        final maxDist = (routes[i].distanceM > routes[j].distanceM ? routes[i].distanceM : routes[j].distanceM);
        if (maxDist > 0 && (distDiff / maxDist) > 0.2) {
          allAgreeDist = false;
          anomalies.add('Routes ${i+1} and ${j+1} distance difference > 20%');
        }
      }
    }
    
    if (!allAgreeDist) {
      confidence -= 0.15;
    }

    final sortedRoutes = List<RouteResult>.from(routes)
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    
    final medianRoute = sortedRoutes[1];
    _validateRoute(medianRoute);

    return ConsensusResult(
      selectedRoute: medianRoute,
      confidence: confidence,
      anomalies: anomalies,
      selectionReason: 'Majority vote / Median distance route selected',
    );
  }

  void _validateRoute(RouteResult route) {
    if (route.polyline.length < 2) {
      throw StateError('Route invalid: polyline length < 2');
    }
    if (route.distanceM <= 0 || route.durationSec <= 0) {
      throw StateError('Route invalid: distance or duration <= 0');
    }
    
    for (final pt in route.polyline) {
      if (pt.latitude.isNaN || pt.latitude.isInfinite || pt.longitude.isNaN || pt.longitude.isInfinite) {
        throw StateError('Route invalid: NaN or Infinite coordinates in polyline');
      }
      // India bounding box (6°-37°N, 68°-97°E)
      if (pt.latitude < 6.0 || pt.latitude > 37.0 || pt.longitude < 68.0 || pt.longitude > 97.0) {
        throw StateError('Route invalid: Points outside India bounding box');
      }
    }
    
    const d = Distance();
    for (int i = 0; i < route.polyline.length - 1; i++) {
      final dist = d.as(LengthUnit.Meter, route.polyline[i], route.polyline[i+1]);
      if (dist > 50000) {
        throw StateError('Route invalid: single-segment jump > 50km');
      }
    }
  }
}
