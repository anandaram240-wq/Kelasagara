import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class FilteredKinematics {
  final LatLng position;
  final double speedMps;
  final double headingDeg;
  final double mahalanobisScore;
  final bool wasOutlierRejected;

  const FilteredKinematics({
    required this.position,
    required this.speedMps,
    required this.headingDeg,
    required this.mahalanobisScore,
    required this.wasOutlierRejected,
  });
}

/// 4-State Coupled ENU [East, North, vEast, vNorth] Kinematic Kalman Filter
class EnuKinematicKalmanFilter {
  static const double _earthRadiusM = 6371000.0;
  static const double _chiSquare99Threshold = 11.34; // 2 DOF 99% gate

  bool _initialized = false;
  double _originLatRad = 0.0;
  double _originLngRad = 0.0;
  double _cosOriginLat = 1.0;
  int _lastTimestampMs = 0;

  // State vector: [E, N, vE, vN]
  double _e = 0.0;
  double _n = 0.0;
  double _ve = 0.0;
  double _vn = 0.0;

  // Diagonal + Cross-Covariance terms of 4x4 symmetric matrix P
  double _pEE = 25.0, _pNN = 25.0;
  double _pVeVe = 9.0, _pVnVn = 9.0;
  double _pEVe = 0.0, _pNVn = 0.0;

  final double processAccelNoiseSigma;

  EnuKinematicKalmanFilter({this.processAccelNoiseSigma = 2.2});

