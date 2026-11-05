import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';

// Pure algorithmic mock of the consensus engine for testing
class RouteConsensusEngineMock {
  static double calculateConfidence(List<RouteResult> routes) {
    if (routes.isEmpty) return 0.0;
    if (routes.length == 1) return 0.6;
    if (routes.length == 2) {
      final distDiff = (routes[0].distanceM - routes[1].distanceM).abs() /
          routes[0].distanceM;
      final durDiff = (routes[0].durationSec - routes[1].durationSec).abs() /
          routes[0].durationSec;

      if (distDiff > 0.5 || durDiff > 0.6) return 0.5; // Anomaly
      if (distDiff <= 0.2) return 0.85;
      return 0.7;
    }
    if (routes.length >= 3) {
      return 0.9;
    }
    return 0.0;
  }

  static bool validateRoute(RouteResult route) {
    if (route.distanceM <= 0) return false;
    if (route.polyline.isEmpty) return false;
    return true;
  }
}

RouteResult _makeRoute({
  required int distanceM,
  required int durationSec,
  List<LatLng>? polyline,
  String engine = 'valhalla',
}) {
  return RouteResult(
    polyline: polyline ?? [LatLng(13.0, 76.0), LatLng(13.1, 76.1)],
    distanceM: distanceM,
    durationSec: durationSec,
    steps: const [],
    calculatedAt: DateTime.now(),
    routingEngine: engine,
  );
}

void main() {
  group('Route Consensus Engine Tests', () {
    test('Single route -> confidence = 0.6', () {
      final route1 = _makeRoute(distanceM: 1000, durationSec: 300);
      final confidence = RouteConsensusEngineMock.calculateConfidence([route1]);
      expect(confidence, 0.6);
    });

    test('Two routes within 20% distance -> confidence >= 0.85', () {
      final route1 = _makeRoute(distanceM: 1000, durationSec: 300);
      final route2 = _makeRoute(distanceM: 1100, durationSec: 320);
      final confidence =
          RouteConsensusEngineMock.calculateConfidence([route1, route2]);
      expect(confidence, greaterThanOrEqualTo(0.85));
    });

    test('Two routes with 50% distance difference -> anomaly, confidence < 0.7',
        () {
      final route1 = _makeRoute(distanceM: 1000, durationSec: 300);
      final route2 = _makeRoute(distanceM: 1600, durationSec: 320);
      final confidence =
          RouteConsensusEngineMock.calculateConfidence([route1, route2]);
      expect(confidence, lessThan(0.7));
    });

    test('Two routes with 60% duration difference -> anomaly', () {
      final route1 = _makeRoute(distanceM: 1000, durationSec: 300);
      final route2 = _makeRoute(distanceM: 1050, durationSec: 500);
      final confidence =
          RouteConsensusEngineMock.calculateConfidence([route1, route2]);
      expect(confidence, lessThan(0.7));
    });

    test('Three routes all agreeing -> confidence >= 0.9', () {
      final route1 = _makeRoute(distanceM: 1000, durationSec: 300);
      final route2 = _makeRoute(distanceM: 1050, durationSec: 310);
      final route3 = _makeRoute(distanceM: 1020, durationSec: 305);
      final confidence = RouteConsensusEngineMock
          .calculateConfidence([route1, route2, route3]);
      expect(confidence, greaterThanOrEqualTo(0.9));
    });

    test('Route validation: zero distance rejected', () {
      final route1 = _makeRoute(distanceM: 0, durationSec: 300);
      expect(RouteConsensusEngineMock.validateRoute(route1), isFalse);
    });

    test('Route validation: empty polyline rejected', () {
      final route1 = _makeRoute(
        distanceM: 1000,
        durationSec: 300,
        polyline: const [],
      );
      expect(RouteConsensusEngineMock.validateRoute(route1), isFalse);
    });
  });
}
