// lib/services/journey_service.dart
// Handles: real GPS streaming via Geolocator.getPositionStream(),
// GPS validation, jump detection, adaptive distance filter,
// Firebase RTDB publishing, arrival detection, and foreground service lifecycle.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/live_location.dart';
import '../models/journey_state.dart';
import 'routing/gps_quality_engine.dart';
import 'navigation_engine.dart';
import '../features/tracking/services/worker_telemetry_service.dart';

typedef OnLocation = void Function(LiveLocation loc);
typedef OnEvent    = void Function(JourneyEvent event);

class JourneyService {
  JourneyService._();
  static final JourneyService instance = JourneyService._();

  StreamSubscription<Position>? _gpsSub;
  // _lastValidLocation removed — jump detection now in GpsQualityEngine (V600)
  int            _nearArrivalCount = 0;
  bool           _isTracking       = false;
  // D6 Fix: Session token — incremented on every startTracking().
  // GPS callbacks compare their captured token to the current token.
  // If stale (token mismatch), the callback is discarded silently.
  int            _sessionToken     = 0;


  String? _bookingId;
  String _jobId = '';
  String? _workerId;
  String? _hirerId;
  double? _destLat;
  double? _destLng;

  OnLocation? _onLocation;
  OnEvent?    _onEvent;

  bool get isTracking => _isTracking;

  // ── Request location permission ────────────────────────────────────────────
  static Future<String?> requestPermission() async {
    // Step 1: check/request location permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      // User permanently denied — must open Settings
      await Geolocator.openAppSettings();
      return 'location_denied_forever';
    }
    if (perm == LocationPermission.denied) {
      return 'location_denied';
    }

