// lib/features/tracking/controllers/hirer_osm_tracking_controller.dart
// Production-grade 60fps controller switching between road-locked interpolation
// and Cubic Hermite spline interpolation for Google Maps worker to OSM/Valhalla hirer shadow sync.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../domain/gmaps_osm_shadow_engine.dart';
import '../domain/road_snapper.dart';
import '../data/models/live_telemetry_model.dart';
import '../data/models/tracking_state_model.dart';
import '../repositories/valhalla_osm_shadow_repository.dart';

class HirerOsmTrackingController extends ChangeNotifier {
  final String bookingId;
  final ValhallaOsmShadowRepository _shadowRepository;
  final GmapsOsmShadowEngine _shadowEngine = GmapsOsmShadowEngine();
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _rtdb;

  TrackingStateModel _state;
  TrackingStateModel get state => _state;

  TrackingGlideMode _glideMode = TrackingGlideMode.osmRoadLocked;
  TrackingGlideMode get glideMode => _glideMode;

  StreamSubscription<DatabaseEvent>? _rtdbSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bookingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _hirerSecureSub;
  Timer? _freshnessTimer;

  // 60fps trajectory state
  List<LatLng> _lockedSubPath = const [];
  LatLng _hermiteStartPos = const LatLng(12.9716, 77.5946);
  LatLng _hermiteEndPos = const LatLng(12.9716, 77.5946);
  double _animStartBearing = 0.0;
  double _animEndBearing = 0.0;

  int _lastSequenceNumber = -1;
  DateTime? _lastTelemetryReceivedAt;
  DateTime? _lastShadowRerouteAt;
  double _emaSpeedMps = 7.5;
  bool _isDisposed = false;

  VoidCallback? onTriggerFrameInterpolation;

  HirerOsmTrackingController({
    required this.bookingId,
    required LatLng initialHirerDestination,
    LatLng? initialWorkerFallback,
    String initialWorkerName = 'Service Partner',
    String initialWorkerPhone = '',
    String initialWorkerCategory = 'Specialist',
    ValhallaOsmShadowRepository? shadowRepository,
    FirebaseFirestore? firestore,
    FirebaseDatabase? rtdb,
  })  : _shadowRepository = shadowRepository ?? ValhallaOsmShadowRepository.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance,
        _state = TrackingStateModel(
          workerAnimatedPosition:
              initialWorkerFallback ?? initialHirerDestination,
          workerTargetPosition:
              initialWorkerFallback ?? initialHirerDestination,
          hirerDestination: initialHirerDestination,
          workerName: initialWorkerName,
          workerPhone: initialWorkerPhone,
          workerCategory: initialWorkerCategory,
        );

  Future<void> initialize() async {
    await _bootstrapInitialWaterfall();
    _listenToBookingDoc();
    _listenToHirerSecureDoc();
    _listenToWorkerRtdbStream();
    _startFreshnessMonitor();
  }

