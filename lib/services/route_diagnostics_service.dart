// lib/services/route_diagnostics_service.dart
// ================================================================
// KELASAGARA — RouteDiagnosticsService
// Programmatic route pipeline diagnostic tool.
// Tests: HTTP → JSON → trip → shape → decode → geometry → endpoint.
// ================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'valhalla_service.dart';

class DiagnosticsReport {
  final String engine;
  final String requestUrl;
  final int?   httpStatus;
  final int    durationMs;
  final bool   jsonParsed;
  final bool   tripPresent;
  final int    legCount;
  final int    maneuverCount;
  final int    shapeLength;
  final int    decodedPoints;
  final double distanceM;
  final int    durationSec;
  final double originErrorM;
  final double destErrorM;
  final bool   geometryValid;
  final String failureReason;
  final List<String> warnings;

  const DiagnosticsReport({
    required this.engine,
    required this.requestUrl,
    this.httpStatus,
    required this.durationMs,
    required this.jsonParsed,
    required this.tripPresent,
    required this.legCount,
    required this.maneuverCount,
    required this.shapeLength,
    required this.decodedPoints,
    required this.distanceM,
    required this.durationSec,
    required this.originErrorM,
    required this.destErrorM,
    required this.geometryValid,
    required this.failureReason,
    required this.warnings,
  });

  bool get success => failureReason.isEmpty;

  String get summary {
    if (!success) return 'ROUTE_INVALID: $failureReason';
    return 'ROUTE_OK | Engine:$engine | '
        '${(distanceM / 1000).toStringAsFixed(2)}km | '
        '${durationSec ~/ 60}min | '
        '${decodedPoints}pts | '
        'originΔ:${originErrorM.toStringAsFixed(0)}m | '
        'destΔ:${destErrorM.toStringAsFixed(0)}m | '
        '${durationMs}ms';
  }
}

class GoldenRouteCase {
  final String name;
  final double originLat, originLon, destLat, destLon;
  final double minDistanceM, maxDistanceM;
  final int    minPoints, minDurationSec;

  const GoldenRouteCase({
    required this.name,
    required this.originLat, required this.originLon,
    required this.destLat, required this.destLon,
    required this.minDistanceM, required this.maxDistanceM,
    required this.minPoints, required this.minDurationSec,
  });
}

class GoldenTestResult {
  final GoldenRouteCase testCase;
  final DiagnosticsReport report;
  final bool passed;
  final List<String> failures;
  const GoldenTestResult({required this.testCase, required this.report, required this.passed, required this.failures});
  @override String toString() => passed
      ? 'GOLDEN_PASS: ${testCase.name} | ${report.summary}'
      : 'GOLDEN_FAIL: ${testCase.name} | ${failures.join(", ")} | ${report.summary}';
}

class RouteDiagnosticsService {
  RouteDiagnosticsService._();
  static final RouteDiagnosticsService instance = RouteDiagnosticsService._();

  // Golden test: Bengaluru Majestic -> Whitefield
  static const GoldenRouteCase bengaluruGolden = GoldenRouteCase(
    name:           'Bengaluru Majestic to Whitefield',
    originLat: 12.9780, originLon: 77.5710,
    destLat:   12.9698, destLon:   77.7499,
    minDistanceM: 15000, maxDistanceM: 35000,
    minPoints: 50, minDurationSec: 1200,
  );

  static const double _maxEndpointErrorM = 500.0;
  static const double _maxJumpM          = 50000.0;

  Future<DiagnosticsReport> runDiagnostics({
    required double originLat, required double originLon,
    required double destLat,   required double destLon,
  }) async {
    final startMs = DateTime.now().millisecondsSinceEpoch;
    final warnings = <String>[];

    if (!_validCoord(originLat, originLon)) {
      return _fail('INVALID_ORIGIN ($originLat,$originLon)', startMs, warnings);
    }
    if (!_validCoord(destLat, destLon)) {
      return _fail('INVALID_DEST ($destLat,$destLon)', startMs, warnings);
    }

    final origin = LatLng(originLat, originLon);
    final dest   = LatLng(destLat, destLon);

    if (ValhallaService.isConfigured) {
      final r = await _testValhalla(origin, dest, startMs, List.from(warnings));
      if (r.success) return r;
      warnings.add('Valhalla: ${r.failureReason}');
    } else {
      warnings.add('Valhalla not configured');
    }

    return _testOsrm(origin, dest, startMs, warnings);
  }

