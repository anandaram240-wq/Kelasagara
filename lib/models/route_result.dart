// lib/models/route_result.dart
// Single canonical RouteResult model for Kelasagara.
// PHASE 1 EXTENDED: ManeuverType enum, RouteStep with polylineStartIndex/End,
// instructionKn (Kannada), streetName — powers NavigationEngine step tracking.
//
// DO NOT add a second route model. Both worker and hirer use this same file.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ── ManeuverType ──────────────────────────────────────────────────────────────
enum ManeuverType {
  depart, destination, continueStr, slightRight, right, sharpRight,
  uTurnRight, uTurnLeft, sharpLeft, left, slightLeft, rampRight, rampLeft,
  exitRight, exitLeft, roundaboutEnter, roundaboutExit,
  ferryEnter, ferryExit, transit, merge, straight, unknown;

  static ManeuverType fromValhallaType(int t) => switch (t) {
    0  => depart,       1  => continueStr,   2  => slightRight,
    3  => right,        4  => sharpRight,    5  => uTurnRight,
    6  => uTurnLeft,    7  => sharpLeft,     8  => left,
    9  => slightLeft,   10 => merge,         11 => rampRight,
    12 => rampLeft,     13 => exitRight,     14 => exitLeft,
    15 => straight,     17 => roundaboutEnter, 18 => roundaboutExit,
    19 => ferryEnter,   20 => ferryExit,
    _ => (t >= 36) ? destination : unknown,
  };

  IconData get icon => switch (this) {
    depart          => Icons.my_location_rounded,
    destination     => Icons.location_on_rounded,
    continueStr     => Icons.arrow_upward_rounded,
    straight        => Icons.arrow_upward_rounded,
    slightRight     => Icons.turn_slight_right_rounded,
    right           => Icons.turn_right_rounded,
    sharpRight      => Icons.turn_sharp_right_rounded,
    uTurnRight      => Icons.u_turn_right_rounded,
    uTurnLeft       => Icons.u_turn_left_rounded,
    sharpLeft       => Icons.turn_sharp_left_rounded,
    left            => Icons.turn_left_rounded,
    slightLeft      => Icons.turn_slight_left_rounded,
    rampRight       => Icons.ramp_right_rounded,
    rampLeft        => Icons.ramp_left_rounded,
    exitRight       => Icons.exit_to_app_rounded,
    exitLeft        => Icons.exit_to_app_rounded,
    roundaboutEnter => Icons.roundabout_right_rounded,
    roundaboutExit  => Icons.roundabout_right_rounded,
    merge           => Icons.merge_rounded,
    ferryEnter      => Icons.directions_boat_rounded,
    ferryExit       => Icons.directions_boat_rounded,
    _               => Icons.navigation_rounded,
  };

  // Kannada prefix for TTS
  String get kannadaPrefix => switch (this) {
    depart          => 'ಪ್ರಾರಂಭಿಸಿ',
    destination     => 'ತಲುಪಿದ್ದೀರಿ',
    continueStr     => 'ಮುಂದೆ ಹೋಗಿ',
    straight        => 'ನೇರವಾಗಿ ಮುಂದೆ',
    slightRight     => 'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ',
    right           => 'ಬಲಕ್ಕೆ ತಿರುಗಿ',
    sharpRight      => 'ಚೂಪಾಗಿ ಬಲಕ್ಕೆ',
    uTurnRight      => 'U-ತಿರುವು ಬಲಕ್ಕೆ',
    uTurnLeft       => 'U-ತಿರುವು ಎಡಕ್ಕೆ',
    sharpLeft       => 'ಚೂಪಾಗಿ ಎಡಕ್ಕೆ',
    left            => 'ಎಡಕ್ಕೆ ತಿರುಗಿ',
    slightLeft      => 'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ',
    rampRight       => 'ರ‍್ಯಾಂಪ್ ಬಲಕ್ಕೆ',
    rampLeft        => 'ರ‍್ಯಾಂಪ್ ಎಡಕ್ಕೆ',
    roundaboutEnter => 'ರೌಂಡ್‌ಅಬೌಟ್ ಒಳಗೆ',
    roundaboutExit  => 'ರೌಂಡ್‌ಅಬೌಟ್ ಹೊರಗೆ',
    merge           => 'ವಿಲೀನಗೊಳ್ಳಿ',
    ferryEnter      => 'ಫೆರಿ ಹತ್ತಿ',
    ferryExit       => 'ಫೆರಿ ಇಳಿಯಿರಿ',
    _               => 'ಮುಂದೆ',
  };

