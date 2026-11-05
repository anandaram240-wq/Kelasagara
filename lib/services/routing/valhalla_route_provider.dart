// lib/services/routing/valhalla_route_provider.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';
import 'package:kelasagaara/services/routing/routing_provider.dart';

class ValhallaRouteProvider implements RoutingProvider {
  final String _baseUrl;
  DateTime? _lastSuccess;
  DateTime? _lastFailure;
  int _consecutiveFails = 0;

  static String normalizeUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  static String get defaultUrl {
    const fromBase = String.fromEnvironment('VALHALLA_BASE_URL', defaultValue: '');
    if (fromBase.isNotEmpty) return fromBase;
    return const String.fromEnvironment('VALHALLA_URL', defaultValue: '');
  }

  String? _version;
  String? get version => _version;

  ValhallaRouteProvider({String? baseUrl})
      : _baseUrl = normalizeUrl(baseUrl ?? defaultUrl) {
    if (_baseUrl.isEmpty) {
      debugPrint('[Valhalla] ⚠️ VALHALLA_BASE_URL / VALHALLA_URL not configured — Valhalla routing is unavailable. '
          'Add --dart-define=VALHALLA_URL=http://... to enable.');
    } else {
      debugPrint('[Valhalla] Configured: $baseUrlSanitized');
    }
  }


