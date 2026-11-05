// lib/models/journey_state.dart
// Canonical journey state machine and centralized configuration.

import 'package:latlong2/latlong.dart';
export 'navigation_destination.dart' show BookingDestination, BookingDestinationContract;

// ── NavigationState & NavigationPhase ──────────────────────────────────────────
// Complete 26-state enterprise state machine for Kelasagara navigation.
// EVERY UI and service decision must derive from this machine.
enum NavigationState {
  idle,
  loadingBooking,
  validatingDestination,
  requestingGps,
  validatingGps,
  requestingRoute,
  validatingRoute,
  routePreviewReady,
  startingJourney,
  navigating,
  gpsDegraded,
  networkDegraded,
  routeRecalculating,
  offRoute,
  nearDestination,
  arrivalPending,
  arrived,
  journeyPaused,
  journeyCompleted,
  journeyCancelled,
  permissionDenied,
  gpsDisabled,
  sessionExpired,
  unauthorized,
  error,
  loggedOut,

  // ── Backward-compatibility aliases for existing V10/V11 code ──────────────
  locationAcquiring,
  routeRequesting,
  routeError,
  routeReady,
  navigationStarting,
  gpsLost,
  rerouting,
  approaching,
  ended;

  bool get isRouting =>
      this == requestingRoute || this == routeRequesting || this == routeRecalculating;

  bool get hasRoute =>
      this == routePreviewReady || this == routeReady ||
      this == startingJourney   || this == navigationStarting ||
      this == navigating        || this == gpsDegraded ||
      this == gpsLost           || this == networkDegraded ||
      this == routeRecalculating|| this == rerouting ||
      this == offRoute          || this == nearDestination ||
      this == approaching       || this == arrivalPending ||
      this == arrived;

  bool get isActive =>
      this == navigating        || this == startingJourney ||
      this == navigationStarting|| this == gpsDegraded ||
      this == gpsLost           || this == networkDegraded ||
      this == routeRecalculating|| this == rerouting ||
      this == offRoute          || this == nearDestination ||
      this == approaching       || this == arrivalPending;

  bool get showNavUI => hasRoute && this != routePreviewReady && this != routeReady;
  bool get canShowMap => hasRoute;
  bool get isError =>
      this == error || this == routeError ||
      this == permissionDenied || this == gpsDisabled ||
      this == unauthorized;
}

/// Backward compatibility alias for existing code referencing NavigationPhase
typedef NavigationPhase = NavigationState;

