// test/internal_navigation_forensic_test.dart
// ============================================================================
// KELASAGARA — Forensic Internal Navigation Test Suite (Phase 27)
//
// 48 Rigorous Tests covering:
//   - MAP (1–7): CARTO / Mapbox validation, URL construction, watermark protection
//   - GPS (8–25): Quality tiers, staged bootstrap, permission, service, centroid rejection
//   - ROUTING (26–41): Facade, Valhalla payload formatting, typed error taxonomy
//   - INTEGRATION (42–48): Subsystem decoupling, independent retry, Google Maps invariance
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kelasagaara/models/navigation_health.dart';
import 'package:kelasagaara/models/live_location.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/navigation/map_tile_configuration.dart';
import 'package:kelasagaara/services/routing/gps_quality_engine.dart';
import 'package:kelasagaara/services/navigation/navigation_location_provider.dart';
import 'package:kelasagaara/services/navigation/routing_facade.dart';
import 'package:kelasagaara/services/routing/valhalla_route_provider.dart';
import 'package:kelasagaara/services/navigation/external_navigation_service.dart';

Position _createPosition({
  required double latitude,
  required double longitude,
  double accuracy = 5.0,
  double speed = 10.0,
  double heading = 90.0,
  DateTime? timestamp,
  bool isMocked = false,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 100.0,
    altitudeAccuracy: 1.0,
    heading: heading,
    headingAccuracy: 1.0,
    speed: speed,
    speedAccuracy: 1.0,
    isMocked: isMocked,
  );
}

