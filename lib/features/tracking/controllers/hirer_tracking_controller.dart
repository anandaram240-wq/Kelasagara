// lib/features/tracking/controllers/hirer_tracking_controller.dart
// Production-grade 60fps polyline-crawl controller with dead-reckoning extrapolation,
// Google Routes API + RTDB shared polyline caching, and Elastic Free-Follow mode.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../domain/road_snapper.dart';
import '../data/models/live_telemetry_model.dart';
import '../data/models/tracking_state_model.dart';
import '../repositories/google_shared_routing_repository.dart';

class HirerTrackingController extends ChangeNotifier {
  final String bookingId;
  final String? workerId;
  final GoogleSharedRoutingRepository _routingRepository;
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _rtdb;

  bool _isExactGoogleRoute = false;

  TrackingStateModel _state;
  TrackingStateModel get state => _state;

  // Convenience backward compatibility getters
  LatLng? get targetWorkerPos => _state.workerTargetPosition;
  double get targetWorkerBearing => _state.workerBearing;
  List<LatLng> get activePolyline => _state.activeRemainingPolyline;
  double get remainingDistanceMeters => _state.remainingDistanceMeters;
  int get etaMinutes => _state.etaMinutes;
  String get arrivalOtp => _state.arrivalOtp;
  bool get isSeedLocation => _state.phase == JourneyLifecyclePhase.accepted;
  JourneyLifecyclePhase get phase => _state.phase;
  SignalFreshness get freshness => _state.freshness;
  int get secondsSinceLastPing => _state.secondsSinceLastPing;

  StreamSubscription<DatabaseEvent>? _rtdbSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bookingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _hirerSecureSub;
  Timer? _freshnessAndDeadReckonTimer;

  List<LatLng> _activeAnimationSubPath = const [];
  double _animStartBearing = 0.0;
  double _animEndBearing = 0.0;

  int? _lastSnappedSegmentIndex;
  int _lastSequenceNumber = -1;
  DateTime? _lastTelemetryReceivedAt;
  DateTime? _lastRerouteAt;
  int _offRouteStrikeCount = 0;
  double _emaSpeedMps = 7.5; // ~27 km/h urban baseline
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// Callback triggered whenever a new trajectory sub-path is ready for 60fps animation.
  VoidCallback? onTriggerFrameInterpolation;

