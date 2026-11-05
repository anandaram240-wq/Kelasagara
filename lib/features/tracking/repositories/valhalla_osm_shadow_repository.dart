// lib/features/tracking/repositories/valhalla_osm_shadow_repository.dart
// Production-grade heading-biased Indian 2-wheeler Valhalla + OSRM Shadow Repository.
// Matches Google Maps shortcuts and detours without Google API billing.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/navigation/routing_facade.dart';
import '../domain/road_snapper.dart';

class OsmShadowRouteResponse {
  final List<LatLng> polyline;
  final double distanceMeters;
  final double durationSeconds;
  final String engineSource; // 'valhalla_gully', 'osrm_bearing', 'facade', 'geodesic'

  const OsmShadowRouteResponse({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.engineSource,
  });
}

class ValhallaOsmShadowRepository {
  /// Public or self-hosted Valhalla endpoint (defaults to OpenStreetMap FOSSGIS Valhalla)
  static const String _defaultValhallaUrl = String.fromEnvironment(
    'VALHALLA_BASE_URL',
    defaultValue: 'https://valhalla1.openstreetmap.de/route',
  );

  final RoutingFacade _routingFacade;
  final FirebaseDatabase _rtdb;
  final Dio _dio;

  static ValhallaOsmShadowRepository? _instance;
  static ValhallaOsmShadowRepository get instance =>
      _instance ??= ValhallaOsmShadowRepository();