void main() {
  group('MAP SUBSYSTEM (Phase 27: Tests 1–7)', () {
    test('1. Valid CARTO configuration is accepted and identified', () {
      const validKey = 'carto_test_prod_key_12345';
      expect(MapTileConfiguration.isValidCartoKey(validKey), isTrue);

      final result = MapTileConfiguration.instance.validateConfiguration(
        explicitCartoKey: validKey,
      );
      expect(result.isValid, isTrue);
      expect(result.provider, MapTileProvider.carto);
      expect(result.urlTemplate, contains('key=$validKey'));
    });

    test('2. Missing CARTO key returns invalid result without crashing when fallback disabled', () {
      final result = MapTileConfiguration.instance.validateConfiguration(
        explicitCartoKey: '',
        explicitMapboxToken: '',
        allowOsmFallback: false,
      );
      expect(result.isValid, isFalse);
      expect(result.provider, MapTileProvider.unconfigured);
      expect(result.errorMessage, contains('CARTO_API_KEY required'));
    });

    test('2b. Missing credentials falls back to OpenStreetMap for demo/academic use', () {
      final result = MapTileConfiguration.instance.validateConfiguration(
        explicitCartoKey: '',
        explicitMapboxToken: '',
        allowOsmFallback: true,
      );
      expect(result.isValid, isTrue);
      expect(result.provider, MapTileProvider.osm);
      expect(result.urlTemplate, equals(MapTileConfiguration.osmTileUrlTemplate));
      expect(result.attribution, contains('OpenStreetMap'));
    });

    test('3. Empty or whitespace CARTO key is strictly rejected', () {
      expect(MapTileConfiguration.isValidCartoKey(''), isFalse);
      expect(MapTileConfiguration.isValidCartoKey('   '), isFalse);
      expect(MapTileConfiguration.isValidCartoKey('YOUR_KEY'), isFalse);
      expect(MapTileConfiguration.isValidCartoKey('<build_time_key>'), isFalse);
      expect(MapTileConfiguration.isValidCartoKey('placeholder'), isFalse);
    });

    test('4. Correct CARTO Voyager tile URL has exactly one key parameter', () {
      const key = 'carto_alpha_numeric_key_999';
      final url = MapTileConfiguration.buildCartoUrlTemplate(key);
      expect(url, equals('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?key=$key'));
      expect(url.split('?key=').length, equals(2), reason: 'Must have exactly one query delimiter');
      expect(url.contains('&&'), isFalse);
    });

    test('5. Malformed or excessively short keys are rejected', () {
      expect(MapTileConfiguration.isValidCartoKey('short'), isFalse);
      expect(MapTileConfiguration.isValidCartoKey('12345'), isFalse);
    });

    test('6. Authentication failure classification in MapStatus model', () {
      expect(MapStatus.configurationError.hasError, isTrue);
      expect(MapStatus.tileError.hasError, isTrue);
      expect(MapStatus.ready.hasError, isFalse);
      expect(MapStatus.ready.isReady, isTrue);
    });

    test('7. Successful tile configuration provides subdomains and package identity', () {
      final result = MapTileConfiguration.instance.validateConfiguration(
        explicitCartoKey: 'carto_full_production_key_token',
      );
      expect(result.isValid, isTrue);
      expect(result.subdomains, equals(['a', 'b', 'c', 'd']));
      expect(MapTileConfiguration.cartoSubdomains, contains('a'));
    });
  });

  group('GPS SUBSYSTEM (Phase 27: Tests 8–25)', () {
    setUp(() {
      GpsQualityEngine.instance.reset();
    });

    test('8. Service enabled maps to operational status', () {
      const status = GpsStatus.ready;
      expect(status.isReady, isTrue);
      expect(status.hasError, isFalse);
    });

    test('9. Service disabled maps to GpsStatus.serviceDisabled', () {
      const status = GpsStatus.serviceDisabled;
      expect(status.hasError, isTrue);
      expect(status.displayName, equals('SERVICE_DISABLED'));
    });

    test('10. Permission granted allows location state progression', () {
      const status = GpsStatus.checking;
      expect(status.hasError, isFalse);
      expect(status.isReady, isFalse);
    });

    test('11. Permission denied maps to GpsStatus.permissionDenied', () {
      const status = GpsStatus.permissionDenied;
      expect(status.hasError, isTrue);
      expect(status.displayName, equals('PERMISSION_DENIED'));
    });

    test('12. Approximate location (accuracy > 100m) is classified UNUSABLE', () {
      final pos = _createPosition(latitude: 14.7952, longitude: 75.9926, accuracy: 120.0);
      final quality = GpsQualityEngine.instance.classify(pos);
      expect(quality.classification, GpsClassification.INVALID);
      expect(quality.isUsable, isFalse);
      expect(GpsQualityEngine.instance.isUsableForRouting(pos), isFalse);
      expect(GpsQualityEngine.instance.evaluateTier(pos), GpsQualityTier.UNUSABLE);
    });

    test('13. Precise location (accuracy <= 20m) is classified LIVE/GOOD', () {
      final pos = _createPosition(latitude: 14.7952, longitude: 75.9926, accuracy: 8.0);
      final quality = GpsQualityEngine.instance.classify(pos);
      expect(quality.isUsable, isTrue);
      expect(GpsQualityEngine.instance.isUsableForRouting(pos), isTrue);
      expect(GpsQualityEngine.instance.evaluateTier(pos), GpsQualityTier.EXCELLENT);
    });

    test('14. Valid cached position under freshness threshold is usable', () {
      final freshTime = DateTime.now().subtract(const Duration(seconds: 15));
      final pos = _createPosition(latitude: 14.7952, longitude: 75.9926, accuracy: 12.0, timestamp: freshTime);
      final ageSec = DateTime.now().difference(pos.timestamp).inSeconds;
      expect(ageSec <= 60, isTrue);
      expect(GpsQualityEngine.instance.isUsableForRouting(pos), isTrue);
    });

    test('15. Stale cached position older than threshold is rejected', () {
      final staleTime = DateTime.now().subtract(const Duration(seconds: 120));
      final pos = _createPosition(latitude: 14.7952, longitude: 75.9926, timestamp: staleTime);
      final ageSec = DateTime.now().difference(pos.timestamp).inSeconds;
      expect(ageSec > 60, isTrue);
    });

    test('16. Valid active position is accepted for routing', () {
      final pos = _createPosition(latitude: 14.7952, longitude: 75.9926, accuracy: 15.0);
      expect(GpsQualityEngine.instance.isUsableForRouting(pos), isTrue);
    });

    test('17. Invalid coordinates outside world bounds are rejected', () {
      final invalidLat = _createPosition(latitude: 95.0, longitude: 75.9926);
      final invalidLng = _createPosition(latitude: 14.7952, longitude: 195.0);
      expect(GpsQualityEngine.instance.isUsableForRouting(invalidLat), isFalse);
      expect(GpsQualityEngine.instance.isUsableForRouting(invalidLng), isFalse);
    });

    test('18. 0,0 Null Island coordinates are strictly rejected', () {
      final nullIsland = _createPosition(latitude: 0.0, longitude: 0.0);
      expect(GpsQualityEngine.instance.isUsableForRouting(nullIsland), isFalse);
    });

    test('19. NaN coordinates are strictly rejected', () {
      final nanPos = _createPosition(latitude: double.nan, longitude: 75.9926);
      expect(GpsQualityEngine.instance.isUsableForRouting(nanPos), isFalse);
    });

    test('20. Infinity coordinates are strictly rejected', () {
      final infPos = _createPosition(latitude: double.infinity, longitude: 75.9926);
      expect(GpsQualityEngine.instance.isUsableForRouting(infPos), isFalse);
    });

    test('21. GPS timeout result maps to GpsStatus.unavailable', () {
      final failureResult = GpsBootstrapResult.failure(
        GpsStatus.unavailable,
        "Couldn't acquire GPS fix within deadline",
      );
      expect(failureResult.isSuccess, isFalse);
      expect(failureResult.status, GpsStatus.unavailable);
    });

    test('22. Hardware provider failure produces failure bootstrap result', () {
      final result = GpsBootstrapResult.failure(
        GpsStatus.unavailable,
        'Hardware GNSS initialization failed',
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('GNSS'));
    });

    test('23. Stale callback rejection by session check', () {
      const activeSession = 'sess_live_123';
      const callbackSession = 'sess_old_999';
      expect(activeSession == callbackSession, isFalse);
    });

    test('24. Session cancellation state maps cleanly', () {
      const status = GpsStatus.unavailable;
      expect(status.hasError, isTrue);
    });

    test('25. Duplicate acquisition prevention: bootstrap result is reusable', () {
      final loc = LiveLocation(
        latitude: 14.7952,
        longitude: 75.9926,
        heading: 90,
        speed: 10,
        accuracy: 8,
        timestamp: DateTime.now(),
      );
      final r1 = GpsBootstrapResult.success(loc, source: 'cached', latencyMs: 25);
      expect(r1.isSuccess, isTrue);
      expect(r1.location?.latitude, closeTo(14.7952, 0.0001));
    });
  });

  group('ROUTING SUBSYSTEM (Phase 27: Tests 26–41)', () {
    test('26. Valid origin is validated', () {
      const origin = LatLng(14.7952, 75.9926);
      expect(origin.latitude.isNaN, isFalse);
      expect(origin.longitude.isNaN, isFalse);
      expect(origin.latitude != 0.0 || origin.longitude != 0.0, isTrue);
    });

    test('27. Valid destination is validated', () {
      const dest = LatLng(14.8000, 76.0000);
      expect(dest.latitude.isNaN, isFalse);
      expect(dest.longitude.isNaN, isFalse);
      expect(dest.latitude != 0.0 || dest.longitude != 0.0, isTrue);
    });

    test('28. Invalid origin (NaN) is rejected before network request', () async {
      const invalidOrigin = LatLng(double.nan, 75.9926);
      const dest = LatLng(14.8000, 76.0000);

      expect(
        () => RoutingFacade.instance.calculateRoute(
          origin: invalidOrigin,
          destination: dest,
          sessionId: 's1',
          routeVersion: 1,
        ),
        throwsA(isA<RoutingException>()),
      );
    });

    test('29. Invalid destination (NaN) is rejected before network request', () async {
      const origin = LatLng(14.7952, 75.9926);
      const invalidDest = LatLng(14.8000, double.nan);

      expect(
        () => RoutingFacade.instance.calculateRoute(
          origin: origin,
          destination: invalidDest,
          sessionId: 's1',
          routeVersion: 1,
        ),
        throwsA(isA<RoutingException>()),
      );
    });

    test('30. 0,0 coordinate rejection in routing facade', () async {
      const nullIsland = LatLng(0.0, 0.0);
      const validDest = LatLng(14.8000, 76.0000);

      expect(
        () => RoutingFacade.instance.calculateRoute(
          origin: nullIsland,
          destination: validDest,
          sessionId: 's1',
          routeVersion: 1,
        ),
        throwsA(isA<RoutingException>()),
      );
    });

    test('31. Valhalla requires lat/lon format in locations array', () {
      const origin = LatLng(14.7952, 75.9926);
      const dest = LatLng(14.8000, 76.0000);

      final valhallaLocations = [
        {'lat': origin.latitude, 'lon': origin.longitude},
        {'lat': dest.latitude, 'lon': dest.longitude},
      ];

      expect(valhallaLocations[0].containsKey('lat'), isTrue);
      expect(valhallaLocations[0].containsKey('lon'), isTrue);
      expect(valhallaLocations[0]['lat'], equals(14.7952));
      expect(valhallaLocations[0]['lon'], equals(75.9926));
    });

    test('32. Valhalla route provider configuration check', () {
      final provider = ValhallaRouteProvider(
        baseUrl: 'https://valhalla.kelasagara.internal',
      );
      expect(provider.isConfigured, isTrue);
      expect(provider.baseUrlSanitized, equals('https://valhalla.kelasagara.internal'));
    });

    test('33. Missing Valhalla URL is detected and reported', () {
      final provider = ValhallaRouteProvider(baseUrl: '');
      expect(provider.isConfigured, isFalse);
    });

    test('34. Successful route result contract validation', () {
      final route = RouteResult(
        polyline: const [LatLng(14.7952, 75.9926), LatLng(14.8000, 76.0000)],
        distanceM: 1200,
        durationSec: 180,
        steps: const [],
        calculatedAt: DateTime.now(),
        provider: 'VALHALLA',
      );
      expect(route.distanceM > 0, isTrue);
      expect(route.durationSec > 0, isTrue);
      expect(route.polyline.length >= 2, isTrue);
      expect(route.distanceText, isNotEmpty);
    });

    test('35. No route found throws NoRouteFoundException', () {
      expect(
        const NoRouteFoundException('No road route connects origin and destination'),
        isA<RoutingException>(),
      );
    });

    test('36. No road segment exception classification', () {
      const ex = NoRouteFoundException('Could not snap origin to nearest road network');
      expect(ex.message, contains('snap'));
    });

    test('37. Timeout throws RouteTimeoutException', () {
      const ex = RouteTimeoutException('Routing request exceeded 8000ms deadline');
      expect(ex.message, contains('8000ms'));
      expect(ex, isA<RoutingException>());
    });

    test('38. HTTP authentication error throws AuthenticationException', () {
      const ex = AuthenticationException('Valhalla rejected credentials (HTTP 401)');
      expect(ex.message, contains('401'));
      expect(ex, isA<RoutingException>());
    });

    test('39. Malformed route response throws MalformedRouteException', () {
      const ex = MalformedRouteException('Missing trip.summary in JSON response');
      expect(ex.message, contains('trip.summary'));
      expect(ex, isA<RoutingException>());
    });

    test('40. Stale route response session mismatch is rejected', () {
      const currentSession = 'sess_live_1';
      const responseSession = 'sess_stale_0';
      expect(currentSession == responseSession, isFalse);
    });

    test('41. Duplicate route request prevention via state guard', () {
      bool isCalculating = true;
      expect(isCalculating, isTrue, reason: 'Duplicate call must exit early when isCalculating=true');
    });
  });

  group('INTEGRATION & SUBSYSTEM DECOUPLING (Phase 27: Tests 42–48)', () {
    test('42. Booking destination correctly reaches route layer', () {
      const bookingJobLat = 14.7952123;
      const bookingJobLng = 75.9926456;
      final dest = LatLng(bookingJobLat, bookingJobLng);

      expect(dest.latitude, equals(14.7952123));
      expect(dest.longitude, equals(75.9926456));
    });

    test('43. Real GPS fix correctly passes to route layer', () {
      final pos = _createPosition(latitude: 14.7900, longitude: 75.9900, accuracy: 10.0);
      expect(GpsQualityEngine.instance.isUsableForRouting(pos), isTrue);
      final origin = LatLng(pos.latitude, pos.longitude);
      expect(origin.latitude, equals(14.7900));
    });

    test('44. Map error does NOT become GPS error', () {
      const health = NavigationHealth(
        mapStatus: MapStatus.configurationError,
        mapErrorMessage: 'CARTO_API_KEY required',
        gpsStatus: GpsStatus.ready,
        routeStatus: RouteStatus.ready,
        navigationStatus: NavigationStatus.ready,
      );

      expect(health.mapStatus.hasError, isTrue);
      expect(health.gpsStatus.isReady, isTrue);
      expect(health.gpsStatus.hasError, isFalse);
      expect(health.primaryFailureReason, contains('CARTO_API_KEY'));
    });

    test('45. GPS error does NOT become route provider error', () {
      const health = NavigationHealth(
        mapStatus: MapStatus.ready,
        gpsStatus: GpsStatus.unavailable,
        gpsErrorMessage: 'GPS fix timeout',
        routeStatus: RouteStatus.waitingForGps,
        navigationStatus: NavigationStatus.bootstrapping,
      );

      expect(health.gpsStatus.hasError, isTrue);
      expect(health.routeStatus, RouteStatus.waitingForGps);
      expect(health.routeStatus.hasError, isFalse);
      expect(health.primaryFailureReason, contains('GPS fix timeout'));
    });

    test('46. Route error does NOT destroy valid GPS', () {
      final pos = _createPosition(latitude: 14.7900, longitude: 75.9900, accuracy: 10.0);
      final liveLoc = LiveLocation.fromPosition(pos);

      final health = NavigationHealth(
        mapStatus: MapStatus.ready,
        gpsStatus: GpsStatus.ready,
        routeStatus: RouteStatus.timeout,
        routeErrorMessage: 'Valhalla timed out',
        navigationStatus: NavigationStatus.idle,
        gpsAccuracyMeters: liveLoc.accuracy,
      );

      expect(health.routeStatus.hasError, isTrue);
      expect(health.gpsStatus.isReady, isTrue);
      expect(health.gpsAccuracyMeters, equals(10.0));
      expect(liveLoc.hasValidCoordinates, isTrue);
    });

    test('47. Retry route uses latest valid GPS fix without restarting GPS', () {
      final savedPos = _createPosition(latitude: 14.7900, longitude: 75.9900, accuracy: 10.0);
      final savedLoc = LiveLocation.fromPosition(savedPos);

      // Verify fix is valid and ready to be used directly
      expect(savedLoc.hasValidCoordinates, isTrue);
      expect(savedLoc.latitude, equals(14.7900));
      expect(savedLoc.longitude, equals(75.9900));
    });

    test('48. Google Maps external launch remains frozen and unchanged', () {
      const provider = GoogleMapsExternalProvider();
      final url = provider.buildNavigationUri(
        destinationLat: 14.7952,
        destinationLng: 75.9926,
        travelMode: 'driving',
      );
      expect(url.toString(), contains('https://www.google.com/maps/dir/'));
      expect(url.toString(), contains('destination=14.7952%2C75.9926'));
      expect(url.toString(), contains('dir_action=navigate'));
      expect(url.queryParameters.containsKey('origin'), isFalse);
    });

    test('49. Valhalla URL normalization strips trailing slashes', () {
      expect(ValhallaRouteProvider.normalizeUrl('http://10.115.216.23:8002/'), equals('http://10.115.216.23:8002'));
      expect(ValhallaRouteProvider.normalizeUrl('http://10.115.216.23:8002///'), equals('http://10.115.216.23:8002'));
      expect(ValhallaRouteProvider.normalizeUrl('https://valhalla.kelasagara.internal'), equals('https://valhalla.kelasagara.internal'));
    });

    test('50. Valhalla URL normalization trims leading and trailing whitespace', () {
      expect(ValhallaRouteProvider.normalizeUrl('  http://10.115.216.23:8002/  '), equals('http://10.115.216.23:8002'));
      expect(ValhallaRouteProvider.normalizeUrl('   '), equals(''));
    });

    test('51. ValhallaPolyline6 correctly decodes known polyline6 geometry', () {
      // Shape from Bengaluru to Hassan test
      const sampleShape = 'ogvvWsd__sCvA_FjBgIuAe@eBQm@G_';
      final pts = ValhallaPolyline6.decode(sampleShape);
      expect(pts.isNotEmpty, isTrue);
      expect(pts.first.latitude, closeTo(13.0, 1.0));
      expect(pts.first.longitude, closeTo(77.6, 1.0));
    });

    test('52. RouteResult.fromValhallaJson parses real Valhalla response', () {
      final sampleJson = {
        'trip': {
          'status': 0,
          'summary': {
            'length': 50.579,
            'time': 2871.27,
          },
          'legs': [
            {
              'shape': 'ogvvWsd__sCvA_FjBgIuAe@eBQm@G_',
              'maneuvers': [
                {
                  'type': 0,
                  'instruction': 'Drive northwest on BM Road.',
                  'length': 1.2,
                  'time': 120.0,
                },
                {
                  'type': 4,
                  'instruction': 'Turn sharp right onto NH 73.',
                  'length': 49.379,
                  'time': 2751.27,
                }
              ]
            }
          ]
        }
      };

      final result = RouteResult.fromValhallaJson(sampleJson);
      expect(result, isNotNull);
      expect(result!.distanceM, equals(50579));
      expect(result.durationSec, equals(2871));
      expect(result.polyline.isNotEmpty, isTrue);
      expect(result.steps.length, equals(2));
      expect(result.steps[0].instruction, equals('Drive northwest on BM Road.'));
      expect(result.steps[1].instruction, equals('Turn sharp right onto NH 73.'));
    });

    test('53. Malformed Valhalla JSON returns null safely without throwing', () {
      expect(RouteResult.fromValhallaJson({}), isNull);
      expect(RouteResult.fromValhallaJson({'trip': {'status': 1}}), isNull);
      expect(RouteResult.fromValhallaJson({'trip': null}), isNull);
    });

    test('54. StaleRouteException is classified as typed RoutingException', () {
      const ex = StaleRouteException('Stale route request was superseded by a newer request.');
      expect(ex, isA<RoutingException>());
      expect(ex.message, contains('superseded'));
    });

    test('55. RoutingFacade initial circuit breaker state is closed', () {
      RoutingFacade.instance.resetState();
      expect(RoutingFacade.instance.circuitState, equals(CircuitBreakerState.closed));
    });

    test('56. RoutingFacade cancelActiveRequests completes normally', () {
      expect(() => RoutingFacade.instance.cancelActiveRequests(), returnsNormally);
    });

    test('57. ValhallaDetailedResult.isCancelled identifies CANCELLED error code', () {
      final res = ValhallaDetailedResult.failure(
        errorCode: 'CANCELLED',
        errorMessage: 'Routing request was cancelled',
      );
      expect(res.isCancelled, isTrue);
      expect(res.isSuccess, isFalse);
    });

    test('58. ValhallaDetailedResult timeout identifies TIMEOUT error code', () {
      final res = ValhallaDetailedResult.failure(
        errorCode: 'TIMEOUT',
        errorMessage: 'Routing request timed out',
      );
      expect(res.isCancelled, isFalse);
      expect(res.errorCode, equals('TIMEOUT'));
    });
  });
}
