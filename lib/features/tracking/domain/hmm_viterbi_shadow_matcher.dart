import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

enum ShadowTrackingMode {
  osmRoadLocked,
  googleShortcutGlide,
}

class ViterbiMatchOutput {
  final ShadowTrackingMode mode;
  final LatLng matchedPosition;
  final double matchedBearingDeg;
  final int matchedSegmentIndex;
  final double crossTrackMeters;
  final double remainingRouteMeters;
  final List<LatLng> activeOsmRoute;
  final List<LatLng> cubicBezierShortcutBridge;
  final bool requiresHeadingBiasedReroute;

  const ViterbiMatchOutput({
    required this.mode,
    required this.matchedPosition,
    required this.matchedBearingDeg,
    required this.matchedSegmentIndex,
    required this.crossTrackMeters,
    required this.remainingRouteMeters,
    required this.activeOsmRoute,
    required this.cubicBezierShortcutBridge,
    required this.requiresHeadingBiasedReroute,
  });
}

class _CandidateSegment {
  final int segIndex;
  final LatLng projectedPoint;
  final double crossTrackDistM;
  final double segmentBearingDeg;
  final double distanceAlongRouteM;
  double logPosterior = double.negativeInfinity;

  _CandidateSegment({
    required this.segIndex,
    required this.projectedPoint,
    required this.crossTrackDistM,
    required this.segmentBearingDeg,
    required this.distanceAlongRouteM,
  });
}

class HmmViterbiShadowMatcher {
  static const double _earthRadiusM = 6371000.0;
  static const double _candidateSearchRadiusM = 45.0;
  static const double _sigmaGpsM = 8.5;
  static const double _sigmaHeadingDeg = 28.0;
  static const double _betaTransitionM = 12.0;

  int? _prevMatchedSegmentIdx;
  double? _prevDistanceAlongRouteM;
  LatLng? _prevRawPoint;
  int _consecutiveGullyStrikes = 0;

  void resetRouteMemory() {
    _prevMatchedSegmentIdx = null;
    _prevDistanceAlongRouteM = null;
    _consecutiveGullyStrikes = 0;
  }