  FilteredKinematics processMeasurement({
    required double lat,
    required double lng,
    required double accuracyMeters,
    required double rawSpeedMps,
    required double rawHeadingDeg,
    required int timestampMs,
  }) {
    final double sigmaPos = math.max(accuracyMeters, 3.0);

    if (!_initialized) {
      _originLatRad = lat * math.pi / 180.0;
      _originLngRad = lng * math.pi / 180.0;
      _cosOriginLat = math.cos(_originLatRad).clamp(0.2, 1.0);
      _e = 0.0;
      _n = 0.0;

      final double hdgRad = rawHeadingDeg * math.pi / 180.0;
      _ve = rawSpeedMps * math.sin(hdgRad);
      _vn = rawSpeedMps * math.cos(hdgRad);

      final double rPos = sigmaPos * sigmaPos;
      _pEE = rPos;
      _pNN = rPos;
      _pVeVe = 4.0;
      _pVnVn = 4.0;
      _pEVe = 0.0;
      _pNVn = 0.0;

      _lastTimestampMs = timestampMs;
      _initialized = true;

      return FilteredKinematics(
        position: LatLng(lat, lng),
        speedMps: rawSpeedMps,
        headingDeg: rawHeadingDeg,
        mahalanobisScore: 0.0,
        wasOutlierRejected: false,
      );
    }

    final double dt =
        ((timestampMs - _lastTimestampMs).clamp(50, 15000)) / 1000.0;
    _lastTimestampMs = timestampMs;

    // 1. PREDICT STEP: x_{k|k-1} = F * x_{k-1}
    final double predE = _e + _ve * dt;
    final double predN = _n + _vn * dt;
    final double predVe = _ve;
    final double predVn = _vn;

    // Process noise Q ( Piecewise white noise acceleration model )
    final double qVar = processAccelNoiseSigma * processAccelNoiseSigma;
    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;
    final double dt4 = dt2 * dt2;

    final double qPos = 0.25 * dt4 * qVar;
    final double qPosVel = 0.5 * dt3 * qVar;
    final double qVel = dt2 * qVar;

    final double pEE = _pEE + 2.0 * dt * _pEVe + dt2 * _pVeVe + qPos;
    final double pEVe = _pEVe + dt * _pVeVe + qPosVel;
    final double pVeVe = _pVeVe + qVel;

    final double pNN = _pNN + 2.0 * dt * _pNVn + dt2 * _pVnVn + qPos;
    final double pNVn = _pNVn + dt * _pVnVn + qPosVel;
    final double pVnVn = _pVnVn + qVel;

    // 2. Convert incoming WGS84 measurement to local ENU meters
    final (double zE, double zN) = _latLngToEnu(lat, lng);

    // Innovation y = z - H * x
    final double yE = zE - predE;
    final double yN = zN - predN;

    final double rMeas = sigmaPos * sigmaPos;
    final double sE = pEE + rMeas;
    final double sN = pNN + rMeas;

    // 3. MAHALANOBIS OUTLIER GATE: d_M^2 = y^T * S^-1 * y
    final double mahalanobisSq = (yE * yE) / sE + (yN * yN) / sN;
    if (mahalanobisSq > _chiSquare99Threshold && dt < 5.0) {
      // Reject multipath spike; coast gently on predicted state with inflated covariance
      _e = predE;
      _n = predN;
      _pEE = pEE * 1.35;
      _pNN = pNN * 1.35;
      return FilteredKinematics(
        position: _enuToLatLng(_e, _n),
        speedMps: math.sqrt(_ve * _ve + _vn * _vn),
        headingDeg: (math.atan2(_ve, _vn) * 180.0 / math.pi + 360.0) % 360.0,
        mahalanobisScore: mahalanobisSq,
        wasOutlierRejected: true,
      );
    }

    // 4. KALMAN UPDATE STEP
    final double kE = pEE / sE;
    final double kVe = pEVe / sE;
    final double kN = pNN / sN;
    final double kVn = pNVn / sN;

    _e = predE + kE * yE;
    _n = predN + kN * yN;

    // Blend Kalman velocity update with Doppler hardware speed when moving
    double updatedVe = predVe + kVe * yE;
    double updatedVn = predVn + kVn * yN;
    if (rawSpeedMps > 0.8 && rawHeadingDeg >= 0.0) {
      final double hdgRad = rawHeadingDeg * math.pi / 180.0;
      final double dopplerVe = rawSpeedMps * math.sin(hdgRad);
      final double dopplerVn = rawSpeedMps * math.cos(hdgRad);
      updatedVe = updatedVe * 0.45 + dopplerVe * 0.55;
      updatedVn = updatedVn * 0.45 + dopplerVn * 0.55;
    }
    _ve = updatedVe;
    _vn = updatedVn;

    // Covariance update P = (I - K*H) * P
    _pEE = (1.0 - kE) * pEE;
    _pEVe = (1.0 - kE) * pEVe;
    _pVeVe = pVeVe - kVe * pEVe;

    _pNN = (1.0 - kN) * pNN;
    _pNVn = (1.0 - kN) * pNVn;
    _pVnVn = pVnVn - kVn * pNVn;

    final double filteredSpeed = math.sqrt(_ve * _ve + _vn * _vn);
    final double filteredHeading = filteredSpeed > 0.5
        ? (math.atan2(_ve, _vn) * 180.0 / math.pi + 360.0) % 360.0
        : rawHeadingDeg;

    return FilteredKinematics(
      position: _enuToLatLng(_e, _n),
      speedMps: filteredSpeed,
      headingDeg: filteredHeading,
      mahalanobisScore: mahalanobisSq,
      wasOutlierRejected: false,
    );
  }

  /// Predicts position forward by [extrapolateSeconds] with exponential velocity damping
  LatLng extrapolateDamped(double extrapolateSeconds) {
    if (!_initialized || extrapolateSeconds <= 0) {
      return _enuToLatLng(_e, _n);
    }
    final double dt = extrapolateSeconds.clamp(0.0, 4.5);
    // Integral of v0 * e^(-0.45 * t) from 0 to dt
    const double dampingLambda = 0.45;
    final double effectiveDt =
        (1.0 - math.exp(-dampingLambda * dt)) / dampingLambda;
    return _enuToLatLng(_e + _ve * effectiveDt, _n + _vn * effectiveDt);
  }

  (double, double) _latLngToEnu(double latDeg, double lngDeg) {
    final double latRad = latDeg * math.pi / 180.0;
    final double lngRad = lngDeg * math.pi / 180.0;
    final double dN = (latRad - _originLatRad) * _earthRadiusM;
    final double dE = (lngRad - _originLngRad) * _cosOriginLat * _earthRadiusM;
    return (dE, dN);
  }

  LatLng _enuToLatLng(double eastM, double northM) {
    final double latRad = _originLatRad + (northM / _earthRadiusM);
    final double lngRad =
        _originLngRad + (eastM / (_earthRadiusM * _cosOriginLat));
    return LatLng(latRad * 180.0 / math.pi, lngRad * 180.0 / math.pi);
  }
}
