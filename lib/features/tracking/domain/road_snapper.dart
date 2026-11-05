// lib/features/tracking/domain/road_snapper.dart
// Production-grade Tier-1 road snapping, Kalman GPS smoothing, and polyline-crawl interpolation.
// Solves 90° corner cutting, parallel service road jumping, and urban canyon jitter.

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class SnapResult {
  final LatLng snappedPoint;
  final int segmentIndex;
  final double segmentFraction;
  final double crossTrackErrorMeters;
  final double roadBearing;
  final bool isSnapped;
  final bool isOffRoute;
  final double remainingRoadDistanceMeters;
  final List<LatLng> remainingPolyline;
  final List<LatLng> traversedPolyline;

  const SnapResult({
    required this.snappedPoint,
    required this.segmentIndex,
    required this.segmentFraction,
    required this.crossTrackErrorMeters,
    required this.roadBearing,
    required this.isSnapped,
    required this.isOffRoute,
    required this.remainingRoadDistanceMeters,
    required this.remainingPolyline,
    required this.traversedPolyline,
  });
}

class TrajectoryPose {
  final LatLng position;
  final double bearing;

  const TrajectoryPose({
    required this.position,
    required this.bearing,
  });
}

/// Lightweight 2D Kinematic Kalman Filter for GPS stabilization in urban canyons.
class KalmanLatLngFilter {
  final double _processNoiseMetersPerSec;
  double _lat = 0.0;
  double _lng = 0.0;
  double _variance = -1.0; // Negative indicates uninitialized
  int _lastTimestampMs = 0;

  KalmanLatLngFilter({double processNoiseMetersPerSec = 3.0})
      : _processNoiseMetersPerSec = processNoiseMetersPerSec;

  void reset() {
    _variance = -1.0;
    _lastTimestampMs = 0;
  }

  LatLng process({
    required double lat,
    required double lng,
    required double accuracyMeters,
    required int timestampMs,
    double speedMps = 0.0,
  }) {
    final effectiveAccuracy = math.max(accuracyMeters, 2.5);

    if (_variance < 0) {
      _lat = lat;
      _lng = lng;
      _variance = effectiveAccuracy * effectiveAccuracy;
      _lastTimestampMs = timestampMs;
      return LatLng(_lat, _lng);
    }

    final dtSeconds =
        math.max(0, timestampMs - _lastTimestampMs) / 1000.0;
    if (dtSeconds > 0) {
      final dynamicQ = math.max(_processNoiseMetersPerSec, speedMps * 0.65);
      _variance += dtSeconds * dynamicQ * dynamicQ;
      _lastTimestampMs = timestampMs;
    }

    final kGain =
        _variance / (_variance + effectiveAccuracy * effectiveAccuracy);
    _lat += kGain * (lat - _lat);
    _lng += kGain * (lng - _lng);
    _variance = (1.0 - kGain) * _variance;

    return LatLng(_lat, _lng);
  }
}

class RoadSnapper {
  static const double _earthRadiusMeters = 6371000.0;
  static const double defaultSnapThresholdMeters = 35.0;
  static const double defaultOffRouteThresholdMeters = 45.0;

  /// Fast equirectangular distance approximation (accurate within 0.1% under 50km).
  static double fastDistanceMeters(LatLng a, LatLng b) {
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final meanLat = _degToRad((a.latitude + b.latitude) * 0.5);
    final x = dLng * math.cos(meanLat);
    final y = dLat;
    return math.sqrt(x * x + y * y) * _earthRadiusMeters;
  }

  /// Backward-compatible alias for fastDistanceMeters.
  static double haversineDistanceMeters(LatLng a, LatLng b) =>
      fastDistanceMeters(a, b);

  /// Calculates forward azimuth bearing in degrees [0, 360) from [start] to [end].
  static double calculateBearing(LatLng start, LatLng end) {
    if (start.latitude == end.latitude && start.longitude == end.longitude) {
      return 0.0;
    }
    final lat1 = _degToRad(start.latitude);
    final lat2 = _degToRad(end.latitude);
    final dLng = _degToRad(end.longitude - start.longitude);

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final theta = math.atan2(y, x);
    return (_radToDeg(theta) + 360.0) % 360.0;
  }

