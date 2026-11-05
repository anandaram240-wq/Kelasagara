// lib/services/routing/ors_route_provider.dart

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';

class OrsRouteProvider implements RoutingProvider {
  final String _apiKey;
  DateTime? _lastSuccess;
  DateTime? _lastFailure;
  int _consecutiveFails = 0;
  final List<DateTime> _requestTimestamps = [];

  OrsRouteProvider({String? apiKey}) 
      : _apiKey = apiKey ?? const String.fromEnvironment('ORS_API_KEY', defaultValue: '');

  @override
  String get name => 'openrouteservice';

  bool get isConfigured => _apiKey.isNotEmpty;

  @override
  PolylineEncoding get polylineEncoding => PolylineEncoding.polyline5;

  @override
  ProviderPriority get priority => ProviderPriority.tertiary;

  @override
  bool get supportsMatrix => true;
  
  bool _checkRateLimit() {
    final now = DateTime.now();
    _requestTimestamps.removeWhere((t) => now.difference(t).inSeconds > 60);
    if (_requestTimestamps.length >= 40) return false;
    _requestTimestamps.add(now);
    return true;
  }

  @override
  Future<ProviderHealth> checkHealthDetailed() async {
    if (!isConfigured) {
      return ProviderHealth(
        online: false,
        latencyMs: 0,
        lastSuccess: _lastSuccess,
        lastFailure: _lastFailure,
        consecutiveFails: _consecutiveFails,
      );
    }
    
    if (!_checkRateLimit()) {
      return ProviderHealth(
        online: false,
        latencyMs: 0,
        lastSuccess: _lastSuccess,
        lastFailure: _lastFailure,
        consecutiveFails: _consecutiveFails,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Authorization': _apiKey,
          'Content-Type': 'application/json; charset=utf-8',
        },
      ));
      
      final resp = await dio.get('https://api.openrouteservice.org/v2/health');
      stopwatch.stop();
      
