// lib/features/tracking/data/repositories/valhalla_routing_repository.dart
// Production-grade resilient routing repository backed by RoutingFacade (Valhalla)
// with secondary OSRM backup and subdivided geodesic failsafe.

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../../../services/navigation/routing_facade.dart';

class ValhallaRouteResponse {
  final List<LatLng> polyline;
  final double distanceMeters;
  final double durationSeconds;
  final bool isFallbackGeodesic;

  const ValhallaRouteResponse({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallbackGeodesic = false,
  });
}

class ValhallaRoutingRepository {
  final RoutingFacade _routingFacade;
  final Dio _dio;

  static ValhallaRoutingRepository? _instance;
  static ValhallaRoutingRepository get instance =>
      _instance ??= ValhallaRoutingRepository();

  ValhallaRoutingRepository({
    RoutingFacade? routingFacade,
    Dio? dioClient,
  })  : _routingFacade = routingFacade ?? RoutingFacade.instance,
        _dio = dioClient ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));

  Future<ValhallaRouteResponse> fetchRoadRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'motorcycle',
  }) async {
    // 1. Primary: Project's RoutingFacade (Valhalla)
    try {
      final result = await _routingFacade
          .calculateRoute(
            origin: origin,
            destination: destination,
            sessionId: 'trk_${DateTime.now().millisecondsSinceEpoch}',
            routeVersion: 1,
            costing: costing,
          )
          .timeout(const Duration(seconds: 6));

      if (result.polyline.length >= 2) {
        return ValhallaRouteResponse(
          polyline: result.polyline,
          distanceMeters: result.distanceM.toDouble(),
          durationSeconds: result.durationSec.toDouble(),
        );
      }
    } catch (_) {
      // Fall through to secondary OSRM backup
    }

    // 2. Secondary: Direct OSRM Road Geometry Backup
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson';
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final decoded = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;
        final routes = decoded['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes.first as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List<dynamic>;
          final points = coords.map((c) {
            final pair = c as List<dynamic>;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          }).toList();

          if (points.length >= 2) {
            return ValhallaRouteResponse(
              polyline: points,
              distanceMeters: (firstRoute['distance'] as num).toDouble(),
              durationSeconds: (firstRoute['duration'] as num).toDouble(),
            );
          }
        }
      }
    } catch (_) {
      // Fall through to subdivided geodesic curve
    }

    // 3. Last-Resort Failsafe: Subdivided Geodesic Line (ensures RoadSnapper always has segments)
    final points = <LatLng>[];
    const steps = 16;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      points.add(
        LatLng(
          origin.latitude + (destination.latitude - origin.latitude) * t,
          origin.longitude + (destination.longitude - origin.longitude) * t,
        ),
      );
    }
    const distCalc = Distance();
    final meters = distCalc.as(LengthUnit.Meter, origin, destination) * 1.25;
    return ValhallaRouteResponse(
      polyline: points,
      distanceMeters: meters,
      durationSeconds: meters / 7.5,
      isFallbackGeodesic: true,
    );
  }

  // Backward-compatible polyline helper
  Future<List<LatLng>> fetchRoadPolyline({
    required LatLng origin,
    required LatLng destination,
    bool forceRefresh = false,
  }) async {
    final res = await fetchRoadRoute(origin: origin, destination: destination);
    return res.polyline;
  }
}
