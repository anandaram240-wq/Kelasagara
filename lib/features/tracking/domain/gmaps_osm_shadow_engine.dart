// lib/features/tracking/domain/gmaps_osm_shadow_engine.dart
// Production-grade Dual-Mode Shadow Tracking, Cubic Hermite Spline Interpolation,
// Elastic Polyline Bridging, and Douglas-Peucker simplification for external Google Maps navigation.

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'road_snapper.dart';

enum TrackingGlideMode {
  /// Worker is on the Valhalla/OSM road polyline (within 22m & aligned within 38°).
  osmRoadLocked,

  /// Worker took a Google Maps shortcut/detour not on the current Valhalla polyline.
  /// Marker glides along their real kinematic spline with an elastic bridge to the route.
  googleShortcutGlide,
}

class ShadowMatchResult {
  final TrackingGlideMode mode;
  final LatLng effectivePosition;
  final double effectiveBearing;
  final int closestSegmentIndex;
  final double crossTrackErrorMeters;
  final bool shouldTriggerShadowReroute;
  final double remainingRoadDistanceMeters;

  /// The active ahead route line (automatically bridged to the worker's live icon
  /// even when the worker is on a Google Maps shortcut).
  final List<LatLng> activeRoutePolyline;

  /// The simplified breadcrumb path the worker has actually driven.
  final List<LatLng> traversedBreadcrumbPolyline;

  const ShadowMatchResult({
    required this.mode,
    required this.effectivePosition,
    required this.effectiveBearing,
    required this.closestSegmentIndex,
    required this.crossTrackErrorMeters,
    required this.shouldTriggerShadowReroute,
    required this.remainingRoadDistanceMeters,
    required this.activeRoutePolyline,
    required this.traversedBreadcrumbPolyline,
  });
}

/// Evaluates how the Worker's Google Maps trajectory maps onto the Hirer's OSM/Valhalla canvas.
class GmapsOsmShadowEngine {
  static const double lockThresholdMeters = 22.0;
  static const double unlockHysteresisMeters = 28.0;
  static const double shadowRerouteThresholdMeters = 32.0;
  static const double maxHeadingDivergenceDeg = 38.0;

  TrackingGlideMode _currentMode = TrackingGlideMode.osmRoadLocked;
  int? _lastSegmentIndex;
  int _offRouteConsecutiveStrikes = 0;
  final List<LatLng> _recordedBreadcrumbs = <LatLng>[];

  void reset() {
    _currentMode = TrackingGlideMode.osmRoadLocked;
    _lastSegmentIndex = null;
    _offRouteConsecutiveStrikes = 0;
    _recordedBreadcrumbs.clear();
  }