  // V700 Fix D3: Singleton Dio — created once, reused for all requests.
  // Eliminates per-request TCP/TLS handshake overhead.
  // Resilient mobile timeouts: 4s connect, 8s receive, 4s send.
  Dio? _dio;
  Dio get _client {
    return _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 4),
      headers: const {'Content-Type': 'application/json'},
    ));
  }

  @override
  String get name => 'valhalla';

  bool get isConfigured => _baseUrl.isNotEmpty;

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

    final stopwatch = Stopwatch()..start();
    try {
      final resp = await _client.get('$_baseUrl/status');
      stopwatch.stop();

      if (resp.statusCode == 200) {
        _lastSuccess = DateTime.now();
        _consecutiveFails = 0;
        if (resp.data is Map) {
          _version = (resp.data as Map)['version']?.toString();
        }
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

  String get baseUrlSanitized {
    if (_baseUrl.isEmpty) return 'not_configured';
    try {
      final uri = Uri.parse(_baseUrl);
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}${uri.path}';
    } catch (_) {
      return 'configured';
    }
  }

  /// Calculates route returning detailed HTTP status and classified error info.
  Future<ValhallaDetailedResult> calculateRouteDetailed({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
    CancelToken? cancelToken,
  }) async {
    if (!isConfigured) {
      return ValhallaDetailedResult.failure(
        errorCode: 'NOT_CONFIGURED',
        errorMessage: 'VALHALLA_URL is not configured.',
      );
    }
    if (!_validCoord(origin.latitude, origin.longitude)) {
      return ValhallaDetailedResult.failure(
        errorCode: 'INVALID_ORIGIN',
        errorMessage: 'Origin coordinates are invalid or zero.',
      );
    }
    if (!_validCoord(destination.latitude, destination.longitude)) {
      return ValhallaDetailedResult.failure(
        errorCode: 'INVALID_DESTINATION',
        errorMessage: 'Destination coordinates are invalid or zero.',
      );
    }

    final body = {
      'locations': [
        {'lat': origin.latitude, 'lon': origin.longitude, 'type': 'break'},
        {'lat': destination.latitude, 'lon': destination.longitude, 'type': 'break'},
      ],
      'costing': costing,
      'directions_options': {'units': 'kilometers'},
      'costing_options': {
        costing: {'use_highways': 0.8, 'use_tolls': 0.5},
      },
    };

    try {
      final resp = await _client.post(
        '$_baseUrl/route',
        data: body,
        cancelToken: cancelToken,
      );
      final statusCode = resp.statusCode ?? 200;
      if (statusCode != 200) {
        return ValhallaDetailedResult.failure(
          httpStatus: statusCode,
          errorCode: 'HTTP_$statusCode',
          errorMessage: 'Valhalla returned HTTP $statusCode',
        );
      }

      final result = RouteResult.fromValhallaJson(resp.data as Map<String, dynamic>);
      if (result == null) {
        return ValhallaDetailedResult.failure(
          httpStatus: statusCode,
          errorCode: 'DECODE_ERROR',
          errorMessage: 'Failed to parse Valhalla JSON or polyline.',
        );
      }

      _lastSuccess = DateTime.now();
      _consecutiveFails = 0;
      return ValhallaDetailedResult.success(result, statusCode);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return ValhallaDetailedResult.failure(
          errorCode: 'CANCELLED',
          errorMessage: 'Routing request was cancelled',
        );
      }
      _lastFailure = DateTime.now();
      _consecutiveFails++;
      final status = e.response?.statusCode;
      final errorData = e.response?.data;
      String msg = e.message ?? 'Network error';
      String code = 'NETWORK_ERROR';

      if (status == 401 || status == 403) {
        code = 'AUTH_ERROR';
        msg = 'Valhalla authentication failed (HTTP $status)';
      } else if (status == 400 || status == 404 || status == 422) {
        code = 'NO_ROUTE';
        msg = 'No road route found between locations';
        if (errorData is Map && errorData.containsKey('error')) {
          msg = errorData['error'].toString();
        }
      } else if (status != null && status >= 500) {
        code = 'SERVER_ERROR';
        msg = 'Valhalla server error (HTTP $status)';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        code = 'TIMEOUT';
        msg = 'Routing request timed out';
      }

      return ValhallaDetailedResult.failure(
        httpStatus: status,
        errorCode: code,
        errorMessage: msg,
      );
    } catch (e) {
      _lastFailure = DateTime.now();
      _consecutiveFails++;
      return ValhallaDetailedResult.failure(
        errorCode: 'UNEXPECTED_ERROR',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<RouteResult?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String costing = 'auto',
  }) async {
    final res = await calculateRouteDetailed(
      origin: origin,
      destination: destination,
      costing: costing,
    );
    return res.route;
  }

  Future<LatLng?> snapToRoad(List<LatLng> gpsPoints) async {
    if (!isConfigured || gpsPoints.isEmpty) return null;

    try {
      final resp = await _client.post('$_baseUrl/trace_attributes', data: {
        'shape': gpsPoints.map((p) => {
          'lat': p.latitude, 'lon': p.longitude, 'type': 'break',
        }).toList(),
        'costing': 'auto',
        'shape_match': 'map_snap',
      });
      if (resp.statusCode == 200) {
        final matched = resp.data['matched_points'] as List?;
        if (matched?.isNotEmpty == true) {
          final last = matched!.last as Map<String, dynamic>?;
          final lat = (last?['lat'] as num?)?.toDouble();
          final lon = (last?['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<MatrixResult?> calculateMatrix({
    required List<LatLng> sources,
    required List<LatLng> targets,
  }) async {
    if (!isConfigured || sources.isEmpty || targets.isEmpty) return null;

    final body = {
      'sources': sources.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'targets': targets.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'costing': 'auto',
    };

    try {
      final resp = await _client.post('$_baseUrl/sources_to_targets', data: body);
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final sourcesToTargets = data['sources_to_targets'] as List?;
        if (sourcesToTargets == null) return null;

        List<List<double?>> distances = [];
        List<List<int?>> durations = [];

        for (final row in sourcesToTargets) {
          final rowList = row as List?;
          if (rowList == null) continue;
          
          List<double?> rowDistances = [];
          List<int?> rowDurations = [];
          
          for (final cell in rowList) {
            final cellMap = cell as Map<String, dynamic>?;
            if (cellMap == null) {
              rowDistances.add(null);
              rowDurations.add(null);
              continue;
            }
            rowDistances.add((cellMap['distance'] as num?)?.toDouble());
            rowDurations.add((cellMap['time'] as num?)?.toInt());
          }
          distances.add(rowDistances);
          durations.add(rowDurations);
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
}

class ValhallaDetailedResult {
  final bool isSuccess;
  final RouteResult? route;
  final int? httpStatus;
  final String? errorCode;
  final String? errorMessage;

  bool get isCancelled => errorCode == 'CANCELLED';

  const ValhallaDetailedResult({
    required this.isSuccess,
    this.route,
    this.httpStatus,
    this.errorCode,
    this.errorMessage,
  });

  factory ValhallaDetailedResult.success(RouteResult route, int statusCode) =>
      ValhallaDetailedResult(
        isSuccess: true,
        route: route,
        httpStatus: statusCode,
      );

  factory ValhallaDetailedResult.failure({
    int? httpStatus,
    String? errorCode,
    required String errorMessage,
  }) =>
      ValhallaDetailedResult(
        isSuccess: false,
        httpStatus: httpStatus,
        errorCode: errorCode,
        errorMessage: errorMessage,
      );
}

