// lib/models/canonical_route.dart
// Kelasagara Navigation V2 — Canonical Route & Maneuver Model.
// Normalizes raw Valhalla / routing engine outputs into strict canonical data contracts.
// Raw router JSON MUST NOT reach UI.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'route_result.dart';

/// Normalized Canonical Maneuver conforming to Part 13 contract.
@immutable
class CanonicalManeuver {
  final String maneuverId;
  final int routeVersion;
  final String type;
  final String instruction;
  final String verbalInstruction;
  final String? roadName;
  final double distanceToManeuver;
  final int durationToManeuver;
  final LatLng beginCoordinate;
  final LatLng endCoordinate;
  final double? bearingBefore;
  final double? bearingAfter;
  final String? exitNumber;

  const CanonicalManeuver({
    required this.maneuverId,
    required this.routeVersion,
    required this.type,
    required this.instruction,
    required this.verbalInstruction,
    this.roadName,
    required this.distanceToManeuver,
    required this.durationToManeuver,
    required this.beginCoordinate,
    required this.endCoordinate,
    this.bearingBefore,
    this.bearingAfter,
    this.exitNumber,
  });

  factory CanonicalManeuver.fromRouteStep(
    RouteStep step, {
    required int routeVersion,
    required int index,
    required List<LatLng> fullPolyline,
  }) {
    final startIdx = step.polylineStartIndex.clamp(0, fullPolyline.isEmpty ? 0 : fullPolyline.length - 1);
    final endIdx = step.polylineEndIndex.clamp(0, fullPolyline.isEmpty ? 0 : fullPolyline.length - 1);

    final begin = fullPolyline.isNotEmpty ? fullPolyline[startIdx] : const LatLng(0, 0);
    final end = fullPolyline.isNotEmpty ? fullPolyline[endIdx] : const LatLng(0, 0);

    return CanonicalManeuver(
      maneuverId: 'maneuver_${routeVersion}_$index',
      routeVersion: routeVersion,
      type: step.maneuverType.name,
      instruction: step.instruction,
      verbalInstruction: step.instructionKn.isNotEmpty ? step.instructionKn : step.instruction,
      roadName: step.streetName,
      distanceToManeuver: step.distanceM.toDouble(),
      durationToManeuver: step.durationSec,
      beginCoordinate: begin,
      endCoordinate: end,
      bearingBefore: null,
      bearingAfter: null,
      exitNumber: null,
    );
  }

  Map<String, dynamic> toMap() => {
    'maneuverId': maneuverId,
    'routeVersion': routeVersion,
    'type': type,
    'instruction': instruction,
    'verbalInstruction': verbalInstruction,
    if (roadName != null) 'roadName': roadName,
    'distanceToManeuver': distanceToManeuver,
    'durationToManeuver': durationToManeuver,
    'beginCoordinate': {'lat': beginCoordinate.latitude, 'lng': beginCoordinate.longitude},
    'endCoordinate': {'lat': endCoordinate.latitude, 'lng': endCoordinate.longitude},
    if (bearingBefore != null) 'bearingBefore': bearingBefore,
    if (bearingAfter != null) 'bearingAfter': bearingAfter,
    if (exitNumber != null) 'exitNumber': exitNumber,
  };
}

/// Normalized Canonical Route conforming to Part 12 contract.
@immutable
class CanonicalRoute {
  final String routeId;
  final String bookingId;
  final String navigationSessionId;
  final int routeVersion;
  final String provider;
  final LatLng origin;
  final LatLng destination;
  final double distanceMeters;
  final int durationSeconds;
  final List<LatLng> geometry;
  final List<Map<String, dynamic>> legs;
  final List<CanonicalManeuver> maneuvers;
  final DateTime calculatedAt;
  final List<String> warnings;

  const CanonicalRoute({
    required this.routeId,
    required this.bookingId,
    required this.navigationSessionId,
    required this.routeVersion,
    required this.provider,
    required this.origin,
    required this.destination,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.geometry,
    required this.legs,
    required this.maneuvers,
    required this.calculatedAt,
    this.warnings = const [],
  });

  /// Factory creating CanonicalRoute from RouteResult
  factory CanonicalRoute.fromRouteResult(
    RouteResult result, {
    required String bookingId,
    required String sessionId,
    required int routeVersion,
  }) {
    final maneuversList = <CanonicalManeuver>[];
    for (int i = 0; i < result.steps.length; i++) {
      maneuversList.add(CanonicalManeuver.fromRouteStep(
        result.steps[i],
        routeVersion: routeVersion,
        index: i,
        fullPolyline: result.polyline,
      ));
    }

    return CanonicalRoute(
      routeId: 'route_${sessionId}_v$routeVersion',
      bookingId: bookingId,
      navigationSessionId: sessionId,
      routeVersion: routeVersion,
      provider: result.provider,
      origin: result.polyline.isNotEmpty ? result.polyline.first : const LatLng(0, 0),
      destination: result.polyline.isNotEmpty ? result.polyline.last : const LatLng(0, 0),
      distanceMeters: result.distanceM.toDouble(),
      durationSeconds: result.durationSec,
      geometry: List.unmodifiable(result.polyline),
      legs: [
        {
          'distance': result.distanceM,
          'duration': result.durationSec,
          'stepsCount': result.steps.length,
        }
      ],
      maneuvers: List.unmodifiable(maneuversList),
      calculatedAt: DateTime.now(),
      warnings: const [],
    );
  }

  Map<String, dynamic> toMap() => {
    'routeId': routeId,
    'bookingId': bookingId,
    'navigationSessionId': navigationSessionId,
    'routeVersion': routeVersion,
    'provider': provider,
    'origin': {'lat': origin.latitude, 'lng': origin.longitude},
    'destination': {'lat': destination.latitude, 'lng': destination.longitude},
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'geometry': geometry.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'legs': legs,
    'maneuvers': maneuvers.map((m) => m.toMap()).toList(),
    'calculatedAt': calculatedAt.toIso8601String(),
    'warnings': warnings,
  };
}
