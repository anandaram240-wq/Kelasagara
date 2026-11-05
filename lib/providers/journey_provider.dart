// lib/providers/journey_provider.dart
// Orchestrates: JourneyService (GPS+RTDB write), Valhalla/HERE routing,
// RTDB listener (hirer side), last-seen timer, journey status transitions,
// secure arrival OTP (Firestore-rule-validated — hirer never sees raw OTP).

import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/journey_state.dart';
import '../models/live_location.dart';
import '../models/route_result.dart';
import '../services/journey_service.dart';
import '../services/route_service.dart';
import '../services/navigation_engine.dart';
import '../services/verified_work_service.dart';
import '../services/booking_service.dart';
import '../services/routing/gps_quality_engine.dart'; // D1 Fix: routeFetchMinAccuracyM constant
import '../services/navigation/navigation_preflight.dart';
import '../services/navigation/routing_facade.dart';
import '../models/navigation_health.dart';
import '../services/navigation/map_tile_configuration.dart';
import '../services/navigation/navigation_location_provider.dart';

class JourneyProvider extends ChangeNotifier {
  // ── Decoupled Navigation Health (Enterprise Model) ────────────────────────
  NavigationHealth _health = NavigationHealth.initial();
  NavigationHealth get health => _health;

  // ── Session info ──────────────────────────────────────────────────────────
  String?  _bookingId;
  String?  _workerId;
  String?  _hirerId;
  String?  _jobId;       // Phase 4: passed to RTDB for tracking identity
  LatLng?  _destination;
  String?  _workerName;
  String?  _jobTitle;
  bool     _isWorkerRole = true; // true = worker phone, false = hirer phone

  // ── Journey state ─────────────────────────────────────────────────────────
  JourneyStatus _status = JourneyStatus.notStarted;
  JourneyStatus get status => _status;

  // ── Worker live position ──────────────────────────────────────────────────
  // Raw position received from GPS (worker) or RTDB (hirer)
  LiveLocation? _workerLocation;
  LiveLocation? get workerLocation => _workerLocation;
  LatLng? get workerLatLng => _workerLocation != null
      ? LatLng(_workerLocation!.latitude, _workerLocation!.longitude)
      : null;

  // ── Navigation Engine (Phase 2 integration) ───────────────────────────────
  Stream<NavState> get navStream => NavigationEngine.instance.stream;
  NavState? get navState => NavigationEngine.instance.current;

  // ── Route ─────────────────────────────────────────────────────────────────
  RouteResult? _route;
  RouteResult? get route => _route;
  List<LatLng> get routePolyline => navState?.remainingPolyline ?? _route?.polyline ?? [];
  List<LatLng> get passedPolyline => navState?.passedPolyline ?? const [];

  // Dynamic ETA/distance: from local NavEngine when active, or live RTDB stream on Hirer side, fallback to route
  String get etaText {
    if (navState != null) return navState!.etaString;
    final liveEtaSec = _workerLocation?.etaSeconds ?? 0;
    if (liveEtaSec > 0) {
      final m = (liveEtaSec / 60).round();
      if (m < 60) return '$m min';
      final h = m ~/ 60;
      final remM = m % 60;
      return remM == 0 ? '${h}h' : '${h}h ${remM}m';
    }
    return _route?.etaText ?? '—';
  }

  String get distanceText {
    if (navState != null) {
      return navState!.remainingDistanceM < 1000
          ? '${navState!.remainingDistanceM.round()} m'
          : '${(navState!.remainingDistanceM / 1000).toStringAsFixed(1)} km';
    }
    final liveRemM = _workerLocation?.remainingMeters ?? 0.0;
    if (liveRemM > 0) {
      return liveRemM < 1000
          ? '${liveRemM.round()} m'
          : '${(liveRemM / 1000).toStringAsFixed(1)} km';
    }
    return _route?.distanceText ?? '—';
  }
  RouteStep? get nextStep  => navState?.currentStep ?? (_route?.steps.isNotEmpty == true ? _route!.steps[0] : null);
  RouteStep? get afterNextStep => navState?.nextStep;
  double     get speedKmh  => navState?.speedKmh ?? 0;
  bool       get isRerouting => navState?.isRerouting ?? false;
  bool       get hasArrived  => navState?.hasArrived ?? false;

  // ── Last-seen / freshness ─────────────────────────────────────────────────
  DateTime?   _lastUpdatedAt;
  DateTime?   get lastUpdatedAt => _lastUpdatedAt;
  int         _secSinceUpdate   = 0;
  int         get secSinceUpdate => _secSinceUpdate;
  Timer?      _freshnessTimer;

  LocationFreshness get freshness =>
      _lastUpdatedAt == null
          ? LocationFreshness.stale
          : LocationFreshness.fromSeconds(_secSinceUpdate);

  String get lastSeenText {
    if (_lastUpdatedAt == null) return 'Location unavailable';
    if (_secSinceUpdate < 5)   return 'Live';
    if (_secSinceUpdate < 60)  return 'Updated ${_secSinceUpdate}s ago';
    final min = _secSinceUpdate ~/ 60;
    return 'Updated ${min}m ago';
  }

  // ── Destination ───────────────────────────────────────────────────────────
  LatLng?  get destination  => _destination;
  String?  get workerName   => _workerName;
  String?  get jobTitle     => _jobTitle;
  String?  get bookingId    => _bookingId;
  String?  get workerId     => _workerId;
  String?  get hirerId      => _hirerId;
  bool     get isWorkerRole => _isWorkerRole;

  // V600: Phone numbers for call button — null if not available in booking doc.
  // Screens show graceful fallback instead of launching blank tel: URI.
  String? _hirerPhone;
  String? _workerPhone;
  String? get hirerPhone  => _hirerPhone;
  String? get workerPhone => _workerPhone;

  // ── Arrival flag (hirer/worker shown ARRIVED prompt) ─────────────────────
  bool _showArrivedPrompt = false;
  bool get showArrivedPrompt => _showArrivedPrompt;

