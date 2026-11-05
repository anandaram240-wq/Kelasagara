import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'road_snapper.dart';

class KinematicFrame {
  final LatLng position;
  final double bearingDegrees;

  const KinematicFrame({
    required this.position,
    required this.bearingDegrees,
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

/// 60fps Cubic Hermite Kinematic Spline Interpolator.
/// Provides C1-continuous trajectory and heading interpolation using start/end
/// coordinates and bearing tangent vectors.
class CubicHermiteSplineInterpolator {
  LatLng? _startPos;
  double _startHeadingDeg = 0.0;
  LatLng? _endPos;
  double _endHeadingDeg = 0.0;

  void setControlSegment({
    required LatLng startPos,
    required double startHeadingDeg,
    required LatLng endPos,
    required double endHeadingDeg,
  }) {
    _startPos = startPos;
    _startHeadingDeg = startHeadingDeg;
    _endPos = endPos;
    _endHeadingDeg = endHeadingDeg;
  }

  KinematicFrame sample(double t) {
    if (_startPos == null || _endPos == null) {
      return KinematicFrame(
        position: _endPos ?? const LatLng(0, 0),
        bearingDegrees: _endHeadingDeg,
      );
    }

    final TrajectoryPose pose = interpolate(
      startPos: _startPos!,
      startBearingDeg: _startHeadingDeg,
      endPos: _endPos!,
      endBearingDeg: _endHeadingDeg,
      t: t,
    );

    return KinematicFrame(
      position: pose.position,
      bearingDegrees: pose.bearing,
    );
  }

  static TrajectoryPose interpolate({
    required LatLng startPos,
    required double startBearingDeg,
    required LatLng endPos,
    required double endBearingDeg,
    required double t,
  }) {
    final double u = t.clamp(0.0, 1.0);
    final double chordMeters = RoadSnapper.fastDistanceMeters(startPos, endPos);

    if (chordMeters < 0.4) {
      return TrajectoryPose(
        position: endPos,
        bearing: RoadSnapper.lerpBearing(startBearingDeg, endBearingDeg, u),
      );
    }

    // Convert bearing vectors into tangent offsets scaled by chord length
    final double tangentScaleDeg = (chordMeters / 111320.0) * 0.85;
    final double startRad = startBearingDeg * (math.pi / 180.0);
    final double endRad = endBearingDeg * (math.pi / 180.0);

    final double m0Lat = math.cos(startRad) * tangentScaleDeg;
    final double m0Lng = math.sin(startRad) * tangentScaleDeg;
    final double m1Lat = math.cos(endRad) * tangentScaleDeg;
    final double m1Lng = math.sin(endRad) * tangentScaleDeg;

    final double u2 = u * u;
    final double u3 = u2 * u;

    // Hermite basis functions
    final double h00 = 2 * u3 - 3 * u2 + 1;
    final double h10 = u3 - 2 * u2 + u;
    final double h01 = -2 * u3 + 3 * u2;
    final double h11 = u3 - u2;

    final double lat = h00 * startPos.latitude +
        h10 * m0Lat +
        h01 * endPos.latitude +
        h11 * m1Lat;
    final double lng = h00 * startPos.longitude +
        h10 * m0Lng +
        h01 * endPos.longitude +
        h11 * m1Lng;

    // Analytic derivative for exact instantaneous tangent heading along the curve
    final double dh00 = 6 * u2 - 6 * u;
    final double dh10 = 3 * u2 - 4 * u + 1;
    final double dh01 = -6 * u2 + 6 * u;
    final double dh11 = 3 * u2 - 2 * u;

    final double dLat = dh00 * startPos.latitude +
        dh10 * m0Lat +
        dh01 * endPos.latitude +
        dh11 * m1Lat;
    final double dLng = dh00 * startPos.longitude +
        dh10 * m0Lng +
        dh01 * endPos.longitude +
        dh11 * m1Lng;

    double instantaneousBearing;
    if (dLat.abs() > 1e-9 || dLng.abs() > 1e-9) {
      final double meanLatRad = ((startPos.latitude + endPos.latitude) * 0.5) *
          (math.pi / 180.0);
      final double theta = math.atan2(dLng * math.cos(meanLatRad), dLat);
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