  Future<GoldenTestResult> runGoldenTest([GoldenRouteCase? tc]) async {
    tc ??= bengaluruGolden;
    final report = await runDiagnostics(
      originLat: tc.originLat, originLon: tc.originLon,
      destLat: tc.destLat, destLon: tc.destLon,
    );
    final failures = <String>[];
    if (!report.success) {
      failures.add(report.failureReason);
    } else {
      if (report.distanceM < tc.minDistanceM) failures.add('dist ${report.distanceM.toInt()}m < min ${tc.minDistanceM.toInt()}m');
      if (report.distanceM > tc.maxDistanceM) failures.add('dist ${report.distanceM.toInt()}m > max ${tc.maxDistanceM.toInt()}m');
      if (report.decodedPoints < tc.minPoints) failures.add('points ${report.decodedPoints} < min ${tc.minPoints}');
      if (report.durationSec < tc.minDurationSec) failures.add('duration ${report.durationSec}s < min ${tc.minDurationSec}s');
    }
    final result = GoldenTestResult(testCase: tc, report: report, passed: failures.isEmpty, failures: failures);
    debugPrint('[RouteDiagnostics] Golden: $result');
    return result;
  }

  Future<DiagnosticsReport> _testValhalla(LatLng origin, LatLng dest, int startMs, List<String> warnings) async {
    final baseUrl = const String.fromEnvironment('VALHALLA_URL', defaultValue: '');
    final url = '$baseUrl/route';
    int? httpStatus;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
      final resp = await dio.post(url, data: {
        'locations': [
          {'lat': origin.latitude, 'lon': origin.longitude, 'type': 'break'},
          {'lat': dest.latitude,   'lon': dest.longitude,   'type': 'break'},
        ],
        'costing': 'auto',
        'directions_options': {'units': 'kilometers'},
      });
      httpStatus = resp.statusCode;
      final dMs = DateTime.now().millisecondsSinceEpoch - startMs;
      if (resp.statusCode != 200) return _failHttp('VALHALLA_HTTP_${resp.statusCode}', httpStatus, dMs, warnings);

      final data = resp.data as Map<String, dynamic>?;
      final trip = data?['trip'] as Map<String, dynamic>?;
      if (trip == null) return _failHttp('VALHALLA_TRIP_MISSING', httpStatus, dMs, warnings);

      final legs = trip['legs'] as List? ?? [];
      if (legs.isEmpty) return _failHttp('VALHALLA_NO_LEGS', httpStatus, dMs, warnings);

      final leg0     = legs[0] as Map<String, dynamic>;
      final shape    = leg0['shape'] as String? ?? '';
      if (shape.isEmpty) return _failHttp('VALHALLA_SHAPE_EMPTY', httpStatus, dMs, warnings);

      final summary  = trip['summary'] as Map<String, dynamic>? ?? {};
      final distM    = ((summary['length'] as num?)?.toDouble() ?? 0) * 1000;
      final durSec   = (summary['time'] as num?)?.toInt() ?? 0;
      final maneuvers= (leg0['maneuvers'] as List?)?.length ?? 0;
      final points   = ValhallaPolyline6.decode(shape);
      if (points.isEmpty) return _failHttp('VALHALLA_DECODE_EMPTY', httpStatus, dMs, warnings);

      return _buildReport('valhalla', url, httpStatus, dMs, shape.length, points, distM, durSec, legs.length, maneuvers, origin, dest, warnings);
    } on DioException catch (e) {
      return _failHttp('VALHALLA_NET:${e.message}', httpStatus, DateTime.now().millisecondsSinceEpoch - startMs, warnings);
    } catch (e) {
      return _failHttp('VALHALLA_ERR:$e', httpStatus, DateTime.now().millisecondsSinceEpoch - startMs, warnings);
    }
  }

  static const String _configuredOsrmUrl =
      String.fromEnvironment('OSRM_URL', defaultValue: '');

  Future<DiagnosticsReport> _testOsrm(LatLng origin, LatLng dest, int startMs, List<String> warnings) async {
    if (_configuredOsrmUrl.isEmpty) {
      return _failHttp('OSRM_URL_NOT_CONFIGURED', 0, 0, warnings);
    }
    final String osrmBase = _configuredOsrmUrl;

    final url = '$osrmBase/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${dest.longitude},${dest.latitude}'
        '?overview=full&geometries=polyline&steps=true';
    int? httpStatus;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
      final resp = await dio.get(url);
      httpStatus = resp.statusCode;
      final dMs = DateTime.now().millisecondsSinceEpoch - startMs;
      if (resp.statusCode != 200) return _failHttp('OSRM_HTTP_${resp.statusCode}', httpStatus, dMs, warnings);

      final data   = resp.data as Map<String, dynamic>?;
      final routes = data?['routes'] as List?;
      if (routes == null || routes.isEmpty) return _failHttp('OSRM_NO_ROUTES', httpStatus, dMs, warnings);

      final r0      = routes[0] as Map<String, dynamic>;
      final geometry = r0['geometry'] as String? ?? '';
      if (geometry.isEmpty) return _failHttp('OSRM_GEOMETRY_EMPTY', httpStatus, dMs, warnings);

      final distM  = (r0['distance'] as num?)?.toDouble() ?? 0;
      final durSec = (r0['duration'] as num?)?.toInt() ?? 0;
      final legs   = (r0['legs'] as List?)?.length ?? 0;
      int maneuvers = 0;
      for (final leg in r0['legs'] as List? ?? []) {
        maneuvers += ((leg as Map<String, dynamic>)['steps'] as List?)?.length ?? 0;
      }
      final points = _decodeP5(geometry);
      if (points.isEmpty) return _failHttp('OSRM_DECODE_EMPTY', httpStatus, dMs, warnings);

      return _buildReport('osrm', url, httpStatus, dMs, geometry.length, points, distM, durSec, legs, maneuvers, origin, dest, warnings);
    } on DioException catch (e) {
      return _failHttp('OSRM_NET:${e.message}', httpStatus, DateTime.now().millisecondsSinceEpoch - startMs, warnings);
    } catch (e) {
      return _failHttp('OSRM_ERR:$e', httpStatus, DateTime.now().millisecondsSinceEpoch - startMs, warnings);
    }
  }

  DiagnosticsReport _buildReport(
    String engine, String url, int? httpStatus, int dMs, int shapeLen,
    List<LatLng> points, double distM, int durSec, int legs, int maneuvers,
    LatLng origin, LatLng dest, List<String> warnings,
  ) {
    const dist = Distance();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.latitude.isNaN || p.latitude.isInfinite || p.longitude.isNaN || p.longitude.isInfinite) {
        return _failHttp('NAN_AT_$i', httpStatus, dMs, warnings);
      }
      if (i > 0) {
        final jmp = dist.as(LengthUnit.Meter, points[i-1], p);
        if (jmp > _maxJumpM) warnings.add('jump ${jmp.toStringAsFixed(0)}m at $i');
      }
    }
    final oErr = dist.as(LengthUnit.Meter, points.first, origin);
    final dErr = dist.as(LengthUnit.Meter, points.last, dest);
    String fail = '';
    if (oErr > _maxEndpointErrorM) fail = 'ORIGIN_MISMATCH ${oErr.toStringAsFixed(0)}m';
    else if (dErr > _maxEndpointErrorM) fail = 'DEST_MISMATCH ${dErr.toStringAsFixed(0)}m';
    else if (distM <= 0) fail = 'ZERO_DISTANCE';
    else if (durSec <= 0) fail = 'ZERO_DURATION';
    else if (points.length < 2) fail = 'TOO_FEW_POINTS';
    debugPrint('[RouteDiag] $engine dist=${distM.toInt()}m dur=${durSec}s pts=${points.length} '
        'oΔ=${oErr.toStringAsFixed(0)}m dΔ=${dErr.toStringAsFixed(0)}m ${fail.isEmpty ? "OK" : "FAIL:$fail"}');
    return DiagnosticsReport(
      engine: engine, requestUrl: url, httpStatus: httpStatus, durationMs: dMs,
      jsonParsed: true, tripPresent: true, legCount: legs, maneuverCount: maneuvers,
      shapeLength: shapeLen, decodedPoints: points.length, distanceM: distM,
      durationSec: durSec, originErrorM: oErr, destErrorM: dErr,
      geometryValid: fail.isEmpty, failureReason: fail,
      warnings: List.unmodifiable(warnings),
    );
  }

  DiagnosticsReport _fail(String r, int startMs, List<String> w) =>
      _failHttp(r, null, DateTime.now().millisecondsSinceEpoch - startMs, w);

  DiagnosticsReport _failHttp(String r, int? http, int dMs, List<String> w) => DiagnosticsReport(
    engine: '', requestUrl: '', httpStatus: http, durationMs: dMs,
    jsonParsed: false, tripPresent: false, legCount: 0, maneuverCount: 0,
    shapeLength: 0, decodedPoints: 0, distanceM: 0, durationSec: 0,
    originErrorM: 0, destErrorM: 0, geometryValid: false,
    failureReason: r, warnings: List.unmodifiable(w),
  );

  bool _validCoord(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;

  static List<LatLng> _decodeP5(String e) {
    if (e.isEmpty) return const [];
    final r = <LatLng>[];
    int i = 0, lat = 0, lng = 0;
    while (i < e.length) {
      int b, s = 0, v = 0;
      do { b = e.codeUnitAt(i++) - 63; v |= (b & 0x1F) << s; s += 5; } while (b >= 0x20 && i < e.length);
      lat += (v & 1) != 0 ? ~(v >> 1) : (v >> 1);
      s = 0; v = 0;
      do { b = e.codeUnitAt(i++) - 63; v |= (b & 0x1F) << s; s += 5; } while (b >= 0x20 && i < e.length);
      lng += (v & 1) != 0 ? ~(v >> 1) : (v >> 1);
      r.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return r;
  }
}