  ShadowMatchResult processWorkerFix({
    required LatLng kalmanPosition,
    required double gpsHeading,
    required double speedMps,
    required List<LatLng> valhallaPolyline,
    required LatLng destination,
    List<LatLng> recentWorkerMicroTrail = const [],
  }) {
    // 1. Append to real driven breadcrumb history & simplify via Douglas-Peucker if large
    _appendBreadcrumb(kalmanPosition, recentWorkerMicroTrail);

    if (valhallaPolyline.length < 2) {
      final directDist =
          RoadSnapper.fastDistanceMeters(kalmanPosition, destination) * 1.25;
      return ShadowMatchResult(
        mode: TrackingGlideMode.googleShortcutGlide,
        effectivePosition: kalmanPosition,
        effectiveBearing: gpsHeading,
        closestSegmentIndex: 0,
        crossTrackErrorMeters: 0.0,
        shouldTriggerShadowReroute: true,
        remainingRoadDistanceMeters: directDist,
        activeRoutePolyline: <LatLng>[kalmanPosition, destination],
        traversedBreadcrumbPolyline: List<LatLng>.unmodifiable(_recordedBreadcrumbs),
      );
    }

    // 2. Run Heading-Aware Map Matcher against current Valhalla/OSM polyline
    final snap = RoadSnapper.snapToPolyline(
      rawPoint: kalmanPosition,
      polyline: valhallaPolyline,
      gpsHeading: gpsHeading,
      speedMps: speedMps,
      previousSegmentIndex: _lastSegmentIndex,
      snapThresholdMeters: _currentMode == TrackingGlideMode.osmRoadLocked
          ? unlockHysteresisMeters
          : lockThresholdMeters,
      offRouteThresholdMeters: shadowRerouteThresholdMeters,
    );

    final segBearing = snap.roadBearing;
    final headingDiff = speedMps >= 1.2
        ? RoadSnapper.angularDifference(gpsHeading, segBearing)
        : 0.0;

    // 3. Determine whether worker is locked to Valhalla road or gliding on a Google Maps shortcut
    final bool canLockToOsmRoad = snap.crossTrackErrorMeters <=
            (_currentMode == TrackingGlideMode.osmRoadLocked
                ? unlockHysteresisMeters
                : lockThresholdMeters) &&
        headingDiff <= maxHeadingDivergenceDeg;

    if (canLockToOsmRoad) {
      _currentMode = TrackingGlideMode.osmRoadLocked;
      _lastSegmentIndex = snap.segmentIndex;
      _offRouteConsecutiveStrikes = 0;

      return ShadowMatchResult(
        mode: TrackingGlideMode.osmRoadLocked,
        effectivePosition: snap.snappedPoint,
        effectiveBearing: snap.roadBearing,
        closestSegmentIndex: snap.segmentIndex,
        crossTrackErrorMeters: snap.crossTrackErrorMeters,
        shouldTriggerShadowReroute: false,
        remainingRoadDistanceMeters: snap.remainingRoadDistanceMeters,
        activeRoutePolyline: snap.remainingPolyline,
        traversedBreadcrumbPolyline: List<LatLng>.unmodifiable(_recordedBreadcrumbs),
      );
    }

    // 4. Worker is on a Google Maps Shortcut/Detour -> Enter Free-Glide Mode!
    _currentMode = TrackingGlideMode.googleShortcutGlide;
    if (snap.crossTrackErrorMeters > shadowRerouteThresholdMeters) {
      _offRouteConsecutiveStrikes++;
    }

    // Trigger a Heading-Biased Valhalla Shadow Reroute after 2 consecutive off-route fixes
    final shouldReroute = _offRouteConsecutiveStrikes >= 2;
    if (shouldReroute) {
      _offRouteConsecutiveStrikes = 0;
    }

    // 5. Build an Elastic Beveled Bridge connecting the worker's live position smoothly
    // to a look-ahead vertex on the Valhalla route so the green line NEVER detaches from the bike!
    final bridgedPolyline = _buildElasticShortcutBridge(
      workerPos: kalmanPosition,
      workerHeading: gpsHeading,
      valhallaPolyline: valhallaPolyline,
      nearestSegmentIdx: snap.segmentIndex,
    );

    final remainingMeters = _computePolylineLengthMeters(bridgedPolyline);

    return ShadowMatchResult(
      mode: TrackingGlideMode.googleShortcutGlide,
      effectivePosition: kalmanPosition,
      effectiveBearing: gpsHeading,
      closestSegmentIndex: snap.segmentIndex,
      crossTrackErrorMeters: snap.crossTrackErrorMeters,
      shouldTriggerShadowReroute: shouldReroute,
      remainingRoadDistanceMeters: remainingMeters,
      activeRoutePolyline: bridgedPolyline,
      traversedBreadcrumbPolyline: List<LatLng>.unmodifiable(_recordedBreadcrumbs),
    );
  }