  ValhallaOsmShadowRepository({
    RoutingFacade? routingFacade,
    FirebaseDatabase? rtdb,
    Dio? dioClient,
  })  : _routingFacade = routingFacade ?? RoutingFacade.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance,
        _dio = dioClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            );

  /// Computes an OpenStreetMap route that shadows the Worker's Google Maps trajectory
  /// by injecting the worker's current heading and Indian two-wheeler gully costing.
  Future<OsmShadowRouteResponse> fetchShadowRoute({
    required String bookingId,
    required LatLng workerPosition,
    required LatLng destination,
    double? workerHeadingDeg,
    double workerSpeedMps = 0.0,
  }) async {
    final hasValidHeading = workerHeadingDeg != null &&
        workerHeadingDeg.isFinite &&
        workerSpeedMps >= 1.2;

    // 1. Primary: Direct Valhalla Request with Indian 2-Wheeler Gully Costing + Heading Lock
    try {
      final valhallaRes = await _queryValhallaWithGullyProfile(
        origin: workerPosition,
        destination: destination,
        headingDeg: hasValidHeading ? workerHeadingDeg : null,
      );
      if (valhallaRes != null && valhallaRes.polyline.length >= 2) {
        unawaited(_broadcastRouteSummaryToRtdb(bookingId, valhallaRes));
        return valhallaRes;
      }
    } catch (_) {}

    // 2. Secondary: OSRM with Bearing Filter (`bearings=heading,45;0,180`)
    // Forces OSRM to snap to the exact street direction the worker is currently driving on in Google Maps!
    try {
      final osrmRes = await _queryOsrmWithBearingConstraint(
        origin: workerPosition,
        destination: destination,
        headingDeg: hasValidHeading ? workerHeadingDeg : null,
      );
      if (osrmRes != null && osrmRes.polyline.length >= 2) {
        unawaited(_broadcastRouteSummaryToRtdb(bookingId, osrmRes));
        return osrmRes;
      }
    } catch (_) {}

    // 3. Tertiary: Existing App RoutingFacade
    try {
      final facadeRes = await _routingFacade
          .calculateRoute(
            origin: workerPosition,
            destination: destination,
            sessionId: 'shd_${DateTime.now().millisecondsSinceEpoch}',
            routeVersion: 1,
            costing: 'motorcycle',
          )
          .timeout(const Duration(seconds: 4));
      if (facadeRes.polyline.length >= 2) {
        return OsmShadowRouteResponse(
          polyline: facadeRes.polyline,
          distanceMeters: facadeRes.distanceM.toDouble(),
          durationSeconds: facadeRes.durationSec.toDouble(),
          engineSource: 'facade',
        );
      }
    } catch (_) {}

    // 4. Failsafe: Subdivided Geodesic Vector
    final fallbackPoints = <LatLng>[];
    for (int i = 0; i <= 16; i++) {
      final t = i / 16.0;
      fallbackPoints.add(
        LatLng(
          workerPosition.latitude +
              (destination.latitude - workerPosition.latitude) * t,
          workerPosition.longitude +
              (destination.longitude - workerPosition.longitude) * t,
        ),
      );
    }
    final dist = RoadSnapper.fastDistanceMeters(workerPosition, destination) * 1.25;
    return OsmShadowRouteResponse(
      polyline: fallbackPoints,
      distanceMeters: dist,
      durationSeconds: (dist / 6.94).clamp(30.0, 3600.0),
      engineSource: 'geodesic',
    );
  }

  Future<OsmShadowRouteResponse?> _queryValhallaWithGullyProfile({
    required LatLng origin,
    required LatLng destination,
    double? headingDeg,
  }) async {
    final payload = {
      'locations': [
        {
          'lat': origin.latitude,
          'lon': origin.longitude,
          'type': 'break',
          if (headingDeg != null) 'heading': headingDeg.round() % 360,
          if (headingDeg != null) 'heading_tolerance': 45,
        },
        {
          'lat': destination.latitude,
          'lon': destination.longitude,
          'type': 'break',
        },
      ],
      // 'motorcycle' + high living_streets & alley acceptance mirrors Google Maps 2-Wheeler mode
      'costing': 'motorcycle',
      'costing_options': {
        'motorcycle': {
          'use_living_streets': 1.0,
          'use_tracks': 0.85,
          'service_penalty': 0.0,
          'service_factor': 0.8,
          'maneuver_penalty': 2.0,
          'use_highways': 0.8,
          'use_trails': 0.4,
          'shortest': false,
        },
      },
      'units': 'kilometers',
    };

    final response = await _dio.post(
      _defaultValhallaUrl,
      options: Options(
        headers: {'Content-Type': 'application/json'},
      ),
      data: payload,
    );

    if (response.statusCode != 200) return null;

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : (response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null);
    if (data == null) return null;

    final trip = data['trip'] as Map<String, dynamic>?;
    final legs = trip?['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) return null;

    final firstLeg = legs.first as Map<String, dynamic>;
    final shapeEncoded = firstLeg['shape'] as String?;
    final summary = trip?['summary'] as Map<String, dynamic>?;

    if (shapeEncoded == null || shapeEncoded.isEmpty) return null;

    // Valhalla uses precision 6 (1e6) for encoded polylines
    final decodedPoints = _decodePolyline(shapeEncoded, precision: 6);
    if (decodedPoints.length < 2) return null;

    final lengthKm = (summary?['length'] as num?)?.toDouble() ?? 1.0;
    final timeSec = (summary?['time'] as num?)?.toDouble() ?? 180.0;

    return OsmShadowRouteResponse(
      polyline: decodedPoints,
      distanceMeters: lengthKm * 1000.0,
      durationSeconds: timeSec,
      engineSource: 'valhalla_gully',
    );
  }

  Future<OsmShadowRouteResponse?> _queryOsrmWithBearingConstraint({
    required LatLng origin,
    required LatLng destination,
    double? headingDeg,
  }) async {
    final bearingParam = headingDeg != null
        ? '&bearings=${headingDeg.round() % 360},45;0,180'
        : '';

    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=polyline$bearingParam';

    final response = await _dio.get(url);
    if (response.statusCode != 200) return null;

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : (response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null);
    if (data == null) return null;

    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as String;
    final points = _decodePolyline(geometry, precision: 5);
    if (points.length < 2) return null;

    return OsmShadowRouteResponse(
      polyline: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      engineSource: 'osrm_bearing',
    );
  }

  Future<void> _broadcastRouteSummaryToRtdb(
    String bookingId,
    OsmShadowRouteResponse route,
  ) async {
    try {
      await _rtdb.ref('liveTracking/$bookingId/routeMeta').set({
        'distanceMeters': route.distanceMeters.round(),
        'durationSeconds': route.durationSeconds.round(),
        'engine': route.engineSource,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// Supports both Precision-5 (Google/OSRM) and Precision-6 (Valhalla) encoded polylines.
  static List<LatLng> _decodePolyline(String encoded, {int precision = 6}) {
    final List<LatLng> points = <LatLng>[];
    final double factor = precision == 6 ? 1e6 : 1e5;
    int index = 0;
    final int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        if (index >= len) break;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / factor, lng / factor));
    }
    return points;
  }
}