  HirerTrackingController({
    required this.bookingId,
    LatLng? initialHirerDestination,
    LatLng? initialWorkerFallback,
    String initialWorkerName = 'Service Partner',
    String initialWorkerPhone = '',
    String initialWorkerCategory = 'Specialist',
    GoogleSharedRoutingRepository? routingRepository,
    FirebaseFirestore? firestore,
    FirebaseDatabase? rtdb,
    this.workerId,
    LatLng? destinationPos,
  })  : _routingRepository =
            routingRepository ?? GoogleSharedRoutingRepository.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance,
        _state = TrackingStateModel(
          workerAnimatedPosition: initialWorkerFallback ??
              initialHirerDestination ??
              destinationPos ??
              const LatLng(12.9716, 77.5946),
          workerTargetPosition: initialWorkerFallback ??
              initialHirerDestination ??
              destinationPos ??
              const LatLng(12.9716, 77.5946),
          hirerDestination: initialHirerDestination ??
              destinationPos ??
              const LatLng(12.9716, 77.5946),
          workerName: initialWorkerName,
          workerPhone: initialWorkerPhone,
          workerCategory: initialWorkerCategory,
        );

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _bootstrapThreeTierWaterfall();
    _listenToBookingDocument();
    _listenToRealtimeTelemetry();
    _startFreshnessAndDeadReckoningMonitor();
  }

  /// Tier 1: RTDB Live Node -> Tier 2: Firestore `workerSeedLocation` -> Tier 3: Worker Profile `lastLocation`
  Future<void> _bootstrapThreeTierWaterfall() async {
    try {
      final bookingSnap =
          await _firestore.collection('bookings').doc(bookingId).get();
      final bookingData = bookingSnap.data();

      LatLng? resolvedOrigin;
      LatLng resolvedDest = _state.hirerDestination;
      String arrivalOtp = _state.arrivalOtp;
      String workerName = _state.workerName;
      String workerPhone = _state.workerPhone;
      String workerCategory = _state.workerCategory;
      String? resolvedWorkerId = workerId;

      if (bookingData != null) {
        try {
          final secSnap = await _firestore
              .collection('bookings')
              .doc(bookingId)
              .collection('hirer_secure')
              .doc('arrival_code')
              .get();
          final secOtp = secSnap.data()?['arrivalOtp']?.toString().trim();
          if (secOtp != null && secOtp.isNotEmpty) {
            arrivalOtp = secOtp;
          } else {
            // Self-heal arrivalOtp exclusively in isolated hirer_secure/arrival_code
            final generatedOtp =
                (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();
            arrivalOtp = generatedOtp;
            final currentUid = FirebaseAuth.instance.currentUser?.uid ?? (bookingData['hirerId']?.toString() ?? '');
            unawaited(
              _firestore
                  .collection('bookings')
                  .doc(bookingId)
                  .collection('hirer_secure')
                  .doc('arrival_code')
                  .set({
                'arrivalOtp': generatedOtp,
                'hirerId': currentUid,
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true)),
            );
          }
        } catch (_) {}

        workerName =
            (bookingData['workerName'] ?? _state.workerName).toString();
        workerPhone =
            (bookingData['workerPhone'] ?? _state.workerPhone).toString();
        workerCategory =
            (bookingData['category'] ?? _state.workerCategory).toString();
        resolvedWorkerId ??= bookingData['workerId']?.toString();

        final jobLoc = _extractLatLng(
          bookingData['location'] ?? bookingData['hirerLocation'],
        );
        if (jobLoc != null) {
          resolvedDest = jobLoc;
        }

        // Check Tier 2: workerSeedLocation on booking document
        resolvedOrigin = _extractLatLng(bookingData['workerSeedLocation']);
      }

      // Check Tier 1: RTDB liveTracking/$bookingId
      final rtdbSnap = await _rtdb.ref('liveTracking/$bookingId').get();
      if (rtdbSnap.exists && rtdbSnap.value is Map) {
        final model = LiveTelemetryModel.fromMap(
          rtdbSnap.value as Map<dynamic, dynamic>,
        );
        if (model.isValidCoordinate) {
          resolvedOrigin = model.latLng;
        }
      }

      // Check Tier 3: Worker's Firestore user profile
      if (resolvedOrigin == null &&
          resolvedWorkerId != null &&
          resolvedWorkerId.isNotEmpty) {
        final userSnap =
            await _firestore.collection('users').doc(resolvedWorkerId).get();
        final userData = userSnap.data();
        if (userData != null) {
          resolvedOrigin = _extractLatLng(
            userData['lastLocation'] ?? userData['location'],
          );
        }
      }

      final startPos = resolvedOrigin ?? resolvedDest;
      _updateState(
        _state.copyWith(
          workerAnimatedPosition: startPos,
          workerTargetPosition: startPos,
          hirerDestination: resolvedDest,
          arrivalOtp: arrivalOtp,
          workerName: workerName,
          workerPhone: workerPhone,
          workerCategory: workerCategory,
        ),
      );

      await _fetchAndApplyRoadRoute(startPos, resolvedDest);
    } catch (_) {}
  }

  void _listenToBookingDocument() {
    _bookingSub?.cancel();
    _bookingSub = _firestore
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString().toLowerCase();

      JourneyLifecyclePhase phase = _state.phase;
      if (status == 'in_progress' || status == 'working') {
        phase = JourneyLifecyclePhase.inProgress;
      } else if (status == 'arrived') {
        phase = JourneyLifecyclePhase.arrivedAtGate;
      }

      _updateState(
        _state.copyWith(
          phase: phase,
        ),
      );
    });

    _hirerSecureSub?.cancel();
    _hirerSecureSub = _firestore
        .collection('bookings')
        .doc(bookingId)
        .collection('hirer_secure')
        .doc('arrival_code')
        .snapshots()
        .listen((secSnap) {
      final secOtp = secSnap.data()?['arrivalOtp']?.toString().trim();
      if (secOtp != null && secOtp.isNotEmpty && secOtp != _state.arrivalOtp) {
        _updateState(_state.copyWith(arrivalOtp: secOtp));
      }
    }, onError: (_) {});
  }

  void _listenToRealtimeTelemetry() {
    _rtdbSub?.cancel();
    _rtdbSub = _rtdb
        .ref('liveTracking/$bookingId')
        .onValue
        .listen((DatabaseEvent event) async {
      final raw = event.snapshot.value;
      if (raw is! Map) return;

      final telemetry = LiveTelemetryModel.fromMap(raw);
      if (!telemetry.isValidCoordinate) return;

      // Reject out-of-order network packets
      if (telemetry.seq > 0 && telemetry.seq < _lastSequenceNumber) {
        return;
      }
      _lastSequenceNumber = telemetry.seq;
      _lastTelemetryReceivedAt =
          DateTime.fromMillisecondsSinceEpoch(telemetry.updatedAtMs);

      await _ingestTelemetryFix(telemetry);
    });
  }

  Future<void> _ingestTelemetryFix(LiveTelemetryModel fix) async {
    if (_state.fullRoutePolyline.length < 2) {
      await _fetchAndApplyRoadRoute(fix.latLng, _state.hirerDestination);
    }

    final snap = RoadSnapper.snapToPolyline(
      rawPoint: fix.latLng,
      polyline: _state.fullRoutePolyline,
      gpsHeading: fix.heading,
      speedMps: fix.speedMps,
      previousSegmentIndex: _lastSnappedSegmentIndex,
      isExactGoogleRoute: _isExactGoogleRoute,
    );

    if (snap.isSnapped) {
      _lastSnappedSegmentIndex = snap.segmentIndex;
    }

    // Hysteresis Off-Route Detector (3 consecutive strikes + 15s cooldown)
    if (snap.isOffRoute && !fix.isSeed) {
      _offRouteStrikeCount++;
      final canReroute = _lastRerouteAt == null ||
          DateTime.now().difference(_lastRerouteAt!).inSeconds >= 15;
      if (_offRouteStrikeCount >= 3 && canReroute && !_state.isRerouting) {
        _offRouteStrikeCount = 0;
        unawaited(_fetchAndApplyRoadRoute(fix.latLng, _state.hirerDestination, forceRefresh: true));
      }
    } else {
      _offRouteStrikeCount = 0;
    }

    // Exponential Moving Average (EMA) speed blending
    if (fix.speedMps >= 0.8) {
      _emaSpeedMps = (_emaSpeedMps * 0.65) + (fix.speedMps * 0.35);
    }
    final effectiveSpeedMps = _emaSpeedMps.clamp(3.2, 16.5);

    // Dynamic Road ETA with 22% urban intersection buffer
    final rawEtaSeconds =
        (snap.remainingRoadDistanceMeters / effectiveSpeedMps) * 1.22;
    final etaMinutes = (rawEtaSeconds / 60.0).ceil().clamp(1, 180);

    // Build Polyline-Crawl sub-path:
    // If snapped, crawl along road vertices; if on Google Maps shortcut (Free-Follow),
    // glide directly from current animated position to the live Kalman GPS position:
    _activeAnimationSubPath = snap.isSnapped
        ? RoadSnapper.extractSubPath(
            polyline: _state.fullRoutePolyline,
            fromPoint: _state.workerAnimatedPosition,
            toPoint: snap.snappedPoint,
          )
        : <LatLng>[_state.workerAnimatedPosition, snap.snappedPoint];

    _animStartBearing = _state.workerBearing;
    _animEndBearing = snap.roadBearing;

    // Lifecycle Phase Resolution
    JourneyLifecyclePhase resolvedPhase = _state.phase;
    if (resolvedPhase != JourneyLifecyclePhase.inProgress) {
      if (fix.status == 'arrived' || snap.remainingRoadDistanceMeters <= 35.0) {
        resolvedPhase = JourneyLifecyclePhase.arrivedAtGate;
      } else if (snap.remainingRoadDistanceMeters <= 250.0) {
        resolvedPhase = JourneyLifecyclePhase.arrivingSoon;
      } else if (!fix.isSeed) {
        resolvedPhase = JourneyLifecyclePhase.enRoute;
      }
    }

    final freshness = _evaluateFreshness(fix);

    _updateState(
      _state.copyWith(
        workerTargetPosition: snap.snappedPoint,
        activeRemainingPolyline: snap.remainingPolyline,
        traversedPolyline: snap.traversedPolyline,
        remainingDistanceMeters: snap.remainingRoadDistanceMeters,
        etaMinutes: etaMinutes,
        freshness: freshness,
        phase: resolvedPhase,
        isSnappedToRoad: snap.isSnapped,
        currentSpeedKmh: fix.speedMps * 3.6,
      ),
    );

    onTriggerFrameInterpolation?.call();
  }

  /// Called at 60fps by the UI's `AnimationController` with `t` in [0.0, 1.0].
  void onAnimationTick(double t) {
    if (_activeAnimationSubPath.isEmpty) return;

    final pose = RoadSnapper.interpolateAlongPath(
      path: _activeAnimationSubPath,
      t: t,
      fallbackStartBearing: _animStartBearing,
      fallbackEndBearing: _animEndBearing,
    );

    _updateState(
      _state.copyWith(
        workerAnimatedPosition: pose.position,
        workerBearing: pose.bearing,
      ),
    );
  }

  void _startFreshnessAndDeadReckoningMonitor() {
    _freshnessAndDeadReckonTimer?.cancel();
    _freshnessAndDeadReckonTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        final lastTime = _lastTelemetryReceivedAt;
        if (lastTime == null) return;

        final ageSec = DateTime.now().difference(lastTime).inSeconds;
        SignalFreshness nextFreshness;

        if (ageSec <= 10) {
          nextFreshness = SignalFreshness.live;
        } else if (ageSec <= 18) {
          nextFreshness = SignalFreshness.deadReckoning;
          // Dead-reckon forward gently along the remaining polyline if enRoute
          if (_state.phase == JourneyLifecyclePhase.enRoute &&
              _state.activeRemainingPolyline.length >= 2 &&
              _state.currentSpeedKmh >= 8.0) {
            final advanceMeters = (_emaSpeedMps * 0.55) * 2.0;
            final extrapolated = RoadSnapper.extrapolateAlongPolyline(
              remainingPolyline: _state.activeRemainingPolyline,
              distanceToAdvanceMeters: advanceMeters,
              currentBearing: _state.workerBearing,
            );
            _activeAnimationSubPath = [
              _state.workerAnimatedPosition,
              extrapolated.position,
            ];
            _animStartBearing = _state.workerBearing;
            _animEndBearing = extrapolated.bearing;
            onTriggerFrameInterpolation?.call();
          }
        } else if (ageSec <= 45) {
          nextFreshness = SignalFreshness.delayed;
        } else {
          nextFreshness = SignalFreshness.weakGps;
        }

        if (nextFreshness != _state.freshness) {
          _updateState(_state.copyWith(freshness: nextFreshness));
        }
      },
    );
  }

  SignalFreshness _evaluateFreshness(LiveTelemetryModel fix) {
    if (fix.isSeed) return SignalFreshness.weakGps;
    if (!fix.isOnline) return SignalFreshness.delayed;
    final ageSec = fix.age().inSeconds;
    if (ageSec <= 10) return SignalFreshness.live;
    if (ageSec <= 18) return SignalFreshness.deadReckoning;
    if (ageSec <= 45) return SignalFreshness.delayed;
    return SignalFreshness.weakGps;
  }

  Future<void> _fetchAndApplyRoadRoute(
    LatLng origin,
    LatLng destination, {
    bool forceRefresh = false,
  }) async {
    _updateState(_state.copyWith(isRerouting: true));
    _lastRerouteAt = DateTime.now();

    final route = await _routingRepository.fetchOrSyncSharedRoute(
      bookingId: bookingId,
      origin: origin,
      destination: destination,
      forceRefresh: forceRefresh,
    );
    _isExactGoogleRoute = route.isExactGoogleRoute;

    final snap = RoadSnapper.snapToPolyline(
      rawPoint: origin,
      polyline: route.polyline,
      isExactGoogleRoute: _isExactGoogleRoute,
    );
    _lastSnappedSegmentIndex = snap.segmentIndex;

    final etaMins = (route.durationSeconds / 60.0).ceil().clamp(1, 180);

    _updateState(
      _state.copyWith(
        fullRoutePolyline: route.polyline,
        activeRemainingPolyline: snap.remainingPolyline,
        traversedPolyline: snap.traversedPolyline,
        remainingDistanceMeters: snap.remainingRoadDistanceMeters,
        etaMinutes: etaMins,
        workerBearing: snap.roadBearing,
        isRerouting: false,
      ),
    );
  }

  LatLng? _extractLatLng(dynamic raw) {
    if (raw is GeoPoint) {
      final lat = raw.latitude;
      final lng = raw.longitude;
      if (!lat.isFinite || lat.isNaN || lat < -90.0 || lat > 90.0) return null;
      if (!lng.isFinite || lng.isNaN || lng < -180.0 || lng > 180.0) return null;
      return LatLng(lat, lng);
    }
    if (raw is Map) {
      final latVal = raw['lat'] ?? raw['latitude'];
      final lngVal = raw['lng'] ?? raw['longitude'];
      if (latVal is num && lngVal is num) {
        final lat = latVal.toDouble();
        final lng = lngVal.toDouble();
        if (!lat.isFinite || lat.isNaN || lat < -90.0 || lat > 90.0) return null;
        if (!lng.isFinite || lng.isNaN || lng < -180.0 || lng > 180.0) return null;
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  void _updateState(TrackingStateModel newState) {
    if (_isDisposed) return;
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _rtdbSub?.cancel();
    _bookingSub?.cancel();
    _hirerSecureSub?.cancel();
    _freshnessAndDeadReckonTimer?.cancel();
    super.dispose();
  }
}