  /// Synthesizes a smooth 4-point cubic bezier lead-in bridge from the worker's live
  /// off-route position back onto the ahead OSM polyline while waiting for Valhalla to reroute.
  List<LatLng> _buildElasticShortcutBridge({
    required LatLng workerPos,
    required double workerHeading,
    required List<LatLng> valhallaPolyline,
    required int nearestSegmentIdx,
  }) {
    // Pick an ahead merge vertex ~120 meters down the existing polyline
    int mergeIdx = (nearestSegmentIdx + 1).clamp(0, valhallaPolyline.length - 1);
    double accum = 0.0;
    while (mergeIdx < valhallaPolyline.length - 1 && accum < 120.0) {
      accum += RoadSnapper.fastDistanceMeters(
        valhallaPolyline[mergeIdx],
        valhallaPolyline[mergeIdx + 1],
      );
      mergeIdx++;
    }

    final targetVertex = valhallaPolyline[mergeIdx];
    final bridgeDist = RoadSnapper.fastDistanceMeters(workerPos, targetVertex);

    final bridged = <LatLng>[workerPos];

    if (bridgeDist > 12.0 && bridgeDist < 600.0) {
      // Project a control point 35% ahead along the worker's current heading vector
      final controlPoint = _projectCoordinate(
        origin: workerPos,
        bearingDeg: workerHeading,
        distanceMeters: bridgeDist * 0.35,
      );

      // Sample 3 smooth quadratic bezier steps between workerPos, controlPoint, and targetVertex
      for (int step = 1; step <= 3; step++) {
        final t = step / 4.0;
        final oneMinusT = 1.0 - t;
        final lat = (oneMinusT * oneMinusT * workerPos.latitude) +
            (2 * oneMinusT * t * controlPoint.latitude) +
            (t * t * targetVertex.latitude);
        final lng = (oneMinusT * oneMinusT * workerPos.longitude) +
            (2 * oneMinusT * t * controlPoint.longitude) +
            (t * t * targetVertex.longitude);
        bridged.add(LatLng(lat, lng));
      }
    }

    bridged.addAll(valhallaPolyline.sublist(mergeIdx));
    return bridged;
  }

  void _appendBreadcrumb(LatLng current, List<LatLng> microTrail) {
    for (final pt in microTrail) {
      if (_recordedBreadcrumbs.isEmpty ||
          RoadSnapper.fastDistanceMeters(_recordedBreadcrumbs.last, pt) >= 4.0) {
        _recordedBreadcrumbs.add(pt);
      }
    }
    if (_recordedBreadcrumbs.isEmpty ||
        RoadSnapper.fastDistanceMeters(_recordedBreadcrumbs.last, current) >=
            3.5) {
      _recordedBreadcrumbs.add(current);
    }

    // Compress breadcrumb history with Ramer-Douglas-Peucker when exceeding 250 points
    if (_recordedBreadcrumbs.length > 250) {
      final simplified = simplifyPolylineRdp(_recordedBreadcrumbs, epsilonMeters: 2.5);
      _recordedBreadcrumbs
        ..clear()
        ..addAll(simplified);
    }
  }

  static double _computePolylineLengthMeters(List<LatLng> pts) {
    double sum = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      sum += RoadSnapper.fastDistanceMeters(pts[i], pts[i + 1]);
    }
    return sum;
  }

  static LatLng _projectCoordinate({
    required LatLng origin,
    required double bearingDeg,
    required double distanceMeters,
  }) {
    const earthRadius = 6371000.0;
    final angDist = distanceMeters / earthRadius;
    final brng = bearingDeg * (math.pi / 180.0);
    final lat1 = origin.latitude * (math.pi / 180.0);
    final lng1 = origin.longitude * (math.pi / 180.0);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(brng),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(brng) * math.sin(angDist) * math.cos(lat1),
          math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(lat2 * (180.0 / math.pi), lng2 * (180.0 / math.pi));
  }

  /// Ramer-Douglas-Peucker polyline simplification to keep `flutter_map` at 60fps.
  static List<LatLng> simplifyPolylineRdp(
    List<LatLng> points, {
    double epsilonMeters = 2.5,
  }) {
    if (points.length < 3) return List<LatLng>.from(points);

    double maxDistance = 0.0;
    int index = 0;
    final end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final proj = RoadSnapper.projectOntoSegment(
        points[i],
        points.first,
        points.last,
      );
      if (proj.distanceMeters > maxDistance) {
        index = i;
        maxDistance = proj.distanceMeters;
      }
    }

    if (maxDistance > epsilonMeters) {
      final left = simplifyPolylineRdp(
        points.sublist(0, index + 1),
        epsilonMeters: epsilonMeters,
      );
      final right = simplifyPolylineRdp(
        points.sublist(index),
        epsilonMeters: epsilonMeters,
      );
      return <LatLng>[
        ...left.sublist(0, left.length - 1),
        ...right,
      ];
    } else {
      return <LatLng>[points.first, points.last];
    }
  }
}

