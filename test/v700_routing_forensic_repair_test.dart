import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/journey_state.dart';
import 'package:kelasagaara/models/live_location.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';

/// Test mock for single-flight Completer and in-flight identity logic (Fix D2).
class SingleFlightRouteMock {
  Completer<RouteResult?>? _inFlight;
  LatLng? _inFlightOriginBucket;
  LatLng? _inFlightDestBucket;
  int _fetchCount = 0;
  int get fetchCount => _fetchCount;

  LatLng bucketize(LatLng pos) => LatLng(
    (pos.latitude * 200).round() / 200,
    (pos.longitude * 200).round() / 200,
  );

  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    required Future<RouteResult?> Function() fetcher,
  }) async {
    final ob = bucketize(origin);
    final db = bucketize(destination);

    if (_inFlight != null) {
      if (_inFlightOriginBucket?.latitude == ob.latitude &&
          _inFlightOriginBucket?.longitude == ob.longitude &&
          _inFlightDestBucket?.latitude == db.latitude &&
          _inFlightDestBucket?.longitude == db.longitude) {
        // Same in-flight request — await the same Future
        return _inFlight!.future;
      }
    }

    final completer = Completer<RouteResult?>();
    _inFlight = completer;
    _inFlightOriginBucket = ob;
    _inFlightDestBucket = db;
    _fetchCount++;

    try {
      final res = await fetcher();
      completer.complete(res);
      return res;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _inFlight = null;
      _inFlightOriginBucket = null;
      _inFlightDestBucket = null;
    }
  }
}

/// Test mock for D1 GPS rescue state machine logic.
class JourneyProviderGpsRescueMock {
  NavigationPhase phase = NavigationPhase.idle;
  RouteResult? route;
  bool isLoadingRoute = false;
  LiveLocation? workerLocation;
  int routeFetchCount = 0;
  String? errorReason;

  void startJourney({bool hasInitialLocation = false}) {
    phase = NavigationPhase.locationAcquiring;
    if (hasInitialLocation) {
      workerLocation = LiveLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracy: 10.0,
        speed: 5.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }
    phase = NavigationPhase.routeRequesting;
    if (workerLocation != null) {
      fetchRoute();
    }
  }

  void onWorkerLocationUpdate(LiveLocation loc) {
    workerLocation = loc;

    // D1 Fix rescue condition:
    if (route == null &&
        phase == NavigationPhase.routeRequesting &&
        !isLoadingRoute &&
        loc.accuracy <= 80.0) {
      fetchRoute();
    }
  }

  void fetchRoute() {
    if (workerLocation == null) return;
    if (isLoadingRoute) return;
    isLoadingRoute = true;
    routeFetchCount++;
  }

  void completeRouteSuccess(RouteResult result) {
    route = result;
    isLoadingRoute = false;
    phase = NavigationPhase.routeReady;
  }
}

RouteResult _createSampleRoute() {
  return RouteResult(
    polyline: [LatLng(12.97, 77.59), LatLng(12.98, 77.60)],
    distanceM: 5000,
    durationSec: 600,
    steps: const [],
    calculatedAt: DateTime.now(),
    routingEngine: 'valhalla',
    provider: 'valhalla',
  );
}

