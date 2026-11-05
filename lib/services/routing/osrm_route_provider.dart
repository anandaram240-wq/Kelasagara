// lib/services/routing/osrm_route_provider.dart

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';

class OsrmRouteProvider implements RoutingProvider {
  // Self-hosted OSRM URL via --dart-define=OSRM_URL=https://your-osrm-host
  // Public demo servers are strictly disabled.
  static const String _configuredUrl =
      String.fromEnvironment('OSRM_URL', defaultValue: '');

  // Whether a self-hosted OSRM is configured.
  bool get isProductionConfigured => _configuredUrl.isNotEmpty;

  DateTime? _lastSuccess;
  DateTime? _lastFailure;
  int _consecutiveFails = 0;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 6),
    sendTimeout: const Duration(seconds: 3),
  ));



  @override
  String get name => 'osrm';

  @override
  PolylineEncoding get polylineEncoding => PolylineEncoding.polyline5;

  @override
  ProviderPriority get priority => ProviderPriority.secondary;

  @override
  bool get supportsMatrix => true;

  @override
  Future<ProviderHealth> checkHealthDetailed() async {
    final stopwatch = Stopwatch()..start();
    try {
      final pingBase = _configuredUrl;
      if (pingBase.isEmpty) {
        return ProviderHealth(
          online: false,
          latencyMs: 0,
          lastSuccess: _lastSuccess,
          lastFailure: _lastFailure,
          consecutiveFails: _consecutiveFails + 1,
        );
      }
      final resp = await _dio.get('$pingBase/route/v1/driving/0,0;0,0');
      stopwatch.stop();

      // OSRM usually returns 400 for 0,0 but responds quickly if online
      if (resp.statusCode != null) {
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
    } catch (e) {
      if (e is DioException && e.response != null) {
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
    }

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
    if (!_validCoord(origin.latitude, origin.longitude) || !_validCoord(destination.latitude, destination.longitude)) {
      return null;
    }

    // Explicit self-hosted OSRM URL via --dart-define=OSRM_URL.
    // Public demo servers are strictly disabled across all execution modes.
    if (_configuredUrl.isEmpty) {
      debugPrint('[OSRM] ❌ OSRM_URL is not configured. Public demo servers are strictly disabled.');
      return null;
    }
    final mirrors = [_configuredUrl];

    for (final osrmBase in mirrors) {
      final url = '$osrmBase/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=polyline&steps=true&radiuses=unlimited;unlimited';

      try {
        final resp = await _dio.get(url);

        if (resp.statusCode != 200) continue;

        final data = resp.data as Map<String, dynamic>;
        final code = data['code'] as String?;
        if (code != 'Ok') continue;

        final routes = data['routes'] as List?;
        if (routes == null || routes.isEmpty) continue;

        final route = routes[0] as Map<String, dynamic>;
        final geometry = route['geometry'] as String? ?? '';
        final distance = (route['distance'] as num?)?.toDouble() ?? 0;
        final duration = (route['duration'] as num?)?.toInt() ?? 0;

        final polyline = _decodePolyline5(geometry);
        if (polyline.isEmpty) continue;

        final cumDist = RouteResult.buildCumDist(polyline);
        int currentPolyIndex = 0;
        double accumulatedDist = 0;

        final legs = route['legs'] as List? ?? [];
        final osrmSteps = <RouteStep>[];

        for (final leg in legs) {
          final legMap = leg as Map<String, dynamic>;
          final steps = legMap['steps'] as List? ?? [];
          for (final step in steps) {
          final s = step as Map<String, dynamic>;
          final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
          final stepDist = (s['distance'] as num?)?.toDouble() ?? 0.0;
          final stepDur = ((s['duration'] as num?)?.toDouble() ?? 0.0).round();
          final stepName = s['name'] as String? ?? '';
          final mTypeStr = maneuver['type'] as String? ?? 'continue';
          final mModStr = maneuver['modifier'] as String? ?? '';

          final maneuverType = _osrmToManeuverType(mTypeStr, mModStr);
          final instruction = _buildOsrmInstruction(maneuver, s);
          final instructionKn = _buildOsrmInstructionKn(maneuverType, stepName);

          accumulatedDist += stepDist;
          int endPolyIndex = currentPolyIndex;
          if (cumDist.isNotEmpty) {
            while (endPolyIndex < cumDist.length - 1 &&
                   cumDist[endPolyIndex] < accumulatedDist) {
              endPolyIndex++;
            }
          }

          osrmSteps.add(RouteStep(
            instruction: instruction,
            instructionKn: instructionKn,
            durationSec: stepDur,
            distanceM: stepDist.round(),
            action: mTypeStr,
            maneuverType: maneuverType,
            polylineStartIndex: currentPolyIndex,
            polylineEndIndex: endPolyIndex,
            streetName: stepName.isNotEmpty ? stepName : null,
          ));

          currentPolyIndex = endPolyIndex;
        }
      }

      if (osrmSteps.isNotEmpty && polyline.isNotEmpty) {
        final last = osrmSteps.removeLast();
        osrmSteps.add(RouteStep(
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
          steps: osrmSteps.isEmpty
              ? [RouteStep.simple(instruction: 'Head to destination', distanceM: distance.round(), durationSec: duration, action: 'depart')]
              : osrmSteps,
          calculatedAt: DateTime.now(),
          routingEngine: 'osrm',
        );
        
        _lastSuccess = DateTime.now();
        _consecutiveFails = 0;
        return result;
      } catch (e) {
        debugPrint('[OSRM] Error on $osrmBase: $e');
        _lastFailure = DateTime.now();
        _consecutiveFails++;
        continue; // Try the next mirror
      }
    }
    
    // If we exhausted all mirrors and got nothing
    return null;
  }

  @override
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    if (sources.isEmpty || targets.isEmpty) return null;
    
    final coords = [...sources, ...targets];
    final coordsStr = coords.map((c) => '${c.longitude},${c.latitude}').join(';');
    
    final sourcesIdx = List.generate(sources.length, (i) => i).join(';');
    final targetsIdx = List.generate(targets.length, (i) => i + sources.length).join(';');

    if (_configuredUrl.isEmpty) {
      debugPrint('[OSRM] ❌ OSRM_URL is not configured for Matrix. Public demo servers are strictly disabled.');
      return null;
    }
    final String osrmBase = _configuredUrl;

    final url = '$osrmBase/table/v1/driving/$coordsStr'
        '?sources=$sourcesIdx&destinations=$targetsIdx&annotations=distance,duration';
        
    try {
      final resp = await _dio.get(url);
      
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        if (data['code'] == 'Ok') {
          final distancesJson = data['distances'] as List?;
          final durationsJson = data['durations'] as List?;
          
          List<List<double?>> distances = [];
          List<List<int?>> durations = [];
          
          for (int i = 0; i < (distancesJson?.length ?? 0); i++) {
            distances.add((distancesJson![i] as List).map((e) => (e as num?)?.toDouble()).toList());
            durations.add((durationsJson![i] as List).map((e) => (e as num?)?.toInt()).toList());
          }
          
          return MatrixResult(
            sources: sources,
            targets: targets,
            distances: distances,
            durations: durations,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static ManeuverType _osrmToManeuverType(String type, String modifier) {
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

  static String _buildOsrmInstruction(Map<String, dynamic> maneuver, Map<String, dynamic> step) {
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

  static String _buildOsrmInstructionKn(ManeuverType mType, String name) {
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

  static List<LatLng> _decodePolyline5(String encoded) {
    if (encoded.isEmpty) return const [];
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      shift = 0; res = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}
