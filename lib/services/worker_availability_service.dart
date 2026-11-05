// lib/services/worker_availability_service.dart
// Phase 3: Worker availability and discovery location service.
//
// RESPONSIBILITIES:
//   - Manages worker isAvailable flag (approved workers only)
//   - Starts GPS stream when worker turns Available ON
//   - Writes discoveryLat/Lng/UpdatedAt to Firestore with throttling
//   - Stops GPS stream when worker turns Available OFF or logs out
//
// LOCATION FOUR-WAY SEPARATION (spec Part 1):
//   1. PROFILE LOCATION     → district/taluk (registration)         — NOT here
//   2. SERVICE AREA         → serviceRadiusKm (declared by worker)  — set here
//   3. DISCOVERY LOCATION   → discoveryLat/Lng (operational GPS)    — managed here
//   4. ACTIVE JOB LOCATION  → liveTracking/{bookingId} in RTDB      — NOT here
//
// GPS POLICY:
//   - distanceFilter: 50 m (only emit when moved > 50 m)
//   - Heartbeat: write every 10 min even if not moved
//   - Accuracy: reject fixes with accuracy > 100 m
//   - NO per-second writes to Firestore
//   - Max ~6 writes/hour per worker at steady state
//
// FRESHNESS THRESHOLDS:
//   FRESH  : < 10 min → show as "Near you now"
//   RECENT : 10–30 min → show with age
//   STALE  : > 30 min → exclude from nearby search
//
// PRIVACY:
//   Discovery location is set ONLY when worker explicitly enables availability.
//   It is NEVER derived from district/taluk or registration address.
//   Discovery coords are operational: they represent where the worker IS,
//   not where the worker LIVES.
//
// MULTI-DEVICE PROTECTION:
//   Each session generates a unique discoverySessionId.
//   Before writing, the service verifies sessionId matches Firestore.
//   If another device has taken over (new sessionId), this stream stops.

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'routing/gps_quality_engine.dart';

/// Freshness state of a worker's discovery location.
enum LocationFreshness {
  /// Updated within 10 minutes — actively nearby.
  fresh,
  /// Updated 10–30 minutes ago — recently active.
  recent,
  /// Updated more than 30 minutes ago — exclude from nearby search.
  stale,
  /// No discoveryUpdatedAt present — never set.
  unknown,
}

/// Result of calling WorkerAvailabilityService.setAvailable().
class WorkerAvailabilityResult {
  final bool success;
  final String? errorMessage;
  final String? sessionId;

  const WorkerAvailabilityResult._({
    required this.success,
    this.errorMessage,
    this.sessionId,
  });

  factory WorkerAvailabilityResult.ok(String sessionId) =>
      WorkerAvailabilityResult._(success: true, sessionId: sessionId);

  factory WorkerAvailabilityResult.failure(String msg) =>
      WorkerAvailabilityResult._(success: false, errorMessage: msg);
}

/// Phase 3: Manages worker availability and discovery location lifecycle.
///
/// Access via WorkerAvailabilityService.instance.
class WorkerAvailabilityService {
  WorkerAvailabilityService._();
  static final WorkerAvailabilityService instance = WorkerAvailabilityService._();

  // ── Freshness thresholds ──────────────────────────────────────────────
  // Chosen to balance responsiveness (workers move between jobs) and
  // Firestore write cost (max 6 writes/hour at steady state).
  // Documented in docs/kelasagara_location_discovery_contract.md.
  static const Duration kFreshThreshold = Duration(minutes: 10);
  static const Duration kRecentThreshold = Duration(minutes: 30);
  static const Duration kStaleAfter = Duration(minutes: 30);

  // ── GPS policy constants ──────────────────────────────────────────────
  // Minimum movement before triggering a Firestore write (metres).
  // distanceFilter on the stream already filters at 50 m; this is a
  // secondary safety check.
  static const double kMinMovementMeters = 50.0;

  // Maximum time between Firestore writes even if worker hasn't moved.
  // Prevents stale discovery entries when worker stays in one place.
  static const Duration kHeartbeatInterval = Duration(minutes: 10);

  // GPS accuracy threshold. Fixes with accuracy > 100 m are LOW_ACCURACY
  // per GpsQualityEngine and are rejected for discovery location.
  static const double kMaxAccuracyMeters = 100.0;

  // Default service radius if worker hasn't declared one.
  static const int kDefaultServiceRadiusKm = 15;

  // ── Session state ─────────────────────────────────────────────────────
  String? _sessionId;
  String? _uid;
  StreamSubscription<Position>? _gpsSub;
  Timer? _heartbeatTimer;
  Position? _lastWrittenPos;
  DateTime? _lastWriteTime;
  static final Random _random = Random();

