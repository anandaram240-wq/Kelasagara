// lib/services/valhalla_service.dart
// Valhalla open-source routing engine client.
// PRODUCTION POLICY: Valhalla is the authoritative routing engine.
// Public demo routers are strictly disabled.
// Requires --dart-define=VALHALLA_URL=... or --dart-define=VALHALLA_BASE_URL=...
//
// ── Self-host Valhalla ──────────────────────────────────────────
//  bash "/Users/ananda/KELASAGARA MAJOR PROJECT/valhalla_setup.sh"
//  (Run after Docker Desktop is open)
//
//  Then build APK:
//  flutter build apk --release \
//    --dart-define=VALHALLA_URL=http://192.168.x.x:8002
//
// ── Phase 1 test ────────────────────────────────────────────────
//  ValhallaService.instance.runDiagnostic() — returns RouteHealthReport
//  with HTTP status, shape length, decode count, first/last point.
//  Call this from the debug panel before enabling navigation.

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import 'routing/routing_provider.dart';

// ── Routing health report (Phase 1 requirement) ──────────────────────────────
class RouteHealthReport {
  final bool serverReachable;
  final bool routeFound;
  final int  httpStatus;
  final String serverUrl;
  final String? errorMessage;
  final double? distanceKm;
  final int?    durationSec;
  final String? shapeRaw;
  final int     shapeDecodedPoints;
  final LatLng? firstPoint;
  final LatLng? lastPoint;
  final String? statusMessage;

  const RouteHealthReport({
    required this.serverReachable,
    required this.routeFound,
    required this.httpStatus,
    required this.serverUrl,
    this.errorMessage,
    this.distanceKm,
    this.durationSec,
    this.shapeRaw,
    this.shapeDecodedPoints = 0,
    this.firstPoint,
    this.lastPoint,
    this.statusMessage,
  });

  @override
  String toString() => '''
RouteHealthReport {
  serverUrl:       $serverUrl
  serverReachable: $serverReachable
  httpStatus:      $httpStatus
  routeFound:      $routeFound
  distanceKm:      $distanceKm
  durationSec:     $durationSec
  shapeLength:     ${shapeRaw?.length ?? 0} chars
  decodedPoints:   $shapeDecodedPoints
  firstPoint:      $firstPoint
  lastPoint:       $lastPoint
  statusMessage:   $statusMessage
  error:           $errorMessage
}''';
}

// ── Routing server status ────────────────────────────────────────────────────
enum RoutingStatus {
  notConfigured,   // VALHALLA_URL not set
  online,          // /status returned 200
  offline,         // cannot reach server
  error,           // unexpected response
}

// ── ValhallaService ──────────────────────────────────────────────────────────
class ValhallaService implements RoutingProvider {
  ValhallaService._();
  static final ValhallaService instance = ValhallaService._();

  @override
  String get name => lastRoutingSource;

  // ── V400 RoutingProvider interface ─────────────────────────────────────────
  @override
  PolylineEncoding get polylineEncoding => PolylineEncoding.polyline6;

  @override
  ProviderPriority get priority => ProviderPriority.primary;

  @override
  bool get supportsMatrix => _configuredUrl.isNotEmpty;

  @override
  Future<bool> checkHealth() async => (await checkStatus()) == RoutingStatus.online;

  @override
  Future<ProviderHealth> checkHealthDetailed() async {
    final sw = Stopwatch()..start();
    final online = (await checkStatus()) == RoutingStatus.online;
    sw.stop();
    return ProviderHealth(
      online: online,
      latencyMs: sw.elapsedMilliseconds,
      lastSuccess: online ? DateTime.now() : null,
      lastFailure: online ? null : DateTime.now(),
    );
  }

