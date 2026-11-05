import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/journey_state.dart';

/// GPS Quality Engine for Kelasagara V400.
/// Wraps raw Geolocator.Position into classified, quality-scored GPS fixes.
/// Used by NavigationEngine and JourneyService to reject bad GPS before routing.

/// GPS quality tiers according to Kelasagara Navigation Policy.
enum GpsQualityTier {
  EXCELLENT,
  GOOD,
  USABLE,
  UNUSABLE;

  bool get isUsable => this != UNUSABLE;
}

/// Classifies a raw GPS position based on accuracy, age, and heuristics.
enum GpsClassification {
  INVALID,
  LOW_ACCURACY,
  STALE,
  GOOD,
  LIVE,
  MOCK_SUSPECTED,
  GPS_JUMP,
  DUPLICATE;

  /// Whether this fix is generally usable for navigation/tracking.
  bool get isUsable => this == LIVE || this == GOOD || this == STALE;

  /// Quality score from 0.0 to 1.0.
  double get qualityScore => switch (this) {
    LIVE => 1.0,
    GOOD => 0.8,
    STALE => 0.4,
    LOW_ACCURACY => 0.3,
    _ => 0.0,
  };

  /// Human-readable reason for the classification (usually rejection reason).
  String get reason => switch (this) {
    INVALID => 'Invalid coordinates or extremely low accuracy',
    LOW_ACCURACY => 'Accuracy is between 50m and 100m',
    STALE => 'Position is older than 15 seconds (Warning: Using stale fix)',
    GOOD => 'Acceptable accuracy and age',
    LIVE => 'High accuracy and recent fix',
    MOCK_SUSPECTED => 'Position is suspected to be mocked',
    GPS_JUMP => 'Unrealistic jump from previous location',
    DUPLICATE => 'Duplicate coordinates within short timeframe',
  };

  /// Maps the internal classification to the journey-wide GpsQuality enum.
  GpsQuality toJourneyGpsQuality() => switch (this) {
    LIVE => GpsQuality.live,
    GOOD => GpsQuality.recent,
    STALE => GpsQuality.stale,
    LOW_ACCURACY => GpsQuality.invalid,
    MOCK_SUSPECTED => GpsQuality.invalid,
    GPS_JUMP => GpsQuality.invalid,
    DUPLICATE => GpsQuality.invalid,
    INVALID => GpsQuality.invalid,
  };
}

/// A wrapped position with its classification result.
class ClassifiedPosition {
  final Position position;
  final GpsClassification classification;
  final double qualityScore;
  final String? rejectReason;

  const ClassifiedPosition({
    required this.position,
    required this.classification,
    required this.qualityScore,
    this.rejectReason,
  });

  /// Convenience getter for lat/lng.
  LatLng get latLng => LatLng(position.latitude, position.longitude);

  /// Whether this position is usable.
  bool get isUsable => classification.isUsable;
}

/// Singleton engine to classify incoming GPS fixes based on history and thresholds.
class GpsQualityEngine {
  GpsQualityEngine._();
  
  /// Singleton instance
  static final GpsQualityEngine instance = GpsQualityEngine._();

  // D1 Fix: Authoritative accuracy threshold for triggering a route fetch.
  // GpsQualityEngine accepts 50–100m as LOW_ACCURACY (usable for tracking).
  // But fetching a route from an 81m-accuracy fix wastes a network call and
  // produces an unreliable route origin snap.
  // JourneyProvider D1-rescue guard MUST use this constant — not a magic literal.
  // Policy: route fetch is only triggered when GPS accuracy ≤ routeFetchMinAccuracyM.
  static const double routeFetchMinAccuracyM = 80.0;

  final List<ClassifiedPosition> _history = [];

  /// Classifies a raw Position into a ClassifiedPosition.
  ClassifiedPosition classify(Position raw) {
    GpsClassification classification = _determineClassification(raw);
    String? rejectReason = !classification.isUsable ? classification.reason : null;

    final classified = ClassifiedPosition(
      position: raw,
      classification: classification,
      qualityScore: classification.qualityScore,
      rejectReason: rejectReason,
    );

    _history.add(classified);
    if (_history.length > 10) {
      _history.removeAt(0);
    }

    return classified;
  }