  /// Shortest-arc angular interpolation preventing 359° -> 1° full-circle spins.
  static double lerpBearing(double startDeg, double endDeg, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final s = ((startDeg % 360.0) + 360.0) % 360.0;
    final e = ((endDeg % 360.0) + 360.0) % 360.0;
    double delta = ((e - s + 540.0) % 360.0) - 180.0;
    return ((s + delta * clampedT) % 360.0 + 360.0) % 360.0;
  }

  /// Absolute shortest angular difference in [0, 180].
  static double angularDifference(double aDeg, double bDeg) {
    final diff = ((aDeg - bDeg).abs()) % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  /// Projects point [p] orthogonally onto line segment [a]->[b].
  /// Returns `(point: projectedPoint, fraction: fractionT [0..1], distanceMeters: dist)`.
  static ({LatLng point, double fraction, double distanceMeters})
      projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    final meanLatRad = _degToRad((a.latitude + b.latitude + p.latitude) / 3.0);
    final cosLat = math.cos(meanLatRad);

    final ax = a.longitude * cosLat;
    final ay = a.latitude;
    final bx = b.longitude * cosLat;
    final by = b.latitude;
    final px = p.longitude * cosLat;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;

    double t = 0.0;
    if (lenSq > 1e-16) {
      t = (((px - ax) * dx + (py - ay) * dy) / lenSq).clamp(0.0, 1.0);
    }

    final projLng = a.longitude + t * (b.longitude - a.longitude);
    final projLat = a.latitude + t * (b.latitude - a.latitude);
    final projected = LatLng(projLat, projLng);
    final dist = fastDistanceMeters(p, projected);

    return (point: projected, fraction: t, distanceMeters: dist);
  }