  Future<void> _bootstrapInitialWaterfall() async {
    try {
      final bookingSnap =
          await _firestore.collection('bookings').doc(bookingId).get();
      final data = bookingSnap.data();

      LatLng? origin;
      LatLng dest = _state.hirerDestination;
      String otp = _state.arrivalOtp;

      // 1. Try secure subcollection first (V21 Isolation)
      try {
        final secureSnap = await _firestore
            .collection('bookings')
            .doc(bookingId)
            .collection('hirer_secure')
            .doc('arrival_code')
            .get();
        if (secureSnap.exists && secureSnap.data() != null) {
          final sOtp = secureSnap.data()!['arrivalOtp']?.toString().trim();
          if (sOtp != null && sOtp.isNotEmpty && sOtp != '----' && sOtp != '------') {
            otp = sOtp;
          }
        }
      } catch (_) {}

      if (data != null) {
        if (otp == '----' || otp == '------' || otp.isEmpty) {
          // Self-heal arrivalOtp exclusively in isolated hirer_secure/arrival_code
          final generatedOtp =
              (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();
          otp = generatedOtp;
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? (data['hirerId']?.toString() ?? '');
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

        final jobLoc = _extractLatLng(
          data['jobLocation'] ??
              data['location'] ??
              data['hirerLocation'] ??
              (data['jobLat'] != null && data['jobLng'] != null
                  ? {'lat': data['jobLat'], 'lng': data['jobLng']}
                  : null),
        );
        if (jobLoc != null) dest = jobLoc;
        origin = _extractLatLng(data['workerSeedLocation']);
      }

      final rtdbSnap = await _rtdb.ref('liveTracking/$bookingId').get();
      if (rtdbSnap.exists && rtdbSnap.value is Map) {
        final model = LiveTelemetryModel.fromMap(
          rtdbSnap.value as Map<dynamic, dynamic>,
        );
        if (model.isValidCoordinate && !model.isSeed) {
          origin = model.latLng;
          _lastTelemetryReceivedAt =
              DateTime.fromMillisecondsSinceEpoch(model.updatedAtMs);
        }
      }

      final isRealOrigin = origin != null &&
          ((origin.latitude - dest.latitude).abs() > 0.0002 ||
              (origin.longitude - dest.longitude).abs() > 0.0002);

      if (isRealOrigin) {
        _hermiteStartPos = origin;
        _hermiteEndPos = origin;

        _updateState(
          _state.copyWith(
            workerAnimatedPosition: origin,
            workerTargetPosition: origin,
            hirerDestination: dest,
            arrivalOtp: otp,
          ),
        );

        await _recomputeValhallaShadowRoute(
          workerPos: origin,
          destination: dest,
        );
      } else {
        // Worker has not started moving yet: keep at destination or initial fallback
        // but DO NOT compute a 0m route and DO NOT set phase to arrived!
        _updateState(
          _state.copyWith(
            workerAnimatedPosition: _state.workerAnimatedPosition,
            workerTargetPosition: _state.workerTargetPosition,
            hirerDestination: dest,
            arrivalOtp: otp,
            phase: JourneyLifecyclePhase.accepted,
            remainingDistanceMeters: 0.0,
            etaMinutes: 0,
            freshness: SignalFreshness.weakGps,
          ),
        );
      }
    } catch (_) {}
  }

  void _listenToBookingDoc() {
    _bookingSub?.cancel();
    _bookingSub = _firestore
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final otp = _state.arrivalOtp;
      final status = (data['status'] ?? '').toString().toLowerCase();

      JourneyLifecyclePhase phase = _state.phase;
      if (status == 'in_progress' || status == 'working') {
        phase = JourneyLifecyclePhase.inProgress;
      } else if (status == 'arrived') {
        phase = JourneyLifecyclePhase.arrivedAtGate;
      } else if (status == 'tracking' || status == 'on_the_way') {
        if (phase == JourneyLifecyclePhase.accepted) {
          phase = JourneyLifecyclePhase.enRoute;
        }
      } else if (status == 'confirmed' ||
          status == 'accepted' ||
          status == 'pending') {
        if (phase != JourneyLifecyclePhase.inProgress) {
          phase = JourneyLifecyclePhase.accepted;
        }
      }

      _updateState(_state.copyWith(arrivalOtp: otp, phase: phase));
    });
  }

  void _listenToHirerSecureDoc() {
    _hirerSecureSub?.cancel();
    _hirerSecureSub = _firestore
        .collection('bookings')
        .doc(bookingId)
        .collection('hirer_secure')
        .doc('arrival_code')
        .snapshots()
        .listen((snap) {
      if (!snap.exists || snap.data() == null) return;
      final secureOtp = snap.data()!['arrivalOtp']?.toString().trim();
      if (secureOtp != null &&
          secureOtp.isNotEmpty &&
          secureOtp != '----' &&
          secureOtp != _state.arrivalOtp) {
        _updateState(_state.copyWith(arrivalOtp: secureOtp));
      }
    }, onError: (_) {});
  }