  bool get isArrival   => this == destination;
  bool get isDeparture => this == depart;
}

// ── RouteStep (extended) ──────────────────────────────────────────────────────
class RouteStep {
  final String       instruction;
  final String       instructionKn;
  final int          durationSec;
  final int          distanceM;
  final String       action;
  final ManeuverType maneuverType;
  final int          polylineStartIndex;
  final int          polylineEndIndex;
  final String?      streetName;

  const RouteStep({
    required this.instruction,
    required this.instructionKn,
    required this.durationSec,
    required this.distanceM,
    required this.action,
    required this.maneuverType,
    required this.polylineStartIndex,
    required this.polylineEndIndex,
    this.streetName,
  });

  // Backward-compat factory
  factory RouteStep.simple({
    required String instruction,
    required int    durationSec,
    required int    distanceM,
    required String action,
  }) => RouteStep(
    instruction:        instruction,
    instructionKn:      ManeuverType.unknown.kannadaPrefix,
    durationSec:        durationSec,
    distanceM:          distanceM,
    action:             action,
    maneuverType:       ManeuverType.unknown,
    polylineStartIndex: 0,
    polylineEndIndex:   0,
  );

  // Factory from Valhalla maneuver JSON
  factory RouteStep.fromValhallaManeuver(
    Map<String, dynamic> m,
    int polylineLength,
  ) {
    final typeInt  = (m['type']             as num?)?.toInt() ?? 0;
    final beginIdx = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
    final endIdx   = (m['end_shape_index']   as num?)?.toInt() ?? (polylineLength - 1);
    final instrEn  = m['instruction'] as String? ?? _maneuverLabel(typeInt);
    final streetNames = m['street_names'] as List?;
    final streetName  = streetNames?.isNotEmpty == true
        ? streetNames!.first.toString() : null;
    final mt = ManeuverType.fromValhallaType(typeInt);
    final instrKn = streetName != null && streetName.isNotEmpty
        ? '${mt.kannadaPrefix} $streetName ಗೆ'
        : mt.kannadaPrefix;

    return RouteStep(
      instruction:        instrEn,
      instructionKn:      instrKn,
      durationSec:        (m['time']   as num?)?.toInt() ?? 0,
      distanceM:          ((m['length'] as num?)?.toDouble() ?? 0.0) * 1000 ~/ 1,
      action:             _maneuverLabel(typeInt),
      maneuverType:       mt,
      polylineStartIndex: beginIdx.clamp(0, polylineLength - 1),
      polylineEndIndex:   endIdx.clamp(0, polylineLength - 1),
      streetName:         streetName,
    );
  }

  String get distanceText {
    if (distanceM <= 0) return '';
    if (distanceM < 1000) return '${distanceM} m';
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }

  static String _maneuverLabel(int type) => switch (type) {
    0  => 'depart',    4  => 'destination', 8  => 'continue',
    9  => 'slight_right', 10 => 'right',   11 => 'sharp_right',
    12 => 'u_turn_right', 13 => 'u_turn_left', 14 => 'sharp_left',
    15 => 'left',    16 => 'slight_left',
    26 => 'roundabout_enter', 27 => 'roundabout_exit',
    _  => 'continue',
  };
}

// ── RouteResult ───────────────────────────────────────────────────────────────
class RouteResult {
  final List<LatLng>    polyline;
  final int             durationSec;
  final int             distanceM;
  final List<RouteStep> steps;
  final DateTime        calculatedAt;
  final String          routingEngine;
  // Precomputed cumulative distances (metres). cumulativeDistances[i] = total
  // road length from polyline[0] to polyline[i]. Enables O(log n) step search.
  final List<double>    cumulativeDistances;

