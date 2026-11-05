// lib/models/live_location.dart
// Validated GPS point. Every Position from Geolocator passes through
// LiveLocation before being published to RTDB or used for routing.

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'journey_state.dart';

class LiveLocation {
  LatLng get latLng => LatLng(latitude, longitude);
  final double latitude;
  final double longitude;
  final double accuracy;
  final double heading;
  final double speed;
  final DateTime timestamp;
  final bool isMocked;
  final int etaSeconds;
  final double remainingMeters;
  final String stepInstruction;
  final String stepInstructionKn;
  final String arrivalStatus;
  final int seq;
  final String sessionId;

  const LiveLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.heading,
    required this.speed,
    required this.timestamp,
    this.isMocked = false,
    this.etaSeconds = 0,
    this.remainingMeters = 0.0,
    this.stepInstruction = '',
    this.stepInstructionKn = '',
    this.arrivalStatus = 'en_route',
    this.seq = 0,
    this.sessionId = '',
  });

  factory LiveLocation.fromPosition(Position p) => LiveLocation(
    latitude:  p.latitude,
    longitude: p.longitude,
    accuracy:  p.accuracy,
    heading:   p.heading < 0 ? 0.0 : p.heading,
    speed:     p.speed > 0 ? (p.speed * 3.6) : 0.0,
    timestamp: p.timestamp,
    isMocked:  p.isMocked,
  );

  factory LiveLocation.fromRtdb(Map<Object?, Object?> m) {
    final lat = (m['latitude'] as num?)?.toDouble() ?? (m['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (m['longitude'] as num?)?.toDouble() ?? (m['lng'] as num?)?.toDouble() ?? 0.0;
    final acc = (m['accuracy'] as num?)?.toDouble() ?? 10.0;
    final hdg = (m['heading'] as num?)?.toDouble() ?? 0.0;
    final spd = (m['speed'] as num?)?.toDouble() ?? 0.0;
    final eta = (m['etaSeconds'] as num?)?.toInt() ?? 0;
    final rem = (m['remainingMeters'] as num?)?.toDouble() ?? 0.0;
    final step = (m['currentStepInstruction'] as String?) ?? '';
    final stepKn = (m['currentStepInstructionKn'] as String?) ?? '';
    final arr = (m['arrivalStatus'] as String?) ?? 'en_route';
    final seqNum = (m['seq'] as num?)?.toInt() ?? 0;
    final sess = (m['sessionId'] as String?) ?? '';
    final rawTs = m['updatedAt'] ?? m['timestamp'];
    final ts = rawTs != null
        ? DateTime.fromMillisecondsSinceEpoch((rawTs as num).toInt())
        : DateTime.now();

    return LiveLocation(
      latitude:          lat,
      longitude:         lng,
      accuracy:          acc,
      heading:           hdg,
      speed:             spd,
      timestamp:         ts,
      etaSeconds:        eta,
      remainingMeters:   rem,
      stepInstruction:   step,
      stepInstructionKn: stepKn,
      arrivalStatus:     arr,
      seq:               seqNum,
      sessionId:         sess,
      isMocked:          false,
    );
  }

  double get speedKmh => speed;

  Map<String, dynamic> toRtdbMap({
    required String workerId,
    required String hirerId,
    required String trackingStatus,
  }) => {
    'workerId':       workerId,
    'hirerId':        hirerId,
    'latitude':       latitude,
    'longitude':      longitude,
    'speed':          speed, // stored in km/h
    'accuracy':       accuracy,
    'heading':        heading,
    'timestamp':      timestamp.millisecondsSinceEpoch,
    'trackingStatus': trackingStatus,
  };

  bool get hasValidCoordinates =>
      latitude != 0.0 && longitude != 0.0 &&
      latitude.abs() <= 90 && longitude.abs() <= 180;

  bool get hasGoodAccuracy =>
      accuracy > 0 && accuracy <= TrackingConfig.accuracyThresholdM;

  bool get hasReasonableSpeed => speed <= (TrackingConfig.maxSpeedMps * 3.6);

  bool get isNotMocked => !isMocked;

  bool get isValid => hasValidCoordinates && hasGoodAccuracy && hasReasonableSpeed;

  bool isReasonableFollowOn(LiveLocation prev) {
    final dtMs = timestamp.difference(prev.timestamp).inMilliseconds;
    if (dtMs < TrackingConfig.minTimestampDeltaMs) return false;
    final distM = Geolocator.distanceBetween(
      prev.latitude, prev.longitude, latitude, longitude);
    if (distM > TrackingConfig.maxJumpDistanceM) return false;
    if (dtMs > 0) {
      final impliedSpeed = distM / (dtMs / 1000.0);
      if (impliedSpeed > TrackingConfig.maxSpeedMps) return false;
    }
    return true;
  }

  double distanceTo(double targetLat, double targetLng) =>
      Geolocator.distanceBetween(latitude, longitude, targetLat, targetLng);

  @override
  String toString() =>
      'LiveLocation(${latitude.toStringAsFixed(6)}, '
      '${longitude.toStringAsFixed(6)} '
      'acc=${accuracy.toStringAsFixed(1)}m '
      'spd=${(speed * 3.6).toStringAsFixed(1)}km/h '
      'mock=$isMocked)';
}
