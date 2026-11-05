// lib/services/navigation_engine.dart
// ================================================================
// KELASAGARA — NavigationEngine
// The full brain of the routing system.
// Combines: GPS filtering, snap-to-road, step tracking,
// off-route detection with auto-rerouting, ETA engine,
// arrival detection, Kannada+English TTS voice guidance,
// and throttled Firebase RTDB publishing.
// ================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/route_result.dart';
import 'navigation/routing_facade.dart';
import 'routing/gps_quality_engine.dart';
import '../features/tracking/domain/arrival_eligibility_policy.dart';

// ── NavState — emitted on Stream<NavState> ────────────────────────────────────
class NavState {
  final LatLng  rawPosition;
  final LatLng  snappedPosition;
  final double  heading;           // degrees 0–360
  final double  speedKmh;
  final double  accuracy;          // metres

  final RouteStep? currentStep;
  final RouteStep? nextStep;
  final double  distanceToNextTurnM;
  final double  remainingDistanceM;
  final int     remainingSeconds;
  final String  etaString;         // "12 min"
  final String  arrivalTimeString; // "9:15 AM"
  final int     currentStepIndex;
  final List<LatLng> passedPolyline;
  final List<LatLng> remainingPolyline;

  final bool isRerouting;
  final bool isSnapped;
  final bool hasArrived;
  final bool isOffRoute;
  final String? rerouteMessage;

  const NavState({
    required this.rawPosition,
    required this.snappedPosition,
    required this.heading,
    required this.speedKmh,
    required this.accuracy,
    this.currentStep,
    this.nextStep,
    required this.distanceToNextTurnM,
    required this.remainingDistanceM,
    required this.remainingSeconds,
    required this.etaString,
    required this.arrivalTimeString,
    required this.currentStepIndex,
    required this.passedPolyline,
    required this.remainingPolyline,
    required this.isRerouting,
    required this.isSnapped,
    required this.hasArrived,
    required this.isOffRoute,
    this.rerouteMessage,
  });

  NavState copyWith({
    LatLng? rawPosition, LatLng? snappedPosition,
    double? heading, double? speedKmh, double? accuracy,
    RouteStep? currentStep, RouteStep? nextStep,
    double? distanceToNextTurnM, double? remainingDistanceM,
    int? remainingSeconds, String? etaString, String? arrivalTimeString,
    int? currentStepIndex, List<LatLng>? passedPolyline,
    List<LatLng>? remainingPolyline, bool? isRerouting, bool? isSnapped,
    bool? hasArrived, bool? isOffRoute, String? rerouteMessage,
  }) => NavState(
    rawPosition:          rawPosition          ?? this.rawPosition,
    snappedPosition:      snappedPosition      ?? this.snappedPosition,
    heading:              heading              ?? this.heading,
    speedKmh:             speedKmh             ?? this.speedKmh,
    accuracy:             accuracy             ?? this.accuracy,
    currentStep:          currentStep          ?? this.currentStep,
    nextStep:             nextStep             ?? this.nextStep,
    distanceToNextTurnM:  distanceToNextTurnM  ?? this.distanceToNextTurnM,
    remainingDistanceM:   remainingDistanceM   ?? this.remainingDistanceM,
    remainingSeconds:     remainingSeconds     ?? this.remainingSeconds,
    etaString:            etaString            ?? this.etaString,
    arrivalTimeString:    arrivalTimeString    ?? this.arrivalTimeString,
    currentStepIndex:     currentStepIndex     ?? this.currentStepIndex,
    passedPolyline:       passedPolyline       ?? this.passedPolyline,
    remainingPolyline:    remainingPolyline    ?? this.remainingPolyline,
    isRerouting:          isRerouting          ?? this.isRerouting,
    isSnapped:            isSnapped            ?? this.isSnapped,
    hasArrived:           hasArrived           ?? this.hasArrived,
    isOffRoute:           isOffRoute           ?? this.isOffRoute,
    rerouteMessage:       rerouteMessage       ?? this.rerouteMessage,
  );
}

// ── NavigationEngine ──────────────────────────────────────────────────────────
class NavigationEngine {
  NavigationEngine._();
  static final NavigationEngine instance = NavigationEngine._();

  // ── Config ────────────────────────────────────────────────────────────────
  // V600: _maxAccuracyM removed — accuracy filtering now in GpsQualityEngine
  // V600: _snapIntervalMs removed — snap-to-road timer eliminated (Bug #4)
  static const double _maxSpeedKmh         = 150.0;  // hard cap for safety
  static const double _offRouteThresholdM  = 50.0;   // perpendicular dist
  static const int    _offRouteGraceCount  = 3;      // ticks before reroute
  static const double _voiceWarningM       = 300.0;  // first TTS trigger
  static const double _voiceNowM           = 80.0;   // second TTS trigger
  static const int    _rtdbThrottleMs      = 2000;   // RTDB push interval
  static const int    _etaUpdateIntervalMs = 5000;   // ETA recalc interval
  static const int    _speedRingSize       = 10;     // GPS speed history

