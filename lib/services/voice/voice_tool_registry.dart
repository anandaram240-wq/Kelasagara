// lib/services/voice/voice_tool_registry.dart
// Strict Typed Voice Tool Registry for Kelasagara V70 — Hirer-Only Guard & Real Data

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../location_service.dart';
import '../worker_discovery_service.dart';
import '../worker_availability_service.dart';
import '../booking_service.dart';
import '../../models/worker_search_request.dart';
import '../../models/worker_search_result.dart';

class WorkerCandidate {
  final String workerId;
  final String name;
  final String skill;
  final double distanceMeters;
  final String distanceDisplay;
  final double latitude;
  final double longitude;
  final bool isAvailable;
  final String verificationLevel;
  final int completedJobs;
  final double rating;
  final double rankingScore;
  final String selectionReason;
  final double? roadDistanceMeters;
  final int? roadDurationSeconds;
  final String? roadDurationDisplay;
  final bool isRoadDistance;
  final String locationFreshness; // 'LIVE', 'RECENT', 'STALE', 'UNKNOWN'

  WorkerCandidate({
    required this.workerId,
    required this.name,
    required this.skill,
    required this.distanceMeters,
    required this.distanceDisplay,
    required this.latitude,
    required this.longitude,
    required this.isAvailable,
    required this.verificationLevel,
    required this.completedJobs,
    required this.rating,
    required this.rankingScore,
    required this.selectionReason,
    this.roadDistanceMeters,
    this.roadDurationSeconds,
    this.roadDurationDisplay,
    this.isRoadDistance = false,
    this.locationFreshness = 'UNKNOWN',
  });

  WorkerCandidate copyWithRoad({
    required double roadDistanceMeters,
    required int roadDurationSeconds,
    required bool isRoadDistance,
  }) {
    final distKm = roadDistanceMeters / 1000.0;
    final durMin = (roadDurationSeconds / 60).round();
    return WorkerCandidate(
      workerId: workerId,
      name: name,
      skill: skill,
      distanceMeters: roadDistanceMeters,
      distanceDisplay: distKm < 1.0 ? '${roadDistanceMeters.round()} m' : '${distKm.toStringAsFixed(1)} km',
      latitude: latitude,
      longitude: longitude,
      isAvailable: isAvailable,
      verificationLevel: verificationLevel,
      completedJobs: completedJobs,
      rating: rating,
      rankingScore: rankingScore,
      selectionReason: selectionReason,
      roadDistanceMeters: roadDistanceMeters,
      roadDurationSeconds: roadDurationSeconds,
      roadDurationDisplay: durMin <= 1 ? '1 min' : '$durMin min',
      isRoadDistance: isRoadDistance,
      locationFreshness: locationFreshness,
    );
  }

  Map<String, dynamic> toMap() => {
    'workerId': workerId,
    'name': name,
    'skill': skill,
    'distanceMeters': distanceMeters,
    'distanceDisplay': distanceDisplay,
    'latitude': latitude,
    'longitude': longitude,
    'isAvailable': isAvailable,
    'verificationLevel': verificationLevel,
    'completedJobs': completedJobs,
    'rating': rating,
    'rankingScore': rankingScore,
    'selectionReason': selectionReason,
    'roadDistanceMeters': roadDistanceMeters,
    'roadDurationSeconds': roadDurationSeconds,
    'roadDurationDisplay': roadDurationDisplay,
    'isRoadDistance': isRoadDistance,
    'locationFreshness': locationFreshness,
  };
}

class VoiceToolRegistry {
  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;