    // Step 2: check GPS is switched on
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return 'gps_off';
    }

    return null; // null = all good
  }

  /// One-shot active GPS fix acquisition with bounded timeout.
  /// Bypasses stream latency for fast navigation bootstrap.
  Future<Position?> acquireInitialFix({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return pos;
    } catch (e) {
      debugPrint('[JourneyService] acquireInitialFix failed or timed out: $e');
      return null;
    }
  }

  // ── Start GPS tracking ─────────────────────────────────────────────────────
  Future<bool> startTracking({
    required String bookingId,
    required String workerId,
    required String hirerId,
    required double destLat,
    required double destLng,
    required OnLocation onLocation,
    required OnEvent onEvent,
  }) async {
    if (_isTracking) {
      debugPrint('[Journey] Already tracking — stopping old session first');
      await stopTracking();
    }

    final error = await requestPermission();
    if (error != null) {
      debugPrint('[Journey] Cannot start: $error');
      return false;
    }

    _bookingId  = bookingId;
    _workerId   = workerId;
    _hirerId    = hirerId;
    _destLat    = destLat;
    _destLng    = destLng;
    _onLocation = onLocation;
    _onEvent    = onEvent;

    try {
      final doc = await FirebaseFirestore.instance.collection('bookings').doc(bookingId).get();
      _jobId = doc.data()?['jobId'] as String? ?? '';
    } catch (e) {
      debugPrint('[Journey] Failed to fetch jobId: $e');
    }

    _nearArrivalCount  = 0;
    _isTracking        = true;
    // D6 Fix: Increment session token for every new tracking session.
    // Any in-flight GPS callbacks from a previous session will see a token
    // mismatch inside _handleRawPosition and discard their data.
    _sessionToken++;

    // V600 FIX: Reset GPS quality engine ring buffer for clean new session.
    // Without this, GPS_JUMP detection inherits old location history from a
    // previous booking session and may incorrectly reject valid positions.
    GpsQualityEngine.instance.reset();

    // Start Android foreground service so GPS survives backgrounding
    await _startForegroundService();

    // V900 Single Authoritative GPS Stream:
    // 1 Hz interval, 2m filter, high accuracy.
    // Managed solely by JourneyService and fed to NavigationEngine.
    final settings = AndroidSettings(
      accuracy:         LocationAccuracy.high,
      distanceFilter:   2,
      intervalDuration: const Duration(seconds: 1),
    );

    try {
      // D6 Fix: Capture the current session token into a local closure variable.
      // If this subscription fires after a new session has started (token mismatch),
      // the callback discards the position rather than corrupting the new session.
      final capturedToken = _sessionToken;
      _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          if (_sessionToken != capturedToken) return; // stale callback — discard
          _handleRawPosition(pos);
        },
        onError: (Object e) {
          debugPrint('[Journey] GPS stream error: $e');
          _onEvent?.call(JourneyEvent.locationUnavailable);
        },
        cancelOnError: false,
      );

      // V700 Fix: Seed initial position with last known fix if available.
      // Validated by GpsQualityEngine (rejects if stale or low accuracy).
      Geolocator.getLastKnownPosition().then((last) {
        if (last != null && _isTracking && _sessionToken == capturedToken) {
          debugPrint('[Journey] Seeding initial position from lastKnownPosition');
          _handleRawPosition(last);
        }
      }).catchError((e) {
        debugPrint('[Journey] getLastKnownPosition non-fatal error: $e');
      });

      // Active one-shot fix: acquire fresh GPS fix in parallel to avoid waiting for stream movement
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).then((pos) {
        if (_isTracking && _sessionToken == capturedToken) {
          debugPrint('[Journey] Fresh initial GPS acquired via getCurrentPosition (acc=${pos.accuracy.toStringAsFixed(0)}m)');
          _handleRawPosition(pos);
        }
      }).catchError((e) {
        debugPrint('[Journey] getCurrentPosition non-fatal error: $e');
      });
    } catch (e) {
      debugPrint('[Journey] Failed to start GPS stream: $e');
      _isTracking = false;
      return false;
    }

    debugPrint('[Journey] Tracking started for booking $bookingId');

    // ── Update RTDB session status immediately (Preserves existing seed lat/lng) ────
    try {
      await FirebaseDatabase.instance.ref('liveTracking/$bookingId').update({
        'jobId':          _jobId,
        'workerId':       workerId,
        'hirerId':        hirerId,
        'trackingStatus': 'active',
        'arrivalStatus':  'en_route',
        'status':         'en_route',
        'updatedAt':      ServerValue.timestamp,
        'lastUpdatedAt':  ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[Journey] RTDB status update error: $e');
    }

    return true;
  }

  // ── Stop tracking ──────────────────────────────────────────────────────────
  Future<void> stopTracking() async {
    _isTracking = false;
    await _gpsSub?.cancel();
    _gpsSub = null;

    // Mark RTDB as stopped
    if (_bookingId != null && _workerId != null) {
      try {
        await FirebaseDatabase.instance
            .ref('liveTracking/$_bookingId')
            .update({'trackingStatus': 'stopped'});
      } catch (_) {}
    }

    await _stopForegroundService();

    _bookingId  = null;
    _jobId      = '';
    _workerId   = null;
    _hirerId    = null;
    _destLat    = null;
    _destLng    = null;
    _onLocation = null;
    _onEvent    = null;
    _nearArrivalCount  = 0;

    debugPrint('[Journey] Tracking stopped');
  }

  // ── Handle raw GPS position ────────────────────────────────────────────────
  void _handleRawPosition(Position raw) {
    // V600 FIX: Use GpsQualityEngine (8-level classifier) instead of ad-hoc
    // accuracy+mock+jump checks. Consistent with NavigationEngine._onGps().
    // classify() returns ClassifiedPosition; .classification is GpsClassification.
    final classified = GpsQualityEngine.instance.classify(raw);
    switch (classified.classification) {
      case GpsClassification.INVALID:
      case GpsClassification.GPS_JUMP:
      case GpsClassification.MOCK_SUSPECTED:
      case GpsClassification.DUPLICATE:
        debugPrint('[Journey] GPS rejected: ${classified.classification} '
            '(acc=${raw.accuracy.toStringAsFixed(0)}m)');
        return;
      case GpsClassification.LOW_ACCURACY:
      case GpsClassification.STALE:
        debugPrint('[Journey] GPS degraded: ${classified.classification} — publishing anyway');
        break;
      default:
        break; // GOOD, LIVE — publish normally
    }

    final loc = LiveLocation.fromPosition(raw);

    // V900: If NavigationEngine is active, feed the position directly.
    // NavigationEngine publishes full telemetry (ETA, remaining road distance, maneuvers).
    if (NavigationEngine.instance.isRunning) {
      NavigationEngine.instance.feedGpsPosition(raw);
    } else {
      // Publish initial/pre-route position so hirer sees where worker is
      _publishToRTDB(loc);
    }

    // Arrival detection
    if (_destLat != null && _destLng != null) {
      final distM = loc.distanceTo(_destLat!, _destLng!);

      if (distM <= TrackingConfig.nearDestinationRadiusM) {
        _onEvent?.call(JourneyEvent.nearDestination);
      }

      if (distM <= TrackingConfig.arrivalRadiusM) {
        _nearArrivalCount++;
        debugPrint('[Journey] Near arrival: count=$_nearArrivalCount dist=${distM.toStringAsFixed(0)}m');
        if (_nearArrivalCount >= TrackingConfig.arrivalStableCount) {
          _onEvent?.call(JourneyEvent.atArrivalRadius);
        }
      } else {
        _nearArrivalCount = 0;
      }
    }

    // Notify provider
    _onLocation?.call(loc);
  }

  // ── Publish validated location to Firebase RTDB ────────────────────────────
  Future<void> _publishToRTDB(LiveLocation loc) async {
    if (_bookingId == null || _workerId == null || _hirerId == null) return;
    if (NavigationEngine.instance.isRunning) return; // Prevent overwriting navigation telemetry

    try {
      final payload = loc.toRtdbMap(
        workerId:       _workerId!,
        hirerId:        _hirerId!,
        trackingStatus: 'active',
      );
      payload['jobId'] = _jobId;
      payload['lat'] = loc.latitude;
      payload['lng'] = loc.longitude;
      if (_destLat != null && _destLng != null) {
        final distM = loc.distanceTo(_destLat!, _destLng!);
        payload['remainingMeters'] = distM;
        final etaSec = (distM / 6.94).round();
        payload['etaSeconds'] = etaSec;
      }
      // Add server timestamp for freshness calculation (separate key)
      payload['lastUpdatedAt'] = ServerValue.timestamp;

      await FirebaseDatabase.instance
          .ref('liveTracking/$_bookingId')
          .update(payload);

      debugPrint('[Journey] RTDB updated: ${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}');
    } catch (e) {
      debugPrint('[Journey] RTDB publish error: $e');
    }
  }

  // ── Android Foreground Service helpers ────────────────────────────────────
  Future<void> _startForegroundService() async {
    try {
      final bId = _bookingId;
      final wId = _workerId;
      if (bId != null && wId != null) {
        await WorkerTelemetryService.instance.startBackgroundTracking(
          bookingId: bId,
          workerId: wId,
          hirerId: _hirerId,
          jobId: _jobId,
        );
      }
    } catch (e) {
      debugPrint('[Journey] Foreground service start error: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await WorkerTelemetryService.instance.stopBackgroundTracking();
    } catch (e) {
      debugPrint('[Journey] Foreground service stop error: $e');
    }
  }
}