  // ── V400 fields ────────────────────────────────────────────────────────────
  /// Monotonically increasing version. Used to discard stale async reroute
  /// responses. A reroute response with version < current is ignored.
  final int             routeVersion;

  /// Cross-provider confidence score (0.0–1.0).
  /// 0.6 = single provider (no cross-validation).
  /// 0.9 = two providers agree within 20%.
  /// 0.95 = three providers agree.
  final double          confidence;

  /// Which provider produced this route: 'valhalla', 'osrm', 'openrouteservice'.
  final String          provider;

  const RouteResult({
    required this.polyline,
    required this.durationSec,
    required this.distanceM,
    required this.steps,
    required this.calculatedAt,
    this.routingEngine = 'valhalla',
    this.cumulativeDistances = const [],
    this.routeVersion = 0,
    this.confidence = 0.6,
    this.provider = 'unknown',
  });

  factory RouteResult.withCumulativeDistances({
    required List<LatLng>    polyline,
    required int             durationSec,
    required int             distanceM,
    required List<RouteStep> steps,
    required DateTime        calculatedAt,
    String                   routingEngine = 'valhalla',
    int                      routeVersion = 0,
    double                   confidence = 0.6,
    String                   provider = 'unknown',
  }) {
    final cum = buildCumDist(polyline);
    return RouteResult(
      polyline:            polyline,
      durationSec:         durationSec,
      distanceM:           distanceM,
      steps:               steps,
      calculatedAt:        calculatedAt,
      routingEngine:       routingEngine,
      cumulativeDistances: cum,
      routeVersion:        routeVersion,
      confidence:          confidence,
      provider:            provider,
    );
  }

  static List<double> buildCumDist(List<LatLng> pts) {
    if (pts.isEmpty) return [];
    final cum = List<double>.filled(pts.length, 0.0);
    const d = Distance();
    for (int i = 1; i < pts.length; i++) {
      cum[i] = cum[i - 1] + d.as(LengthUnit.Meter, pts[i - 1], pts[i]);
    }
    return cum;
  }

  // ── Display helpers ───────────────────────────────────────────────────────
  String get etaText {
    if (durationSec <= 0) return '—';
    final m = durationSec ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60; final rm = m % 60;
    return rm == 0 ? '${h}h' : '${h}h ${rm}m';
  }

  String get distanceText {
    if (distanceM <= 0) return '—';
    if (distanceM < 1000) return '${distanceM}m';
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }

  String get arrivalTimeText {
    if (durationSec <= 0) return '—';
    final eta = DateTime.now().add(Duration(seconds: durationSec));
    final h   = eta.hour;
    final m   = eta.minute.toString().padLeft(2, '0');
    final ap  = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $ap';
  }

  bool   get isStale             => DateTime.now().difference(calculatedAt).inMinutes >= 10;
  double get totalPolylineLength => cumulativeDistances.isNotEmpty ? cumulativeDistances.last : distanceM.toDouble();

  // ── Valhalla JSON parser (Phase 1 updated) ────────────────────────────────
  static RouteResult? fromValhallaJson(Map<String, dynamic> json) {
    try {
      final trip = json['trip'] as Map<String, dynamic>?;
      if (trip == null) return null;
      if ((trip['status'] as int? ?? -1) != 0) return null;

      final summary     = trip['summary'] as Map<String, dynamic>?;
      final durationSec = (summary?['time']   as num?)?.toInt()    ?? 0;
      final distanceM   = ((summary?['length'] as num?)?.toDouble() ?? 0.0) * 1000 ~/ 1;

      final legs  = trip['legs'] as List?;
      final leg0  = legs?.isNotEmpty == true ? legs![0] as Map<String, dynamic>? : null;
      final shape = leg0?['shape'] as String? ?? '';
      final polyline = ValhallaPolyline6.decode(shape);
      if (polyline.isEmpty) return null;

      final rawManeuvers = leg0?['maneuvers'] as List? ?? [];
      final steps = rawManeuvers
          .whereType<Map<String, dynamic>>()
          .map((m) => RouteStep.fromValhallaManeuver(m, polyline.length))
          .toList();

      return RouteResult.withCumulativeDistances(
        polyline:      polyline,
        durationSec:   durationSec,
        distanceM:     distanceM,
        steps:         steps,
        calculatedAt:  DateTime.now(),
        routingEngine: 'valhalla',
      );
    } catch (_) { return null; }
  }

