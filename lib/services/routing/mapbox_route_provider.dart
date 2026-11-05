import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';

class MapboxRouteProvider implements RoutingProvider {
  final String _accessToken;
  DateTime? _lastSuccess;
  DateTime? _lastFailure;
  int _consecutiveFails = 0;

  MapboxRouteProvider({String? accessToken})
      : _accessToken = accessToken ?? const String.fromEnvironment('MAPBOX_ACCESS_TOKEN', defaultValue: '');

  Dio? _dio;
  Dio get _client {
    return _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 3),
      headers: const {'Content-Type': 'application/json'},
    ));
  }

  @override
  String get name => 'mapbox';

  bool get isConfigured => _accessToken.isNotEmpty;

  @override
  PolylineEncoding get polylineEncoding => PolylineEncoding.polyline6;

  @override
  ProviderPriority get priority => ProviderPriority.primary;

  @override
  bool get supportsMatrix => true;

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
    
    // Simple health check query (driving profile, short route)
    final stopwatch = Stopwatch()..start();
    try {
      final resp = await _client.get(
        'https://api.mapbox.com/directions/v5/mapbox/driving/-73.989,40.733;-74,40.733',
        queryParameters: {'access_token': _accessToken},
      );
      stopwatch.stop();

      if (resp.statusCode == 200) {
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

    // mapbox/driving is standard for cars/auto
    final profile = costing == 'auto' ? 'driving' : 'driving';
    final coords = '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';

    try {
      final resp = await _client.get(
        'https://api.mapbox.com/directions/v5/mapbox/$profile/$coords',
        queryParameters: {
          'alternatives': 'false',
          'geometries': 'polyline6',
          'overview': 'full',
          'steps': 'true',
          'access_token': _accessToken,
        },
      );

      if (resp.statusCode != 200) return null;

      final data = resp.data as Map<String, dynamic>;
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) return null;

      final routeData = data['routes'][0] as Map<String, dynamic>;
      
      final duration = (routeData['duration'] as num?)?.toInt() ?? 0;
      final distance = (routeData['distance'] as num?)?.toDouble() ?? 0.0;
      final geometry = routeData['geometry'] as String? ?? '';
      
      final polyline = ValhallaPolyline6.decode(geometry);
      
      List<RouteStep> mapboxSteps = [];
      
      final legs = routeData['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final steps = legs[0]['steps'] as List?;
        if (steps != null) {
          int currentPolyIndex = 0;
          for (var step in steps) {
            final sData = step as Map<String, dynamic>;
            final stepDist = (sData['distance'] as num?)?.toDouble() ?? 0.0;
            final stepDur = (sData['duration'] as num?)?.toInt() ?? 0;
            final maneuver = sData['maneuver'] as Map<String, dynamic>? ?? {};
            
            final geom = sData['geometry'] as String? ?? '';
            final stepPoly = ValhallaPolyline6.decode(geom);
            final endPolyIndex = currentPolyIndex + (stepPoly.length > 1 ? stepPoly.length - 1 : 0);
            
            final type = maneuver['type'] as String? ?? '';
            final modifier = maneuver['modifier'] as String? ?? '';
            final mType = _mapboxToManeuverType(type, modifier);
            
            final stepName = sData['name'] as String? ?? '';
            
            mapboxSteps.add(RouteStep(
              instruction: _buildMapboxInstruction(maneuver, sData),
              instructionKn: _buildMapboxInstructionKn(mType, stepName),
              durationSec: stepDur,
              distanceM: stepDist.round(),
              action: type,
              maneuverType: mType,
              polylineStartIndex: currentPolyIndex,
              polylineEndIndex: endPolyIndex,
              streetName: stepName.isNotEmpty ? stepName : null,
            ));
            
            currentPolyIndex = endPolyIndex;
          }
        }
      }
      
      if (mapboxSteps.isNotEmpty && polyline.isNotEmpty) {
        final last = mapboxSteps.removeLast();
        mapboxSteps.add(RouteStep(
          instruction: last.instruction,
          instructionKn: last.instructionKn,
          durationSec: last.durationSec,
          distanceM: last.distanceM,
          action: last.action,
          maneuverType: last.maneuverType,
          polylineStartIndex: last.polylineStartIndex,
          polylineEndIndex: polyline.length - 1,
          streetName: last.streetName,
        ));
      }

      final result = RouteResult.withCumulativeDistances(
        polyline: polyline,
        distanceM: distance.round(),
        durationSec: duration,
        steps: mapboxSteps.isEmpty
            ? [RouteStep.simple(instruction: 'Head to destination', distanceM: distance.round(), durationSec: duration, action: 'depart')]
            : mapboxSteps,
        calculatedAt: DateTime.now(),
        routingEngine: 'mapbox',
      );
      
      if (result != null) {
        _lastSuccess = DateTime.now();
        _consecutiveFails = 0;
      }
      return result;
    } catch (e) {
      debugPrint('[Mapbox] calculateRoute error: $e');
      _lastFailure = DateTime.now();
      _consecutiveFails++;
      return null;
    }
  }

  static ManeuverType _mapboxToManeuverType(String type, String modifier) {
    switch (type) {
      case 'depart': return ManeuverType.depart;
      case 'arrive': return ManeuverType.destination;
      case 'merge':  return ManeuverType.merge;
      case 'on ramp':  return modifier.contains('left') ? ManeuverType.rampLeft : ManeuverType.rampRight;
      case 'off ramp': return modifier.contains('left') ? ManeuverType.exitLeft : ManeuverType.exitRight;
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn': return ManeuverType.roundaboutEnter;
      case 'turn':
      case 'end of road':
      case 'fork':
        if (modifier == 'sharp left')   return ManeuverType.sharpLeft;
        if (modifier == 'left')         return ManeuverType.left;
        if (modifier == 'slight left')  return ManeuverType.slightLeft;
        if (modifier == 'sharp right')  return ManeuverType.sharpRight;
        if (modifier == 'right')        return ManeuverType.right;
        if (modifier == 'slight right') return ManeuverType.slightRight;
        if (modifier == 'uturn')        return ManeuverType.uTurnRight;
        if (modifier == 'straight')     return ManeuverType.straight;
        return ManeuverType.continueStr;
      default:
        return ManeuverType.continueStr;
    }
  }

  static String _buildMapboxInstruction(Map<String, dynamic> maneuver, Map<String, dynamic> step) {
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    final name = step['name'] as String? ?? '';
    final road = name.isNotEmpty ? ' onto $name' : '';

    switch (type) {
      case 'depart': return 'Head ${modifier.isNotEmpty ? modifier : 'forward'}$road';
      case 'arrive': return 'You have arrived at your destination';
      case 'turn':
        if (modifier.contains('left')) return 'Turn left$road';
        if (modifier.contains('right')) return 'Turn right$road';
        return 'Turn${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      case 'new name': return 'Continue$road';
      case 'merge': return 'Merge${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      case 'on ramp': return 'Take the ramp$road';
      case 'off ramp': return 'Take the exit$road';
      case 'fork': return 'Keep ${modifier.contains('left') ? 'left' : 'right'}$road';
      case 'end of road': return 'Turn ${modifier.contains('left') ? 'left' : 'right'}$road';
      case 'roundabout': return 'Enter the roundabout';
      case 'rotary': return 'Enter the rotary';
      case 'roundabout turn': return 'Turn${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      default: return 'Continue$road';
    }
  }

  static String _buildMapboxInstructionKn(ManeuverType mType, String name) {
    final road = name.isNotEmpty ? ' $name ಕಡೆಗೆ' : '';
    switch (mType) {
      case ManeuverType.depart: return 'ಗಮ್ಯಸ್ಥಾನಕ್ಕೆ ಪ್ರಯಾಣ ಪ್ರಾರಂಭಿಸಿ';
      case ManeuverType.destination: return 'ನೀವು ತಲುಪಬೇಕಾದ ಸ್ಥಳಕ್ಕೆ ತಲುಪಿದ್ದೀರಿ';
      case ManeuverType.left: return '$road ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.slightLeft: return '$road ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.sharpLeft: return '$road ಚೂಪಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.right: return '$road ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.slightRight: return '$road ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.sharpRight: return '$road ಚೂಪಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.uTurnRight:
      case ManeuverType.uTurnLeft: return 'ಯು-ಟರ್ನ್ ಮಾಡಿ';
      case ManeuverType.roundaboutEnter: return 'ವೃತ್ತವನ್ನು ಪ್ರವೇಶಿಸಿ';
      case ManeuverType.merge: return 'ರಸ್ತೆಯಲ್ಲಿ ವಿಲೀನಗೊಳ್ಳಿ';
      default: return '$road ನೇರವಾಗಿ ಮುಂದೆ ಹೋಗಿ';
    }
  }

  @override
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    if (!isConfigured || sources.isEmpty || targets.isEmpty) return null;

    final profile = 'driving';
    
    // Mapbox Matrix API: coordinates are semicolon separated
    // sources and targets indices are passed
    final allPoints = [...sources, ...targets];
    final coords = allPoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    
    final sourcesParam = List.generate(sources.length, (i) => i).join(';');
    final targetsParam = List.generate(targets.length, (i) => i + sources.length).join(';');

    try {
      final resp = await _client.get(
        'https://api.mapbox.com/directions-matrix/v1/mapbox/$profile/$coords',
        queryParameters: {
          'sources': sourcesParam,
          'destinations': targetsParam,
          'annotations': 'distance,duration',
          'access_token': _accessToken,
        },
      );

      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        
        List<List<double?>> distances = [];
        List<List<int?>> durations = [];
        
        if (data['distances'] != null) {
          for (var row in data['distances']) {
            distances.add((row as List).map((e) => (e as num?)?.toDouble()).toList());
          }
        }
        
        if (data['durations'] != null) {
          for (var row in data['durations']) {
            durations.add((row as List).map((e) => (e as num?)?.toInt()).toList());
          }
        }

        return MatrixResult(
          sources: sources,
          targets: targets,
          distances: distances.isNotEmpty ? distances : [],
          durations: durations.isNotEmpty ? durations : [],
        );
      }
    } catch (_) {}
    return null;
  }
}
