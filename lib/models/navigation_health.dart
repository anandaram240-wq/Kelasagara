// lib/models/navigation_health.dart
// ============================================================================
// KELASAGARA — Enterprise Navigation Subsystem Health & State Model
//
// Separates the monolithic navigation state into 4 independent subsystems:
//   1. MapStatus: Tile renderer & configuration health
//   2. GpsStatus: Device hardware location acquisition health
//   3. RouteStatus: Turn-by-turn road route calculation health
//   4. NavigationStatus: High-level guidance & journey session state
//
// Principles:
//   - Decoupled failures: Map failure != GPS failure != Route failure.
//   - Zero guessing: UI accurately identifies the FIRST failing subsystem.
//   - Independent retry: Retrying a route uses latest valid GPS without
//     restarting GPS acquisition or tearing down map state.
// ============================================================================

import 'package:flutter/foundation.dart';

/// Health status of the map renderer and tile provider.
enum MapStatus {
  /// Map widget is mounting or initializing controller.
  initializing,

  /// Valid tiles configured and map ready for interaction.
  ready,

  /// Map API key or base URL is missing / invalid at build or startup time.
  configurationError,

  /// HTTP or network failure fetching tile images (e.g. 401/403/timeout).
  tileError;

  bool get isReady => this == ready;
  bool get hasError => this == configurationError || this == tileError;

  String get displayName => switch (this) {
    initializing => 'INITIALIZING',
    ready => 'READY',
    configurationError => 'CONFIG_ERROR',
    tileError => 'TILE_ERROR',
  };
}

/// Health status of the device GPS and location acquisition stack.
enum GpsStatus {
  /// Checking system location service and app permissions.
  checking,

  /// Location permission is not yet requested or needs worker consent.
  permissionRequired,

  /// Worker denied location permission or denied forever.
  permissionDenied,

  /// Hardware device location service (GPS) is turned off in Android settings.
  serviceDisabled,

  /// Actively acquiring first usable hardware fix (one-shot or stream).
  acquiring,

  /// Real hardware GPS fix received, validated, and fresh.
  ready,

  /// Last known fix is older than threshold (stale) or degrading.
  stale,

  /// Timeout or hardware failure unable to produce a usable location.
  unavailable;

  bool get isReady => this == ready;
  bool get isUsable => this == ready || this == stale;
  bool get hasError =>
      this == permissionDenied || this == serviceDisabled || this == unavailable;

  String get displayName => switch (this) {
    checking => 'CHECKING',
    permissionRequired => 'PERMISSION_REQUIRED',
    permissionDenied => 'PERMISSION_DENIED',
    serviceDisabled => 'SERVICE_DISABLED',
    acquiring => 'ACQUIRING',
    ready => 'READY',
    stale => 'STALE',
    unavailable => 'UNAVAILABLE',
  };
}

/// Health status of the road routing calculation engine.
enum RouteStatus {
  /// Waiting for a valid device GPS fix before routing can begin.
  waitingForGps,

  /// Route calculation request in flight to routing provider.
  requesting,

  /// Road route calculated, validated, polyline geometry decoded.
  ready,

  /// Routing engine responded with no road connection between points.
  noRoute,

  /// Routing server unreachable, refused connection, or HTTP 5xx.
  providerUnavailable,

  /// Request deadline exceeded (e.g. 8s timeout).
  timeout,

  /// Origin or destination coordinates violate contracts (NaN, 0,0, etc.).
  invalidRequest,

  /// Response body could not be decoded or polyline geometry was invalid.
  decodeError,

  /// Provider rejected credentials or authentication failed (HTTP 401/403).
  authenticationError;

  bool get isReady => this == ready;
  bool get isCalculating => this == requesting;
  bool get hasError =>
      this == noRoute ||
      this == providerUnavailable ||
      this == timeout ||
      this == invalidRequest ||
      this == decodeError ||
      this == authenticationError;

  String get displayName => switch (this) {
    waitingForGps => 'WAITING_FOR_GPS',
    requesting => 'REQUESTING',
    ready => 'READY',
    noRoute => 'NO_ROUTE',
    providerUnavailable => 'PROVIDER_UNAVAILABLE',
    timeout => 'TIMEOUT',
    invalidRequest => 'INVALID_REQUEST',
    decodeError => 'DECODE_ERROR',
    authenticationError => 'AUTH_ERROR',
  };
}

/// Overall high-level state of the navigation journey session.
enum NavigationStatus {
  /// No active navigation session.
  idle,

  /// Validating prerequisites: booking, destination, map, GPS, route.
  bootstrapping,

  /// Route preview ready; worker can review route before tapping Start.
  ready,