  // ── Arrival OTP (worker side — NEVER exposed to hirer) ───────────────────
  // Shown ONLY to the worker after they tap "I Have Arrived".
  // Hirer enters it manually — Firestore rule validates, hirer app never reads it.
  String? _arrivalOtp;
  String? get arrivalOtp => _arrivalOtp;   // null until arrived; only worker sees
  bool    _otpVerified = false;
  bool    get otpVerified => _otpVerified;

  // ── Route loading indicator ───────────────────────────────────────────────
  bool _isLoadingRoute = false;
  bool get isLoadingRoute  => _isLoadingRoute;

  // ── NavigationPhase — single authoritative state ──────────────────────────
  // V10: All UI must derive from this. Never from unrelated booleans.
  NavigationPhase _phase = NavigationPhase.idle;
  NavigationPhase get phase => _phase;

  // ── NavigationBootstrapState & Session ────────────────────────────────────
  NavigationBootstrapState _bootstrapState = NavigationBootstrapState.idle;
  NavigationBootstrapState get bootstrapState => _bootstrapState;

  int _routeVersion = 0;
  int get routeVersion => _routeVersion;

  String _activeRequestId = '';
  String get activeRequestId => _activeRequestId;

  String _navigationSessionId = '';
  String get navigationSessionId => _navigationSessionId;

  Timer? _locationTimeoutTimer;
  Timer? _routeTimeoutTimer;

  /// Route fetch failed — show error UI with retry.
  String? _routeErrorReason;
  String? get routeErrorReason => _routeErrorReason;

  /// Route has been fetched and validated — ready for preview or navigation.
  bool get isRouteReady => _route != null && !_isLoadingRoute &&
      (_phase == NavigationPhase.routeReady ||
       _phase == NavigationPhase.navigationStarting ||
       _phase.hasRoute);

  /// NavEngine is actively running turn-by-turn (worker has tapped START NAVIGATION).
  bool get isNavigating => _phase.isActive && NavigationEngine.instance.isRunning;

  // Expose RouteService state so UI can show correct message
  RouteState get routeState   => RouteService.instance.state;
  String     get routeError   => _routeErrorReason ?? RouteService.instance.lastError;
  bool       get routeServerConfigured => RoutingFacade.instance.isValhallaConfigured;

  // ── V5.2 Voice Direct Booking Readiness Invariants ───────────────────────
  bool _isVoiceDirectBooking = false;
  bool _trackingProvisioned = false;
  bool get isVoiceDirectBooking => _isVoiceDirectBooking;
  bool get isTrackingProvisioned => _trackingProvisioned;
  bool get isTrackingReady => !_isVoiceDirectBooking || _trackingProvisioned;

  // ── Hirer RTDB subscription ───────────────────────────────────────────────
  StreamSubscription<DatabaseEvent>? _rtdbSub;

  // ── Booking Firestore subscription ────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _bookingSub;

  // ─────────────────────────────────────────────────────────────────────────
  // WORKER SIDE: init + start journey
  // ─────────────────────────────────────────────────────────────────────────

  /// Called by WorkerJourneyScreen before the screen is shown.
  Future<void> initWorker({
    required String bookingId,
    required String workerId,
    required String hirerId,
    required String jobId,          // Phase 4: forwarded to RTDB payload for identity
    required double destLat,
    required double destLng,
    required String workerName,
    required String jobTitle,
    required String currentBookingStatus,
  }) async {
    _bookingId    = bookingId;
    _workerId     = workerId;
    _hirerId      = hirerId;
    _jobId        = jobId;          // Phase 4: stored for startJourney->startTracking
    _destination  = LatLng(destLat, destLng);
    _workerName   = workerName;
    _jobTitle     = jobTitle;
    _isWorkerRole = true;
    _status       = JourneyStatus.fromBookingStatus(currentBookingStatus);

    _bootstrapState = NavigationBootstrapState.checkingBooking;
    notifyListeners();

    // Contract 1: Booking Destination Validation
    _bootstrapState = NavigationBootstrapState.checkingDestination;
    final destContract = BookingDestinationContract(
      bookingId:  bookingId,
      jobLat:     destLat,
      jobLng:     destLng,
      jobAddress: jobTitle,
      workerId:   workerId,
      hirerId:    hirerId,
    );
    if (!destContract.isValid()) {
      _bootstrapState = NavigationBootstrapState.destinationInvalid;
      _phase = NavigationState.error;
      _routeErrorReason = 'Invalid job destination coordinates';
      _health = _health.copyWith(
        routeStatus: RouteStatus.invalidRequest,
        routeErrorMessage: 'Invalid job destination coordinates',
        navigationStatus: NavigationStatus.fatalError,
        sessionErrorMessage: 'Invalid job destination coordinates',
      );
      notifyListeners();
      return;
    }

    // Evaluate Map Tile Configuration at startup
    final mapVal = MapTileConfiguration.instance.validateConfiguration();
    _health = _health.copyWith(
      mapStatus: mapVal.isValid ? MapStatus.ready : MapStatus.configurationError,
      activeMapProvider: mapVal.provider.name.toUpperCase(),
      mapErrorMessage: mapVal.errorMessage,
      navigationStatus: NavigationStatus.bootstrapping,
    );

    _startFreshnessTimer();
    _subscribeBookingStatus(bookingId);
    notifyListeners();

    // Automatically trigger bounded bootstrap sequence:
    // permission -> location services -> real GPS -> route
    await bootstrapNavigation();
  }