  GpsClassification _determineClassification(Position raw) {
    // 1. Check for NaN/Infinite/zero/out-of-range coords or hardcoded centroids
    if (raw.latitude.isNaN || raw.latitude.isInfinite ||
        raw.longitude.isNaN || raw.longitude.isInfinite ||
        raw.latitude < -90.0 || raw.latitude > 90.0 ||
        raw.longitude < -180.0 || raw.longitude > 180.0 ||
        (raw.latitude == 0.0 && raw.longitude == 0.0)) {
      return GpsClassification.INVALID;
    }

    // 2. Check isMocked
    if (raw.isMocked) {
      return GpsClassification.MOCK_SUSPECTED;
    }

    // 3. Check accuracy > 100m
    if (raw.accuracy > 100.0) {
      return GpsClassification.INVALID;
    }

    // 4. Check accuracy 50-100m
    if (raw.accuracy >= 50.0 && raw.accuracy <= 100.0) {
      return GpsClassification.LOW_ACCURACY;
    }

    // 5. Check age > 15s
    final ageMs = DateTime.now().difference(raw.timestamp).inMilliseconds.abs();
    if (ageMs > 15000) {
      return GpsClassification.STALE;
    }

    if (_history.isNotEmpty) {
      final lastPos = _history.last.position;
      final timeDiffMs = raw.timestamp.difference(lastPos.timestamp).inMilliseconds.abs();
      final latDiff = (raw.latitude - lastPos.latitude).abs();
      final lngDiff = (raw.longitude - lastPos.longitude).abs();

      // 6. Check duplicate
      if (latDiff <= 0.00001 && lngDiff <= 0.00001 && timeDiffMs < 500) {
        return GpsClassification.DUPLICATE;
      }
    }

    // 7. Check jump from last valid fix
    final lastValidPos = lastValid;
    if (lastValidPos != null) {
      final distM = Geolocator.distanceBetween(
        lastValidPos.position.latitude,
        lastValidPos.position.longitude,
        raw.latitude,
        raw.longitude,
      );
      final timeDiffS = raw.timestamp.difference(lastValidPos.position.timestamp).inSeconds.abs();
      if (distM > 1000.0 && timeDiffS > 0) {
        final impliedSpeed = distM / timeDiffS;
        // > 55.6 m/s (200 km/h)
        if (impliedSpeed > 55.6) {
          return GpsClassification.GPS_JUMP;
        }
      } else if (distM > 1000.0 && timeDiffS == 0) {
        return GpsClassification.GPS_JUMP;
      }
    }

    // 8. Check accuracy < 15m AND age < 3s
    if (raw.accuracy < 15.0 && ageMs < 3000) {
      return GpsClassification.LIVE;
    }

    // 9. Otherwise
    return GpsClassification.GOOD;
  }

  /// Clears the position history buffer.
  void reset() {
    _history.clear();
  }

  /// Retrieves the most recent usable fix from the buffer, if any.
  ClassifiedPosition? get lastValid {
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i].isUsable) {
        return _history[i];
      }
    }
    return null;
  }

  /// Calculates the rolling average accuracy of the recent fixes.
  double get averageAccuracy {
    if (_history.isEmpty) return 0.0;
    double sum = 0.0;
    for (var fix in _history) {
      sum += fix.position.accuracy;
    }
    return sum / _history.length;
  }

  /// Detects and rejects forbidden hardcoded fallback centroids.
  static bool isHardcodedCentroid(double lat, double lng) {
    if (lat == 0.0 && lng == 0.0) return true;
    if ((lat - 13.0068).abs() < 0.0002 && (lng - 76.0996).abs() < 0.0002) return true;
    if ((lat - 13.0060).abs() < 0.0002 && (lng - 76.0954).abs() < 0.0002) return true;
    if ((lat - 12.9716).abs() < 0.0002 && (lng - 77.5946).abs() < 0.0002) return true;
    return false;
  }

  /// Evaluates whether a raw position is usable for initiating road route calculation.
  /// Does NOT require heading or speed to be non-zero (stationary worker is valid).
  bool isUsableForRouting(Position raw) {
    if (raw.latitude.isNaN || raw.latitude.isInfinite ||
        raw.longitude.isNaN || raw.longitude.isInfinite ||
        raw.latitude < -90.0 || raw.latitude > 90.0 ||
        raw.longitude < -180.0 || raw.longitude > 180.0 ||
        (raw.latitude == 0.0 && raw.longitude == 0.0)) {
      return false;
    }
    if (isHardcodedCentroid(raw.latitude, raw.longitude)) {
      return false;
    }
    if (raw.isMocked) return false;
    if (raw.accuracy.isNaN || raw.accuracy.isInfinite || raw.accuracy > 100.0) {
      return false;
    }
    return true;
  }

  /// Classifies position into explicit policy tiers: EXCELLENT, GOOD, USABLE, UNUSABLE.
  GpsQualityTier evaluateTier(Position raw) {
    if (!isUsableForRouting(raw)) return GpsQualityTier.UNUSABLE;
    final ageMs = DateTime.now().difference(raw.timestamp).inMilliseconds.abs();
    if (raw.accuracy < 15.0 && ageMs < 5000) return GpsQualityTier.EXCELLENT;
    if (raw.accuracy < 30.0 && ageMs < 15000) return GpsQualityTier.GOOD;
    return GpsQualityTier.USABLE;
  }
}