  ViterbiMatchOutput match({
    required LatLng workerPos,
    required double workerHeadingDeg,
    required double workerSpeedMps,
    required List<LatLng> osmPolyline,
  }) {
    if (osmPolyline.length < 2) {
      return ViterbiMatchOutput(
        mode: ShadowTrackingMode.googleShortcutGlide,
        matchedPosition: workerPos,
        matchedBearingDeg: workerHeadingDeg,
        matchedSegmentIndex: 0,
        crossTrackMeters: 0.0,
        remainingRouteMeters: osmPolyline.isNotEmpty
            ? haversineMeters(workerPos, osmPolyline.last)
            : 0.0,
        activeOsmRoute: osmPolyline,
        cubicBezierShortcutBridge: const [],
        requiresHeadingBiasedReroute: true,
      );
    }

    // 1. Precompute cumulative distances along polyline and extract candidates within 45m
    final List<_CandidateSegment> candidates = [];
    double cumulativeDistM = 0.0;
    _CandidateSegment? absoluteClosest;

    for (int i = 0; i < osmPolyline.length - 1; i++) {
      final LatLng a = osmPolyline[i];
      final LatLng b = osmPolyline[i + 1];
      final double segLen = haversineMeters(a, b);
      final (LatLng proj, double tRatio) = _projectPointWithRatio(workerPos, a, b);
      final double dPerp = haversineMeters(workerPos, proj);
      final double brng = bearingBetween(a, b);

      final _CandidateSegment cand = _CandidateSegment(
        segIndex: i,
        projectedPoint: proj,
        crossTrackDistM: dPerp,
        segmentBearingDeg: brng,
        distanceAlongRouteM: cumulativeDistM + segLen * tRatio,
      );

      if (absoluteClosest == null || dPerp < absoluteClosest.crossTrackDistM) {
        absoluteClosest = cand;
      }
      if (dPerp <= _candidateSearchRadiusM) {
        candidates.add(cand);
      }
      cumulativeDistM += segLen;
    }

    final double totalRouteLengthM = cumulativeDistM;
    final double euclideanStepM = _prevRawPoint != null
        ? haversineMeters(_prevRawPoint!, workerPos)
        : 0.0;
    _prevRawPoint = workerPos;

    // 2. Evaluate Viterbi Emission + Transition Log-Probabilities
    _CandidateSegment? bestWinner;

    for (final cand in candidates) {
      final double zDist = cand.crossTrackDistM / _sigmaGpsM;
      final double hdgDiff = workerSpeedMps > 1.1
          ? angularDiffDeg(workerHeadingDeg, cand.segmentBearingDeg)
          : 0.0;
      final double zHdg = hdgDiff / _sigmaHeadingDeg;

      // Log Emission Probability
      final double logEmission = -0.5 * (zDist * zDist) - 0.5 * (zHdg * zHdg);

      // Log Transition Probability (Topological continuity vs Euclidean displacement)
      double logTransition = 0.0;
      if (_prevDistanceAlongRouteM != null && _prevMatchedSegmentIdx != null) {
        final double routeStepM =
            cand.distanceAlongRouteM - _prevDistanceAlongRouteM!;
        final double discrepancyM = (euclideanStepM - routeStepM.abs()).abs();
        logTransition = -(discrepancyM / _betaTransitionM);

        // Heavy penalty for reversing backward along a one-way or main road
        if (routeStepM < -6.0) {
          logTransition -= 4.5;
        }
      }

      cand.logPosterior = logEmission + logTransition;
      if (bestWinner == null || cand.logPosterior > bestWinner.logPosterior) {
        bestWinner = cand;
      }
    }

    // 3. Decide between `osmRoadLocked` vs `googleShortcutGlide`
    final bool isStrongRoadMatch = bestWinner != null &&
        bestWinner.crossTrackDistM <= 19.0 &&
        (workerSpeedMps <= 1.1 ||
            angularDiffDeg(workerHeadingDeg, bestWinner.segmentBearingDeg) <=
                34.0);

    if (isStrongRoadMatch) {
      _consecutiveGullyStrikes = 0;
      _prevMatchedSegmentIdx = bestWinner.segIndex;
      _prevDistanceAlongRouteM = bestWinner.distanceAlongRouteM;

      final List<LatLng> trimmed = [
        bestWinner.projectedPoint,
        ...osmPolyline.sublist(bestWinner.segIndex + 1),
      ];

      final double remMeters =
          math.max(0.0, totalRouteLengthM - bestWinner.distanceAlongRouteM);

      return ViterbiMatchOutput(
        mode: ShadowTrackingMode.osmRoadLocked,
        matchedPosition: bestWinner.projectedPoint,
        matchedBearingDeg: bestWinner.segmentBearingDeg,
        matchedSegmentIndex: bestWinner.segIndex,
        crossTrackMeters: bestWinner.crossTrackDistM,
        remainingRouteMeters: remMeters,
        activeOsmRoute: trimmed,
        cubicBezierShortcutBridge: const [],
        requiresHeadingBiasedReroute: false,
      );
    }

    // 4. GOOGLE SHORTCUT GLIDE MODE (Worker is on a Google Maps Gully Shortcut)
    _consecutiveGullyStrikes++;
    final _CandidateSegment refSeg = bestWinner ?? absoluteClosest!;

    final (LatLng anchorPt, int anchorIdx, double anchorBearing) =
        _findAheadAnchor(
      polyline: osmPolyline,
      startIdx: refSeg.segIndex,
      startPoint: refSeg.projectedPoint,
      lookaheadM: 70.0,
    );

    // Synthesize C1-Continuous 16-Point Cubic Bezier Bridge
    final List<LatLng> cubicBridge = _buildCubicBezierShortcutBridge(
      workerPos: workerPos,
      workerHeadingDeg: workerSpeedMps > 0.8
          ? workerHeadingDeg
          : bearingBetween(workerPos, anchorPt),
      anchorPos: anchorPt,
      anchorRoadBearingDeg: anchorBearing,
    );

    final List<LatLng> aheadRoute = [
      anchorPt,
      ...osmPolyline.sublist(anchorIdx + 1),
    ];

    final double remMeters = haversineMeters(workerPos, anchorPt) +
        _polylineLength(aheadRoute);

    final bool shouldReroute =
        refSeg.crossTrackDistM > 36.0 && _consecutiveGullyStrikes >= 2;
    if (shouldReroute) {
      _consecutiveGullyStrikes = 0;
    }

    return ViterbiMatchOutput(
      mode: ShadowTrackingMode.googleShortcutGlide,
      matchedPosition: workerPos,
      matchedBearingDeg: workerHeadingDeg,
      matchedSegmentIndex: refSeg.segIndex,
      crossTrackMeters: refSeg.crossTrackDistM,
      remainingRouteMeters: remMeters,
      activeOsmRoute: aheadRoute,
      cubicBezierShortcutBridge: cubicBridge,
      requiresHeadingBiasedReroute: shouldReroute,
    );
  }