  /// Elastic Hybrid Map Matching designed for workers navigating via external Google Maps.
  /// - Soft-snaps ONLY when within [snapThresholdMeters] (22m) AND heading aligns within 40°.
  /// - If the worker takes a Google Maps traffic shortcut, cleanly releases the snap lock
  ///   and tracks the real Kalman-filtered GPS trajectory without jumping sideways.
  static SnapResult snapToPolyline({
    required LatLng rawPoint,
    required List<LatLng> polyline,
    double? gpsHeading,
    double speedMps = 0.0,
    int? previousSegmentIndex,
    bool isExactGoogleRoute = false,
    double? customSnapThresholdMeters,
    double offRouteThresholdMeters = 55.0,
    double? snapThresholdMeters,
  }) {
    // Use tighter 22m snap when using a non-Google fallback route so we never pull
    // a worker off their real Google Maps shortcut onto an outdated main road.
    final effectiveSnapThresholdMeters = customSnapThresholdMeters ??
        snapThresholdMeters ??
        (isExactGoogleRoute ? 32.0 : 22.0);

    if (polyline.length < 2) {
      return SnapResult(
        snappedPoint: rawPoint,
        segmentIndex: 0,
        segmentFraction: 0.0,
        crossTrackErrorMeters: 0.0,
        roadBearing: gpsHeading ?? 0.0,
        isSnapped: false,
        isOffRoute: false,
        remainingRoadDistanceMeters:
            polyline.isNotEmpty ? fastDistanceMeters(rawPoint, polyline.last) : 0.0,
        remainingPolyline: [rawPoint, ...polyline],
        traversedPolyline: [rawPoint],
      );
    }

    int bestSegmentIdx = 0;
    double bestFraction = 0.0;
    LatLng bestPoint = rawPoint;
    double bestRawDistance = double.infinity;
    double bestCompositeScore = double.infinity;
    double bestRoadBearing = gpsHeading ?? 0.0;
    double bestHeadingDiff = 0.0;

    final hasReliableHeading = gpsHeading != null && speedMps >= 1.2;

    for (int i = 0; i < polyline.length - 1; i++) {
      final segStart = polyline[i];
      final segEnd = polyline[i + 1];
      final proj = projectOntoSegment(rawPoint, segStart, segEnd);
      final segBearing = calculateBearing(segStart, segEnd);

      double compositeScore = proj.distanceMeters;
      double angleDiff = 0.0;

      if (hasReliableHeading) {
        angleDiff = angularDifference(gpsHeading, segBearing);
        compositeScore += (angleDiff / 180.0) * 35.0;
      }

      if (previousSegmentIndex != null) {
        final indexDelta = i - previousSegmentIndex;
        if (indexDelta < -1) {
          compositeScore += indexDelta.abs() * 14.0;
        } else if (indexDelta > 15) {
          compositeScore += (indexDelta - 15) * 3.0;
        }
      }

      if (compositeScore < bestCompositeScore) {
        bestCompositeScore = compositeScore;
        bestRawDistance = proj.distanceMeters;
        bestSegmentIdx = i;
        bestFraction = proj.fraction;
        bestPoint = proj.point;
        bestRoadBearing = segBearing;
        bestHeadingDiff = angleDiff;
      }
    }

    // Elastic Gate: Only snap if close to the line AND not turning away onto a Google Maps shortcut
    final headingAligned = !hasReliableHeading || bestHeadingDiff <= 42.0;
    final isSnapped =
        bestRawDistance <= effectiveSnapThresholdMeters && headingAligned;
    final isOffRoute = bestRawDistance > offRouteThresholdMeters;

    // In Free-Follow mode (worker on Google Maps shortcut), use exact Kalman GPS position & heading
    final effectivePoint = isSnapped ? bestPoint : rawPoint;
    final effectiveBearing = isSnapped
        ? bestRoadBearing
        : (gpsHeading ?? bestRoadBearing);

    final remaining = <LatLng>[effectivePoint];
    double remainingMeters = 0.0;

    if (isSnapped) {
      final firstHopEnd = polyline[bestSegmentIdx + 1];
      remainingMeters += fastDistanceMeters(effectivePoint, firstHopEnd);
      remaining.add(firstHopEnd);

      for (int i = bestSegmentIdx + 1; i < polyline.length - 1; i++) {
        remainingMeters += fastDistanceMeters(polyline[i], polyline[i + 1]);
        remaining.add(polyline[i + 1]);
      }
    } else {
      // Worker is on a Google Maps shortcut: connect their live position smoothly
      // to the ahead route vertex and calculate realistic urban road distance (1.22x straight-line)
      final rejoinIdx =
          (bestSegmentIdx + 2).clamp(0, polyline.length - 1);
      remainingMeters =
          fastDistanceMeters(rawPoint, polyline.last) * 1.22;
      remaining.addAll(polyline.sublist(rejoinIdx));
    }

    final traversed = <LatLng>[
      ...polyline.sublist(0, bestSegmentIdx + 1),
      effectivePoint,
    ];

    return SnapResult(
      snappedPoint: effectivePoint,
      segmentIndex: bestSegmentIdx,
      segmentFraction: bestFraction,
      crossTrackErrorMeters: bestRawDistance,
      roadBearing: effectiveBearing,
      isSnapped: isSnapped,
      isOffRoute: isOffRoute,
      remainingRoadDistanceMeters: remainingMeters,
      remainingPolyline: remaining,
      traversedPolyline: traversed,
    );
  }

  /// Extracts the exact road sub-path between two points so animations crawl along corners
  /// instead of cutting straight across buildings.
  static List<LatLng> extractSubPath({
    required List<LatLng> polyline,
    required LatLng fromPoint,
    required LatLng toPoint,
  }) {
    if (polyline.length < 2) return [fromPoint, toPoint];

    final startSnap = snapToPolyline(rawPoint: fromPoint, polyline: polyline);
    final endSnap = snapToPolyline(
      rawPoint: toPoint,
      polyline: polyline,
      previousSegmentIndex: startSnap.segmentIndex,
    );

    if (!startSnap.isSnapped ||
        !endSnap.isSnapped ||
        endSnap.segmentIndex < startSnap.segmentIndex ||
        (endSnap.segmentIndex == startSnap.segmentIndex &&
            endSnap.segmentFraction <= startSnap.segmentFraction)) {
      return [fromPoint, toPoint];
    }

    final path = <LatLng>[startSnap.snappedPoint];
    for (int i = startSnap.segmentIndex + 1; i <= endSnap.segmentIndex; i++) {
      path.add(polyline[i]);
    }
    path.add(endSnap.snappedPoint);
    return path;
  }