      if (resp.statusCode == 200 && resp.data['status'] == 'ready') {
        _lastSuccess = DateTime.now();
        _consecutiveFails = 0;
        return ProviderHealth(
          online: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          lastSuccess: _lastSuccess,
          lastFailure: _lastFailure,
          consecutiveFails: 0,
        );
      }
    } catch (_) {}
    
    stopwatch.stop();
    _lastFailure = DateTime.now();
    _consecutiveFails++;
    
    return ProviderHealth(
      online: false,
      latencyMs: stopwatch.elapsedMilliseconds,
      lastSuccess: _lastSuccess,
      lastFailure: _lastFailure,
      consecutiveFails: _consecutiveFails,
    );
  }

  @override
  Future<bool> checkHealth() async {
    final h = await checkHealthDetailed();
    return h.online;
  }

  bool _validCoord(double lat, double lng) =>
      lat.isFinite && lng.isFinite &&
      lat >= -90 && lat <= 90 &&
      lng >= -180 && lng <= 180 &&
      !(lat == 0 && lng == 0);

  @override
  Future<RouteResult?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
  }) async {
    if (!isConfigured) return null;
    if (!_validCoord(origin.latitude, origin.longitude) || !_validCoord(destination.latitude, destination.longitude)) {
      return null;
    }
    if (!_checkRateLimit()) return null;

    final body = {
      'coordinates': [
        [origin.longitude, origin.latitude],
        [destination.longitude, destination.latitude],
      ],
      'instructions': true,
      'geometry': true,
    };

    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Authorization': _apiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8'
      },
    ));

    try {
      final resp = await client.post('https://api.openrouteservice.org/v2/directions/driving-car', data: body);
      if (resp.statusCode != 200) return null;

      final data = resp.data as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;

      final feature = features[0] as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return null;

      final polyline = coords.map((c) {
        final pt = c as List;
        return LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
      }).toList();

      final properties = feature['properties'] as Map<String, dynamic>;
      final summary = properties['summary'] as Map<String, dynamic>;
      final distance = (summary['distance'] as num?)?.toDouble() ?? 0;
      final duration = (summary['duration'] as num?)?.toDouble() ?? 0;
      
      final segments = properties['segments'] as List?;
      final steps = <RouteStep>[];
      
      if (segments != null && segments.isNotEmpty) {
        final segment = segments[0] as Map<String, dynamic>;
        final orsSteps = segment['steps'] as List? ?? [];
        
        for (final s in orsSteps) {
          final step = s as Map<String, dynamic>;
          final type = (step['type'] as num?)?.toInt() ?? 0;
          final instr = step['instruction'] as String? ?? 'Continue';
          final name = step['name'] as String? ?? '';
          final dist = (step['distance'] as num?)?.toDouble() ?? 0.0;
          final dur = (step['duration'] as num?)?.toDouble() ?? 0.0;
          final waypoints = step['way_points'] as List?;
          
          int beginIdx = 0;
          int endIdx = polyline.length - 1;
          if (waypoints != null && waypoints.length >= 2) {
            beginIdx = (waypoints[0] as num).toInt();
            endIdx = (waypoints[1] as num).toInt();
          }

          final mType = _orsToManeuverType(type);
          
          steps.add(RouteStep(
            instruction: instr,
            instructionKn: mType.kannadaPrefix + (name.isNotEmpty ? ' $name ಕಡೆಗೆ' : ''),
            durationSec: dur.round(),
            distanceM: dist.round(),
            action: type.toString(),
            maneuverType: mType,
            polylineStartIndex: beginIdx,
            polylineEndIndex: endIdx,
            streetName: name.isNotEmpty ? name : null,
          ));
        }
      }

      final result = RouteResult.withCumulativeDistances(
        polyline: polyline,
        distanceM: distance.round(),
        durationSec: duration.round(),
        steps: steps,
        calculatedAt: DateTime.now(),
        routingEngine: 'openrouteservice',
      );

      _lastSuccess = DateTime.now();
      _consecutiveFails = 0;
      return result;
    } catch (e) {
      _lastFailure = DateTime.now();
      _consecutiveFails++;
      return null;
    }
  }

  @override
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    if (!isConfigured || sources.isEmpty || targets.isEmpty) return null;
    if (!_checkRateLimit()) return null;

    final body = {
      'locations': [...sources, ...targets].map((p) => [p.longitude, p.latitude]).toList(),
      'sources': List.generate(sources.length, (i) => i),
      'destinations': List.generate(targets.length, (i) => i + sources.length),
      'metrics': ['distance', 'duration'],
    };

    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Authorization': _apiKey,
        'Content-Type': 'application/json; charset=utf-8',
      },
    ));

    try {
      final resp = await client.post('https://api.openrouteservice.org/v2/matrix/driving-car', data: body);
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        
        final distancesJson = data['distances'] as List?;
        final durationsJson = data['durations'] as List?;
        
        if (distancesJson == null || durationsJson == null) return null;
        
        List<List<double?>> distances = [];
        List<List<int?>> durations = [];
        
        for (int i = 0; i < distancesJson.length; i++) {
          distances.add((distancesJson[i] as List).map((e) => (e as num?)?.toDouble()).toList());
          durations.add((durationsJson[i] as List).map((e) => (e as num?)?.toInt()).toList());
        }
        
        return MatrixResult(
          sources: sources,
          targets: targets,
          distances: distances,
          durations: durations,
        );
      }
    } catch (_) {}
    return null;
  }
  
  static ManeuverType _orsToManeuverType(int type) {
    switch (type) {
      case 0: return ManeuverType.left;
      case 1: return ManeuverType.right;
      case 2: return ManeuverType.sharpLeft;
      case 3: return ManeuverType.sharpRight;
      case 4: return ManeuverType.slightLeft;
      case 5: return ManeuverType.slightRight;
      case 6: return ManeuverType.continueStr;
      case 7: return ManeuverType.roundaboutEnter;
      case 8: return ManeuverType.roundaboutExit;
      case 9: return ManeuverType.uTurnLeft;
      case 10: return ManeuverType.destination;
      case 11: return ManeuverType.depart;
      case 12: return ManeuverType.left; 
      case 13: return ManeuverType.right;
      default: return ManeuverType.continueStr;
    }
  }
}