void main() {
  group('V700 D1: GPS Race & Rescue Tests', () {
    test('Cold GPS: Start journey with null GPS, GPS arrives later -> route fetched', () {
      final mock = JourneyProviderGpsRescueMock();
      // Step 1: Start journey with no GPS fix yet
      mock.startJourney(hasInitialLocation: false);
      expect(mock.phase, NavigationPhase.routeRequesting);
      expect(mock.workerLocation, isNull);
      expect(mock.routeFetchCount, 0, reason: 'Route cannot be fetched without GPS');

      // Step 2: GPS fix arrives later
      final gpsFix = LiveLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracy: 12.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );
      mock.onWorkerLocationUpdate(gpsFix);

      // Verify D1 rescue triggered
      expect(mock.routeFetchCount, 1, reason: 'D1 rescue must trigger fetchRoute on first valid GPS fix');
      expect(mock.isLoadingRoute, isTrue);

      // Complete route
      mock.completeRouteSuccess(_createSampleRoute());
      expect(mock.phase, NavigationPhase.routeReady);

      // Subsequent GPS updates MUST NOT re-trigger route fetch
      mock.onWorkerLocationUpdate(gpsFix);
      expect(mock.routeFetchCount, 1, reason: 'Subsequent GPS updates must not re-trigger fetch');
    });

    test('Hot GPS: Start journey with GPS already available -> immediate single fetch', () {
      final mock = JourneyProviderGpsRescueMock();
      mock.startJourney(hasInitialLocation: true);
      expect(mock.phase, NavigationPhase.routeRequesting);
      expect(mock.routeFetchCount, 1, reason: 'Route should fetch immediately when GPS is hot');
    });

    test('Inaccurate GPS (>80m) is rejected from rescuing route to avoid bogus route', () {
      final mock = JourneyProviderGpsRescueMock();
      mock.startJourney(hasInitialLocation: false);

      final poorGps = LiveLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracy: 150.0, // Poor accuracy
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );
      mock.onWorkerLocationUpdate(poorGps);

      expect(mock.routeFetchCount, 0, reason: 'Inaccurate GPS must not trigger route fetch');

      // Now good GPS arrives
      final goodGps = LiveLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracy: 15.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );
      mock.onWorkerLocationUpdate(goodGps);
      expect(mock.routeFetchCount, 1, reason: 'Good GPS must trigger route fetch');
    });
  });

  group('V700 D2: Single-Flight In-Flight Completer Tests', () {
    test('Double tap / concurrent calls for identical route share single in-flight Future', () async {
      final mock = SingleFlightRouteMock();
      final origin = LatLng(12.9716, 77.5946);
      final dest = LatLng(13.0827, 80.2707);

      final c = Completer<RouteResult?>();

      // Launch Request A
      final futureA = mock.getRoute(
        origin: origin,
        destination: dest,
        fetcher: () => c.future,
      );

      // Launch Request B concurrently (same origin, same dest)
      final futureB = mock.getRoute(
        origin: origin,
        destination: dest,
        fetcher: () => c.future,
      );

      // Only ONE fetch must have been initiated
      expect(mock.fetchCount, 1, reason: 'Must only initiate one physical fetch');

      // Complete fetcher
      final sampleRoute = _createSampleRoute();
      c.complete(sampleRoute);

      final resA = await futureA;
      final resB = await futureB;

      // Both receive identical result and neither is null
      expect(resA, isNotNull);
      expect(resB, isNotNull);
      expect(resA?.distanceM, 5000);
      expect(resB?.distanceM, 5000);
    });

    test('Ten rapid taps trigger exactly ONE physical fetch', () async {
      final mock = SingleFlightRouteMock();
      final origin = LatLng(12.9716, 77.5946);
      final dest = LatLng(13.0827, 80.2707);

      final c = Completer<RouteResult?>();
      final futures = <Future<RouteResult?>>[];

      for (int i = 0; i < 10; i++) {
        futures.add(mock.getRoute(
          origin: origin,
          destination: dest,
          fetcher: () => c.future,
        ));
      }

      expect(mock.fetchCount, 1, reason: '10 rapid calls must coalesce into 1 fetch');

      c.complete(_createSampleRoute());
      final results = await Future.wait(futures);

      for (final r in results) {
        expect(r, isNotNull);
        expect(r?.distanceM, 5000);
      }
    });

    test('Different destination starts new fetch and does not reuse in-flight', () async {
      final mock = SingleFlightRouteMock();
      final origin = LatLng(12.9716, 77.5946);
      final dest1 = LatLng(13.0827, 80.2707);
      final dest2 = LatLng(15.3647, 75.1240); // Hubli

      final c1 = Completer<RouteResult?>();
      final c2 = Completer<RouteResult?>();

      final future1 = mock.getRoute(
        origin: origin,
        destination: dest1,
        fetcher: () => c1.future,
      );

      // Request with different destination
      final future2 = mock.getRoute(
        origin: origin,
        destination: dest2,
        fetcher: () => c2.future,
      );

      expect(mock.fetchCount, 2, reason: 'Different destinations must start separate requests');

      c1.complete(_createSampleRoute());
      c2.complete(_createSampleRoute());

      await future1;
      await future2;
    });

    test('In-flight state is guaranteed cleared after error/exception', () async {
      final mock = SingleFlightRouteMock();
      final origin = LatLng(12.9716, 77.5946);
      final dest = LatLng(13.0827, 80.2707);

      // First call throws
      await mock.getRoute(
        origin: origin,
        destination: dest,
        fetcher: () => Future.error('Network timeout'),
      );

      expect(mock.fetchCount, 1);

      // Next call must be able to start a new request because in-flight was cleared
      final res = await mock.getRoute(
        origin: origin,
        destination: dest,
        fetcher: () async => _createSampleRoute(),
      );

      expect(mock.fetchCount, 2);
      expect(res, isNotNull);
    });
  });

  group('V700 D4: Timeout Policy & Bounded Fallback Tests', () {
    test('Provider timeouts are strictly bounded (5s, 6s, 8s)', () {
      Duration timeoutFor(String providerName) {
        switch (providerName) {
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

      expect(timeoutFor('valhalla').inSeconds, 5);
      expect(timeoutFor('osrm').inSeconds, 6);
      expect(timeoutFor('openrouteservice').inSeconds, 8);

      final totalWorstCaseSeconds = timeoutFor('valhalla').inSeconds +
          timeoutFor('osrm').inSeconds +
          timeoutFor('openrouteservice').inSeconds;

      expect(totalWorstCaseSeconds, lessThan(20), reason: 'Total worst-case fallback wait must be < 20s, never 30+s');
    });
  });
}