  /// Automatic and deterministic bootstrap sequence via NavigationPreflight:
  /// CHECKING_PERMISSION -> CHECKING_LOCATION_SERVICE -> REQUESTING_LOCATION ->
  /// LOCATION_ACQUIRED -> LOCATION_VALIDATED -> ROUTING -> ROUTE_VALIDATED -> READY.
  /// Bounded with strict 10s location timeout and 8s route timeout.
  Future<void> bootstrapNavigation() async {
    _locationTimeoutTimer?.cancel();
    _routeTimeoutTimer?.cancel();

    _navigationSessionId = 'nav_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    _activeRequestId = 'req_${DateTime.now().millisecondsSinceEpoch % 10000}';
    _routeVersion++;
    final currentSessionId = _navigationSessionId;
    _routeErrorReason = null;
    _health = _health.copyWith(
      navigationStatus: NavigationStatus.bootstrapping,
      sessionId: currentSessionId,
      requestId: _activeRequestId,
    );

    final statusSub = NavigationPreflight.instance.statusStream.listen((status) {
      if (_navigationSessionId != currentSessionId) return;
      switch (status) {
        case PreflightStatus.bookingValidating:
          _bootstrapState = NavigationBootstrapState.checkingBooking;
          _phase = NavigationPhase.loadingBooking;
          break;
        case PreflightStatus.destinationValidating:
          _bootstrapState = NavigationBootstrapState.checkingDestination;
          _phase = NavigationPhase.validatingDestination;
          break;
        case PreflightStatus.permissionChecking:
          _bootstrapState = NavigationBootstrapState.checkingPermission;
          _phase = NavigationPhase.locationAcquiring;
          _health = _health.copyWith(gpsStatus: GpsStatus.checking);
          break;
        case PreflightStatus.locationServiceChecking:
          _bootstrapState = NavigationBootstrapState.checkingLocationService;
          _phase = NavigationPhase.locationAcquiring;
          _health = _health.copyWith(gpsStatus: GpsStatus.checking);
          break;
        case PreflightStatus.gpsAcquiring:
          _bootstrapState = NavigationBootstrapState.requestingLocation;
          _phase = NavigationPhase.locationAcquiring;
          _health = _health.copyWith(gpsStatus: GpsStatus.acquiring);
          break;
        case PreflightStatus.gpsValidating:
          _bootstrapState = NavigationBootstrapState.locationValidated;
          _phase = NavigationPhase.locationAcquiring;
          break;
        case PreflightStatus.routeFetching:
          _bootstrapState = NavigationBootstrapState.routing;
          _phase = NavigationPhase.routeRequesting;
          _health = _health.copyWith(routeStatus: RouteStatus.requesting);
          break;
        case PreflightStatus.routeValidating:
          _bootstrapState = NavigationBootstrapState.routeValidated;
          _phase = NavigationPhase.routeRequesting;
          break;
        case PreflightStatus.ready:
          _bootstrapState = NavigationBootstrapState.ready;
          _phase = NavigationPhase.routeReady;
          _health = _health.copyWith(
            routeStatus: RouteStatus.ready,
            navigationStatus: NavigationStatus.ready,
          );
          break;
        case PreflightStatus.failed:
          _phase = NavigationPhase.routeError;
          break;
        case PreflightStatus.idle:
          break;
      }
      notifyListeners();
    });

    try {
      final result = await NavigationPreflight.instance.prepare(
        bookingId: _bookingId ?? '',
        jobId: _jobId ?? '',
        workerId: _workerId ?? '',
        destLat: _destination?.latitude ?? 0.0,
        destLng: _destination?.longitude ?? 0.0,
        jobAddress: _jobTitle ?? '',
        currentBookingStatus: _status.firestoreStatus,
        sessionId: currentSessionId,
      );

      if (_navigationSessionId != currentSessionId) return;

      if (result.isReady) {
        _workerLocation = result.initialLocation;
        _lastUpdatedAt = DateTime.now();
        _secSinceUpdate = 0;
        _route = result.initialRoute;
        _routeErrorReason = null;
        _bootstrapState = NavigationBootstrapState.ready;
        _phase = NavigationPhase.routeReady;
        _health = _health.copyWith(
          gpsStatus: GpsStatus.ready,
          gpsAccuracyMeters: result.initialLocation?.accuracy,
          routeStatus: RouteStatus.ready,
          routeErrorMessage: null,
          navigationStatus: NavigationStatus.ready,
          activeRouteProvider: result.initialRoute?.provider.toUpperCase() ?? 'VALHALLA',
          sessionId: currentSessionId,
          requestId: _activeRequestId,
        );
        notifyListeners();
      } else {
        _bootstrapState = _mapPreflightFailure(result.failureReason);
        _routeErrorReason = result.errorMessage ?? 'Navigation preflight failed.';
        _updateHealthForFailure(result.failureReason, _routeErrorReason);
        if (result.failureReason == PreflightFailureReason.permissionDenied) {
          _phase = NavigationPhase.permissionDenied;
        } else if (result.failureReason == PreflightFailureReason.locationServiceDisabled) {
          _phase = NavigationPhase.gpsDisabled;
        } else {
          _phase = NavigationPhase.routeError;
        }
        notifyListeners();
      }
    } finally {
      await statusSub.cancel();
    }
  }