  /// Interpolates position and road-tangent bearing along a multi-vertex sub-path at progress `t` in [0, 1].
  static TrajectoryPose interpolateAlongPath({
    required List<LatLng> path,
    required double t,
    required double fallbackStartBearing,
    required double fallbackEndBearing,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    if (path.isEmpty) {
      return TrajectoryPose(
        position: const LatLng(0, 0),
        bearing: fallbackEndBearing,
      );
    }
    if (path.length == 1) {
      return TrajectoryPose(
        position: path.first,
        bearing: lerpBearing(fallbackStartBearing, fallbackEndBearing, clampedT),
      );
    }

    final segmentLengths = <double>[];
    double totalLength = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      final len = fastDistanceMeters(path[i], path[i + 1]);
      segmentLengths.add(len);
      totalLength += len;
    }

    if (totalLength < 0.25) {
      return TrajectoryPose(
        position: path.last,
        bearing: lerpBearing(fallbackStartBearing, fallbackEndBearing, clampedT),
      );
    }

    final targetDist = totalLength * clampedT;
    double accumulated = 0.0;

    for (int i = 0; i < segmentLengths.length; i++) {
      final segLen = segmentLengths[i];
      if (accumulated + segLen >= targetDist || i == segmentLengths.length - 1) {
        final localT =
            segLen > 1e-6 ? ((targetDist - accumulated) / segLen).clamp(0.0, 1.0) : 1.0;
        final a = path[i];
        final b = path[i + 1];
        final pos = LatLng(
          a.latitude + (b.latitude - a.latitude) * localT,
          a.longitude + (b.longitude - a.longitude) * localT,
        );
        final segBearing =
            segLen > 0.3 ? calculateBearing(a, b) : fallbackEndBearing;
        return TrajectoryPose(
          position: pos,
          bearing: lerpBearing(fallbackStartBearing, segBearing, clampedT),
        );
      }
      accumulated += segLen;
    }

    return TrajectoryPose(
      position: path.last,
      bearing: fallbackEndBearing,
    );
  }

  /// Dead-reckoning extrapolation forward along the remaining polyline when GPS is temporarily delayed.
  static TrajectoryPose extrapolateAlongPolyline({
    required List<LatLng> remainingPolyline,
    required double distanceToAdvanceMeters,
    required double currentBearing,
  }) {
    if (remainingPolyline.isEmpty) {
      return TrajectoryPose(
        position: const LatLng(0, 0),
        bearing: currentBearing,
      );
    }
    if (remainingPolyline.length == 1 || distanceToAdvanceMeters <= 0.1) {
      return TrajectoryPose(
        position: remainingPolyline.first,
        bearing: currentBearing,
      );
    }

    double remainingAdvance = distanceToAdvanceMeters;
    for (int i = 0; i < remainingPolyline.length - 1; i++) {
      final a = remainingPolyline[i];
      final b = remainingPolyline[i + 1];
      final segLen = fastDistanceMeters(a, b);
      if (segLen >= remainingAdvance && segLen > 1e-6) {
        final frac = (remainingAdvance / segLen).clamp(0.0, 1.0);
        final pos = LatLng(
          a.latitude + (b.latitude - a.latitude) * frac,
          a.longitude + (b.longitude - a.longitude) * frac,
        );
        return TrajectoryPose(
          position: pos,
          bearing: calculateBearing(a, b),
        );
      }
      remainingAdvance -= segLen;
    }

    return TrajectoryPose(
      position: remainingPolyline.last,
      bearing: currentBearing,
    );
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