/// 60fps Cubic Hermite Kinematic Spline Interpolator.
/// Uses start/end positions AND headings so even when the worker is off-Valhalla-route on a
/// Google Maps gully turn, the bike marker curves smoothly around the corner instead of cutting straight!
class CubicHermiteSplineInterpolator {
  static TrajectoryPose interpolate({
    required LatLng startPos,
    required double startBearingDeg,
    required LatLng endPos,
    required double endBearingDeg,
    required double t,
  }) {
    final u = t.clamp(0.0, 1.0);
    final chordMeters = RoadSnapper.fastDistanceMeters(startPos, endPos);

    if (chordMeters < 0.4) {
      return TrajectoryPose(
        position: endPos,
        bearing: RoadSnapper.lerpBearing(startBearingDeg, endBearingDeg, u),
      );
    }

    // Convert bearing vectors into tangent offsets scaled by chord length
    final tangentScaleDeg = (chordMeters / 111320.0) * 0.85;
    final startRad = startBearingDeg * (math.pi / 180.0);
    final endRad = endBearingDeg * (math.pi / 180.0);

    final m0Lat = math.cos(startRad) * tangentScaleDeg;
    final m0Lng = math.sin(startRad) * tangentScaleDeg;
    final m1Lat = math.cos(endRad) * tangentScaleDeg;
    final m1Lng = math.sin(endRad) * tangentScaleDeg;

    final u2 = u * u;
    final u3 = u2 * u;

    // Hermite basis functions
    final h00 = 2 * u3 - 3 * u2 + 1;
    final h10 = u3 - 2 * u2 + u;
    final h01 = -2 * u3 + 3 * u2;
    final h11 = u3 - u2;

    final lat = h00 * startPos.latitude +
        h10 * m0Lat +
        h01 * endPos.latitude +
        h11 * m1Lat;
    final lng = h00 * startPos.longitude +
        h10 * m0Lng +
        h01 * endPos.longitude +
        h11 * m1Lng;

    // Analytic derivative for exact instantaneous tangent heading along the curve
    final dh00 = 6 * u2 - 6 * u;
    final dh10 = 3 * u2 - 4 * u + 1;
    final dh01 = -6 * u2 + 6 * u;
    final dh11 = 3 * u2 - 2 * u;

    final dLat = dh00 * startPos.latitude +
        dh10 * m0Lat +
        dh01 * endPos.latitude +
        dh11 * m1Lat;
    final dLng = dh00 * startPos.longitude +
        dh10 * m0Lng +
        dh01 * endPos.longitude +
        dh11 * m1Lng;

    double instantaneousBearing;
    if (dLat.abs() > 1e-9 || dLng.abs() > 1e-9) {
      final meanLatRad = ((startPos.latitude + endPos.latitude) * 0.5) *
          (math.pi / 180.0);
      final theta = math.atan2(dLng * math.cos(meanLatRad), dLat);
      instantaneousBearing = (theta * (180.0 / math.pi) + 360.0) % 360.0;
    } else {
      instantaneousBearing =
          RoadSnapper.lerpBearing(startBearingDeg, endBearingDeg, u);
    }

    return TrajectoryPose(
      position: LatLng(lat, lng),
      bearing: instantaneousBearing,
    );
  }
}
