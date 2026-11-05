import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';

/// Pure-logic mock of the V400 RoutingOrchestrator for unit testing.
/// Tests orchestrator logic without network or platform dependencies.
class RoutingOrchestratorMock {
  int _version = 0;

  int getRouteVersion() {
    _version++;
    return _version;
  }

  bool isRouteStale(DateTime routeTime) {
    return DateTime.now().difference(routeTime).inMinutes > 10;
  }

  bool validateCoordinates(LatLng coord) {
    if (coord.latitude == 0 && coord.longitude == 0) return false;
    if (coord.latitude.isNaN || coord.longitude.isNaN) return false;
    if (coord.latitude.isInfinite || coord.longitude.isInfinite) return false;
    if (coord.latitude < 6 || coord.latitude > 37) return false;
    if (coord.longitude < 68 || coord.longitude > 97) return false;
    return true;
  }

  bool isSamePosition(LatLng origin, LatLng destination) {
    final latDiff = (origin.latitude - destination.latitude).abs();
    final lngDiff = (origin.longitude - destination.longitude).abs();
    return latDiff < 0.0001 && lngDiff < 0.0001;
  }

  bool validateRoute(RouteResult route) {
    if (route.distanceM <= 0) return false;
    if (route.durationSec <= 0) return false;
    if (route.polyline.length < 2) return false;
    return true;
  }

  bool isSameCacheBucket(LatLng pos1, LatLng pos2) {
    final latDiff = (pos1.latitude - pos2.latitude).abs();
    final lngDiff = (pos1.longitude - pos2.longitude).abs();
    return latDiff <= 0.01 && lngDiff <= 0.01;
  }

  String selectProvider(bool valhallaAvailable, bool osrmAvailable) {
    if (valhallaAvailable) return 'valhalla';
    if (osrmAvailable) return 'osrm';
    return 'none';
  }
}

RouteResult _makeValidRoute({
  int distanceM = 15000,
  int durationSec = 1800,
  String engine = 'valhalla',
}) {
  return RouteResult(
    polyline: [LatLng(12.97, 77.59), LatLng(12.98, 77.60), LatLng(13.00, 77.75)],
    distanceM: distanceM,
    durationSec: durationSec,
    steps: const [],
    calculatedAt: DateTime.now(),
    routingEngine: engine,
  );
}

void main() {
  group('Routing Orchestrator Tests', () {
    test('Route version increment', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.getRouteVersion(), 1);
      expect(orch.getRouteVersion(), 2);
      expect(orch.getRouteVersion(), 3);
    });

    test('Stale route detection (>10 min)', () {
      final orch = RoutingOrchestratorMock();
      final staleTime = DateTime.now().subtract(const Duration(minutes: 15));
      final freshTime = DateTime.now().subtract(const Duration(minutes: 5));
      expect(orch.isRouteStale(staleTime), isTrue);
      expect(orch.isRouteStale(freshTime), isFalse);
    });

    test('Coordinate validation rejects (0,0) and NaN', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.validateCoordinates(LatLng(0, 0)), isFalse);
      expect(orch.validateCoordinates(LatLng(double.nan, 77.0)), isFalse);
      expect(orch.validateCoordinates(LatLng(12.97, double.infinity)), isFalse);
    });

    test('Same position (origin ≈ destination) rejected', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.isSamePosition(
        LatLng(12.9716, 77.5946),
        LatLng(12.97165, 77.59465),
      ), isTrue);
      expect(orch.isSamePosition(
        LatLng(12.9716, 77.5946),
        LatLng(13.0, 77.6),
      ), isFalse);
    });

    test('India bounding box: Bangalore OK, London rejected', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.validateCoordinates(LatLng(12.9716, 77.5946)), isTrue);
      expect(orch.validateCoordinates(LatLng(51.5, -0.1)), isFalse);
    });

    test('Route validation: distance > 0, duration > 0, polyline >= 2', () {
      final orch = RoutingOrchestratorMock();
      final validRoute = _makeValidRoute();
      expect(orch.validateRoute(validRoute), isTrue);

      final zeroDistRoute = _makeValidRoute(distanceM: 0);
      expect(orch.validateRoute(zeroDistRoute), isFalse);

      final zeroDurRoute = _makeValidRoute(durationSec: 0);
      expect(orch.validateRoute(zeroDurRoute), isFalse);

      final emptyPolyRoute = RouteResult(
        polyline: const [],
        distanceM: 1000,
        durationSec: 300,
        steps: const [],
        calculatedAt: DateTime.now(),
      );
      expect(orch.validateRoute(emptyPolyRoute), isFalse);
    });

    test('Cache bucket: positions within 0.01° -> same bucket', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.isSameCacheBucket(
        LatLng(12.9716, 77.5946),
        LatLng(12.9750, 77.5990),
      ), isTrue);
      expect(orch.isSameCacheBucket(
        LatLng(12.9716, 77.5946),
        LatLng(13.1000, 77.7000),
      ), isFalse);
    });

    test('Provider priority: Valhalla > OSRM', () {
      final orch = RoutingOrchestratorMock();
      expect(orch.selectProvider(true, true), 'valhalla');
      expect(orch.selectProvider(false, true), 'osrm');
      expect(orch.selectProvider(false, false), 'none');
    });
  });
}