  @override
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    if (_configuredUrl.isEmpty) return null;
    // Matrix via Valhalla /sources_to_targets
    try {
      final payload = {
        'sources': sources
            .map((p) => {'lon': p.longitude, 'lat': p.latitude})
            .toList(),
        'targets': targets
            .map((p) => {'lon': p.longitude, 'lat': p.latitude})
            .toList(),
        'costing': 'auto',
      };
      final resp = await _dio.post('$_configuredUrl/sources_to_targets',
          data: payload);
      final data = resp.data as Map<String, dynamic>;
      final sourcesData =
          (data['sources_to_targets'] as List).cast<List<dynamic>>();
      final distances = <List<double?>>[];
      final durations = <List<int?>>[];
      for (final row in sourcesData) {
        final dRow = <double?>[];
        final tRow = <int?>[];
        for (final cell in row) {
          final c = cell as Map<String, dynamic>?;
          dRow.add((c?['distance'] as num?)?.toDouble());
          tRow.add((c?['time'] as num?)?.toInt());
        }
        distances.add(dRow);
        durations.add(tRow);
      }
      return MatrixResult(
        sources: sources,
        targets: targets,
        distances: distances,
        durations: durations,
      );
    } catch (e) {
      debugPrint('[ValhallaService] Matrix error: $e');
      return null;
    }
  }

  @override
  Future<RouteResult?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
  }) => getRoute(origin: origin, destination: destination, costing: costing);

  // Requires --dart-define=VALHALLA_URL=http://192.168.x.x:8002
  // NO default fallback to public endpoints (they are unstable).
  static const String _configuredUrl =
      String.fromEnvironment('VALHALLA_URL', defaultValue: '');

  static String get baseUrl => _configuredUrl;
  static bool   get isConfigured => _configuredUrl.isNotEmpty;

  RoutingStatus _lastKnownStatus = RoutingStatus.notConfigured;
  RoutingStatus get lastKnownStatus => _lastKnownStatus;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),  // Fast fail → OSRM fallback
    receiveTimeout: const Duration(seconds: 8),  // was 15s — Valhalla on LAN responds in <3s
    headers: {'Content-Type': 'application/json'},
  ));

  // ── Health check (/status endpoint) ─────────────────────────────────────────
  Future<RoutingStatus> checkStatus() async {
    if (!isConfigured) {
      _lastKnownStatus = RoutingStatus.notConfigured;
      debugPrint('[Valhalla] ❌ Not configured — set VALHALLA_URL via --dart-define');
      return RoutingStatus.notConfigured;
    }
    try {
      final resp = await _dio.get(
        '$_configuredUrl/status',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (resp.statusCode == 200) {
        _lastKnownStatus = RoutingStatus.online;
        debugPrint('[Valhalla] ✅ Server online: $_configuredUrl');
        return RoutingStatus.online;
      }
      _lastKnownStatus = RoutingStatus.error;
      debugPrint('[Valhalla] ⚠️  Unexpected HTTP ${resp.statusCode}');
      return RoutingStatus.error;
    } on DioException catch (e) {
      _lastKnownStatus = RoutingStatus.offline;
      debugPrint('[Valhalla] ❌ Server offline: ${e.message}');
      return RoutingStatus.offline;
    }
  }

  // ── Phase 1 diagnostic (12-point test) ──────────────────────────────────────
  // Tests routing from Bengaluru to Hassan (real Karnataka coordinates).
  // Call this from the debug panel before enabling navigation.
  Future<RouteHealthReport> runDiagnostic({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!isConfigured) {
      return const RouteHealthReport(
        serverReachable: false,
        routeFound:      false,
        httpStatus:      0,
        serverUrl:       'NOT CONFIGURED',
        errorMessage:
            'Set VALHALLA_URL via --dart-define=VALHALLA_URL=http://192.168.x.x:8002',
      );
    }

    // 1. Server reachable?
    final status = await checkStatus();
    if (status != RoutingStatus.online) {
      return RouteHealthReport(
        serverReachable: false,
        routeFound:      false,
        httpStatus:      0,
        serverUrl:       _configuredUrl,
        errorMessage:    'Server unreachable at $_configuredUrl/status\n'
                         'Is Docker running? Run: docker start kelasagara_valhalla',
      );
    }

    // 2. POST /route
    final body = {
      'locations': [
        {'lat': origin.latitude,      'lon': origin.longitude,      'type': 'break'},
        {'lat': destination.latitude, 'lon': destination.longitude, 'type': 'break'},
      ],
      'costing': 'auto',
      'directions_options': {'units': 'kilometers'},
    };

    try {
      final resp = await _dio.post('$_configuredUrl/route', data: body);

      if (resp.statusCode != 200) {
        return RouteHealthReport(
          serverReachable: true,
          routeFound:      false,
          httpStatus:      resp.statusCode ?? 0,
          serverUrl:       _configuredUrl,
          errorMessage:    'HTTP ${resp.statusCode}: ${resp.data}',
        );
      }

      // 3. Parse response
      final data    = resp.data as Map<String, dynamic>;
      final trip    = data['trip']    as Map<String, dynamic>?;
      final summary = trip?['summary'] as Map<String, dynamic>?;
      final legs    = trip?['legs']   as List?;
      final leg0    = (legs?.isNotEmpty == true) ? legs![0] as Map<String, dynamic>? : null;
      final shape   = leg0?['shape'] as String? ?? '';
      final statusMsg = trip?['status_message'] as String?;

      // 4. Decode Polyline6
      final decoded = ValhallaPolyline6.decode(shape);

      return RouteHealthReport(
        serverReachable:    true,
        routeFound:         trip != null && shape.isNotEmpty,
        httpStatus:         200,
        serverUrl:          _configuredUrl,
        distanceKm:         (summary?['length'] as num?)?.toDouble(),
        durationSec:        (summary?['time']   as num?)?.toInt(),
        shapeRaw:           shape,
        shapeDecodedPoints: decoded.length,
        firstPoint:         decoded.isNotEmpty ? decoded.first : null,
        lastPoint:          decoded.isNotEmpty ? decoded.last  : null,
        statusMessage:      statusMsg,
      );
    } on DioException catch (e) {
      return RouteHealthReport(
        serverReachable: true,
        routeFound:      false,
        httpStatus:      e.response?.statusCode ?? 0,
        serverUrl:       _configuredUrl,
        errorMessage:    'HTTP error: ${e.message}',
      );
    } catch (e) {
      return RouteHealthReport(
        serverReachable: true,
        routeFound:      false,
        httpStatus:      200,
        serverUrl:       _configuredUrl,
        errorMessage:    'Parse error: $e',
      );
    }
  }

  // ── Get real road route ──────────────────────────────────────────────────────
  // Priority: Valhalla (self-hosted) → OSRM (public, free, no key needed).
  // Returns null ONLY when both engines fail — never fake data.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
  }) async {
    // Coordinate validation (same for both engines)
    if (!_validCoord(origin.latitude, origin.longitude)) {
      debugPrint('[Routing] ❌ Invalid origin: $origin');
      return null;
    }
    if (!_validCoord(destination.latitude, destination.longitude)) {
      debugPrint('[Routing] ❌ Invalid destination: $destination');
      return null;
    }
    if (_samePosition(origin, destination)) {
      debugPrint('[Routing] ⚠️  Origin = destination — already at job location');
      return null;
    }

    // ── Try Valhalla first (if configured) ──────────────────────────────────
    if (isConfigured) {
      final result = await _getRouteFromValhalla(origin, destination, costing);
      if (result != null) return result;
      debugPrint('[Routing] Valhalla failed → trying OSRM fallback');
    } else {
      debugPrint('[Routing] Valhalla not configured → using OSRM public API');
      _lastKnownStatus = RoutingStatus.notConfigured;
    }

    // ── OSRM public fallback ─────────────────────────────────────────────────
    return _getRouteFromOsrm(origin, destination);
  }

  static bool _isLocalLanUrl(String url) {
    return url.contains('127.0.0.1') ||
           url.contains('localhost') ||
           url.contains('192.168.') ||
           url.contains('10.') ||
           RegExp(r'172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(url);
  }

  Future<RouteResult?> _getRouteFromValhalla(
      LatLng origin, LatLng destination, String costing) async {
    final body = {
      'locations': [
        {'lat': origin.latitude,      'lon': origin.longitude,      'type': 'break'},
        {'lat': destination.latitude, 'lon': destination.longitude, 'type': 'break'},
      ],
      'costing': costing,
      'directions_options': {'units': 'kilometers'},
      'costing_options': {
        costing: {'use_highways': 0.8, 'use_tolls': 0.5},
      },
    };

    try {
      debugPrint('[Valhalla] → POST route '
          '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)} → '
          '${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}');

      // Fast-fail probe for local LAN IPs when device is on 4G/5G mobile data
      final isLocal = _isLocalLanUrl(_configuredUrl);
      final client = isLocal
          ? Dio(BaseOptions(
              connectTimeout: const Duration(milliseconds: 1500),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'Content-Type': 'application/json'},
            ))
          : _dio;

      final resp = await client.post('$_configuredUrl/route', data: body);
      if (resp.statusCode != 200) return null;

      final result = RouteResultValhalla.fromValhallaJson(resp.data as Map<String, dynamic>);
      if (result == null) return null;

      debugPrint('[Valhalla] ✅ ${result.distanceText} / ${result.etaText} / ${result.polyline.length} pts');
      _lastKnownStatus = RoutingStatus.online;
      lastRoutingSource = 'valhalla';
      return result;

    } on DioException catch (e) {
      _lastKnownStatus = RoutingStatus.offline;
      debugPrint('[Valhalla] ❌ ${e.message} (offline on 4G/5G)');
      return null;
    } catch (e) {
      debugPrint('[Valhalla] ❌ $e');
      return null;
    }
  }

  static const String _configuredOsrmUrl =
      String.fromEnvironment('OSRM_URL', defaultValue: '');

  // ── OSRM API — real OpenStreetMap road data ────────
  // Uses driving profile with radiuses=unlimited for rural coverage.
  Future<RouteResult?> _getRouteFromOsrm(LatLng origin, LatLng destination) async {
    if (_configuredOsrmUrl.isEmpty) {
      debugPrint('[Valhalla/OSRM] ❌ OSRM_URL is not configured. Public demo servers are disabled.');
      return null;
    }
    final String osrmBase = _configuredOsrmUrl;
    // radiuses=unlimited;unlimited ensures rural points snap to nearest road
    final url = '$osrmBase/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=polyline&steps=true&radiuses=unlimited;unlimited';

    try {
      debugPrint('[OSRM] → GET $url');
      final resp = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      )).get(url);

      if (resp.statusCode != 200) {
        debugPrint('[OSRM] ❌ HTTP ${resp.statusCode}');
        return null;
      }

      final data   = resp.data as Map<String, dynamic>;
      final code   = data['code'] as String?;
      if (code != 'Ok') {
        debugPrint('[OSRM] ❌ code=$code');
        return null;
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route    = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as String? ?? '';
      final distance = (route['distance'] as num?)?.toDouble() ?? 0; // metres
      final duration = (route['duration'] as num?)?.toInt() ?? 0;    // seconds

      // OSRM uses precision-5 polyline (standard Google format)
      final polyline = _decodePolyline5(geometry);
      if (polyline.isEmpty) {
        debugPrint('[OSRM] ❌ Empty polyline decoded');
        return null;
      }

      // Build cumulative distance array to accurately project steps to polyline indices
      final cumDist = RouteResult.buildCumDist(polyline);
      int currentPolyIndex = 0;
      double accumulatedDist = 0;

      // Build steps from OSRM legs → steps → maneuvers
      final legs      = route['legs'] as List? ?? [];
      final osrmSteps = <RouteStep>[];

      for (final leg in legs) {
        final legMap = leg as Map<String, dynamic>;
        final steps  = legMap['steps'] as List? ?? [];
        for (final step in steps) {
          final s           = step as Map<String, dynamic>;
          final maneuver    = s['maneuver'] as Map<String, dynamic>? ?? {};
          final stepDist    = (s['distance'] as num?)?.toDouble() ?? 0.0;
          final stepDur     = ((s['duration'] as num?)?.toDouble() ?? 0.0).round();
          final stepName    = s['name'] as String? ?? '';
          final mTypeStr    = maneuver['type'] as String? ?? 'continue';
          final mModStr     = maneuver['modifier'] as String? ?? '';

          final maneuverType = _osrmToManeuverType(mTypeStr, mModStr);
          final instruction  = _buildOsrmInstruction(maneuver, s);
          final instructionKn= _buildOsrmInstructionKn(maneuverType, stepName);

          accumulatedDist += stepDist;
          int endPolyIndex = currentPolyIndex;
          if (cumDist.isNotEmpty) {
            while (endPolyIndex < cumDist.length - 1 &&
                   cumDist[endPolyIndex] < accumulatedDist) {
              endPolyIndex++;
            }
          }

          osrmSteps.add(RouteStep(
            instruction:        instruction,
            instructionKn:      instructionKn,
            durationSec:        stepDur,
            distanceM:          stepDist.round(),
            action:             mTypeStr,
            maneuverType:       maneuverType,
            polylineStartIndex: currentPolyIndex,
            polylineEndIndex:   endPolyIndex,
            streetName:         stepName.isNotEmpty ? stepName : null,
          ));

          currentPolyIndex = endPolyIndex;
        }
      }

      // Guarantee the final step reaches the end of the polyline
      if (osrmSteps.isNotEmpty && polyline.isNotEmpty) {
        final last = osrmSteps.removeLast();
        osrmSteps.add(RouteStep(
          instruction:        last.instruction,
          instructionKn:      last.instructionKn,
          durationSec:        last.durationSec,
          distanceM:          last.distanceM,
          action:             last.action,
          maneuverType:       last.maneuverType,
          polylineStartIndex: last.polylineStartIndex,
          polylineEndIndex:   polyline.length - 1,
          streetName:         last.streetName,
        ));
      }

      final result = RouteResult.withCumulativeDistances(
        polyline:      polyline,
        distanceM:     distance.round(),
        durationSec:   duration,
        steps:         osrmSteps.isEmpty
            ? [RouteStep.simple(instruction: 'Head to destination', distanceM: distance.round(), durationSec: duration, action: 'depart')]
            : osrmSteps,
        calculatedAt:  DateTime.now(),
        routingEngine: 'osrm',
      );

      lastRoutingSource = 'osrm';
      debugPrint('[OSRM] ✅ ${result.distanceText} / ${result.etaText} / ${polyline.length} pts / ${osrmSteps.length} steps');
      return result;

    } on DioException catch (e) {
      debugPrint('[OSRM] ❌ Network error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[OSRM] ❌ Parse error: $e');
      return null;
    }
  }

  // Map OSRM maneuver type + modifier to canonical ManeuverType
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

  // OSRM instruction builder (English)
  static String _buildOsrmInstruction(Map<String, dynamic> maneuver, Map<String, dynamic> step) {
    final type      = maneuver['type']      as String? ?? '';
    final modifier  = maneuver['modifier']  as String? ?? '';
    final name      = step['name']          as String? ?? '';
    final road      = name.isNotEmpty ? ' onto $name' : '';

    switch (type) {
      case 'depart':          return 'Head ${modifier.isNotEmpty ? modifier : 'forward'}$road';
      case 'arrive':          return 'You have arrived at your destination';
      case 'turn':
        if (modifier.contains('left'))  return 'Turn left$road';
        if (modifier.contains('right')) return 'Turn right$road';
        return 'Turn${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      case 'new name':        return 'Continue$road';
      case 'merge':           return 'Merge${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      case 'on ramp':         return 'Take the ramp$road';
      case 'off ramp':        return 'Take the exit$road';
      case 'fork':            return 'Keep ${modifier.contains('left') ? 'left' : 'right'}$road';
      case 'end of road':     return 'Turn ${modifier.contains('left') ? 'left' : 'right'}$road';
      case 'roundabout':      return 'Enter the roundabout';
      case 'rotary':          return 'Enter the rotary';
      case 'roundabout turn': return 'Turn${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      default:                return 'Continue$road';
    }
  }

  // OSRM instruction builder (Kannada)
  static String _buildOsrmInstructionKn(ManeuverType mType, String name) {
    final road = name.isNotEmpty ? ' $name ಕಡೆಗೆ' : '';
    switch (mType) {
      case ManeuverType.depart:          return 'ಗಮ್ಯಸ್ಥಾನಕ್ಕೆ ಪ್ರಯಾಣ ಪ್ರಾರಂಭಿಸಿ';
      case ManeuverType.destination:     return 'ನೀವು ತಲುಪಬೇಕಾದ ಸ್ಥಳಕ್ಕೆ ತಲುಪಿದ್ದೀರಿ';
      case ManeuverType.left:            return '$road ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.slightLeft:      return '$road ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.sharpLeft:       return '$road ಚೂಪಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.right:           return '$road ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.slightRight:     return '$road ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.sharpRight:      return '$road ಚೂಪಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿ';
      case ManeuverType.uTurnRight:
      case ManeuverType.uTurnLeft:       return 'ಯು-ಟರ್ನ್ ಮಾಡಿ';
      case ManeuverType.roundaboutEnter: return 'ವೃತ್ತವನ್ನು ಪ್ರವೇಶಿಸಿ';
      case ManeuverType.merge:           return 'ರಸ್ತೆಯಲ್ಲಿ ವಿಲೀನಗೊಳ್ಳಿ';
      default:                           return '$road ನೇರವಾಗಿ ಮುಂದೆ ಹೋಗಿ';
    }
  }

  // Standard precision-5 polyline decoder (used by OSRM / Google)
  static List<LatLng> _decodePolyline5(String encoded) {
    if (encoded.isEmpty) return const [];
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do {
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      shift = 0; res = 0;
      do {
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  /// Which engine provided the last successful route: 'valhalla' | 'osrm' | 'none'
  String lastRoutingSource = 'none';

  // ── Map matching (Meili) — snap GPS trace to roads ───────────────────────────
  Future<LatLng?> snapToRoad(List<LatLng> gpsPoints) async {
    if (!isConfigured || gpsPoints.isEmpty) return null;
    try {
      final resp = await _dio.post('$_configuredUrl/trace_attributes', data: {
        'shape': gpsPoints.map((p) => {
          'lat': p.latitude, 'lon': p.longitude, 'type': 'break',
        }).toList(),
        'costing':     'auto',
        'shape_match': 'map_snap',
      });
      if (resp.statusCode == 200) {
        final matched = resp.data['matched_points'] as List?;
        if (matched?.isNotEmpty == true) {
          final last = matched!.last as Map<String, dynamic>?;
          final lat  = (last?['lat'] as num?)?.toDouble();
          final lon  = (last?['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  bool _validCoord(double lat, double lng) =>
      lat.isFinite && lng.isFinite &&
      lat >= -90 && lat <= 90 &&
      lng >= -180 && lng <= 180 &&
      !(lat == 0 && lng == 0);

  bool _samePosition(LatLng a, LatLng b) {
    const eps = 0.0001;
    return (a.latitude - b.latitude).abs() < eps &&
           (a.longitude - b.longitude).abs() < eps;
  }
}

// ── Polyline6 decoder ─────────────────────────────────────────────────────────
// Valhalla encodes route geometry with Google Polyline Algorithm at PRECISION 6
// (factor 1e6, not the standard 5 = 1e5).
// A precision-5 decoder will misplace coordinates by ~10x.
class ValhallaPolyline6 {
  ValhallaPolyline6._();

  /// Decodes a Valhalla Polyline6 encoded string into [LatLng] list.
  static List<LatLng> decode(String encoded) {
    if (encoded.isEmpty) return const [];

    final result = <LatLng>[];
    int index = 0;
    int lat   = 0;
    int lng   = 0;

    while (index < encoded.length) {
      // Decode one delta value
      int b, shift = 0, res = 0;

      // latitude delta
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);

      if (index >= encoded.length) break;

      // longitude delta
      shift = 0;
      res   = 0;
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);

      result.add(LatLng(lat / 1e6, lng / 1e6));
    }

    return result;
  }

  /// Verify decoded coordinates are within Karnataka/India bounds.
  static bool isInKarnataka(LatLng p) =>
      p.latitude  >= 10.0 && p.latitude  <= 20.0 &&
      p.longitude >= 73.0 && p.longitude <= 80.0;
}