  // ── HERE Flexible Polyline parser (fallback) ──────────────────────────────
  static RouteResult? fromHereJson(Map<String, dynamic> json) {
    try {
      final routes   = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final section  = (routes[0] as Map<String, dynamic>)['sections'] as List?;
      if (section == null || section.isEmpty) return null;
      final sec0     = section[0] as Map<String, dynamic>;
      final summary  = sec0['summary'] as Map<String, dynamic>?;
      final durSec   = (summary?['duration'] as num?)?.toInt() ?? 0;
      final distM    = (summary?['length']   as num?)?.toInt() ?? 0;
      final polyline = HereFlexiblePolyline.decode(sec0['polyline'] as String? ?? '');
      return RouteResult.withCumulativeDistances(
        polyline:      polyline,
        durationSec:   durSec,
        distanceM:     distM,
        steps:         const [],
        calculatedAt:  DateTime.now(),
        routingEngine: 'here',
      );
    } catch (_) { return null; }
  }
}

// ── ValhallaPolyline6 decoder ─────────────────────────────────────────────────
class ValhallaPolyline6 {
  ValhallaPolyline6._();
  static const double _factor = 1e6;

  static List<LatLng> decode(String encoded) {
    if (encoded.isEmpty) return const [];
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift; shift += 5;
      } while (b >= 0x20);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      if (index >= encoded.length) break;
      shift = 0; res = 0;
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift; shift += 5;
      } while (b >= 0x20);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / _factor, lng / _factor));
    }
    return result;
  }
}

// ── HERE Flexible Polyline decoder ────────────────────────────────────────────
class HereFlexiblePolyline {
  HereFlexiblePolyline._();
  static const _enc =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static List<LatLng> decode(String encoded) {
    if (encoded.isEmpty) return const [];
    int pos = 0;
    int decodeUint() {
      int result = 0, shift = 0, delta;
      do {
        if (pos >= encoded.length) break;
        delta   = _enc.indexOf(encoded[pos++]);
        if (delta < 0) break;
        result |= (delta & 0x1F) << shift; shift += 5;
      } while (delta >= 0x20);
      return result;
    }
    int decodeSigned() { final v = decodeUint(); return (v & 1) != 0 ? ~v >> 1 : v >> 1; }
    final header = decodeUint();
    if ((header & 0xF) != 1) return const [];
    final precision    = (header >> 7) & 0xF;
    final thirdDimType = (header >> 11) & 0x7;
    final factor       = math.pow(10, precision).toDouble();
    final result = <LatLng>[];
    double lat = 0, lng = 0;
    while (pos < encoded.length) {
      lat += decodeSigned() / factor;
      if (pos >= encoded.length) break;
      lng += decodeSigned() / factor;
      if (thirdDimType > 0 && pos < encoded.length) decodeSigned();
      result.add(LatLng(lat, lng));
    }
    return result;
  }
}
// ── Polyline5 decoder (OSRM / Google standard) ───────────────────────────────
// V400: Consolidated from 3 duplicate copies in valhalla_service.dart,
// route_diagnostics_service.dart, and inline lambdas. Single source of truth.
class Polyline5Decoder {
  Polyline5Decoder._();

  /// Decodes a standard precision-5 polyline (Google / OSRM format).
  static List<LatLng> decode(String encoded) {
    if (encoded.isEmpty) return const [];
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      if (index >= encoded.length) break;
      shift = 0; res = 0;
      do {
        if (index >= encoded.length) break;
        b    = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}

// ── Backward-compat extension ─────────────────────────────────────────────────
extension RouteResultValhalla on RouteResult {
  static RouteResult? fromValhallaJson(Map<String, dynamic> json) =>
      RouteResult.fromValhallaJson(json);
}