  // ── State ─────────────────────────────────────────────────────────────────
  final StreamController<NavState> _ctrl =
      StreamController<NavState>.broadcast();
  Stream<NavState> get stream => _ctrl.stream;
  NavState? _current;
  NavState? get current => _current;

  RouteResult? _route;
  LatLng?      _destination;
  String?      _bookingId;
  bool         _voiceEnabled = true;
  bool         _running = false;
  bool         _hasArrived = false;
  bool         get isRunning => _running;

  // Sub-system state
  StreamSubscription<Position>? _gpsSub;
  // _snapTimer removed — snap-to-road eliminated in V600
  Timer?  _etaTimer;
  Timer?  _rtdbTimer;

  final List<Position>  _gpsBuffer    = [];   // kept for polyline index smoothing
  final List<double>    _speedBuffer  = [];   // for ETA smoothing
  int     _offRouteCount  = 0;
  bool    _isRerouting    = false;
  int     _rerouteBackoff = 0;   // seconds
  int     _currentStepIdx = 0;
  int     _seq = 0;
  String  _sessionId = '';

  // V900 Forensic Repair: tracking fields for robust speed derivation and snapping
  Position? _lastValidPos;
  DateTime? _lastPosTime;
  int       _arrivalCandidateCount = 0;
  static const int _arrivalRequiredStableFixes = 2;
  DateTime? _lastRerouteTime;
  int       _currentPolylineSegmentIdx = 0;

  // V400: Route versioning — discard stale async reroute responses
  int     _routeVersion   = 0;

  // V600: _originalCosting removed — RoutingOrchestrator handles costing internally

  // V400: Max consecutive reroute failures before showing manual nav
  int     _consecutiveRerouteFails = 0;
  static const int _maxRerouteAttempts = 3;

  // Voice TTS state
  final FlutterTts _tts = FlutterTts();
  Object _speechSessionToken = Object();
  bool  _voice300mFired = false;
  bool  _voice80mFired  = false;

  // RTDB
  DateTime? _lastRtdbPush;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Feeds a validated GPS position directly into NavigationEngine.
  /// Called by JourneyService so a single high-accuracy GPS stream is shared.
  void feedGpsPosition(Position pos) {
    if (_running) _onGps(pos);
  }