  void _listenToWorkerRtdbStream() {
    _rtdbSub?.cancel();
    _rtdbSub = _rtdb
        .ref('liveTracking/$bookingId')
        .onValue
        .listen((DatabaseEvent event) async {
      final raw = event.snapshot.value;
      if (raw is! Map) return;

      final fix = LiveTelemetryModel.fromMap(raw);
      if (!fix.isValidCoordinate) return;

      if (fix.seq > 0 && fix.seq < _lastSequenceNumber) return;
      _lastSequenceNumber = fix.seq;
      _lastTelemetryReceivedAt =
          DateTime.fromMillisecondsSinceEpoch(fix.updatedAtMs);

      // Extract rolling 5-point micro-trail sent by worker background service
      final microTrail = <LatLng>[];
      final rawTrail = raw['trail'];
      if (rawTrail is List) {
        for (final item in rawTrail) {
          if (item is Map) {
            final lat = (item['lat'] as num?)?.toDouble();
            final lng = (item['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              microTrail.add(LatLng(lat, lng));
            }
          }
        }
      }

      await _processIncomingWorkerFix(fix, microTrail);
    });
  }

  Future<void> _processIncomingWorkerFix(
    LiveTelemetryModel fix,
    List<LatLng> microTrail,
  ) async {
    if (_state.fullRoutePolyline.length < 2) {
      await _recomputeValhallaShadowRoute(
        workerPos: fix.latLng,
        destination: _state.hirerDestination,
        headingDeg: fix.heading,
        speedMps: fix.speedMps,
      );
    }

    // Run the Dual-Mode Google-Maps-to-OSM Shadow Engine
    final shadow = _shadowEngine.processWorkerFix(
      kalmanPosition: fix.latLng,
      gpsHeading: fix.heading,
      speedMps: fix.speedMps,
      valhallaPolyline: _state.fullRoutePolyline,
      destination: _state.hirerDestination,
      recentWorkerMicroTrail: microTrail,
    );

    _glideMode = shadow.mode;

    // Trigger Heading-Biased Valhalla Shadow Reroute if worker took a Google Maps shortcut
    // (10-second cooldown prevents API spam while rapidly adapting the OSM line to Google Maps)
    final canReroute = _lastShadowRerouteAt == null ||
        DateTime.now().difference(_lastShadowRerouteAt!).inSeconds >= 10;

    if (shadow.shouldTriggerShadowReroute &&
        !fix.isSeed &&
        canReroute &&
        !_state.isRerouting) {
      unawaited(
        _recomputeValhallaShadowRoute(
          workerPos: fix.latLng,
          destination: _state.hirerDestination,
          headingDeg: fix.heading,
          speedMps: fix.speedMps,
        ),
      );
    }

    // Configure 60fps animation parameters for either RoadLocked or CubicHermite Free-Glide
    _hermiteStartPos = _state.workerAnimatedPosition;
    _hermiteEndPos = shadow.effectivePosition;
    _animStartBearing = _state.workerBearing;
    _animEndBearing = shadow.effectiveBearing;

    if (shadow.mode == TrackingGlideMode.osmRoadLocked) {
      _lockedSubPath = RoadSnapper.extractSubPath(
        polyline: _state.fullRoutePolyline,
        fromPoint: _state.workerAnimatedPosition,
        toPoint: shadow.effectivePosition,
      );
    } else {
      _lockedSubPath = const [];
    }

    // Dynamic Urban Speed EMA + Road ETA
    if (fix.speedMps >= 0.8) {
      _emaSpeedMps = (_emaSpeedMps * 0.65) + (fix.speedMps * 0.35);
    }
    final clampedSpeed = _emaSpeedMps.clamp(3.2, 16.5);
    final etaSeconds = (shadow.remainingRoadDistanceMeters / clampedSpeed) * 1.2;
    final etaMinutes = (etaSeconds / 60.0).ceil().clamp(1, 180);

    // Resolve Journey Phase
    JourneyLifecyclePhase phase = _state.phase;
    if (phase != JourneyLifecyclePhase.inProgress) {
      if (fix.status == 'arrived' ||
          (!fix.isSeed &&
              shadow.remainingRoadDistanceMeters > 0 &&
              shadow.remainingRoadDistanceMeters <= 35.0 &&
              phase != JourneyLifecyclePhase.accepted)) {
        phase = JourneyLifecyclePhase.arrivedAtGate;
      } else if (fix.status == 'approaching' ||
          (!fix.isSeed &&
              shadow.remainingRoadDistanceMeters > 0 &&
              shadow.remainingRoadDistanceMeters <= 150.0 &&
              phase != JourneyLifecyclePhase.accepted)) {
        phase = JourneyLifecyclePhase.arrivingSoon;
      } else if (!fix.isSeed &&
          (fix.status == 'on_the_way' || fix.status == 'tracking')) {
        phase = JourneyLifecyclePhase.enRoute;
      }
    }

    _updateState(
      _state.copyWith(
        workerTargetPosition: shadow.effectivePosition,
        activeRemainingPolyline: shadow.activeRoutePolyline,
        traversedPolyline: shadow.traversedBreadcrumbPolyline,
        remainingDistanceMeters: shadow.remainingRoadDistanceMeters,
        etaMinutes: etaMinutes,
        freshness: fix.isSeed ? SignalFreshness.weakGps : SignalFreshness.live,
        phase: phase,
        isSnappedToRoad: shadow.mode == TrackingGlideMode.osmRoadLocked,
        currentSpeedKmh: fix.speedMps * 3.6,
      ),
    );

    onTriggerFrameInterpolation?.call();
  }

  /// Driven at 60fps by `HirerTrackingScreen`'s `AnimationController`.
  void onAnimationTick(double t) {
    final TrajectoryPose pose;

    if (_glideMode == TrackingGlideMode.osmRoadLocked &&
        _lockedSubPath.length >= 2) {
      // Crawl along exact OSM road vertices when locked
      pose = RoadSnapper.interpolateAlongPath(
        path: _lockedSubPath,
        t: t,
        fallbackStartBearing: _animStartBearing,
        fallbackEndBearing: _animEndBearing,
      );
    } else {
      // Smooth Cubic Hermite kinematic curve when gliding along a Google Maps shortcut
      pose = CubicHermiteSplineInterpolator.interpolate(
        startPos: _hermiteStartPos,
        startBearingDeg: _animStartBearing,
        endPos: _hermiteEndPos,
        endBearingDeg: _animEndBearing,
        t: t,
      );
    }

    _updateState(
      _state.copyWith(
        workerAnimatedPosition: pose.position,
        workerBearing: pose.bearing,
      ),
    );
  }

  Future<void> _recomputeValhallaShadowRoute({
    required LatLng workerPos,
    required LatLng destination,
    double? headingDeg,
    double speedMps = 0.0,
  }) async {
    _updateState(_state.copyWith(isRerouting: true));
    _lastShadowRerouteAt = DateTime.now();

    final route = await _shadowRepository.fetchShadowRoute(
      bookingId: bookingId,
      workerPosition: workerPos,
      destination: destination,
      workerHeadingDeg: headingDeg,
      workerSpeedMps: speedMps,
    );

    final shadow = _shadowEngine.processWorkerFix(
      kalmanPosition: workerPos,
      gpsHeading: headingDeg ?? _state.workerBearing,
      speedMps: speedMps,
      valhallaPolyline: route.polyline,
      destination: destination,
    );

    _updateState(
      _state.copyWith(
        fullRoutePolyline: route.polyline,
        activeRemainingPolyline: shadow.activeRoutePolyline,
        traversedPolyline: shadow.traversedBreadcrumbPolyline,
        remainingDistanceMeters: shadow.remainingRoadDistanceMeters,
        etaMinutes: (route.durationSeconds / 60.0).ceil().clamp(1, 180),
        isRerouting: false,
      ),
    );
  }

  void _startFreshnessMonitor() {
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final last = _lastTelemetryReceivedAt;
      if (last == null) {
        if (_state.phase == JourneyLifecyclePhase.accepted &&
            _state.freshness != SignalFreshness.weakGps) {
          _updateState(_state.copyWith(freshness: SignalFreshness.weakGps));
        }
        return;
      }
      final age = DateTime.now().difference(last).inSeconds;
      final next = age <= 15
          ? SignalFreshness.live
          : (age <= 45 ? SignalFreshness.deadReckoning : SignalFreshness.delayed);
      if (next != _state.freshness) {
        _updateState(_state.copyWith(freshness: next));
      }
    });
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

  void _updateState(TrackingStateModel next) {
    if (_isDisposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _rtdbSub?.cancel();
    _bookingSub?.cancel();
    _hirerSecureSub?.cancel();
    _freshnessTimer?.cancel();
    super.dispose();
  }
}