  void _updateHealthForFailure(PreflightFailureReason reason, String? errorMsg) {
    switch (reason) {
      case PreflightFailureReason.permissionDenied:
        _health = _health.copyWith(
          gpsStatus: GpsStatus.permissionDenied,
          gpsErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.locationServiceDisabled:
        _health = _health.copyWith(
          gpsStatus: GpsStatus.serviceDisabled,
          gpsErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.locationTimeout:
      case PreflightFailureReason.locationAccuracyLow:
        _health = _health.copyWith(
          gpsStatus: GpsStatus.unavailable,
          gpsErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.routeTimeout:
        _health = _health.copyWith(
          routeStatus: RouteStatus.timeout,
          routeErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.routingConfigurationMissing:
      case PreflightFailureReason.routeUnavailable:
        _health = _health.copyWith(
          routeStatus: RouteStatus.providerUnavailable,
          routeErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.routeAuthenticationError:
        _health = _health.copyWith(
          routeStatus: RouteStatus.authenticationError,
          routeErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.routeNoRoute:
        _health = _health.copyWith(
          routeStatus: RouteStatus.noRoute,
          routeErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.routeMalformed:
        _health = _health.copyWith(
          routeStatus: RouteStatus.decodeError,
          routeErrorMessage: errorMsg,
          navigationStatus: NavigationStatus.idle,
        );
        break;
      case PreflightFailureReason.bookingInvalid:
      case PreflightFailureReason.destinationInvalid:
      case PreflightFailureReason.none:
      case PreflightFailureReason.unknown:
        _health = _health.copyWith(
          navigationStatus: NavigationStatus.fatalError,
          sessionErrorMessage: errorMsg,
        );
        break;
    }
  }

  NavigationBootstrapState _mapPreflightFailure(PreflightFailureReason reason) {
    switch (reason) {
      case PreflightFailureReason.bookingInvalid:
        return NavigationBootstrapState.bookingInvalid;
      case PreflightFailureReason.destinationInvalid:
        return NavigationBootstrapState.destinationInvalid;
      case PreflightFailureReason.permissionDenied:
        return NavigationBootstrapState.permissionDenied;
      case PreflightFailureReason.locationServiceDisabled:
        return NavigationBootstrapState.locationServiceDisabled;
      case PreflightFailureReason.locationTimeout:
        return NavigationBootstrapState.locationTimeout;
      case PreflightFailureReason.locationAccuracyLow:
        return NavigationBootstrapState.locationAccuracyTooLow;
      case PreflightFailureReason.routeTimeout:
        return NavigationBootstrapState.routeTimeout;
      case PreflightFailureReason.routingConfigurationMissing:
      case PreflightFailureReason.routeUnavailable:
        return NavigationBootstrapState.routeUnavailable;
      case PreflightFailureReason.routeAuthenticationError:
        return NavigationBootstrapState.routeUnavailable;
      case PreflightFailureReason.routeNoRoute:
        return NavigationBootstrapState.routeUnavailable;
      case PreflightFailureReason.routeMalformed:
        return NavigationBootstrapState.routeInvalid;
      case PreflightFailureReason.none:
      case PreflightFailureReason.unknown:
        return NavigationBootstrapState.navigationInitializationFailed;
    }
  }

  /// Worker taps START JOURNEY.
  Future<bool> startJourney() async {
    if (_bookingId == null || _workerId == null || _hirerId == null) return false;
    if (_destination == null) return false;

    // ── V5.2 VOICE DIRECT BOOKING READINESS GUARD ─────────────────────────
    // For voice direct bookings, trackingProvisioned == false means production RTDB
    // resources are not yet available. The worker must not start a journey while
    // tracking provisioning is incomplete.
    // This guard strictly does NOT interfere with public jobs or profile bookings.
    if (_isVoiceDirectBooking && !_trackingProvisioned) {
      // Re-read fresh document to avoid race with snapshot listener
      try {
        final bSnap = await FirebaseFirestore.instance.collection('bookings').doc(_bookingId).get();
        if (bSnap.exists) {
          final bData = bSnap.data()!;
          final isDirect = bData['isDirectBooking'] as bool? ?? false;
          final bSource = (bData['bookingSource'] ?? bData['source']) as String?;
          _isVoiceDirectBooking = isDirect && (bSource == 'voice_command_center');
          _trackingProvisioned = bData['trackingProvisioned'] as bool? ?? false;
        }
      } catch (e) {
        debugPrint('[Journey] Failed to refresh trackingProvisioned: $e');
      }

      if (_isVoiceDirectBooking && !_trackingProvisioned) {
        debugPrint('[Journey] Voice direct booking $_bookingId tracking not yet provisioned. Journey start blocked.');
        _routeErrorReason = 'PROVISIONING_INCOMPLETE';
        notifyListeners();
        return false;
      }
    }

    // ── Phase transition: IDLE → LOCATION_ACQUIRING ───────────────────────
    _phase = NavigationPhase.locationAcquiring;
    _routeErrorReason = null;
    notifyListeners();

    final started = await JourneyService.instance.startTracking(
      bookingId:  _bookingId!,
      workerId:   _workerId!,
      hirerId:    _hirerId!,
      destLat:    _destination!.latitude,
      destLng:    _destination!.longitude,
      onLocation: _onWorkerLocationUpdate,
      onEvent:    _onJourneyEvent,
    );

    if (!started) {
      // GPS/permission failed — go back to idle, let screen show error
      _phase = NavigationPhase.idle;
      notifyListeners();
      return false;
    }

    // Update Firestore booking status
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(_bookingId)
          .update({
        'status':           'tracking',
        'journeyStartedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Journey] Firestore startJourney error: $e');
    }

    _status = JourneyStatus.journeyStarted;
    _phase = NavigationPhase.routeRequesting;
    notifyListeners();

    // If route is already fetched, we are ready!
    if (_route != null) {
      _phase = NavigationPhase.routeReady;
      _bootstrapState = NavigationBootstrapState.ready;
      notifyListeners();
    } else if (_workerLocation != null) {
      _fetchRoute();
    } else {
      debugPrint('[Route] Waiting for GPS fix before fetching route...');
    }
    return true;
  }

  /// Independent retry: Map
  /// Re-evaluates MapTileConfiguration without touching GPS or Route.
  void retryMap() {
    final res = MapTileConfiguration.instance.validateConfiguration();
    _health = _health.copyWith(
      mapStatus: res.isValid ? MapStatus.ready : MapStatus.configurationError,
      activeMapProvider: res.provider.name.toUpperCase(),
      mapErrorMessage: res.errorMessage,
    );
    notifyListeners();
  }

  /// Independent retry: GPS
  /// Re-acquires device GPS fix without restarting map or clearing route if present.
  /// On successful fix, automatically triggers route calculation if route is missing.
  Future<void> retryGps() async {
    _health = _health.copyWith(
      gpsStatus: GpsStatus.acquiring,
      gpsErrorMessage: null,
    );
    notifyListeners();

    final gpsResult = await NavigationLocationProvider.instance.acquireInitialPosition(
      sessionId: _navigationSessionId.isNotEmpty ? _navigationSessionId : 'retry_gps',
      requestId: 'req_retry_gps_${DateTime.now().millisecondsSinceEpoch}',
      timeout: const Duration(seconds: 12),
    );

    if (gpsResult.isSuccess && gpsResult.location != null) {
      _workerLocation = gpsResult.location;
      _lastUpdatedAt = DateTime.now();
      _secSinceUpdate = 0;
      _health = _health.copyWith(
        gpsStatus: GpsStatus.ready,
        gpsAccuracyMeters: gpsResult.location!.accuracy,
        gpsAgeMs: gpsResult.latencyMs,
        gpsErrorMessage: null,
      );
      notifyListeners();

      // If route is missing or was failed, retry route with this fresh GPS fix
      if (_route == null || _health.routeStatus.hasError) {
        await retryRoute();
      }
    } else {
      _health = _health.copyWith(
        gpsStatus: gpsResult.status,
        gpsErrorMessage: gpsResult.errorMessage,
      );
      notifyListeners();
    }
  }

  /// Independent retry: Route
  /// Calculates route using the latest valid GPS position WITHOUT reacquiring GPS.
  /// If no usable GPS position exists, gracefully escalates to retryGps().
  Future<void> retryRoute() async {
    if (_workerLocation != null && _workerLocation!.hasValidCoordinates) {
      _health = _health.copyWith(
        routeStatus: RouteStatus.requesting,
        routeErrorMessage: null,
      );
      _routeErrorReason = null;
      notifyListeners();
      await _fetchRoute();
    } else {
      debugPrint('[Retry] No valid GPS fix available for route retry — triggering retryGps');
      await retryGps();
    }
  }

  /// Deterministic retry: cancels pending operations and restarts bootstrap sequence.
  void retryBootstrap() {
    _locationTimeoutTimer?.cancel();
    _routeTimeoutTimer?.cancel();
    _routeErrorReason = null;
    bootstrapNavigation();
  }

  /// Worker taps START NAVIGATION from route preview.
  /// Route is already fetched. This enforces the Navigation Contract:
  /// route != null AND distanceM > 0 AND NavEngine not already running.
  Future<void> startNavigation() async {
    // ── Navigation Contract enforcement ───────────────────────────────────
    if (_route == null) {
      debugPrint('[NavContract] VIOLATION: startNavigation() called with route=null');
      return;
    }
    if (_route!.distanceM <= 0) {
      debugPrint('[NavContract] VIOLATION: route.distanceM=${_route!.distanceM}');
      return;
    }
    if (_destination == null) {
      debugPrint('[NavContract] VIOLATION: destination=null');
      return;
    }
    if (NavigationEngine.instance.isRunning) {
      debugPrint('[NavContract] NavEngine already running — ignoring duplicate start');
      return;
    }
    if (_phase != NavigationPhase.routeReady) {
      debugPrint('[NavContract] Wrong phase: $_phase — must be routeReady');
      return;
    }

    _phase = NavigationPhase.navigationStarting;
    _bootstrapState = NavigationBootstrapState.startingGuidance;
    notifyListeners();
    debugPrint('[NavContract] ✅ ALL CHECKS PASSED → starting NavigationEngine');

    // Ensure JourneyService continuous tracking is started
    if (!JourneyService.instance.isTracking && _bookingId != null && _workerId != null && _hirerId != null) {
      await JourneyService.instance.startTracking(
        bookingId:  _bookingId!,
        workerId:   _workerId!,
        hirerId:    _hirerId!,
        destLat:    _destination!.latitude,
        destLng:    _destination!.longitude,
        onLocation: _onWorkerLocationUpdate,
        onEvent:    _onJourneyEvent,
      );
      try {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(_bookingId)
            .update({
          'status': 'tracking',
          'journeyStartedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[Journey] Firestore startNavigation update error: $e');
      }
    }

    await NavigationEngine.instance.start(
      route:        _route!,
      destination:  _destination!,
      bookingId:    _bookingId!,
      voiceEnabled: true,
    );
    _phase = NavigationPhase.navigating;
    _bootstrapState = NavigationBootstrapState.navigating;
    notifyListeners();
  }

  void _onWorkerLocationUpdate(LiveLocation loc) {
    _workerLocation  = loc;
    _lastUpdatedAt   = DateTime.now();
    _secSinceUpdate  = 0;
    notifyListeners();

    // V700 FIX D1: GPS race rescue.
    //
    // PROBLEM: startJourney() calls _fetchRoute() before JourneyService's GPS
    // stream emits its first position. _fetchRoute() silently returns when
    // _workerLocation == null (line 562). Phase stays routeRequesting forever.
    //
    // FIX: When the first valid GPS fix arrives and we're still waiting for a
    // route, re-trigger _fetchRoute() exactly once.
    //
    // Guard conditions (ALL must be true to trigger):
    //   1. _route == null          — no route has been successfully loaded yet
    //   2. phase == routeRequesting — we are in the "waiting for route" phase
    //   3. !_isLoadingRoute        — no request is currently in flight
    //   4. loc is valid            — GPS fix has a reasonable accuracy
    //
    // After the first successful route, _phase advances to routeReady or
    // beyond, so this block never fires on subsequent GPS updates.
    if (_route == null &&
        _phase == NavigationPhase.routeRequesting &&
        !_isLoadingRoute &&
        loc.accuracy <= GpsQualityEngine.routeFetchMinAccuracyM) { // D1 Fix: use authoritative constant
      debugPrint('[Route] D1-RESCUE: GPS arrived (acc=${loc.accuracy.toStringAsFixed(0)}m) '
          '— triggering deferred route fetch');
      _fetchRoute();
    }
  }

  void _onJourneyEvent(JourneyEvent event) {
    switch (event) {
      case JourneyEvent.nearDestination:
        if (_status == JourneyStatus.travelling) {
          _status = JourneyStatus.approaching;
          notifyListeners();
        }
      case JourneyEvent.atArrivalRadius:
        _showArrivedPrompt = true;
        notifyListeners();
      case JourneyEvent.offRoute:
        debugPrint('[Journey] Off-route event');
      case JourneyEvent.locationUnavailable:
        _status = JourneyStatus.paused;
        notifyListeners();
      case JourneyEvent.locationRestored:
        if (_status == JourneyStatus.paused) {
          _status = JourneyStatus.travelling;
          notifyListeners();
        }
    }
  }

  // ── Worker: mark arrived (75m Geofence Doorstep Handshake) ─────────────
  // Transitions booking to arrived, unlocking Customer Arrival OTP entry.
  Future<bool> markArrived() async {
    if (_bookingId == null || _workerId == null) return false;
    try {
      final res = await BookingService.instance.recordArrival(
        workerUid: _workerId!,
        bookingId: _bookingId!,
      );

      if (res.success) {
        await FirebaseDatabase.instance
            .ref('liveTracking/$_bookingId')
            .update({'trackingStatus': 'arrived'});

        _status            = JourneyStatus.arrived;
        _showArrivedPrompt = false;
        debugPrint('[Journey] Arrived within 75m doorstep geofence — OTP entry unlocked');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Journey] markArrived error: $e');
      return false;
    }
  }

  // ── Worker: submit arrival OTP for authoritative backend verification ─────
  Future<({bool success, String error})> verifyArrivalOtp(String enteredOtp) async {
    if (_bookingId == null) return (success: false, error: 'No active booking');
    if (enteredOtp.trim().length != 6) return (success: false, error: 'Enter 6-digit code');

    final res = await BookingService.instance.verifyArrivalOtp(
      bookingId: _bookingId!,
      enteredOtp: enteredOtp.trim(),
    );

    if (res.success) {
      _otpVerified = true;
      _status = JourneyStatus.workStarted;
      debugPrint('[Journey] Arrival OTP verified via backend ✅');
      notifyListeners();
      return (success: true, error: '');
    } else {
      return (success: false, error: res.error);
    }
  }

  void resetArrivalOtp() {
    _arrivalOtp  = null;
    _otpVerified = false;
    notifyListeners();
  }

  void setOtpVerified() {
    _otpVerified = true;
    _status = JourneyStatus.workStarted;
    notifyListeners();
  }

  // ── Worker: start work ────────────────────────────────────────────────────
  Future<void> startWork() async {
    if (_bookingId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(_bookingId)
          .update({
        'status':        'working',
        'workStartedAt': FieldValue.serverTimestamp(),
      });
      _status = JourneyStatus.workStarted;
      notifyListeners();
    } catch (e) {
      debugPrint('[Journey] startWork error: $e');
    }
  }

  // ── Worker: complete work ─────────────────────────────────────────────────
  // ── Worker: request work completion (triggers hirer confirmation banner) ──
  Future<({bool success, String error})> requestWorkCompletion() async {
    if (_bookingId == null || _workerId == null) {
      return (success: false, error: 'No active booking');
    }
    try {
      final result = await VerifiedWorkService.instance.requestCompletion(
        bookingId: _bookingId!,
        workerId:  _workerId!,
      );
      if (result.success) {
        _status = JourneyStatus.completionRequested;
        // Stop navigation but not GPS — journey technically still active
        await NavigationEngine.instance.stop();
        notifyListeners();
      }
      return result;
    } catch (e) {
      debugPrint('[Journey] requestWorkCompletion error: $e');
      return (success: false, error: e.toString());
    }
  }

  // Keep old name as alias for any backward-compat call sites
  Future<void> completeWork() async {
    await requestWorkCompletion();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HIRER SIDE: subscribe to RTDB live location
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initHirer({
    required String bookingId,
    required double destLat,
    required double destLng,
    required String workerName,
    required String jobTitle,
    required String currentBookingStatus,
    String? hirerId,
  }) async {
    _bookingId    = bookingId;
    _hirerId      = hirerId;
    _destination  = LatLng(destLat, destLng);
    _workerName   = workerName;
    _jobTitle     = jobTitle;
    _isWorkerRole = false;
    _status       = JourneyStatus.fromBookingStatus(currentBookingStatus);

    _startFreshnessTimer();
    _subscribeRTDB(bookingId);
    _subscribeBookingStatus(bookingId);
    notifyListeners();
  }

  void _subscribeRTDB(String bookingId) {
    _rtdbSub?.cancel();
    _rtdbSub = FirebaseDatabase.instance
        .ref('liveTracking/$bookingId')
        .onValue
        .listen((event) {
      if (!event.snapshot.exists) return;
      final data = event.snapshot.value as Map<Object?, Object?>?;
      if (data == null) return;

      final loc = LiveLocation.fromRtdb(data);
      if (!loc.hasValidCoordinates) return;

      _workerLocation  = loc;
      _lastUpdatedAt   = DateTime.now();
      _secSinceUpdate  = 0;
      notifyListeners();

      // V600 FIX: Guard against route fetch spam.
      // Without this guard, _fetchRoute() was called on EVERY RTDB update
      // (every 4s) while route=null, causing redundant parallel requests.
      // Now we only call _fetchRoute() if not already loading.
      if (_route == null && _destination != null && !_isLoadingRoute) {
        _fetchRoute();
      }
    }, onError: (Object e) {
      debugPrint('[Journey] RTDB listener error: $e');
    });
  }

  void _subscribeBookingStatus(String bookingId) {
    _bookingSub?.cancel();
    _bookingSub = FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final s = data['status'] as String? ?? '';
      final newStatus = JourneyStatus.fromBookingStatus(s);
      final verified = data['arrivalVerified'] as bool? ?? false;
      final workerPhoneFromDoc = data['workerPhone'] as String?;
      final hirerPhoneFromDoc = data['hirerPhone'] as String?;

      final bSource = (data['bookingSource'] ?? data['source']) as String?;
      final isDirect = data['isDirectBooking'] as bool? ?? false;
      final newIsVoice = isDirect && (bSource == 'voice_command_center');
      final newProvisioned = data['trackingProvisioned'] as bool? ?? false;

      bool shouldNotify = false;
      if (newIsVoice != _isVoiceDirectBooking) {
        _isVoiceDirectBooking = newIsVoice;
        shouldNotify = true;
      }
      if (newProvisioned != _trackingProvisioned) {
        _trackingProvisioned = newProvisioned;
        shouldNotify = true;
      }
      if (newStatus != _status) {
        _status = newStatus;
        shouldNotify = true;
      }
      if (verified != _otpVerified) {
        _otpVerified = verified;
        shouldNotify = true;
      }
      if (!_isWorkerRole && _arrivalOtp == null && _bookingId != null) {
        FirebaseFirestore.instance
            .collection('bookings')
            .doc(_bookingId)
            .collection('hirer_secure')
            .doc('arrival_code')
            .get()
            .then((secSnap) {
          final sOtp = secSnap.data()?['arrivalOtp']?.toString().trim();
          if (sOtp != null && sOtp.isNotEmpty && _arrivalOtp != sOtp) {
            _arrivalOtp = sOtp;
            notifyListeners();
          }
        }).catchError((_) {});
      }
      if (workerPhoneFromDoc != null && workerPhoneFromDoc.isNotEmpty && _workerPhone != workerPhoneFromDoc) {
        _workerPhone = workerPhoneFromDoc;
        shouldNotify = true;
      }
      if (hirerPhoneFromDoc != null && hirerPhoneFromDoc.isNotEmpty && _hirerPhone != hirerPhoneFromDoc) {
        _hirerPhone = hirerPhoneFromDoc;
        shouldNotify = true;
      }

      // Tier 2 Fallback: if RTDB has not yet arrived, seed location from booking
      final seedLoc = data['workerSeedLocation'] as Map<String, dynamic>?;
      if (_workerLocation == null && seedLoc != null && seedLoc['lat'] != null && seedLoc['lng'] != null) {
        final sLat = (seedLoc['lat'] as num).toDouble();
        final sLng = (seedLoc['lng'] as num).toDouble();
        if (sLat != 0.0 && sLng != 0.0) {
          _workerLocation = LiveLocation(
            latitude: sLat,
            longitude: sLng,
            accuracy: 15.0,
            heading: 0.0,
            speed: 0.0,
            timestamp: DateTime.now(),
          );
          _lastUpdatedAt = DateTime.now();
          _secSinceUpdate = 0;
          shouldNotify = true;
          if (_route == null && _destination != null && !_isLoadingRoute) {
            _fetchRoute();
          }
        }
      }
      if (shouldNotify) {
        notifyListeners();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchRoute({String? requestId, String? sessionId}) async {
    if (_destination == null) {
      _phase = NavigationPhase.routeError;
      _bootstrapState = NavigationBootstrapState.destinationInvalid;
      _routeErrorReason = 'Destination coordinates are missing.';
      notifyListeners();
      return;
    }
    if (_workerLocation == null) {
      debugPrint('[Route] Cannot fetch route: waiting for GPS fix');
      return;
    }
    if (_isLoadingRoute) {
      debugPrint('[Route] Fetch already in progress — skipping duplicate call');
      return;
    }

    final reqId = requestId ?? 'req_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final sessId = sessionId ?? _navigationSessionId;
    _activeRequestId = reqId;

    _isLoadingRoute = true;
    _bootstrapState = NavigationBootstrapState.routing;
    _phase = NavigationPhase.routeRequesting;
    _health = _health.copyWith(
      routeStatus: RouteStatus.requesting,
      routeErrorMessage: null,
    );
    notifyListeners();

    final sw = Stopwatch()..start();
    debugPrint('[ROUTE] request=$reqId START '
        'origin=(${_workerLocation!.latitude.toStringAsFixed(5)}, ${_workerLocation!.longitude.toStringAsFixed(5)}) '
        'dest=(${_destination!.latitude.toStringAsFixed(5)}, ${_destination!.longitude.toStringAsFixed(5)})');

    final origin = LatLng(_workerLocation!.latitude, _workerLocation!.longitude);
    final reqSentMs = sw.elapsedMilliseconds;

    try {
      final result = await RoutingFacade.instance.calculateRoute(
        origin: origin,
        destination: _destination!,
        sessionId: sessId.isNotEmpty ? sessId : 'sess_${DateTime.now().millisecondsSinceEpoch}',
        routeVersion: 1,
        timeout: const Duration(seconds: 8),
      );

      final respReceivedMs = sw.elapsedMilliseconds;
      _isLoadingRoute = false;

      // Stale request check: discard if session changed
      if (sessId.isNotEmpty && _navigationSessionId.isNotEmpty && _navigationSessionId != sessId) {
        debugPrint('[Route] Stale route response discarded (session mismatch)');
        return;
      }

      // ── ROUTE SUCCESS ─────────────────────────────────────────────────────
      _route = result;
      _routeErrorReason = null;

      // Validate route contract
      if (result.distanceM <= 0 || result.durationSec <= 0 || result.polyline.isEmpty) {
        _route = null;
        _routeErrorReason = 'Route returned invalid geometry '
            '(dist=${result.distanceM}m, dur=${result.durationSec}s, '
            'pts=${result.polyline.length}).';
        _phase = NavigationPhase.routeError;
        _bootstrapState = NavigationBootstrapState.routeInvalid;
        _health = _health.copyWith(
          routeStatus: RouteStatus.decodeError,
          routeErrorMessage: _routeErrorReason,
        );
        debugPrint('[ROUTE] request=$reqId CONTRACT_FAIL — $_routeErrorReason');
        notifyListeners();
        return;
      }

      final validatedMs = sw.elapsedMilliseconds;

      // ── Phase: ROUTE_REQUESTING → ROUTE_READY ────────────────────────────
      _phase = NavigationPhase.routeReady;
      _bootstrapState = NavigationBootstrapState.ready;
      _health = _health.copyWith(
        routeStatus: RouteStatus.ready,
        routeErrorMessage: null,
        activeRouteProvider: result.provider.toUpperCase(),
        routeLatencyMs: respReceivedMs,
        sessionId: sessId,
        requestId: reqId,
      );
      debugPrint('[ROUTE] request=$reqId provider=${result.provider} '
          'REQUEST_SENT=${reqSentMs}ms RESPONSE=${respReceivedMs}ms '
          'VALIDATE=${validatedMs}ms ACTIVATED=${sw.elapsedMilliseconds}ms '
          '— ${result.distanceText} / ${result.etaText} (${result.steps.length} steps)');
      notifyListeners();

      // ── Start NavigationEngine if journey has started ────────────────────
      if (_destination != null && _bookingId != null && _isWorkerRole &&
          _status == JourneyStatus.journeyStarted && !NavigationEngine.instance.isRunning) {
        _phase = NavigationPhase.navigationStarting;
        _bootstrapState = NavigationBootstrapState.startingGuidance;
        notifyListeners();
        debugPrint('[Route] NAVIGATION_SESSION_CREATED — starting NavEngine');
        NavigationEngine.instance.start(
          route:        result,
          destination:  _destination!,
          bookingId:    _bookingId!,
          voiceEnabled: true,
        ).then((_) {
          _phase = NavigationPhase.navigating;
          _bootstrapState = NavigationBootstrapState.navigating;
          debugPrint('[Route] GPS_STREAM_STARTED — NavEngine running → phase=NAVIGATING');
          notifyListeners();
        });
      }
    } on StaleRouteException catch (e) {
      _isLoadingRoute = false;
      debugPrint('[ROUTE] request=$reqId STALE_DISCARD: ${e.message}');
      return;
    } on RouteTimeoutException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.timeout,
        bootstrap: NavigationBootstrapState.routeTimeout,
        reason: e.message,
      );
    } on TimeoutException {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.timeout,
        bootstrap: NavigationBootstrapState.routeTimeout,
        reason: 'Route calculation timed out (8s limit). Please check your connection and retry.',
      );
    } on AuthenticationException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.authenticationError,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: e.message,
      );
    } on NoRouteFoundException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.noRoute,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: e.message,
      );
    } on RoutingConfigurationException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.providerUnavailable,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: e.message,
      );
    } on MalformedRouteException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.decodeError,
        bootstrap: NavigationBootstrapState.routeInvalid,
        reason: e.message,
      );
    } on RouteUnavailableException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.providerUnavailable,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: e.message,
      );
    } on RoutingException catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.providerUnavailable,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: e.message,
      );
    } catch (e) {
      _handleRouteFailure(
        requestId: reqId,
        status: RouteStatus.providerUnavailable,
        bootstrap: NavigationBootstrapState.routeUnavailable,
        reason: 'Route request failed: $e',
      );
    }
  }

  void _handleRouteFailure({
    required String requestId,
    required RouteStatus status,
    required NavigationBootstrapState bootstrap,
    required String reason,
  }) {
    _isLoadingRoute = false;

    // Stale-While-Revalidate: If we ALREADY have a valid active route, do NOT destroy it!
    // The driver/worker continues navigating smoothly on the current route without UI disruption.
    if (_route != null) {
      debugPrint('[ROUTE] request=$requestId RECALC_FAIL (preserving active route): $reason');
      _health = _health.copyWith(
        routeErrorMessage: reason,
      );
      notifyListeners();
      return;
    }

    // No existing route: Initial route calculation failed.
    _route = null;
    _phase = NavigationPhase.routeError;
    _bootstrapState = bootstrap;
    _routeErrorReason = reason;
    _health = _health.copyWith(
      routeStatus: status,
      routeErrorMessage: reason,
    );
    debugPrint('[ROUTE] request=$requestId INITIAL_FAIL: $reason');
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FRESHNESS TIMER
  // ─────────────────────────────────────────────────────────────────────────

  void _startFreshnessTimer() {
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastUpdatedAt != null) {
        _secSinceUpdate = DateTime.now().difference(_lastUpdatedAt!).inSeconds;
        notifyListeners();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLEANUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> teardown() async {
    await NavigationEngine.instance.stop();
    await JourneyService.instance.stopTracking();
    resetProvider();
  }

  void resetProvider() {
    _locationTimeoutTimer?.cancel();
    _routeTimeoutTimer?.cancel();
    _bookingId          = null;
    _workerId           = null;
    _hirerId            = null;
    _destination        = null;
    _workerName         = null;
    _jobTitle           = null;
    _status             = JourneyStatus.notStarted;
    _phase              = NavigationPhase.idle;      // ← Part 69: booking isolation
    _bootstrapState     = NavigationBootstrapState.idle;
    _routeVersion       = 0;
    _activeRequestId    = '';
    _navigationSessionId = '';
    _routeErrorReason   = null;
    _workerLocation     = null;
    _route              = null;
    _lastUpdatedAt      = null;
    _secSinceUpdate     = 0;
    _showArrivedPrompt  = false;
    _isLoadingRoute     = false;
    _rtdbSub?.cancel();
    _bookingSub?.cancel();
    _freshnessTimer?.cancel();
    RouteService.instance.clearCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _rtdbSub?.cancel();
    _bookingSub?.cancel();
    _freshnessTimer?.cancel();
    super.dispose();
  }
}
