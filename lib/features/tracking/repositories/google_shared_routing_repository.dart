// lib/features/tracking/repositories/google_shared_routing_repository.dart
// Production-grade shared routing repository supporting Google Routes API v2,
// RTDB shared polyline caching, and OSRM/Valhalla fallbacks with 1 API call per trip.

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/navigation/routing_facade.dart';

class SharedRouteResult {
  final List<LatLng> polyline;
  final String encodedPolyline;
  final double distanceMeters;
  final double durationSeconds;
  final bool isExactGoogleRoute;

  const SharedRouteResult({
    required this.polyline,
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isExactGoogleRoute,
  });
}

class GoogleSharedRoutingRepository {
  /// Pass via `--dart-define=GOOGLE_MAPS_API_KEY=AIza...` or inject directly.
  static const String _googleApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  final FirebaseDatabase _rtdb;
  final Dio _dio;
  final RoutingFacade _routingFacade;

  static GoogleSharedRoutingRepository? _instance;
  static GoogleSharedRoutingRepository get instance =>
      _instance ??= GoogleSharedRoutingRepository();

  GoogleSharedRoutingRepository({
    FirebaseDatabase? rtdb,
    Dio? dioClient,
    RoutingFacade? routingFacade,
  })  : _rtdb = rtdb ?? FirebaseDatabase.instance,
        _dio = dioClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            ),
        _routingFacade = routingFacade ?? RoutingFacade.instance;

  /// Fetches the route and syncs `encodedPolyline` into `liveTracking/$bookingId`
  /// so the Hirer views the exact Google route without paying for duplicate API calls.
  Future<SharedRouteResult> fetchOrSyncSharedRoute({
    required String bookingId,
    required LatLng origin,
    required LatLng destination,
    bool forceRefresh = false,
  }) async {
    final trackingRef = _rtdb.ref('liveTracking/$bookingId');

    // 1. Check RTDB Shared Cache first (if not forcing a reroute)
    if (!forceRefresh) {
      try {
        final snap = await trackingRef.get();
        if (snap.exists && snap.value is Map) {
          final map = snap.value as Map<dynamic, dynamic>;
          final cachedEncoded = map['encodedPolyline']?.toString() ?? '';
          final cachedDist = (map['routeDistanceMeters'] as num?)?.toDouble();
          final cachedDur = (map['routeDurationSeconds'] as num?)?.toDouble();
          final isGoogle = map['isGoogleRoute'] == true;

          if (cachedEncoded.isNotEmpty) {
            final decodedPoints = PolylineCodec.decode(cachedEncoded);
            if (decodedPoints.length >= 2) {
              return SharedRouteResult(
                polyline: decodedPoints,
                encodedPolyline: cachedEncoded,
                distanceMeters: cachedDist ?? 1000.0,
                durationSeconds: cachedDur ?? 180.0,
                isExactGoogleRoute: isGoogle,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Primary: Google Routes API v2 (Traffic-Aware Two-Wheeler / Driving)
    if (_googleApiKey.isNotEmpty) {
      final googleRoute = await _fetchFromGoogleRoutesV2(origin, destination);
      if (googleRoute != null) {
        await _cacheRouteInRtdb(trackingRef, googleRoute);
        return googleRoute;
      }
    }

    // 3. Fallback: OSRM / Valhalla Road Network (marked `isExactGoogleRoute: false`
    // so the Hirer controller uses Elastic Free-Follow on Google Maps shortcuts)
    final fallbackRoute = await _fetchFallbackRoadGeometry(origin, destination);
    await _cacheRouteInRtdb(trackingRef, fallbackRoute);
    return fallbackRoute;
  }

  Future<SharedRouteResult?> _fetchFromGoogleRoutesV2(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      const url = 'https://routes.googleapis.com/directions/v2:computeRoutes';
      final body = {
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            }
          }
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            }
          }
        },
        'travelMode': 'TWO_WHEELER',
        'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
      };

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': _googleApiKey,
            'X-Goog-FieldMask':
                'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
          },
        ),
        data: body,
      );

      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final encoded =
              (route['polyline'] as Map<String, dynamic>)['encodedPolyline']
                  as String;
          final distMeters = (route['distanceMeters'] as num).toDouble();
          final durString = (route['duration'] as String).replaceAll('s', '');
          final durSeconds = double.tryParse(durString) ?? (distMeters / 7.5);

          final points = PolylineCodec.decode(encoded);
          if (points.length >= 2) {
            return SharedRouteResult(
              polyline: points,
              encodedPolyline: encoded,
              distanceMeters: distMeters,
              durationSeconds: durSeconds,
              isExactGoogleRoute: true,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<SharedRouteResult> _fetchFallbackRoadGeometry(
    LatLng origin,
    LatLng destination,
  ) async {
    // Try OSRM public driving endpoint first
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=polyline';
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final decoded = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;
        final routes = decoded['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final first = routes.first as Map<String, dynamic>;
          final encoded = first['geometry'] as String;
          final points = PolylineCodec.decode(encoded);
          if (points.length >= 2) {
            return SharedRouteResult(
              polyline: points,
              encodedPolyline: encoded,
              distanceMeters: (first['distance'] as num).toDouble(),
              durationSeconds: (first['duration'] as num).toDouble(),
              isExactGoogleRoute: false,
            );
          }
        }
      }
    } catch (_) {}

    // Secondary Fallback: Existing RoutingFacade
    try {
      final res = await _routingFacade
          .calculateRoute(
            origin: origin,
            destination: destination,
            sessionId: 'trk_${DateTime.now().millisecondsSinceEpoch}',
            routeVersion: 1,
          )
          .timeout(const Duration(seconds: 4));
      if (res.polyline.length >= 2) {
        final encoded = PolylineCodec.encode(res.polyline);
        return SharedRouteResult(
          polyline: res.polyline,
          encodedPolyline: encoded,
          distanceMeters: res.distanceM.toDouble(),
          durationSeconds: res.durationSec.toDouble(),
          isExactGoogleRoute: false,
        );
      }
    } catch (_) {}

    // Final Failsafe: Direct interpolated vector
    final points = <LatLng>[origin, destination];
    const dist = Distance();
    final meters = dist.as(LengthUnit.Meter, origin, destination) * 1.25;
    return SharedRouteResult(
      polyline: points,
      encodedPolyline: PolylineCodec.encode(points),
      distanceMeters: meters,
      durationSeconds: meters / 7.5,
      isExactGoogleRoute: false,
    );
  }

  Future<void> _cacheRouteInRtdb(
    DatabaseReference ref,
    SharedRouteResult route,
  ) async {
    try {
      await ref.update({
        'encodedPolyline': route.encodedPolyline,
        'routeDistanceMeters': route.distanceMeters.round(),
        'routeDurationSeconds': route.durationSeconds.round(),
        'isGoogleRoute': route.isExactGoogleRoute,
      });
    } catch (_) {}
  }
}

/// Zero-dependency Google Encoded Polyline Algorithm Encoder & Decoder.
class PolylineCodec {
  static List<LatLng> decode(String encoded) {
    final List<LatLng> points = [];
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

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  static String encode(List<LatLng> points) {
    final StringBuffer result = StringBuffer();
    int prevLat = 0;
    int prevLng = 0;

    for (final point in points) {
      final int lat = (point.latitude * 1e5).round();
      final int lng = (point.longitude * 1e5).round();

      _encodeValue(lat - prevLat, result);
      _encodeValue(lng - prevLng, result);

      prevLat = lat;
      prevLng = lng;
    }
    return result.toString();
  }

  static void _encodeValue(int value, StringBuffer result) {
    int v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      result.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    result.writeCharCode(v + 63);
  }
}