  // ── Public API ────────────────────────────────────────────────────────

  /// Enable availability for [uid]. Called by WorkerDashboard availability toggle.
  ///
  /// Flow:
  ///   1. Stop any existing session (supports app-restart re-enable).
  ///   2. Check + request location permission.
  ///   3. Get initial GPS fix and validate with GpsQualityEngine.
  ///   4. Write discoveryLat/Lng + isAvailable=true + new sessionId to Firestore.
  ///   5. Start ongoing GPS stream with 50 m distance filter.
  ///
  /// Returns [WorkerAvailabilityResult.failure] with explanation if:
  ///   - Location permission denied.
  ///   - GPS unavailable or accuracy too low.
  ///   - Firestore write fails.
  Future<WorkerAvailabilityResult> setAvailable({
    required String uid,
    required int serviceRadiusKm,
  }) async {
    debugPrint('[WorkerAvailabilityService] setAvailable uid=$uid radius=${serviceRadiusKm}km');

    // Cancel any active session first
    await _stopInternal();

    // 1. Location permission
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return WorkerAvailabilityResult.failure(
          'Location permission required. Your current location helps '
          'hirers find you when you are available.',
        );
      }
    } catch (_) {
      return WorkerAvailabilityResult.failure(
        'Could not check location permission. Please try again.',
      );
    }

    // 2. Get initial GPS fix
    Position initialPos;
    try {
      initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return WorkerAvailabilityResult.failure(
        'Could not get your location. Please check GPS and try again.',
      );
    }

    // 3. Validate with GpsQualityEngine
    final classified = GpsQualityEngine.instance.classify(initialPos);
    if (!classified.isUsable) {
      return WorkerAvailabilityResult.failure(
        'GPS accuracy is too low (${initialPos.accuracy.toStringAsFixed(0)} m). '
        'Please move to an open area and try again.',
      );
    }

    // 4. Create session and write to Firestore
    _sessionId = _newSessionId();
    _uid = uid;
    _lastWrittenPos = null;
    _lastWriteTime = null;

    try {
      await _writeDiscovery(
        uid: uid,
        pos: initialPos,
        isAvailable: true,
        serviceRadiusKm: serviceRadiusKm,
        sessionId: _sessionId!,
      );
    } catch (e) {
      debugPrint('[WorkerAvailabilityService] Initial write failed: $e');
      _sessionId = null;
      _uid = null;
      return WorkerAvailabilityResult.failure(
        'Could not save your availability. Please check connection and try again.',
      );
    }

    _lastWrittenPos = initialPos;
    _lastWriteTime = DateTime.now();

    // 5. Start ongoing GPS stream
    _startGpsStream(uid);

    debugPrint('[WorkerAvailabilityService] Session started: $_sessionId');
    return WorkerAvailabilityResult.ok(_sessionId!);
  }

  /// Disable availability for [uid]. Called by WorkerDashboard or logout handler.
  ///
  /// Stops GPS stream. Writes isAvailable=false + clears sessionId to Firestore.
  /// Keeps discoveryLat/Lng in place (freshness check will mark them stale).
  Future<void> setUnavailable(String uid) async {
    debugPrint('[WorkerAvailabilityService] setUnavailable uid=$uid');
    await _stopInternal();
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isAvailable': false,
        'discoverySessionId': '',
        // Keep discoveryLat/Lng for audit trail; freshness expires naturally
        'discoveryUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[WorkerAvailabilityService] setUnavailable write error: $e');
    }
    _sessionId = null;
    _uid = null;
  }

  /// Resume an availability session after app restart.
  ///
  /// If the server shows isAvailable=true after restart, call this to:
  ///   - Create a new session (invalidates any stale device)
  ///   - Refresh discovery location immediately
  ///
  /// If user was not available, do nothing.
  Future<WorkerAvailabilityResult> resumeIfAvailable({
    required String uid,
    required bool serverIsAvailable,
    required int serviceRadiusKm,
  }) async {
    if (!serverIsAvailable) return WorkerAvailabilityResult.failure('Not available');
    debugPrint('[WorkerAvailabilityService] Resuming session for uid=$uid');
    return setAvailable(uid: uid, serviceRadiusKm: serviceRadiusKm);
  }

  /// Check the freshness of a discovery location timestamp.
  ///
  /// Used by WorkerDiscoveryService to exclude stale workers from nearby results.
  static LocationFreshness checkFreshness(DateTime? updatedAt) {
    if (updatedAt == null) return LocationFreshness.unknown;
    final age = DateTime.now().difference(updatedAt);
    if (age <= kFreshThreshold) return LocationFreshness.fresh;
    if (age <= kRecentThreshold) return LocationFreshness.recent;
    return LocationFreshness.stale;
  }

  /// Whether a GPS session is currently active.
  bool get isSessionActive => _sessionId != null && _uid != null;

  /// Current session ID (null if not active).
  String? get currentSessionId => _sessionId;

  /// Current worker UID being tracked (null if not active).
  String? get trackedUid => _uid;

  // ── Internal ──────────────────────────────────────────────────────────

  void _startGpsStream(String uid) {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Only emit when worker moves > 50 m — limits Firestore write frequency
        distanceFilter: 50,
      ),
    ).listen(
      (pos) => _onPosition(uid, pos),
      onError: (e) =>
          debugPrint('[WorkerAvailabilityService] GPS stream error: $e'),
    );

    // Heartbeat: write even if stationary, every kHeartbeatInterval
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(kHeartbeatInterval, (_) {
      final lastPos = _lastWrittenPos;
      final sid = _sessionId;
      if (lastPos != null && sid != null && _uid == uid) {
        FirebaseFirestore.instance.collection('users').doc(uid).update({
          'discoveryUpdatedAt': FieldValue.serverTimestamp(),
          'discoverySessionId': sid,
          // Heartbeat: refresh timestamp, keep existing lat/lng
        }).catchError(
          (e) => debugPrint('[WorkerAvailabilityService] Heartbeat error: $e'),
        );
      }
    });
  }

  Future<void> _onPosition(String uid, Position pos) async {
    final sid = _sessionId;
    if (sid == null || _uid != uid) return;

    // Validate quality
    final classified = GpsQualityEngine.instance.classify(pos);
    if (!classified.isUsable) {
      debugPrint(
        '[WorkerAvailabilityService] Fix rejected: ${classified.rejectReason}',
      );
      return;
    }

    // Additional movement check (stream distanceFilter should handle this,
    // but guard against edge cases)
    final lastPos = _lastWrittenPos;
    if (lastPos != null) {
      final dist = Geolocator.distanceBetween(
        lastPos.latitude, lastPos.longitude,
        pos.latitude, pos.longitude,
      );
      final timeSinceWrite = _lastWriteTime != null
          ? DateTime.now().difference(_lastWriteTime!)
          : kHeartbeatInterval;
      if (dist < kMinMovementMeters && timeSinceWrite < kHeartbeatInterval) {
        return; // Not enough movement and not time for heartbeat yet
      }
    }

    try {
      // Multi-device guard: verify session ownership before writing
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) return;
      final serverSid = doc.data()?['discoverySessionId'] as String? ?? '';
      if (serverSid.isNotEmpty && serverSid != sid) {
        debugPrint(
          '[WorkerAvailabilityService] Session $sid stolen by $serverSid — stopping.',
        );
        await _stopInternal();
        return;
      }

      final radius =
          (doc.data()?['serviceRadiusKm'] as num?)?.toInt() ??
          kDefaultServiceRadiusKm;

      await _writeDiscovery(
        uid: uid,
        pos: pos,
        isAvailable: true,
        serviceRadiusKm: radius,
        sessionId: sid,
      );
      _lastWrittenPos = pos;
      _lastWriteTime = DateTime.now();
      debugPrint(
        '[WorkerAvailabilityService] Updated: ${pos.latitude.toStringAsFixed(5)}, '
        '${pos.longitude.toStringAsFixed(5)} accuracy=${pos.accuracy.toStringAsFixed(0)}m',
      );
    } catch (e) {
      debugPrint('[WorkerAvailabilityService] Position write failed: $e');
    }
  }

  Future<void> _writeDiscovery({
    required String uid,
    required Position pos,
    required bool isAvailable,
    required int serviceRadiusKm,
    required String sessionId,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isAvailable': isAvailable,
      'discoveryLat': pos.latitude,
      'discoveryLng': pos.longitude,
      'discoveryUpdatedAt': FieldValue.serverTimestamp(),
      'discoverySessionId': sessionId,
      'discoveryAccuracy': pos.accuracy,
      'serviceRadiusKm': serviceRadiusKm,
    });
  }

  Future<void> _stopInternal() async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastWrittenPos = null;
    _lastWriteTime = null;
  }

  /// Force-stop GPS stream without writing isAvailable=false to Firestore.
  /// Called on logout — avoids Firestore writes after sign-out.
  void forceStop() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sessionId = null;
    _uid = null;
    debugPrint('[WorkerAvailability] Force-stopped on logout (no Firestore write).');
  }

  String _newSessionId() =>
      '${DateTime.now().millisecondsSinceEpoch}_'
      '${_random.nextInt(999999).toString().padLeft(6, '0')}';
}