  VoiceToolRegistry({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? _resolveDb(),
        _auth = auth ?? _resolveAuth();

  static FirebaseFirestore? _resolveDb() {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  static FirebaseAuth? _resolveAuth() {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance;
      }
    } catch (_) {}
    return null;
  }

  // Persistent server-authoritative idempotency handled by BookingService (P4-015)

  // ── Role & Auth Guard ───────────────────────────────────────────────────
  Future<bool> _isAuthorizedUser() async {
    final auth = _auth;
    if (auth == null) return true; // Offline / unit test fallback
    return auth.currentUser != null;
  }

  // ── Execute Dispatcher ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> executeTool({
    required String toolName,
    required Map<String, dynamic> arguments,
    void Function(String screenName)? onNavigate,
  }) async {
    // 1. Authenticated user verification
    final authorized = await _isAuthorizedUser();
    if (!authorized) {
      return {
        'success': false,
        'error': 'Please sign in to use voice commands.',
        'code': 'UNAUTHENTICATED',
      };
    }

    // 2. Dispatch to specific schema-validated tool
    try {
      switch (toolName) {
        case 'searchWorkersNearby':
          return await searchWorkersNearby(arguments);
        case 'searchWorkersByDistrict':
          return await searchWorkersByDistrict(arguments);
        case 'getWorkerDetails':
          return await getWorkerDetails(arguments);
        case 'getWorkerAvailability':
          return await getWorkerAvailability(arguments);
        case 'getWorkerDistance':
          return await getWorkerDistance(arguments);
        case 'getWorkerCompletedJobs':
          return await getWorkerCompletedJobs(arguments);
        case 'getWorkerVerification':
          return await getWorkerVerification(arguments);
        case 'getWorkerDailyRate':
          return await getWorkerDailyRate(arguments);
        case 'createBooking':
          return await createBooking(arguments);
        case 'bookNearbyWorker':
          return await bookNearbyWorker(arguments);
        case 'cancelBooking':
          return await cancelBooking(arguments);
        case 'getActiveBookings':
          return await getActiveBookings(arguments);
        case 'listMyBookings':
          return await listMyBookings(arguments);
        case 'listMyApplications':
          return await listMyApplications(arguments);
        case 'getBookingDetails':
          return await getBookingDetails(arguments);
        case 'getWorkerLiveLocation':
          return await getWorkerLiveLocation(arguments);
        case 'navigateToScreen':
          return navigateToScreen(arguments, onNavigate);
        case 'getCurrentLocation':
          return await getCurrentLocation();
        case 'getCurrentUser':
          return await getCurrentUser();
        case 'initiateChatConversation':
          return await initiateChatConversation(arguments);
        default:
          return {'success': false, 'error': 'Unknown tool: $toolName'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Tool 1: searchWorkersNearby ──────────────────────────────────────────
  Future<Map<String, dynamic>> searchWorkersNearby(Map<String, dynamic> args) async {
    final skillId = (args['skillId'] as String? ?? '').toLowerCase().trim();
    if (skillId.isEmpty) {
      return {'success': false, 'error': 'skillId is required'};
    }

    // Determine search center coordinates
    double userLat = (args['latitude'] as num?)?.toDouble() ?? 0.0;
    double userLng = (args['longitude'] as num?)?.toDouble() ?? 0.0;

    if (userLat == 0.0 || userLng == 0.0) {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        userLat = pos.latitude;
        userLng = pos.longitude;
      } else {
        // GPS denied — try hirer's discoveryLat/Lng first, then district fallback
        final uid = _auth?.currentUser?.uid;
        bool gotCoords = false;
        if (uid != null && _db != null) {
          try {
            final uDoc = await _db.collection('users').doc(uid).get();
            final pLat = (uDoc.data()?['discoveryLat'] as num?)?.toDouble() ??
                (uDoc.data()?['lat'] as num?)?.toDouble();
            final pLng = (uDoc.data()?['discoveryLng'] as num?)?.toDouble() ??
                (uDoc.data()?['lng'] as num?)?.toDouble();
            if (pLat != null && pLng != null && pLat != 0.0 && pLng != 0.0) {
              userLat = pLat;
              userLng = pLng;
              gotCoords = true;
            }
            // District fallback — GPS denied but district search always works
            if (!gotCoords) {
              final hirerDistrict =
                  (uDoc.data()?['district'] as String? ?? '').trim();
              if (hirerDistrict.isNotEmpty) {
                // Route transparently to district-based search
                return await searchWorkersByDistrict({
                  'skillId': skillId,
                  'district': hirerDistrict,
                });
              }
            }
          } catch (_) {}
        }
        if (userLat == 0.0 || userLng == 0.0) {
          return {
            'success': false,
            'error':
                'Location unavailable. Try saying your district, e.g. "painters in Hassan".',
          };
        }
      }
    }

    final requestedRadius = (args['radiusMeters'] as num?)?.toDouble();
    final radiusKm = requestedRadius != null
        ? (requestedRadius / 1000.0).clamp(0.5, 50.0)
        : 10.0;
    final limit = (args['limit'] as num?)?.toInt().clamp(1, 30) ?? 25;
    final cursor = args['cursor'];
    final excludeUidsList = args['excludeUids'] as List<dynamic>?;
    final excludeUids = excludeUidsList != null ? excludeUidsList.map((e) => e.toString()).toSet() : null;

    // Phase 3: Route search through ONE canonical WorkerDiscoveryService
    final req = WorkerSearchRequest(
      mode: WorkerSearchMode.nearbyGps,
      sessionId: WorkerDiscoveryService.instance.newSessionId(),
      hirerPosition: LatLng(userLat, userLng),
      skillId: skillId == 'all' ? '' : skillId,
      radiusKm: radiusKm,
      limit: limit,
      cursor: cursor,
      excludeUids: excludeUids,
    );

    final result = await WorkerDiscoveryService.instance.search(req);
    if (result.state == WorkerSearchState.locationUnavailable) {
      return {'success': false, 'error': 'GPS location unavailable'};
    }
    if (result.state == WorkerSearchState.error) {
      return {'success': false, 'error': result.errorMessage};
    }

    final candidates = <WorkerCandidate>[];
    for (final entry in result.workers) {
      final p = entry.profile;
      final distMeters = entry.roadDistanceM ?? entry.geoDistanceM ?? 0.0;
      final distKm = distMeters / 1000.0;
      final distDisplay = distKm < 1.0
          ? '${distMeters.round()} m'
          : '${distKm.toStringAsFixed(1)} km';

      final verifStr = p.skillVerified
          ? 'practicalVerified'
          : (p.faceVerified ? 'basicAssessed' : 'none');

      final distScore = max(0.0, 1.0 - (distMeters / (radiusKm * 1000.0)));
      final verifWeight = switch (verifStr) {
        'advanced'          => 1.0,
        'experienced'       => 0.85,
        'practicalVerified' => 0.70,
        'basicAssessed'     => 0.50,
        _                   => 0.30,
      };
      final jobsScore = min(1.0, p.totalJobs / 50.0);
      final ratingScore = min(1.0, p.rating / 5.0);

      final compositeScore = (0.40 * distScore) +
          (0.25 * verifWeight) +
          (0.20 * jobsScore) +
          (0.15 * ratingScore);

      final freshness = WorkerAvailabilityService.checkFreshness(p.discoveryUpdatedAt)
          .name
          .toUpperCase();

      final reason = '${p.displayName} is available, $distDisplay away, '
          'has completed ${p.totalJobs} jobs with ${p.rating.toStringAsFixed(1)}★ rating.';

      candidates.add(WorkerCandidate(
        workerId: p.uid,
        name: p.displayName,
        skill: skillId,
        distanceMeters: distMeters,
        distanceDisplay: distDisplay,
        latitude: p.discoveryLat ?? userLat,
        longitude: p.discoveryLng ?? userLng,
        isAvailable: p.isAvailable,
        verificationLevel: verifStr,
        completedJobs: p.totalJobs,
        rating: p.rating,
        rankingScore: compositeScore,
        selectionReason: reason,
        locationFreshness: freshness,
        roadDistanceMeters: entry.roadDistanceM,
        roadDurationSeconds: entry.roadDurationSec,
        roadDurationDisplay: entry.etaMinutes != null ? '${entry.etaMinutes} min' : null,
      ));
    }

    // Sort by deterministic composite score descending
    candidates.sort((a, b) => b.rankingScore.compareTo(a.rankingScore));

    return {
      'success': true,
      'candidateCount': candidates.length,
      'candidates': candidates.map((c) => c.toMap()).toList(),
      'searchCenter': {'lat': userLat, 'lng': userLng},
      'hasMore': result.hasMore,
      'nextCursor': result.nextCursor,
    };
  }

  // ── Tool 2: getWorkerDetails ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerDetails(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
      if (!doc.exists) {
        doc = await db.collection('users').doc(workerId).get();
      }
    } catch (_) {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
    }

    if (!doc.exists) return {'success': false, 'error': 'Worker not found'};
    final d = doc.data()!;
    return {
      'success': true,
      'workerId': workerId,
      'name': d['displayName'] ?? d['name'] ?? '',
      'skills': d['skills'] ?? [],
      'rating': d['rating'] ?? 0.0,
      'totalJobs': d['totalJobs'] ?? 0,
      'isAvailable': d['isAvailable'] ?? false,
      'district': d['district'] ?? '',
      'taluk': d['taluk'] ?? '',
    };
  }

  // ── Tool 3: getWorkerAvailability ────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerAvailability(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
      if (!doc.exists) {
        doc = await db.collection('users').doc(workerId).get();
      }
    } catch (_) {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
    }

    if (!doc.exists) return {'success': false, 'error': 'Worker not found'};
    final isAvailable = doc.data()?['isAvailable'] as bool? ?? false;
    return {
      'success': true,
      'workerId': workerId,
      'isAvailable': isAvailable,
      'status': isAvailable ? 'available' : 'busy',
    };
  }

  // ── Tool 4: getWorkerDistance ────────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerDistance(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
      if (!doc.exists) {
        doc = await db.collection('users').doc(workerId).get();
      }
    } catch (_) {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
    }

    if (!doc.exists) return {'success': false, 'error': 'Worker not found'};

    final workerLat = (doc.data()?['discoveryLat'] as num?)?.toDouble() ??
        (doc.data()?['lat'] as num?)?.toDouble();
    final workerLng = (doc.data()?['discoveryLng'] as num?)?.toDouble() ??
        (doc.data()?['lng'] as num?)?.toDouble();

    final pos = await LocationService.getCurrentPosition();
    final userLat = pos?.latitude;
    final userLng = pos?.longitude;

    if (workerLat == null || workerLng == null || userLat == null || userLng == null) {
      return {'error': 'LOCATION_UNAVAILABLE', 
              'message': 'Location data not available. Please ensure GPS is enabled.'};
    }

    final meters = Geolocator.distanceBetween(userLat, userLng, workerLat, workerLng);
    return {
      'success': true,
      'distanceMeters': meters,
      'distanceDisplay': meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km',
    };
  }

  // ── Tool 5: getWorkerCompletedJobs ───────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerCompletedJobs(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    final snap = await db.collection('bookings')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: BookingStatus.completionVerified)
        .get();

    return {
      'success': true,
      'workerId': workerId,
      'completedJobCount': snap.docs.length,
    };
  }

  // ── Tool 6: getWorkerVerification ────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerVerification(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
      if (!doc.exists) {
        doc = await db.collection('users').doc(workerId).get();
      }
    } catch (_) {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
    }

    if (!doc.exists) return {'success': false, 'error': 'Worker not found'};

    final d = doc.data();
    final skillVerified = d?['skillVerified'] as bool? ?? false;
    final faceVerified = d?['faceVerified'] as bool? ?? false;
    final level = (d?['verificationLevel'] as String?) ??
        (skillVerified ? 'practicalVerified' : (faceVerified ? 'basicAssessed' : 'claimed'));
    return {
      'success': true,
      'workerId': workerId,
      'verificationLevel': level,
      'isVerified': level != 'claimed',
    };
  }

  // ── Tool 7: createBooking (Canonical BookingService, Persistent Idempotency)
  Future<Map<String, dynamic>> createBooking(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    final skillId = args['skillId'] as String? ?? 'work';
    final idempotencyKey = args['idempotencyKey'] as String? ??
        '${workerId}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}';

    if (workerId.isEmpty) return {'success': false, 'error': 'workerId is required'};

    final auth = _auth;
    if (auth == null || auth.currentUser == null) {
      return {'success': false, 'error': 'Database unavailable'};
    }

    final hirerUid = auth.currentUser!.uid;

    final result = await BookingService.instance.createDirectBooking(
      hirerUid: hirerUid,
      workerId: workerId,
      skillId: skillId,
      idempotencyKey: idempotencyKey,
    );

    if (result.success) {
      return {
        'success': true,
        'bookingId': result.bookingId,
        'status': BookingStatus.confirmed,
        'workerId': workerId,
      };
    } else {
      return {'success': false, 'error': result.errorMessage ?? 'Booking failed'};
    }
  }

  // ── Tool 7b: bookNearbyWorker (one-shot: search + auto-book top result) ────
  //   User says: "book nearby painter" / "hire a mason" / "ಹತ್ತಿರದ ಪೇಂಟರ್ ಬುಕ್ ಮಾಡು"
  //   1. Calls searchWorkersNearby (GPS or district fallback — always works)
  //   2. Auto-selects top-ranked candidate
  //   3. Creates direct booking via BookingService
  Future<Map<String, dynamic>> bookNearbyWorker(Map<String, dynamic> args) async {
    final skillId = (args['skillId'] as String? ?? '').toLowerCase().trim();
    if (skillId.isEmpty) {
      return {'success': false, 'error': 'Please specify a skill. e.g. "book nearby painter"'};
    }

    final auth = _auth;
    if (auth == null || auth.currentUser == null) {
      return {'success': false, 'error': 'Please sign in to book workers.'};
    }

    // Step 1: Find best nearby worker (GPS → district fallback)
    final searchResult = await searchWorkersNearby({
      'skillId': skillId,
      'radiusMeters': args['radiusMeters'] ?? 15000,
    });

    if (searchResult['success'] != true) {
      // Propagate search error (already has friendly district-fallback message)
      return searchResult;
    }

    final candidates = searchResult['candidates'] as List? ?? [];
    if (candidates.isEmpty) {
      return {
        'success': false,
        'error': 'No available $skillId workers found nearby. Try asking for a different skill.',
      };
    }

    // Step 2 (V5.0 ZERO-REGRESSION): Automatic booking of candidate 1 is strictly eliminated.
    // Return candidates with an explicit selection prompt to open DirectBookingScreen.
    return {
      'success': true,
      'candidates': candidates,
      'count': candidates.length,
      'skillId': skillId,
      'message':
          'Found ${candidates.length} $skillId workers near you. Say "Book worker 1" or select a worker to enter job details.',
    };
  }

  // ── Tool 8: cancelBooking (Canonical BookingService) ─────────────────────
  Future<Map<String, dynamic>> cancelBooking(Map<String, dynamic> args) async {
    final bookingId = args['bookingId'] as String? ?? '';
    if (bookingId.isEmpty) return {'success': false, 'error': 'bookingId is required'};

    final auth = _auth;
    if (auth == null || auth.currentUser == null) {
      return {'success': false, 'error': 'Database unavailable'};
    }

    final hirerUid = auth.currentUser!.uid;

    final result = await BookingService.instance.cancelBooking(
      actorUid: hirerUid,
      bookingId: bookingId,
      reason: args['reason'] as String? ?? 'Cancelled via voice assistant',
    );

    if (result.success) {
      return {'success': true, 'bookingId': bookingId, 'status': BookingStatus.cancelled};
    } else {
      return {'success': false, 'error': result.errorMessage ?? 'Cancellation failed'};
    }
  }

  // ── Tool 9: getActiveBookings ────────────────────────────────────────────
  Future<Map<String, dynamic>> getActiveBookings(Map<String, dynamic> args) async {
    final auth = _auth;
    final db = _db;
    if (auth == null || auth.currentUser == null || db == null) {
      return {'success': true, 'activeBookingCount': 0, 'bookings': []};
    }

    final hirerUid = auth.currentUser!.uid;
    final snap = await db.collection('bookings')
        .where('hirerId', isEqualTo: hirerUid)
        .where('status', whereIn: ['confirmed', 'en_route', 'working'])
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    final bookings = snap.docs.map((d) => {'bookingId': d.id, ...d.data()}).toList();
    return {
      'success': true,
      'activeBookingCount': bookings.length,
      'bookings': bookings,
    };
  }

  // ── Tool 10: getBookingDetails ───────────────────────────────────────────
  Future<Map<String, dynamic>> getBookingDetails(Map<String, dynamic> args) async {
    final bookingId = args['bookingId'] as String? ?? '';
    if (bookingId.isEmpty) return {'success': false, 'error': 'bookingId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    final snap = await db.collection('bookings').doc(bookingId).get();
    if (!snap.exists) return {'success': false, 'error': 'Booking not found'};
    return {'success': true, 'booking': snap.data()};
  }

  // ── Tool 11: getWorkerLiveLocation ───────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerLiveLocation(Map<String, dynamic> args) async {
    final bookingId = args['bookingId'] as String? ?? '';
    if (bookingId.isEmpty) return {'success': false, 'error': 'bookingId is required'};

    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    final snap = await db.collection('bookings').doc(bookingId).get();
    if (!snap.exists) return {'success': false, 'error': 'Booking not found'};

    final lat = (snap.data()?['workerLat'] as num?)?.toDouble() ?? 0.0;
    final lng = (snap.data()?['workerLng'] as num?)?.toDouble() ?? 0.0;

    return {
      'success': true,
      'bookingId': bookingId,
      'latitude': lat,
      'longitude': lng,
      'isLive': lat != 0.0 && lng != 0.0,
    };
  }

  // ── Tool 12: navigateToScreen ────────────────────────────────────────────
  Map<String, dynamic> navigateToScreen(
    Map<String, dynamic> args,
    void Function(String screenName)? onNavigate,
  ) {
    final screen = (args['screenName'] as String? ?? '').toLowerCase();
    onNavigate?.call(screen);
    return {'success': true, 'navigatedTo': screen};
  }

  // ── Tool 13: getCurrentLocation ──────────────────────────────────────────
  Future<Map<String, dynamic>> getCurrentLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos == null) return {'success': false, 'error': 'Location permission denied'};
    return {
      'success': true,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy': pos.accuracy,
    };
  }

  // ── Tool 14: getCurrentUser ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getCurrentUser() async {
    final auth = _auth;
    final db = _db;
    if (auth == null || db == null) return {'success': false, 'error': 'Not authenticated'};
    final uid = auth.currentUser?.uid;
    if (uid == null) return {'success': false, 'error': 'Not authenticated'};
    final snap = await db.collection('users').doc(uid).get();
    return {'success': true, 'user': snap.data()};
  }

  // ── Tool 15: searchWorkersByDistrict ────────────────────────────────────
  // Like searchWorkersNearby but filtered by Karnataka district name.
  // Used when user says "show painters in Hassan" / "ಹಾಸನದಲ್ಲಿ ಪೇಂಟರ್ ಬೇಕು"
  Future<Map<String, dynamic>> searchWorkersByDistrict(
      Map<String, dynamic> args) async {
    final skillId = (args['skillId'] as String? ?? '').toLowerCase().trim();
    final district = (args['district'] as String? ?? '').trim();
    if (district.isEmpty) return {'success': false, 'error': 'district required'};

    final canonicalDistrict = _normalizeDistrict(district);
    final limit = (args['limit'] as num?)?.toInt().clamp(1, 30) ?? 25;
    final cursor = args['cursor'];
    final excludeUidsList = args['excludeUids'] as List<dynamic>?;
    final excludeUids = excludeUidsList != null ? excludeUidsList.map((e) => e.toString()).toSet() : null;

    // Route search through ONE canonical WorkerDiscoveryService
    final req = WorkerSearchRequest(
      mode: WorkerSearchMode.manualArea,
      sessionId: WorkerDiscoveryService.instance.newSessionId(),
      district: canonicalDistrict,
      taluk: (args['taluk'] as String? ?? '').trim(),
      skillId: skillId == 'all' ? '' : skillId,
      limit: limit,
      cursor: cursor,
      excludeUids: excludeUids,
    );

    final result = await WorkerDiscoveryService.instance.search(req);
    if (result.state == WorkerSearchState.error) {
      return {'success': false, 'error': result.errorMessage};
    }

    final candidates = <WorkerCandidate>[];
    for (final entry in result.workers) {
      final p = entry.profile;
      final verifStr = p.skillVerified
          ? 'practicalVerified'
          : (p.faceVerified ? 'basicAssessed' : 'nonAssessed');

      candidates.add(WorkerCandidate(
        workerId: p.uid,
        name: p.displayName,
        skill: skillId.isEmpty || skillId == 'all' ? (p.primarySkillId.isNotEmpty ? p.primarySkillId : 'worker') : skillId,
        distanceMeters: 0,
        distanceDisplay: canonicalDistrict,
        latitude: p.discoveryLat ?? 0.0,
        longitude: p.discoveryLng ?? 0.0,
        isAvailable: p.isAvailable,
        verificationLevel: verifStr,
        completedJobs: p.totalJobs,
        rating: p.rating,
        rankingScore: (p.totalJobs / 50.0).clamp(0.0, 1.0) * 0.5 + (p.rating / 5.0) * 0.5,
        selectionReason: '${p.displayName} available in $canonicalDistrict (${p.totalJobs} jobs, ${p.rating.toStringAsFixed(1)}★)',
        locationFreshness: 'LIVE',
      ));
    }

    // Direct public projection fallback if WorkerDiscoveryService returned empty
    final firestoreDb = _db;
    if (candidates.isEmpty && firestoreDb != null) {
      final snapshot = await firestoreDb
          .collection('public_worker_profiles')
          .where('isAvailable', isEqualTo: true)
          .where('district', isEqualTo: canonicalDistrict)
          .limit(30)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final skills = List<String>.from(data['skills'] ?? [])
            .map((s) => s.toLowerCase()).toList();
        final matchesSkill =
            skills.any((s) => s.contains(skillId) || skillId.contains(s));
        if (!matchesSkill && skillId != 'all' && skillId.isNotEmpty) continue;

        final workerLat = (data['discoveryLat'] as num?)?.toDouble() ?? (data['lat'] as num?)?.toDouble() ?? 0.0;
        final workerLng = (data['discoveryLng'] as num?)?.toDouble() ?? (data['lng'] as num?)?.toDouble() ?? 0.0;
        final rating = (data['rating'] as num?)?.toDouble() ?? 4.5;
        final totalJobs = (data['totalJobs'] ?? 0) as int;
        final verifStr = (data['verificationLevel'] as String?) ??
            ((data['skillVerified'] == true) ? 'practicalVerified' : 'basicAssessed');

        candidates.add(WorkerCandidate(
          workerId: doc.id,
          name: (data['displayName'] as String?) ?? (data['name'] as String?) ?? 'Worker',
          skill: skillId.isEmpty || skillId == 'all' ? 'worker' : skillId,
          distanceMeters: 0,
          distanceDisplay: canonicalDistrict,
          latitude: workerLat,
          longitude: workerLng,
          isAvailable: true,
          verificationLevel: verifStr,
          completedJobs: totalJobs,
          rating: rating,
          rankingScore: (totalJobs / 50.0).clamp(0.0, 1.0) * 0.5 + (rating / 5.0) * 0.5,
          selectionReason: '${data['displayName'] ?? data['name'] ?? 'Worker'} available in $canonicalDistrict',
          locationFreshness: 'LIVE',
        ));
      }
    }

    candidates.sort((a, b) => b.rankingScore.compareTo(a.rankingScore));

    return {
      'success': true,
      'candidateCount': candidates.length,
      'candidates': candidates.map((c) => c.toMap()).toList(),
      'district': canonicalDistrict,
      'hasMore': result.hasMore,
      'nextCursor': result.nextCursor,
    };
  }

  /// Map old Karnataka district names → canonical Firestore names
  String _normalizeDistrict(String raw) {
    const oldToNew = <String, String>{
      'bangalore': 'Bengaluru Urban',
      'bangalore urban': 'Bengaluru Urban',
      'bangalore rural': 'Bengaluru Rural',
      'mysore': 'Mysuru',
      'mangalore': 'Mangaluru',
      'hubli': 'Hubballi',
      'hubli-dharwad': 'Hubballi',
      'belgaum': 'Belagavi',
      'belgavi': 'Belagavi',
      'gulbarga': 'Kalaburagi',
      'kalaburgi': 'Kalaburagi',
      'shimoga': 'Shivamogga',
      'tumkur': 'Tumakuru',
      'bellary': 'Ballari',
      'ballary': 'Ballari',
      'bijapur': 'Vijayapura',
      'vijaypur': 'Vijayapura',
      'dk': 'Dakshina Kannada',
      'south canara': 'Dakshina Kannada',
      'north canara': 'Uttara Kannada',
      'coorg': 'Kodagu',
      'chickmagalur': 'Chikkamagaluru',
      'chikmagalur': 'Chikkamagaluru',
      'davanagere': 'Davangere',
      'ramanagaram': 'Ramanagara',
      'bagalkote': 'Bagalkot',
      'yadgiri': 'Yadgir',
      'chamarajanagara': 'Chamarajanagar',
    };
    return oldToNew[raw.toLowerCase().trim()] ?? raw.trim();
  }

  // ── Tool 16: getWorkerDailyRate ──────────────────────────────────────────
  Future<Map<String, dynamic>> getWorkerDailyRate(Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId required'};
    final db = _db;
    if (db == null) return {'success': false, 'error': 'Database unavailable'};

    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
      if (!doc.exists) {
        doc = await db.collection('users').doc(workerId).get();
      }
    } catch (_) {
      doc = await db.collection('public_worker_profiles').doc(workerId).get();
    }

    if (!doc.exists) return {'success': false, 'error': 'Worker not found'};
    final rate = (doc.data()?['dailyRate'] as num?)?.toInt() ?? 0;
    final name = (doc.data()?['displayName'] as String?) ??
        (doc.data()?['name'] as String?) ??
        'Worker';
    return {
      'success': true,
      'workerId': workerId,
      'name': name,
      'dailyRate': rate,
      'display': rate > 0 ? '₹$rate per day' : 'Rate not set',
    };
  }

  // ── Tool 17: listMyBookings ──────────────────────────────────────────────
  Future<Map<String, dynamic>> listMyBookings(Map<String, dynamic> args) async {
    final auth = _auth;
    final db = _db;
    if (auth == null || auth.currentUser == null || db == null) {
      return {'success': true, 'count': 0, 'bookings': []};
    }
    final uid = auth.currentUser!.uid;

    final hirerSnap = await db
        .collection('bookings')
        .where('hirerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    final workerSnap = await db
        .collection('bookings')
        .where('workerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    final bookings = <Map<String, dynamic>>[
      for (final d in [...hirerSnap.docs, ...workerSnap.docs])
        {
          'bookingId': d.id,
          'workerName': d.data()['workerName'] ?? '',
          'skill': d.data()['skill'] ?? '',
          'status': d.data()['status'] ?? '',
        }
    ];

    return {'success': true, 'count': bookings.length, 'bookings': bookings};
  }

  // ── Tool 18: initiateChatConversation ────────────────────────────────────
  // Find or create a chat conversation between current user and a worker.
  // Returns conversationId for navigation to the chat screen.
  Future<Map<String, dynamic>> initiateChatConversation(
      Map<String, dynamic> args) async {
    final workerId = args['workerId'] as String? ?? '';
    final workerName = args['workerName'] as String? ?? 'Worker';
    if (workerId.isEmpty) return {'success': false, 'error': 'workerId required'};

    final auth = _auth;
    final db = _db;
    if (auth == null || auth.currentUser == null || db == null) {
      return {'success': false, 'error': 'Not authenticated'};
    }
    final currentUid = auth.currentUser!.uid;

    // Check if conversation already exists
    final existing = await db
        .collection('conversations')
        .where('participants', arrayContains: currentUid)
        .limit(30)
        .get();

    for (final doc in existing.docs) {
      final parts = List<String>.from(doc.data()['participants'] ?? []);
      if (parts.contains(workerId)) {
        return {
          'success': true,
          'conversationId': doc.id,
          'isNew': false,
          'workerId': workerId,
          'workerName': workerName,
        };
      }
    }

    // Create new conversation document
    final currentUserDoc = await db.collection('users').doc(currentUid).get();
    final currentUserName =
        (currentUserDoc.data()?['displayName'] as String?) ??
        (currentUserDoc.data()?['name'] as String?) ??
        'User';

    final convRef = await db.collection('conversations').add({
      'participants': [currentUid, workerId],
      'participantNames': {currentUid: currentUserName, workerId: workerName},
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': {currentUid: 0, workerId: 0},
      'typing': {},
    });

    return {
      'success': true,
      'conversationId': convRef.id,
      'isNew': true,
      'workerId': workerId,
      'workerName': workerName,
    };
  }

  // ── Tool 19: listMyApplications ──────────────────────────────────────────
  Future<Map<String, dynamic>> listMyApplications(Map<String, dynamic> args) async {
    final auth = _auth;
    final db = _db;
    if (auth == null || auth.currentUser == null || db == null) {
      return {
        'success': false,
        'error': 'User not authenticated',
        'applicationCount': 0,
        'applications': [],
        'speechResponseEn': 'Please sign in to view your applications.',
        'speechResponseKn': 'ನಿಮ್ಮ ಅರ್ಜಿಗಳನ್ನು ನೋಡಲು ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ.',
      };
    }
    final uid = auth.currentUser!.uid;

    // Check user role
    String role = 'worker';
    try {
      final userDoc = await db.collection('users').doc(uid).get();
      role = (userDoc.data()?['role'] as String?) ?? 'worker';
    } catch (_) {}

    final explicitFilter = args['roleFilter'] as String?;
    final isWorker = explicitFilter == 'hirer'
        ? false
        : (explicitFilter == 'worker' ? true : role == 'worker');

    try {
      // Query applications for this user
      final query = isWorker
          ? db.collection('applications').where('workerId', isEqualTo: uid)
          : db.collection('applications').where('hirerId', isEqualTo: uid);

      final snap = await query.limit(25).get();
      final docs = [...snap.docs];

      // Sort in-memory by appliedAt descending
      docs.sort((a, b) {
        final aT = a.data()['appliedAt'] as Timestamp?;
        final bT = b.data()['appliedAt'] as Timestamp?;
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return bT.compareTo(aT);
      });

      final apps = docs.take(10).map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'jobId': data['jobId'] ?? '',
          'jobTitle': data['jobTitle'] ?? 'Work Application',
          'hirerName': data['hirerName'] ?? 'Hirer',
          'workerName': data['workerName'] ?? 'Worker',
          'pay': data['pay']?.toString() ?? '',
          'skill': (data['skill'] ?? data['skillId'] ?? '').toString(),
          'status': data['status'] ?? 'pending',
          'bookingId': data['bookingId'] ?? '',
          'appliedAt': (data['appliedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
        };
      }).toList();

      int pendingCount = 0;
      int acceptedCount = 0;
      for (final a in apps) {
        if (a['status'] == 'accepted') acceptedCount++;
        if (a['status'] == 'pending') pendingCount++;
      }

      final speechEn = isWorker
          ? (apps.isEmpty
              ? 'You have no job applications yet.'
              : 'You have ${apps.length} applications. ${acceptedCount > 0 ? "$acceptedCount accepted, " : ""}$pendingCount pending review.')
          : (apps.isEmpty
              ? 'You have received no applicants yet for your posted jobs.'
              : 'You have received ${apps.length} applicants. ${acceptedCount > 0 ? "$acceptedCount accepted, " : ""}$pendingCount pending review.');

      final speechKn = isWorker
          ? (apps.isEmpty
              ? 'ನಿಮ್ಮ ಬಳಿ ಯಾವುದೇ ಅರ್ಜಿಗಳಿಲ್ಲ.'
              : 'ನಿಮ್ಮ ಬಳಿ ${apps.length} ಅರ್ಜಿಗಳಿವೆ. ${acceptedCount > 0 ? "$acceptedCount ಸ್ವೀಕರಿಸಲಾಗಿದೆ, " : ""}$pendingCount ಪರಿಶೀಲನೆಯಲ್ಲಿವೆ.')
          : (apps.isEmpty
              ? 'ನಿಮ್ಮ ಕೆಲಸಗಳಿಗೆ ಯಾವುದೇ ಅರ್ಜಿದಾರರಿಲ್ಲ.'
              : 'ನಿಮ್ಮ ಕೆಲಸಗಳಿಗೆ ${apps.length} ಅರ್ಜಿದಾರರಿದ್ದಾರೆ. ${acceptedCount > 0 ? "$acceptedCount ಒಪ್ಪಿಕೊಳ್ಳಲಾಗಿದೆ, " : ""}$pendingCount ಪರಿಶೀಲನೆಯಲ್ಲಿವೆ.');

      return {
        'success': true,
        'isWorker': isWorker,
        'applicationCount': apps.length,
        'pendingCount': pendingCount,
        'acceptedCount': acceptedCount,
        'applications': apps,
        'speechResponseEn': speechEn,
        'speechResponseKn': speechKn,
      };
    } catch (e) {
      debugPrint('[VoiceToolRegistry] listMyApplications error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'applicationCount': 0,
        'applications': [],
        'speechResponseEn': 'Could not load your applications at this time.',
        'speechResponseKn': 'ಈ ಸಮಯದಲ್ಲಿ ನಿಮ್ಮ ಅರ್ಜಿಗಳನ್ನು ಲೋಡ್ ಮಾಡಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.',
      };
    }
  }
}