/// State Machine Transition Guard
class NavigationStateMachine {
  static const Map<NavigationState, Set<NavigationState>> _allowedTransitions = {
    NavigationState.idle: {
      NavigationState.loadingBooking,
      NavigationState.requestingGps,
      NavigationState.locationAcquiring,
      NavigationState.loggedOut,
      NavigationState.unauthorized,
      NavigationState.routeRequesting,
    },
    NavigationState.loadingBooking: {
      NavigationState.validatingDestination,
      NavigationState.error,
      NavigationState.unauthorized,
      NavigationState.idle,
    },
    NavigationState.validatingDestination: {
      NavigationState.requestingGps,
      NavigationState.locationAcquiring,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.requestingGps: {
      NavigationState.validatingGps,
      NavigationState.permissionDenied,
      NavigationState.gpsDisabled,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.locationAcquiring: {
      NavigationState.requestingRoute,
      NavigationState.routeRequesting,
      NavigationState.validatingGps,
      NavigationState.permissionDenied,
      NavigationState.gpsDisabled,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.validatingGps: {
      NavigationState.requestingRoute,
      NavigationState.routeRequesting,
      NavigationState.gpsDegraded,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.requestingRoute: {
      NavigationState.validatingRoute,
      NavigationState.routeReady,
      NavigationState.routePreviewReady,
      NavigationState.routeError,
      NavigationState.networkDegraded,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.routeRequesting: {
      NavigationState.validatingRoute,
      NavigationState.routeReady,
      NavigationState.routePreviewReady,
      NavigationState.routeError,
      NavigationState.networkDegraded,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.validatingRoute: {
      NavigationState.routePreviewReady,
      NavigationState.routeReady,
      NavigationState.routeError,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.routePreviewReady: {
      NavigationState.startingJourney,
      NavigationState.navigationStarting,
      NavigationState.idle,
      NavigationState.error,
    },
    NavigationState.routeReady: {
      NavigationState.startingJourney,
      NavigationState.navigationStarting,
      NavigationState.idle,
      NavigationState.error,
    },
    NavigationState.startingJourney: {
      NavigationState.navigating,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.navigationStarting: {
      NavigationState.navigating,
      NavigationState.error,
      NavigationState.idle,
    },
    NavigationState.navigating: {
      NavigationState.gpsDegraded,
      NavigationState.gpsLost,
      NavigationState.networkDegraded,
      NavigationState.offRoute,
      NavigationState.nearDestination,
      NavigationState.approaching,
      NavigationState.arrivalPending,
      NavigationState.arrived,
      NavigationState.journeyPaused,
      NavigationState.journeyCancelled,
      NavigationState.sessionExpired,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.gpsDegraded: {
      NavigationState.navigating,
      NavigationState.gpsLost,
      NavigationState.offRoute,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.gpsLost: {
      NavigationState.navigating,
      NavigationState.gpsDegraded,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.networkDegraded: {
      NavigationState.navigating,
      NavigationState.routeRecalculating,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.offRoute: {
      NavigationState.routeRecalculating,
      NavigationState.rerouting,
      NavigationState.navigating,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.routeRecalculating: {
      NavigationState.navigating,
      NavigationState.offRoute,
      NavigationState.networkDegraded,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.rerouting: {
      NavigationState.navigating,
      NavigationState.offRoute,
      NavigationState.networkDegraded,
      NavigationState.error,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.nearDestination: {
      NavigationState.arrivalPending,
      NavigationState.approaching,
      NavigationState.arrived,
      NavigationState.navigating,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.approaching: {
      NavigationState.arrivalPending,
      NavigationState.arrived,
      NavigationState.navigating,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.arrivalPending: {
      NavigationState.arrived,
      NavigationState.navigating,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.arrived: {
      NavigationState.journeyCompleted,
      NavigationState.ended,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.journeyPaused: {
      NavigationState.navigating,
      NavigationState.journeyCancelled,
      NavigationState.loggedOut,
      NavigationState.idle,
    },
    NavigationState.journeyCompleted: {
      NavigationState.idle,
      NavigationState.ended,
      NavigationState.loggedOut,
    },
    NavigationState.ended: {
      NavigationState.idle,
      NavigationState.loggedOut,
    },
    NavigationState.journeyCancelled: {
      NavigationState.idle,
      NavigationState.loggedOut,
    },
    NavigationState.permissionDenied: {
      NavigationState.requestingGps,
      NavigationState.locationAcquiring,
      NavigationState.idle,
    },
    NavigationState.gpsDisabled: {
      NavigationState.requestingGps,
      NavigationState.locationAcquiring,
      NavigationState.idle,
    },
    NavigationState.sessionExpired: {
      NavigationState.idle,
      NavigationState.loggedOut,
    },
    NavigationState.unauthorized: {
      NavigationState.idle,
      NavigationState.loggedOut,
    },
    NavigationState.error: {
      NavigationState.idle,
      NavigationState.requestingRoute,
      NavigationState.routeRequesting,
      NavigationState.loggedOut,
    },
    NavigationState.routeError: {
      NavigationState.idle,
      NavigationState.requestingRoute,
      NavigationState.routeRequesting,
      NavigationState.loggedOut,
    },
    NavigationState.loggedOut: {
      NavigationState.idle,
    },
  };

  /// Verify if transitioning from [from] to [to] is legal
  static bool canTransition(NavigationState from, NavigationState to) {
    if (from == to) return true;
    final allowed = _allowedTransitions[from];
    return allowed != null && allowed.contains(to);
  }
}

// ── FORMAL SYSTEM CONTRACTS ──────────────────────────────────────────────────

// Contract 1: Booking Destination & Contract is exported from navigation_destination.dart


/// Contract 2: GPS Position Quality & Classification
enum GpsQuality {
  live,
  recent,
  delayed,
  stale,
  offline,
  invalid,
  permissionDenied,
  gpsDisabled;

  static GpsQuality classify({
    required double accuracyM,
    required DateTime timestamp,
    required bool isMocked,
  }) {
    if (isMocked || accuracyM > 40.0) return GpsQuality.invalid;
    final ageMs = DateTime.now().difference(timestamp).inMilliseconds.abs();
    if (ageMs <= 3000 && accuracyM <= 15.0) return GpsQuality.live;
    if (ageMs <= 6000 && accuracyM <= 25.0) return GpsQuality.recent;
    if (ageMs <= 15000) return GpsQuality.delayed;
    if (ageMs <= 30000) return GpsQuality.stale;
    return GpsQuality.offline;
  }
}

/// Contract 4: Journey Session
class JourneySessionContract {
  final String sessionId;
  final String bookingId;
  final String workerId;
  final String hirerId;
  final DateTime startedAt;
  final DateTime lastHeartbeat;
  final int sequenceNumber;
  final JourneyStatus status;

  const JourneySessionContract({
    required this.sessionId,
    required this.bookingId,
    required this.workerId,
    required this.hirerId,
    required this.startedAt,
    required this.lastHeartbeat,
    required this.sequenceNumber,
    required this.status,
  });
}

enum JourneyStatus {
  notStarted,
  confirmed,
  windowOpen,
  workerReady,
  journeyStarted,
  travelling,
  approaching,
  arrived,
  workStarted,
  completionRequested,   // worker requested completion, hirer yet to confirm
  workCompleted,
  paused,
  cancelled,
  expired;

  static JourneyStatus fromBookingStatus(String s) => switch (s) {
    'confirmed'            => confirmed,
    'tracking'             => travelling,
    'approaching'          => approaching,
    'arrived'              => arrived,
    'working'              => workStarted,
    'completion_requested' => completionRequested,
    'completed'            => workCompleted,
    'completion_verified'  => workCompleted,
    'cancelled'            => cancelled,
    _                      => notStarted,
  };

  String get firestoreStatus => switch (this) {
    journeyStarted || travelling || approaching => 'tracking',
    arrived       => 'arrived',
    workStarted   => 'working',
    workCompleted => 'completed',
    cancelled     => 'cancelled',
    _             => 'confirmed',
  };

  String toFirestore() => firestoreStatus;

  String get rtdbStatus => switch (this) {
    journeyStarted || travelling || approaching => 'active',
    arrived || workStarted => 'arrived',
    workCompleted => 'completed',
    paused        => 'paused',
    _             => 'stopped',
  };

  bool get isActive =>
      this == journeyStarted || this == travelling || this == approaching;
  bool get isTerminal =>
      this == workCompleted || this == cancelled || this == expired;
  bool get workerCanStart =>
      this == confirmed || this == windowOpen || this == workerReady;
}

enum JourneyEvent {
  nearDestination,
  atArrivalRadius,
  offRoute,
  locationUnavailable,
  locationRestored,
}

enum LocationFreshness {
  live,
  recent,
  delayed,
  stale;

  static LocationFreshness fromSeconds(int sec) {
    if (sec < 10)  return live;
    if (sec < 30)  return recent;
    if (sec < 120) return delayed;
    return stale;
  }

  String get label => switch (this) {
    live    => 'LIVE',
    recent  => 'RECENT',
    delayed => 'DELAYED',
    stale   => 'STALE',
  };

  int get colorHex => switch (this) {
    live    => 0xFF22C55E,
    recent  => 0xFF84CC16,
    delayed => 0xFFF97316,
    stale   => 0xFFEF4444,
  };
}

class TrackingConfig {
  TrackingConfig._();

  static const int    normalIntervalMs          = 4000;
  static const int    nearDestinationIntervalMs = 2000;
  static const int    stationaryIntervalMs      = 10000;
  static const double minimumDistanceDeltaM     = 15.0;

  static const double accuracyThresholdM        = 50.0;
  static const double maxSpeedMps               = 55.6;
  static const double maxJumpDistanceM          = 1000.0;
  static const int    minTimestampDeltaMs       = 500;

  static const double arrivalRadiusM            = 150.0;
  static const int    arrivalStableCount        = 3;
  static const double nearDestinationRadiusM    = 500.0;

  static const double routeDeviationM           = 150.0;
  static const int    minRouteRecalcIntervalSec = 120;
  static const int    routeCacheMaxAgeMin       = 10;

  static const int    journeyWindowHours        = 2;

  static const int    staleLiveSec              = 10;
  static const int    staleRecentSec            = 30;
  static const int    staleDelayedSec           = 120;

  static const int    markerAnimDurationMs      = 900;
}

// ── NAVIGATION BOOTSTRAP STATE MACHINE ───────────────────────────────────────
/// Explicit state machine governing the transition from worker arrival at job
/// screen through location readiness, route validation, and navigation launch.
/// Strictly eliminates infinite loading spinners.
enum NavigationBootstrapState {
  idle,
  checkingBooking,
  checkingDestination,
  checkingPermission,
  checkingLocationService,
  requestingLocation,
  locationAcquired,
  locationValidated,
  routing,
  routeValidated,
  ready,
  startingGuidance,
  navigating,

  // Explicit failure states
  bookingInvalid,
  destinationInvalid,
  permissionDenied,
  locationServiceDisabled,
  locationTimeout,
  locationUnavailable,
  locationAccuracyTooLow,
  routeTimeout,
  routeUnavailable,
  routeInvalid,
  navigationInitializationFailed;

  bool get isLoading =>
      this == checkingBooking ||
      this == checkingDestination ||
      this == checkingPermission ||
      this == checkingLocationService ||
      this == requestingLocation ||
      this == locationAcquired ||
      this == locationValidated ||
      this == routing ||
      this == routeValidated ||
      this == startingGuidance;

  bool get isFailure =>
      this == bookingInvalid ||
      this == destinationInvalid ||
      this == permissionDenied ||
      this == locationServiceDisabled ||
      this == locationTimeout ||
      this == locationUnavailable ||
      this == locationAccuracyTooLow ||
      this == routeTimeout ||
      this == routeUnavailable ||
      this == routeInvalid ||
      this == navigationInitializationFailed;

  bool get isReady => this == ready;
  bool get isNavigating => this == navigating;
}

/// Navigation session metadata ensuring single-booking ownership and async safety.
class NavigationSession {
  final String navigationSessionId;
  final String bookingId;
  final String jobId;
  final String workerId;
  final String hirerId;
  final LatLng origin;
  final LatLng destination;
  final NavigationBootstrapState state;
  final int routeVersion;
  final String activeRequestId;
  final DateTime startedAt;
  final DateTime? lastLocationAt;
  final DateTime? lastRouteAt;

  const NavigationSession({
    required this.navigationSessionId,
    required this.bookingId,
    required this.jobId,
    required this.workerId,
    required this.hirerId,
    required this.origin,
    required this.destination,
    required this.state,
    required this.routeVersion,
    required this.activeRequestId,
    required this.startedAt,
    this.lastLocationAt,
    this.lastRouteAt,
  });

  NavigationSession copyWith({
    NavigationBootstrapState? state,
    int? routeVersion,
    String? activeRequestId,
    LatLng? origin,
    DateTime? lastLocationAt,
    DateTime? lastRouteAt,
  }) {
    return NavigationSession(
      navigationSessionId: navigationSessionId,
      bookingId: bookingId,
      jobId: jobId,
      workerId: workerId,
      hirerId: hirerId,
      origin: origin ?? this.origin,
      destination: destination,
      state: state ?? this.state,
      routeVersion: routeVersion ?? this.routeVersion,
      activeRequestId: activeRequestId ?? this.activeRequestId,
      startedAt: startedAt,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
      lastRouteAt: lastRouteAt ?? this.lastRouteAt,
    );
  }
}