  /// Turn-by-turn navigation actively running with live guidance.
  active,

  /// Worker has deviated beyond threshold distance from active route polyline.
  offRoute,

  /// Rerouting calculation in progress from current off-route fix.
  rerouting,

  /// Worker has arrived within destination threshold.
  arrived,

  /// Unrecoverable error in session (unauthorized, booking cancelled, etc.).
  fatalError;

  bool get isActive => this == active || this == offRoute || this == rerouting;
  bool get isReady => this == ready || isActive || this == arrived;

  String get displayName => switch (this) {
    idle => 'IDLE',
    bootstrapping => 'BOOTSTRAPPING',
    ready => 'READY',
    active => 'ACTIVE',
    offRoute => 'OFF_ROUTE',
    rerouting => 'REROUTING',
    arrived => 'ARRIVED',
    fatalError => 'FATAL_ERROR',
  };
}

/// Comprehensive navigation diagnostic health snapshot.
@immutable
class NavigationHealth {
  final MapStatus mapStatus;
  final GpsStatus gpsStatus;
  final RouteStatus routeStatus;
  final NavigationStatus navigationStatus;

  final String? mapErrorMessage;
  final String? gpsErrorMessage;
  final String? routeErrorMessage;
  final String? sessionErrorMessage;

  final String activeMapProvider;
  final String activeRouteProvider;
  final double? gpsAccuracyMeters;
  final int? gpsAgeMs;
  final int? routeLatencyMs;
  final String sessionId;
  final String requestId;

  const NavigationHealth({
    this.mapStatus = MapStatus.initializing,
    this.gpsStatus = GpsStatus.checking,
    this.routeStatus = RouteStatus.waitingForGps,
    this.navigationStatus = NavigationStatus.idle,
    this.mapErrorMessage,
    this.gpsErrorMessage,
    this.routeErrorMessage,
    this.sessionErrorMessage,
    this.activeMapProvider = 'CARTO',
    this.activeRouteProvider = 'VALHALLA',
    this.gpsAccuracyMeters,
    this.gpsAgeMs,
    this.routeLatencyMs,
    this.sessionId = '',
    this.requestId = '',
  });

  /// Factory for initial startup state
  factory NavigationHealth.initial() => const NavigationHealth();

  NavigationHealth copyWith({
    MapStatus? mapStatus,
    GpsStatus? gpsStatus,
    RouteStatus? routeStatus,
    NavigationStatus? navigationStatus,
    String? mapErrorMessage,
    String? gpsErrorMessage,
    String? routeErrorMessage,
    String? sessionErrorMessage,
    String? activeMapProvider,
    String? activeRouteProvider,
    double? gpsAccuracyMeters,
    int? gpsAgeMs,
    int? routeLatencyMs,
    String? sessionId,
    String? requestId,
  }) {
    return NavigationHealth(
      mapStatus: mapStatus ?? this.mapStatus,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      routeStatus: routeStatus ?? this.routeStatus,
      navigationStatus: navigationStatus ?? this.navigationStatus,
      mapErrorMessage: mapErrorMessage ?? this.mapErrorMessage,
      gpsErrorMessage: gpsErrorMessage ?? this.gpsErrorMessage,
      routeErrorMessage: routeErrorMessage ?? this.routeErrorMessage,
      sessionErrorMessage: sessionErrorMessage ?? this.sessionErrorMessage,
      activeMapProvider: activeMapProvider ?? this.activeMapProvider,
      activeRouteProvider: activeRouteProvider ?? this.activeRouteProvider,
      gpsAccuracyMeters: gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      gpsAgeMs: gpsAgeMs ?? this.gpsAgeMs,
      routeLatencyMs: routeLatencyMs ?? this.routeLatencyMs,
      sessionId: sessionId ?? this.sessionId,
      requestId: requestId ?? this.requestId,
    );
  }

  /// Identifies the first failing subsystem in deterministic order:
  /// Map -> GPS -> Route -> Navigation Session.
  String? get primaryFailureReason {
    if (mapStatus.hasError) return mapErrorMessage ?? 'Map configuration or tile error.';
    if (gpsStatus.hasError) return gpsErrorMessage ?? 'GPS location acquisition failed.';
    if (routeStatus.hasError) return routeErrorMessage ?? 'Road route calculation failed.';
    if (navigationStatus == NavigationStatus.fatalError) {
      return sessionErrorMessage ?? 'Navigation session encountered an unrecoverable error.';
    }
    return null;
  }

  /// Whether the complete navigation stack is operational.
  bool get isFullyHealthy =>
      mapStatus.isReady &&
      gpsStatus.isReady &&
      routeStatus.isReady &&
      navigationStatus.isReady;
}