  /// Start navigation on a given route toward destination.
  /// Call this after worker taps "Start Journey".
  Future<void> start({
    required RouteResult route,
    required LatLng      destination,
    required String      bookingId,
    bool voiceEnabled = true,
    bool manageGpsStream = false,
  }) async {
    if (_running) await stop();

    _route        = route;
    _destination  = destination;
    _bookingId    = bookingId;
    _voiceEnabled = voiceEnabled;
    _running      = true;
    _hasArrived   = false;
    _currentStepIdx = 0;
    _offRouteCount  = 0;
    _rerouteBackoff = 0;
    _seq            = 0;
    _sessionId      = '${bookingId}_${DateTime.now().millisecondsSinceEpoch}';
    _lastValidPos   = null;
    _lastPosTime    = null;
    _arrivalCandidateCount = 0;
    _lastRerouteTime = null;
    _currentPolylineSegmentIdx = 0;
    _gpsBuffer.clear();
    _speedBuffer.clear();

    await _initTts();

    // V600 FIX: Reset GPS quality history for clean new session
    GpsQualityEngine.instance.reset();

    // If manageGpsStream is true (e.g. standalone mode/testing), open GPS stream.
    // In production journey flow, JourneyService manages the single high-accuracy stream
    // and feeds it via feedGpsPosition() to prevent dual-stream lock contention.
    if (manageGpsStream) {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy:         LocationAccuracy.high,
          intervalDuration: const Duration(seconds: 1),
          distanceFilter:   2,
        ),
      ).listen(
        _onGps,
        onError: (e) => debugPrint('[NavEngine] GPS stream error: $e'),
        cancelOnError: false,
      );
    }

    // V600 FIX: Snap-to-road timer REMOVED.
    // _doSnap() called ValhallaService.snapToRoad (/trace_attributes) every 3s
    // creating a 3rd concurrent HTTP request to Valhalla during rerouting.
    // NavigationEngine._nearestPolylineIndex() provides equivalent snap-to-route
    // projection without any network call. Removing snap eliminates the 3rd
    // Valhalla caller and reduces reroute + snap collisions.

    // ETA recalc every 5s
    _etaTimer = Timer.periodic(
      const Duration(milliseconds: _etaUpdateIntervalMs), (_) => _recalcEta());

    debugPrint('[NavEngine] ✅ Started | route: ${route.distanceText} / ${route.etaText}');

    // Announce departure
    if (_voiceEnabled) {
      await Future.delayed(const Duration(seconds: 2));
      _speak('Navigation started. ${route.distanceText} to destination.',
             '${route.distanceText} ದೂರ. ಪ್ರಯಾಣ ಪ್ರಾರಂಭ.');
    }
  }

  Future<void> stop() async {
    _running = false;
    _speechSessionToken = Object(); // Invalidate all pending or delayed TTS speech
    _gpsSub?.cancel();
    // _snapTimer removed in V600 — snap-to-road eliminated
    _etaTimer?.cancel();
    _rtdbTimer?.cancel();
    _gpsSub   = null;
    _etaTimer  = null;
    _rtdbTimer = null;
    _route     = null;
    try {
      await _tts.stop();
    } catch (_) {}
    
    // Clear session state to prevent state leaking across sessions/screens
    _sessionId = '';
    _bookingId = null;
    _current = null;
    _destination = null;
    _routeVersion = 0;
    _isRerouting = false;
    _offRouteCount = 0;
    _arrivalCandidateCount = 0;
    _lastValidPos = null;
    _lastPosTime = null;
    _lastRerouteTime = null;
    _currentPolylineSegmentIdx = 0;
    _gpsBuffer.clear();
    _speedBuffer.clear();

    debugPrint('[NavEngine] ⏹ Stopped');
  }

  void pauseVoice()  => _voiceEnabled = false;
  void resumeVoice() => _voiceEnabled = true;

  void setVoiceEnabled(bool enabled) {
    _voiceEnabled = enabled;
    if (!enabled) {
      _speechSessionToken = Object();
      try {
        _tts.stop().catchError((_) => null);
      } catch (_) {}
    }
  }

  void setMuted(bool muted) => setVoiceEnabled(!muted);

  void repeatInstruction() {
    if (!_running || _current == null) return;
    final step = _current!.currentStep;
    if (step != null) {
      _speak(step.instruction, step.instructionKn);
    }
  }

  void onLocation(Position pos) => feedGpsPosition(pos);

  void feedLiveLocation(dynamic loc) {
    if (loc is Position) {
      feedGpsPosition(loc);
    } else {
      feedGpsPosition(Position(
        latitude: (loc.latitude as num).toDouble(),
        longitude: (loc.longitude as num).toDouble(),
        timestamp: loc.timestamp as DateTime,
        accuracy: (loc.accuracy as num).toDouble(),
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: (loc.heading as num).toDouble(),
        headingAccuracy: 0.0,
        speed: ((loc.speed as num).toDouble()) / 3.6,
        speedAccuracy: 0.0,
      ));
    }
  }

  Future<void> forceReroute() async {
    if (_current == null || _destination == null) return;
    await _triggerReroute(_current!.snappedPosition);
  }

  // ── GPS handler ───────────────────────────────────────────────────────────
  void _onGps(Position pos) {
    if (!_running) return;

    // V600 FIX: Route every Position through GpsQualityEngine (8-level classifier)
    // instead of the old ad-hoc accuracy+speed filter.
    // classify() returns ClassifiedPosition; .classification is the GpsClassification enum.
    // Rejects: INVALID, GPS_JUMP, MOCK_SUSPECTED, DUPLICATE.
    // Allows:  GOOD, LIVE, LOW_ACCURACY, STALE (with degraded mode notification).
    final classified = GpsQualityEngine.instance.classify(pos);
    switch (classified.classification) {
      case GpsClassification.INVALID:
      case GpsClassification.GPS_JUMP:
      case GpsClassification.MOCK_SUSPECTED:
      case GpsClassification.DUPLICATE:
        debugPrint('[NavEngine] GPS rejected: ${classified.classification} '
            '(acc=${pos.accuracy.toStringAsFixed(0)}m)');
        return;
      case GpsClassification.LOW_ACCURACY:
      case GpsClassification.STALE:
        // Allow but note degraded quality — do NOT reject to avoid GPS blackout
        debugPrint('[NavEngine] GPS degraded: ${classified.classification}');
        break;
      default:
        break; // GOOD, LIVE — proceed normally
    }

    // V900 Speed engine: use hardware speed if valid (> 0), or derive from displacement delta
    double rawSpeedKmh = 0.0;
    if (pos.speed > 0) {
      rawSpeedKmh = (pos.speed * 3.6).clamp(0.0, _maxSpeedKmh);
    } else if (_lastValidPos != null && _lastPosTime != null) {
      final dt = pos.timestamp.difference(_lastPosTime!).inMilliseconds / 1000.0;
      if (dt >= 0.5 && dt <= 10.0) {
        const d = Distance();
        final distM = d.as(
          LengthUnit.Meter,
          LatLng(pos.latitude, pos.longitude),
          LatLng(_lastValidPos!.latitude, _lastValidPos!.longitude),
        );
        rawSpeedKmh = ((distM / dt) * 3.6).clamp(0.0, _maxSpeedKmh);
      }
    }
    _lastValidPos = pos;
    _lastPosTime = pos.timestamp;

    final double speedKmh;
    if (rawSpeedKmh < 2.0) {
      speedKmh = 0.0; // Stationary suppression
    } else {
      final prevSpeed = (_current?.speedKmh != null && _current!.speedKmh >= 2.0)
          ? _current!.speedKmh
          : rawSpeedKmh;
      speedKmh = (0.35 * rawSpeedKmh + 0.65 * prevSpeed).clamp(0.0, _maxSpeedKmh);
    }
    _speedBuffer.add(speedKmh);
    if (_speedBuffer.length > _speedRingSize) _speedBuffer.removeAt(0);

    // Smooth heading: preserve previous heading when stopped (< 2 km/h) to prevent map spinning
    final rawHeading = pos.heading < 0 ? 0.0 : pos.heading;
    final prevHeading = _current?.heading ?? rawHeading;
    final heading = (speedKmh == 0.0 && _current != null)
        ? _current!.heading
        : _lerpAngle(prevHeading, rawHeading, 0.35);

    // 5-point sliding window
    _gpsBuffer.add(pos);
    if (_gpsBuffer.length > 5) _gpsBuffer.removeAt(0);

    final rawLatLng = LatLng(pos.latitude, pos.longitude);
    final poly = _route?.polyline ?? const [];

    // V900 Forensic Fix: Project rawLatLng onto route polyline dynamically.
    // NEVER reuse old snapped position!
    final projection = _projectOntoPolyline(
      rawLatLng,
      poly,
      hintIndex: _currentPolylineSegmentIdx,
      maxSnapDistanceM: 25.0,
    );
    final snapped = projection.position;
    final isSnapped = projection.isSnapped;
    _currentPolylineSegmentIdx = projection.nearestSegmentIndex;

    // Update step tracking with nearest segment index
    _updateStepTracking(rawLatLng, snapped, projection.nearestSegmentIndex);

    // Off-route detection with persistent state filter and accuracy gating
    _checkOffRoute(rawLatLng, projection.distanceM, pos.accuracy);

    // Arrival detection with candidate stability gating
    _checkArrival(rawLatLng, _current?.remainingDistanceM ?? 0.0, pos.accuracy);

    // Publish state
    _emitState(
      raw:       rawLatLng,
      snapped:   snapped,
      heading:   heading,
      speed:     speedKmh,
      accuracy:  pos.accuracy,
      isSnapped: isSnapped,
    );

    // Push to RTDB
    _maybePublishRtdb();
  }

  // ── Snap to road ──────────────────────────────────────────────────────────
  // Handled dynamically by _projectOntoPolyline() and _projectOntoSegment().

  // ── Step tracking ─────────────────────────────────────────────────────────
  void _updateStepTracking(LatLng rawPos, LatLng snappedPos, int segmentIdx) {
    final route = _route;
    if (route == null || route.polyline.isEmpty) return;

    final nearestIdx = segmentIdx.clamp(0, route.polyline.length - 1);
    final cumDist    = route.cumulativeDistances.isNotEmpty
        ? route.cumulativeDistances
        : RouteResult.buildCumDist(route.polyline);
    final totalLen   = route.totalPolylineLength;

    // Find current step
    int stepIdx = _currentStepIdx;
    final steps = route.steps;
    if (steps.isNotEmpty) {
      // Advance step if we've passed its end (valid for Valhalla, Mapbox, and OSRM)
      while (stepIdx < steps.length - 1 &&
             steps[stepIdx].polylineEndIndex > 0 &&
             nearestIdx >= steps[stepIdx].polylineEndIndex) {
        stepIdx++;
        _onStepAdvance(stepIdx);
      }
      _currentStepIdx = stepIdx;
    }

    // Distances
    final coveredDist   = cumDist.isNotEmpty ? cumDist[nearestIdx] : 0.0;
    final remainingDist = (totalLen - coveredDist).clamp(0.0, double.infinity);

    // Distance to next turn
    double distToNext = remainingDist;
    if (stepIdx < steps.length) {
      final nextStepStart = steps[stepIdx].polylineStartIndex;
      if (cumDist.isNotEmpty && nextStepStart < cumDist.length && nextStepStart >= nearestIdx) {
        distToNext = (cumDist[nextStepStart] - coveredDist).clamp(0.0, double.infinity);
      }
    }

    // Split polyline
    final passed    = route.polyline.sublist(0, nearestIdx.clamp(0, route.polyline.length));
    final remaining = route.polyline.sublist(nearestIdx.clamp(0, route.polyline.length));

    // Trigger voice at 300m and 80m before next turn
    if (stepIdx < steps.length) {
      if (distToNext <= _voiceWarningM && !_voice300mFired) {
        _voice300mFired = true;
        _voice80mFired  = false;
        final step = steps[stepIdx];
        _speak(
          'In ${distToNext.round()} metres, ${step.instruction}',
          '${distToNext.round()} ಮೀಟರ್‌ನಲ್ಲಿ, ${step.instructionKn}',
        );
      }
      if (distToNext <= _voiceNowM && !_voice80mFired) {
        _voice80mFired = true;
        final step = steps[stepIdx];
        _speak(step.instruction, step.instructionKn);
      }
    }

    // Update state with new distances and polylines
    if (_current != null) {
      _current = _current!.copyWith(
        currentStepIndex:    stepIdx,
        currentStep:         stepIdx < steps.length ? steps[stepIdx] : null,
        nextStep:            stepIdx + 1 < steps.length ? steps[stepIdx + 1] : null,
        distanceToNextTurnM: distToNext,
        remainingDistanceM:  remainingDist,
        passedPolyline:      passed,
        remainingPolyline:   remaining,
      );
    }
  }

  void _onStepAdvance(int newStepIdx) {
    debugPrint('[NavEngine] Step advanced → $newStepIdx');
    _voice300mFired = false;
    _voice80mFired  = false;
  }

  // ── Off-route detection ───────────────────────────────────────────────────
  void _checkOffRoute(LatLng pos, double distToPolylineM, double accuracy) {
    if (_route == null || _isRerouting || _hasArrived) return;

    if (distToPolylineM > _offRouteThresholdM && accuracy <= 40.0) {
      _offRouteCount++;
      debugPrint('[NavEngine] Off-route: ${distToPolylineM.round()}m (count: $_offRouteCount, acc: ${accuracy.round()}m)');
      if (_offRouteCount >= _offRouteGraceCount) {
        final now = DateTime.now();
        if (_lastRerouteTime == null || now.difference(_lastRerouteTime!).inSeconds >= 15) {
          _lastRerouteTime = now;
          _triggerReroute(pos);
        }
      }
    } else {
      _offRouteCount = 0;
    }

    if (_current != null) {
      _current = _current!.copyWith(isOffRoute: distToPolylineM > _offRouteThresholdM);
    }
  }

  Future<void> _triggerReroute(LatLng from) async {
    if (_isRerouting || !_running) return;

    // V400: Max reroute attempts — don't spam the routing server
    if (_consecutiveRerouteFails >= _maxRerouteAttempts) {
      debugPrint('[NavEngine] Max reroute attempts reached — manual navigation');
      if (_current != null) {
        _current = _current!.copyWith(
          isRerouting: false,
          isOffRoute: true,
          rerouteMessage: 'Could not find route. Please navigate manually.',
        );
        _ctrl.add(_current!);
      }
      return;
    }

    // Exponential backoff
    if (_rerouteBackoff > 0) {
      debugPrint('[NavEngine] Reroute backoff: ${_rerouteBackoff}s');
      await Future.delayed(Duration(seconds: _rerouteBackoff));
    }

    _isRerouting   = true;
    _offRouteCount = 0;

    // V400: Increment route version BEFORE request so stale responses are detected
    final requestVersion = ++_routeVersion;
    final requestSessionId = _sessionId;

    debugPrint('[NavEngine] ↺ Rerouting from $from (v$requestVersion, session: $requestSessionId)');

    if (_current != null) {
      _current = _current!.copyWith(isRerouting: true, rerouteMessage: 'Recalculating...');
      _ctrl.add(_current!);
    }

    if (_voiceEnabled) {
      _speak('Recalculating route.', 'ಮಾರ್ಗ ಮರು ಲೆಕ್ಕ ಹಾಕುತ್ತಿದ್ದೇನೆ.');
    }

    try {
      // Production Valhalla Reroute via RoutingFacade (Zero fallback to public demo/secondary routers)
      final newRoute = await RoutingFacade.instance.calculateRoute(
        origin: from,
        destination: _destination!,
        sessionId: requestSessionId,
        routeVersion: requestVersion,
        timeout: const Duration(seconds: 8),
      );

      // Discard stale response if session ended, switched, or newer reroute was triggered
      if (!_running || requestSessionId != _sessionId || requestVersion < _routeVersion) {
        debugPrint('[NavEngine] Discarding stale reroute v$requestVersion (current: v$_routeVersion, running: $_running)');
        _isRerouting = false;
        return;
      }

      _route          = newRoute;
      _currentStepIdx = 0;
      _voice300mFired = false;
      _voice80mFired  = false;
      _rerouteBackoff = 0;
      _isRerouting    = false;
      _consecutiveRerouteFails = 0;

      if (_current != null) {
        _current = _current!.copyWith(
          isRerouting:  false,
          isOffRoute:   false,
          rerouteMessage: 'Route found',
        );
        _ctrl.add(_current!);
      }

      if (_voiceEnabled) {
        _speak(
          'Route found. ${newRoute.distanceText} remaining.',
          'ಹೊಸ ಮಾರ್ಗ ಸಿಕ್ಕಿದೆ. ${newRoute.distanceText} ಉಳಿದಿದೆ.',
        );
      }
      debugPrint('[NavEngine] ✅ Reroute complete: ${newRoute.distanceText} / ${newRoute.etaText}');
    } on StaleRouteException {
      _isRerouting = false;
      debugPrint('[NavEngine] Stale reroute superseded — ignoring');
    } catch (e) {
      _isRerouting    = false;
      _consecutiveRerouteFails++;
      _rerouteBackoff = math.min((_rerouteBackoff == 0 ? 30 : _rerouteBackoff * 2), 120);
      debugPrint('[NavEngine] Reroute error: $e');
      if (_current != null) {
        _current = _current!.copyWith(
          isRerouting: false,
          rerouteMessage: 'Route update unavailable',
        );
        _ctrl.add(_current!);
      }
    }
  }

  // ── Arrival detection ─────────────────────────────────────────────────────
  void _checkArrival(LatLng pos, double remainingRoadM, double accuracy) {
    if (_hasArrived || _destination == null) return;
    const d = Distance();
    final directDistM = d.as(LengthUnit.Meter, pos, _destination!);

    // Canonical 75-metre doorstep arrival geofence via shared ArrivalEligibilityPolicy
    final isWithinGate = ArrivalEligibilityPolicy.isLocationWithinArrivalGate(
      workerLocation: pos,
      destinationLocation: _destination!,
      accuracyMeters: accuracy,
    );
    final isCandidate = (remainingRoadM > 0 && remainingRoadM <= ArrivalEligibilityPolicy.kGeofenceRadiusMeters) ||
        isWithinGate;

    if (isCandidate) {
      _arrivalCandidateCount++;
      debugPrint('[NavEngine] Arrival candidate #$_arrivalCandidateCount '
          '(direct=${directDistM.round()}m, road=${remainingRoadM.round()}m, acc=${accuracy.round()}m)');
      if (_arrivalCandidateCount >= _arrivalRequiredStableFixes ||
          (directDistM <= 75.0 && _current != null && _current!.speedKmh < 5.0) ||
          directDistM <= 45.0) {
        _hasArrived = true;
        debugPrint('[NavEngine] 🏁 ARRIVED at destination');
        if (_current != null) {
          _current = _current!.copyWith(hasArrived: true, remainingDistanceM: 0, remainingSeconds: 0);
          _ctrl.add(_current!);
        }
        if (_voiceEnabled) {
          _speak(
            'You have arrived at your destination.',
            'ನೀವು ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನ ತಲುಪಿದ್ದೀರಿ.',
          );
        }
        // Push arrival to RTDB
        _publishRtdbNow(arrivalStatus: 'arrived');
        // Stop GPS after short delay
        Future.delayed(const Duration(seconds: 5), stop);
      }
    } else {
      _arrivalCandidateCount = 0;
    }
  }

  // ── ETA recalculation ─────────────────────────────────────────────────────
  void _recalcEta() {
    if (_current == null || _route == null || _hasArrived) return;
    final remainingM = _current!.remainingDistanceM;
    if (remainingM <= 0) return;

    // Average speed from ring buffer
    double avgSpeedKmh = _speedBuffer.isNotEmpty
        ? _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length
        : 20.0; // fallback 20 km/h
    avgSpeedKmh = avgSpeedKmh.clamp(5.0, _maxSpeedKmh);

    final avgSpeedMs   = avgSpeedKmh / 3.6;
    final rawEtaSec    = (remainingM / avgSpeedMs).round();
    // Smooth: 70% old, 30% new
    final prevEtaSec   = _current!.remainingSeconds;
    final smoothedEta  = prevEtaSec > 0
        ? (0.7 * prevEtaSec + 0.3 * rawEtaSec).round()
        : rawEtaSec;

    final etaStr = _formatEta(smoothedEta);
    final etaTime = DateTime.now().add(Duration(seconds: smoothedEta));
    final etaTimeStr = _formatTime(etaTime);

    if (_current != null) {
      _current = _current!.copyWith(
        remainingSeconds:  smoothedEta,
        etaString:         etaStr,
        arrivalTimeString: etaTimeStr,
      );
      _ctrl.add(_current!);
    }
  }

  // ── State emission ────────────────────────────────────────────────────────
  void _emitState({
    required LatLng raw,
    required LatLng snapped,
    required double heading,
    required double speed,
    required double accuracy,
    required bool   isSnapped,
  }) {
    if (!_running) return;
    final route = _route;

    // Initialise state if first GPS fix
    if (_current == null) {
      final totalSec = route?.durationSec ?? 0;
      _current = NavState(
        rawPosition:          raw,
        snappedPosition:      snapped,
        heading:              heading,
        speedKmh:             speed,
        accuracy:             accuracy,
        currentStep:          route?.steps.isNotEmpty == true ? route!.steps[0] : null,
        nextStep:             route?.steps.length == null ? null
                              : (route!.steps.length > 1 ? route.steps[1] : null),
        distanceToNextTurnM:  route?.steps.isNotEmpty == true
                              ? route!.steps[0].distanceM.toDouble() : 0,
        remainingDistanceM:   route?.distanceM.toDouble() ?? 0,
        remainingSeconds:     totalSec,
        etaString:            route?.etaText ?? '—',
        arrivalTimeString:    route?.arrivalTimeText ?? '—',
        currentStepIndex:     0,
        passedPolyline:       const [],
        remainingPolyline:    route?.polyline ?? const [],
        isRerouting:          false,
        isSnapped:            isSnapped,
        hasArrived:           false,
        isOffRoute:           false,
      );
    } else {
      _current = _current!.copyWith(
        rawPosition:     raw,
        snappedPosition: snapped,
        heading:         heading,
        speedKmh:        speed,
        accuracy:        accuracy,
        isSnapped:       isSnapped,
        isRerouting:     _isRerouting,
        hasArrived:      _hasArrived,
      );
    }
    _ctrl.add(_current!);
  }

  // ── RTDB publish ──────────────────────────────────────────────────────────
  void _maybePublishRtdb() {
    if (_bookingId == null || _current == null) return;
    final now = DateTime.now();
    if (_lastRtdbPush != null &&
        now.difference(_lastRtdbPush!).inMilliseconds < _rtdbThrottleMs) {
      return;
    }
    _lastRtdbPush = now;
    _publishRtdbNow();
  }

  void _publishRtdbNow({String arrivalStatus = 'en_route'}) {
    final state = _current;
    final id    = _bookingId;
    if (state == null || id == null) return;

    try {
      _seq++;
      FirebaseDatabase.instance.ref('liveTracking/$id').update({
        'sessionId':               _sessionId,
        'seq':                     _seq,
        'lat':                     state.snappedPosition.latitude,
        'lng':                     state.snappedPosition.longitude,
        'heading':                 state.heading,
        'speed':                   state.speedKmh,
        'snapped':                 state.isSnapped,
        'etaSeconds':              state.remainingSeconds,
        'remainingMeters':         state.remainingDistanceM,
        'currentStepInstruction':  state.currentStep?.instruction ?? '',
        'currentStepInstructionKn':state.currentStep?.instructionKn ?? '',
        'arrivalStatus':           state.hasArrived ? 'arrived' : arrivalStatus,
        'updatedAt':               ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[NavEngine] RTDB publish error: $e');
    }
  }

  // ── TTS ───────────────────────────────────────────────────────────────────
  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.85);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[NavEngine] TTS init error: $e');
    }
  }

  Future<void> _speak(String english, String kannada) async {
    final localToken = _speechSessionToken;
    if (!_voiceEnabled || !_running) return;
    try {
      await _tts.stop();
      if (!_running || localToken != _speechSessionToken) return;
      await _tts.setLanguage('en-IN');
      await _tts.speak(english);
      if (kannada.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 2200));
        if (!_running || localToken != _speechSessionToken) return;
        await _tts.setLanguage('kn-IN');
        await _tts.speak(kannada);
      }
    } catch (e) {
      debugPrint('[NavEngine] TTS error: $e');
    }
  }

  // ── Math helpers ──────────────────────────────────────────────────────────

  /// Projects [raw] onto the route [polyline] within [maxSnapDistanceM].
  /// Uses a windowed search around [hintIndex] for performance on dense polylines.
  ({LatLng position, bool isSnapped, int nearestSegmentIndex, double distanceM}) _projectOntoPolyline(
    LatLng raw,
    List<LatLng> polyline, {
    double maxSnapDistanceM = 25.0,
    int? hintIndex,
  }) {
    if (polyline.isEmpty) {
      return (position: raw, isSnapped: false, nearestSegmentIndex: 0, distanceM: 0.0);
    }
    if (polyline.length == 1) {
      const d = Distance();
      final dist = d.as(LengthUnit.Meter, raw, polyline[0]);
      return (
        position: dist <= maxSnapDistanceM ? polyline[0] : raw,
        isSnapped: dist <= maxSnapDistanceM,
        nearestSegmentIndex: 0,
        distanceM: dist,
      );
    }

    int startIdx = 0;
    int endIdx = polyline.length - 1;

    if (hintIndex != null && hintIndex >= 0 && hintIndex < polyline.length - 1) {
      startIdx = math.max(0, hintIndex - 10);
      endIdx = math.min(polyline.length - 1, hintIndex + 35);
    }

    double minDistance = double.infinity;
    LatLng bestProjection = raw;
    int bestSegmentIdx = startIdx;

    void searchRange(int start, int end) {
      for (int i = start; i < end; i++) {
        final res = _projectOntoSegment(raw, polyline[i], polyline[i + 1]);
        if (res.distanceM < minDistance) {
          minDistance = res.distanceM;
          bestProjection = res.projection;
          bestSegmentIdx = i;
        }
      }
    }

    searchRange(startIdx, endIdx);

    // Fallback to full scan if worker is beyond local search window
    if (hintIndex != null && minDistance > maxSnapDistanceM) {
      searchRange(0, polyline.length - 1);
    }

    final isSnapped = minDistance <= maxSnapDistanceM;
    return (
      position: isSnapped ? bestProjection : raw,
      isSnapped: isSnapped,
      nearestSegmentIndex: bestSegmentIdx,
      distanceM: minDistance,
    );
  }

  /// Projects point [p] onto segment [a]-[b] and calculates perpendicular distance.
  ({LatLng projection, double distanceM}) _projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    const kLat = 111320.0;
    final kLng = 111320.0 * math.cos(p.latitude * math.pi / 180.0);
    final px = p.longitude * kLng;
    final py = p.latitude  * kLat;
    final ax = a.longitude * kLng;
    final ay = a.latitude  * kLat;
    final bx = b.longitude * kLng;
    final by = b.latitude  * kLat;
    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) {
      final d = math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
      return (projection: a, distanceM: d);
    }
    final t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);
    final projLat = a.latitude  + tc * (b.latitude  - a.latitude);
    final projLng = a.longitude + tc * (b.longitude - a.longitude);
    final cx = ax + tc * dx;
    final cy = ay + tc * dy;
    final dist = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
    return (projection: LatLng(projLat, projLng), distanceM: dist);
  }

  /// Lerp angle with shortest arc (handles 359° → 1° wrap correctly).
  double _lerpAngle(double from, double to, double t) {
    double diff = (to - from + 540) % 360 - 180;
    return (from + diff * t + 360) % 360;
  }

  @visibleForTesting
  ({LatLng position, bool isSnapped, int nearestSegmentIndex, double distanceM})
  projectOntoPolylineForTest(LatLng raw, List<LatLng> polyline, {int? hintIndex, double maxSnapDistanceM = 25.0}) =>
      _projectOntoPolyline(raw, polyline, hintIndex: hintIndex, maxSnapDistanceM: maxSnapDistanceM);

  @visibleForTesting
  ({LatLng projection, double distanceM}) projectOntoSegmentForTest(LatLng p, LatLng a, LatLng b) =>
      _projectOntoSegment(p, a, b);

  @visibleForTesting
  double lerpAngleForTest(double from, double to, double t) => _lerpAngle(from, to, t);

  String _formatEta(int seconds) {
    if (seconds <= 0) return '< 1 min';
    final m = seconds ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60; final rm = m % 60;
    return rm == 0 ? '${h}h' : '${h}h ${rm}m';
  }

  String _formatTime(DateTime t) {
    final h  = t.hour;
    final m  = t.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $ap';
  }
}
