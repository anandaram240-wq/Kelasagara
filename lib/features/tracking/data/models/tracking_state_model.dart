// lib/features/tracking/data/models/tracking_state_model.dart
// Production-grade immutable tracking state for Hirer view.

import 'package:latlong2/latlong.dart';

enum SignalFreshness {
  live,          // Updated within 10s
  deadReckoning, // Extrapolating smoothly (10s - 18s)
  delayed,       // 18s - 45s old
  weakGps,       // > 45s old or seed-only fallback
}

enum JourneyLifecyclePhase {
  accepted,
  enRoute,
  arrivingSoon,
  arrivedAtGate,
  inProgress,
}

// Backward-compatibility alias
typedef TrackingLifecyclePhase = JourneyLifecyclePhase;

class TrackingStateModel {
  final LatLng workerAnimatedPosition;
  final LatLng workerTargetPosition;
  final LatLng hirerDestination;
  final double workerBearing;
  final List<LatLng> fullRoutePolyline;
  final List<LatLng> activeRemainingPolyline;
  final List<LatLng> traversedPolyline;
  final double remainingDistanceMeters;
  final int etaMinutes;
  final SignalFreshness freshness;
  final JourneyLifecyclePhase phase;
  final String arrivalOtp;
  final String workerName;
  final String workerPhone;
  final String workerCategory;
  final String? workerAvatarUrl;
  final double workerRating;
  final bool isSnappedToRoad;
  final bool isRerouting;
  final double currentSpeedKmh;

  const TrackingStateModel({
    required this.workerAnimatedPosition,
    required this.workerTargetPosition,
    required this.hirerDestination,
    this.workerBearing = 0.0,
    this.fullRoutePolyline = const [],
    this.activeRemainingPolyline = const [],
    this.traversedPolyline = const [],
    this.remainingDistanceMeters = 0.0,
    this.etaMinutes = 1,
    this.freshness = SignalFreshness.weakGps,
    this.phase = JourneyLifecyclePhase.accepted,
    this.arrivalOtp = '------',
    this.workerName = 'Worker',
    this.workerPhone = '',
    this.workerCategory = 'Service Partner',
    this.workerAvatarUrl,
    this.workerRating = 4.8,
    this.isSnappedToRoad = false,
    this.isRerouting = false,
    this.currentSpeedKmh = 0.0,
  });

  // Backward compatibility getters
  LatLng? get targetWorkerPos => workerTargetPosition;
  double get targetWorkerBearing => workerBearing;
  List<LatLng> get activePolyline => activeRemainingPolyline;
  bool get isSeedLocation => phase == JourneyLifecyclePhase.accepted;
  int get secondsSinceLastPing => freshness == SignalFreshness.live ? 2 : 15;

  /// Returns true only if worker has an actual, distinct active GPS position
  /// rather than uninitialized (0,0) or identical destination fallback while still accepted.
  bool get hasActiveWorkerPosition {
    if (workerAnimatedPosition.latitude == 0.0 &&
        workerAnimatedPosition.longitude == 0.0) {
      return false;
    }
    if (phase == JourneyLifecyclePhase.accepted) {
      final latDiff =
          (workerAnimatedPosition.latitude - hirerDestination.latitude).abs();
      final lngDiff =
          (workerAnimatedPosition.longitude - hirerDestination.longitude).abs();
      if (latDiff < 0.0001 && lngDiff < 0.0001) {
        return false;
      }
    }
    return true;
  }

  String get formattedDistance {
    if (phase == JourneyLifecyclePhase.accepted || remainingDistanceMeters <= 0.0) {
      return '--';
    }
    if (remainingDistanceMeters < 1000) {
      return '${remainingDistanceMeters.round()} m';
    }
    return '${(remainingDistanceMeters / 1000.0).toStringAsFixed(1)} km';
  }

  String get formattedEta {
    if (phase == JourneyLifecyclePhase.inProgress) {
      return 'In Progress';
    }
    if (phase == JourneyLifecyclePhase.arrivedAtGate) {
      return 'Arrived';
    }
    if (phase == JourneyLifecyclePhase.accepted) {
      return 'Preparing';
    }
    if (etaMinutes <= 1) return '1 min';
    return '$etaMinutes mins';
  }

  TrackingStateModel copyWith({
    LatLng? workerAnimatedPosition,
    LatLng? workerTargetPosition,
    LatLng? hirerDestination,
    double? workerBearing,
    List<LatLng>? fullRoutePolyline,
    List<LatLng>? activeRemainingPolyline,
    List<LatLng>? traversedPolyline,
    double? remainingDistanceMeters,
    int? etaMinutes,
    SignalFreshness? freshness,
    JourneyLifecyclePhase? phase,
    String? arrivalOtp,
    String? workerName,
    String? workerPhone,
    String? workerCategory,
    String? workerAvatarUrl,
    double? workerRating,
    bool? isSnappedToRoad,
    bool? isRerouting,
    double? currentSpeedKmh,
  }) {
    return TrackingStateModel(
      workerAnimatedPosition:
          workerAnimatedPosition ?? this.workerAnimatedPosition,
      workerTargetPosition: workerTargetPosition ?? this.workerTargetPosition,
      hirerDestination: hirerDestination ?? this.hirerDestination,
      workerBearing: workerBearing ?? this.workerBearing,
      fullRoutePolyline: fullRoutePolyline ?? this.fullRoutePolyline,
      activeRemainingPolyline:
          activeRemainingPolyline ?? this.activeRemainingPolyline,
      traversedPolyline: traversedPolyline ?? this.traversedPolyline,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      freshness: freshness ?? this.freshness,
      phase: phase ?? this.phase,
      arrivalOtp: arrivalOtp ?? this.arrivalOtp,
      workerName: workerName ?? this.workerName,
      workerPhone: workerPhone ?? this.workerPhone,
      workerCategory: workerCategory ?? this.workerCategory,
      workerAvatarUrl: workerAvatarUrl ?? this.workerAvatarUrl,
      workerRating: workerRating ?? this.workerRating,
      isSnappedToRoad: isSnappedToRoad ?? this.isSnappedToRoad,
      isRerouting: isRerouting ?? this.isRerouting,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
    );
  }
}
