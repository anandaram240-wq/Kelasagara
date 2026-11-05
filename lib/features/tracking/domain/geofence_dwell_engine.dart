// lib/features/tracking/domain/geofence_dwell_engine.dart
// Production-grade geofence dwell engine for worker approach and arrival detection.
// Evaluates 150m Approaching and 35m Arrived geofences with noise hysteresis.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'road_snapper.dart';

enum GeofenceStage {
  enRoute,
  approaching,
  arrived;

  String get wireValue {
    switch (this) {
      case GeofenceStage.enRoute:
        return 'on_the_way';
      case GeofenceStage.approaching:
        return 'approaching';
      case GeofenceStage.arrived:
        return 'arrived';
    }
  }

  static GeofenceStage fromWire(String? status) {
    switch (status) {
      case 'arrived':
      case 'completed':
        return GeofenceStage.arrived;
      case 'approaching':
      case 'arriving_soon':
        return GeofenceStage.approaching;
      default:
        return GeofenceStage.enRoute;
    }
  }
}

class BilingualNotificationPayload {
  final String titleKn;
  final String titleEn;
  final String bodyKn;
  final String bodyEn;

  const BilingualNotificationPayload({
    required this.titleKn,
    required this.titleEn,
    required this.bodyKn,
    required this.bodyEn,
  });
}

class GeofenceEvaluationResult {
  final GeofenceStage previousStage;
  final GeofenceStage currentStage;
  final double distanceMeters;
  final bool hasTransition;

  const GeofenceEvaluationResult({
    required this.previousStage,
    required this.currentStage,
    required this.distanceMeters,
    required this.hasTransition,
  });

  bool get didTransitionToApproaching =>
      hasTransition && currentStage == GeofenceStage.approaching;

  bool get didTransitionToArrived =>
      hasTransition && currentStage == GeofenceStage.arrived;
}

class GeofenceDwellEngine {
  final LatLng destination;
  GeofenceStage _currentStage;
  int _consecutiveArrivedHits = 0;
  DateTime? _firstQualifyingFixTimestamp;
  DateTime? _lastQualifyingFixTimestamp;

  static const double approachingRadiusMeters = 150.0;
  static const double arrivedRadiusMeters = 75.0;
  static const double maxAccuracyMeters = 35.0;
  static const int requiredArrivedDwellHits = 3;
  static const Duration minDwellDuration = Duration(seconds: 10);
  static const Duration maxStaleDuration = Duration(seconds: 60);

  GeofenceDwellEngine({
    required this.destination,
    GeofenceStage initialStage = GeofenceStage.enRoute,
  }) : _currentStage = initialStage;

  GeofenceStage get currentStage => _currentStage;
  int get consecutiveArrivedHits => _consecutiveArrivedHits;
  DateTime? get firstQualifyingFixTimestamp => _firstQualifyingFixTimestamp;

  void resetDwell() {
    _consecutiveArrivedHits = 0;
    _firstQualifyingFixTimestamp = null;
    _lastQualifyingFixTimestamp = null;
  }

  GeofenceEvaluationResult evaluateFix({
    required LatLng workerPosition,
    required double speedMps,
    required double accuracyMeters,
    required DateTime timestamp,
    bool isSeed = false,
  }) {
    final previous = _currentStage;
    final distMeters =
        RoadSnapper.fastDistanceMeters(workerPosition, destination);

    GeofenceStage next = _currentStage;

    if (_currentStage == GeofenceStage.arrived) {
      // Terminal milestone; do not regress to enRoute during delivery handshake
      next = GeofenceStage.arrived;
    } else if (distMeters <= arrivedRadiusMeters) {
      final isFresh = DateTime.now().difference(timestamp).abs() <= maxStaleDuration;
      final isDuplicate = _lastQualifyingFixTimestamp != null &&
          timestamp.isAtSameMomentAs(_lastQualifyingFixTimestamp!);
      final isAccurate = accuracyMeters <= maxAccuracyMeters && accuracyMeters >= 0.0;

      if (!isSeed && isFresh && isAccurate && !isDuplicate) {
        if (_consecutiveArrivedHits == 0) {
          _firstQualifyingFixTimestamp = timestamp;
        }
        _lastQualifyingFixTimestamp = timestamp;
        _consecutiveArrivedHits++;

        final dwellDuration = _firstQualifyingFixTimestamp != null
            ? timestamp.difference(_firstQualifyingFixTimestamp!)
            : Duration.zero;

        if (_consecutiveArrivedHits >= requiredArrivedDwellHits &&
            dwellDuration >= minDwellDuration) {
          next = GeofenceStage.arrived;
        } else {
          next = GeofenceStage.approaching;
        }
      }
    } else {
      _consecutiveArrivedHits = 0;
      _firstQualifyingFixTimestamp = null;
      _lastQualifyingFixTimestamp = null;
      if (distMeters <= approachingRadiusMeters) {
        next = GeofenceStage.approaching;
      } else {
        next = GeofenceStage.enRoute;
      }
    }

    final hasChanged = next != previous;
    if (hasChanged) {
      _currentStage = next;
    }

    return GeofenceEvaluationResult(
      previousStage: previous,
      currentStage: next,
      distanceMeters: distMeters,
      hasTransition: hasChanged,
    );
  }

  static BilingualNotificationPayload buildBilingualAlert({
    required GeofenceStage milestone,
    required String workerName,
    required String arrivalOtp,
  }) {
    if (milestone == GeofenceStage.arrived) {
      return BilingualNotificationPayload(
        titleKn: '$workerName ಸ್ಥಳಕ್ಕೆ ತಲುಪಿದ್ದಾರೆ',
        titleEn: '$workerName has Arrived',
        bodyKn: 'ಕೆಲಸ ಪ್ರಾರಂಭಿಸಲು OTP $arrivalOtp ನೀಡಿ',
        bodyEn: 'Share arrival OTP $arrivalOtp with $workerName to start job',
      );
    } else {
      return BilingualNotificationPayload(
        titleKn: '$workerName ಸಮೀಪದಲ್ಲಿದ್ದಾರೆ (150m)',
        titleEn: '$workerName is Approaching (150m)',
        bodyKn: '$workerName ಇನ್ನು ಕೆಲವೇ ಕ್ಷಣಗಳಲ್ಲಿ ನಿಮ್ಮ ಸ್ಥಳ ತಲುಪಲಿದ್ದಾರೆ',
        bodyEn: '$workerName is arriving in less than 2 minutes',
      );
    }
  }

  static Future<void> persistGeofenceTransition({
    required String bookingId,
    required GeofenceStage milestone,
    required String workerName,
    required String arrivalOtp,
  }) async {
    try {
      final payload = <String, dynamic>{
        'trackingStatus': milestone.wireValue,
        'geofenceMilestone': milestone.name,
        'geofenceTransitionAt': FieldValue.serverTimestamp(),
      };
      if (milestone == GeofenceStage.arrived) {
        payload['status'] = 'arrived';
        payload['arrivalStatus'] = 'arrived';
        payload['arrivedAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).set(
        payload,
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