  /// C1 Cubic Bezier B(t) = (1-t)^3 P0 + 3(1-t)^2 t P1 + 3(1-t) t^2 P2 + t^3 P3
  /// Aligns P1 with worker's live heading and P2 with the target OSM road tangent
  static List<LatLng> _buildCubicBezierShortcutBridge({
    required LatLng workerPos,
    required double workerHeadingDeg,
    required LatLng anchorPos,
    required double anchorRoadBearingDeg,
    int samples = 16,
  }) {
    final double chordM = haversineMeters(workerPos, anchorPos);
    final double handleDistM = (chordM * 0.38).clamp(10.0, 40.0);

    // P1 projects forward along worker's heading
    final LatLng p1 =
        offsetPoint(workerPos, handleDistM, workerHeadingDeg);
    // P2 projects backward from the anchor along the reverse of the OSM road bearing
    final LatLng p2 = offsetPoint(
      anchorPos,
      handleDistM,
      (anchorRoadBearingDeg + 180.0) % 360.0,
    );

    final List<LatLng> pts = [];
    for (int i = 0; i <= samples; i++) {
      final double t = i / samples;
      final double u = 1.0 - t;
      final double b0 = u * u * u;
      final double b1 = 3 * u * u * t;
      final double b2 = 3 * u * t * t;
      final double b3 = t * t * t;

      final double lat = b0 * workerPos.latitude +
          b1 * p1.latitude +
          b2 * p2.latitude +
          b3 * anchorPos.latitude;
      final double lng = b0 * workerPos.longitude +
          b1 * p1.longitude +
          b2 * p2.longitude +
          b3 * anchorPos.longitude;
      pts.add(LatLng(lat, lng));
    }
    return pts;
  }

  static (LatLng, int, double) _findAheadAnchor({
    required List<LatLng> polyline,
    required int startIdx,
    required LatLng startPoint,
    required double lookaheadM,
  }) {
    double acc = 0.0;
    LatLng cur = startPoint;
    for (int i = startIdx; i < polyline.length - 1; i++) {
      final LatLng nxt = polyline[i + 1];
      final double d = haversineMeters(cur, nxt);
      final double brng = bearingBetween(cur, nxt);
      if (acc + d >= lookaheadM) {
        final double r = d > 0 ? ((lookaheadM - acc) / d).clamp(0.0, 1.0) : 0.0;
        return (
          LatLng(
            cur.latitude + (nxt.latitude - cur.latitude) * r,
            cur.longitude + (nxt.longitude - cur.longitude) * r,
          ),
          i,
          brng
        );
      }
      acc += d;
      cur = nxt;
    }
    final int lastSeg = polyline.length - 2;
    return (
      polyline.last,
      lastSeg,
      bearingBetween(polyline[lastSeg], polyline.last)
    );
  }

  static (LatLng, double) _projectPointWithRatio(LatLng p, LatLng a, LatLng b) {
    final double cosLat = math.cos(a.latitude * math.pi / 180.0);
    final double ax = a.longitude * cosLat, ay = a.latitude;
    final double bx = b.longitude * cosLat, by = b.latitude;
    final double px = p.longitude * cosLat, py = p.latitude;
    final double dx = bx - ax, dy = by - ay;
    final double lenSq = dx * dx + dy * dy;
    if (lenSq == 0.0) return (a, 0.0);
    final double t = (((px - ax) * dx + (py - ay) * dy) / lenSq).clamp(0.0, 1.0);
    return (LatLng(ay + t * dy, (ax + t * dx) / cosLat), t);
  }

  static double _polylineLength(List<LatLng> pts) {
    double sum = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      sum += haversineMeters(pts[i], pts[i + 1]);
    }
    return sum;
  }

  static LatLng offsetPoint(LatLng origin, double meters, double bearingDeg) {
    final double dRad = meters / _earthRadiusM;
    final double bRad = bearingDeg * math.pi / 180.0;
    final double lat1 = origin.latitude * math.pi / 180.0;
    final double lon1 = origin.longitude * math.pi / 180.0;
    final double lat2 = math.asin(
      math.sin(lat1) * math.cos(dRad) +
          math.cos(lat1) * math.sin(dRad) * math.cos(bRad),
    );
    final double lon2 = lon1 +
        math.atan2(
          math.sin(bRad) * math.sin(dRad) * math.cos(lat1),
          math.cos(dRad) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180.0 / math.pi, lon2 * 180.0 / math.pi);
  }

  static double haversineMeters(LatLng p1, LatLng p2) {
    final double dLat = (p2.latitude - p1.latitude) * math.pi / 180.0;
    final double dLon = (p2.longitude - p1.longitude) * math.pi / 180.0;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * math.pi / 180.0) *
            math.cos(p2.latitude * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return _earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double bearingBetween(LatLng a, LatLng b) {
    final double lat1 = a.latitude * math.pi / 180.0;
    final double lat2 = b.latitude * math.pi / 180.0;
    final double dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  static double angularDiffDeg(double a, double b) {
    final double d = (a - b).abs() % 360.0;
    return d > 180.0 ? 360.0 - d : d;
  }
}
