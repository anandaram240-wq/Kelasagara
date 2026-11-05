// lib/services/worker_discovery_service.dart
// Phase 3: ONE canonical WorkerDiscoveryService.
//
// This is the ONLY worker search engine in Kelasagara.
// Do NOT create VoiceWorkerSearchService, NearbyWorkerService,
// ManualAreaWorkerService, HirerSearchService2, or any second search engine.
//
// Used by:
//   - HirerDashboard (_FindWorkersSection)
//   - Voice AI (via VoiceToolRegistry — future migration)
//
// Data source: users/{uid} (approved workers only)
//
// NEARBY GPS MODE — geo query approach:
//   Firestore does not support true geospatial queries.
//   We use a lat-range bounding box (single-field inequality),
//   then filter by lng range and exact haversine in Dart.
//   Fetch up to 50 candidates → filter → paginate → MatrixService.
//   No geohash package required.
//
// AREA MODE:
//   District + optional taluk filter with indexed Firestore query.
//   No GPS required.
//
// MATRIX ENRICHMENT:
//   Workers now have discoveryLat/Lng — MatrixService receives real coords.
//   MatrixService failure is non-fatal; workers still appear with ETA unavailable.
//
// PAGINATION:
//   Cursor-based (startAfterDocument). hasMore detected by limit+1 trick.
//   nextCursor is the last DocumentSnapshot of the current page.

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/user_profile.dart';
import '../models/worker_search_request.dart';
import '../models/worker_search_result.dart';
import 'location_service.dart';
import 'routing/matrix_service.dart';
import 'worker_availability_service.dart';

/// ONE canonical worker discovery service.
/// Singleton — access via WorkerDiscoveryService.instance.
class WorkerDiscoveryService {
  WorkerDiscoveryService._();
  static final WorkerDiscoveryService instance = WorkerDiscoveryService._();

  /// Default marketplace collection: privacy-preserving public projection (V6.3.4.3 Gate 1).
  static String workerCollection = 'public_worker_profiles';

  // Stale-response guard — invalidates in-flight requests when a newer search starts.
  String? _activeSessionId;

  static final Random _random = Random();

  // ── Public API ────────────────────────────────────────────────────────

  /// Search for workers using [request].
  ///
  /// Returns a [WorkerSearchResult] with state and workers.
  /// Never throws — all errors are returned as [WorkerSearchState.error].
  ///
  /// For nearbyGps/nearbyJob:
  ///   - Bounding box Firestore query on discoveryLat
  ///   - Client-side lng + haversine + freshness + service-radius filters
  ///   - MatrixService enrichment with real worker coords
  ///
  /// For manualArea:
  ///   - district + optional taluk Firestore query
  ///   - MatrixService enrichment if hirer has GPS
  Future<WorkerSearchResult> search(WorkerSearchRequest request) async {
    // Register session — all prior sessions are now stale
    _activeSessionId = request.sessionId;
    final mySessionId = request.sessionId;

    // Validate
    final validationError = request.validate();
    if (validationError != null) {
      if ((request.mode == WorkerSearchMode.nearbyGps ||
              request.mode == WorkerSearchMode.nearbyJob) &&
          request.hirerPosition == null) {
        return WorkerSearchResult.locationUnavailable(mySessionId);
      }
      return WorkerSearchResult.error(mySessionId, validationError);
    }

    try {
      final isGpsMode = request.mode == WorkerSearchMode.nearbyGps ||
          request.mode == WorkerSearchMode.nearbyJob;

      _DiscoveryScanResult scanResult;
      if (isGpsMode) {
        scanResult = await _searchNearby(request, mySessionId);
      } else {
        scanResult = await _searchArea(request, mySessionId);
      }

      if (scanResult.isStale || _activeSessionId != mySessionId) {
        return WorkerSearchResult.idle(mySessionId);
      }

      final profiles = scanResult.profiles;
      final hasMore = scanResult.hasMore;
      final lastScannedDoc = scanResult.lastScannedDoc;

      if (profiles.isEmpty) {
        if (hasMore && lastScannedDoc != null) {
          return WorkerSearchResult.success(
            sessionId: mySessionId,
            workers: const [],
            hasMore: true,
            nextCursor: lastScannedDoc,
            lastScannedDocumentCursor: lastScannedDoc,
          );
        }
        return WorkerSearchResult.empty(mySessionId);
      }

      // ── MatrixService enrichment ──────────────────────────────────
      final entries = await _enrichWithMatrix(
        profiles: profiles,
        hirerPosition: request.hirerPosition,
        isGpsMode: isGpsMode,
        mySessionId: mySessionId,
      );

      if (_activeSessionId != mySessionId) {
        return WorkerSearchResult.idle(mySessionId);
      }

      // ── Ranking ───────────────────────────────────────────────────
      final ranked = _rank(entries);

      return WorkerSearchResult.success(
        sessionId: mySessionId,
        workers: ranked,
        hasMore: hasMore,
        nextCursor: hasMore ? lastScannedDoc : null,
        lastScannedDocumentCursor: lastScannedDoc,
        lastReturnedCandidate: ranked.isNotEmpty ? ranked.last : null,
      );
    } on FirebaseException catch (e) {
      debugPrint('[WorkerDiscoveryService] Firestore error: code=${e.code}, plugin=${e.plugin}, message=${e.message}');
      return WorkerSearchResult.error(
        mySessionId,
        'Worker search is temporarily unavailable. Please try again.',
      );
    } catch (e) {
      debugPrint('[WorkerDiscoveryService] Unexpected error: $e');
      return WorkerSearchResult.error(
        mySessionId,
        'Worker search is temporarily unavailable. Please try again.',
      );
    }
  }

  // ── GPS nearby search ─────────────────────────────────────────────────

  Future<_DiscoveryScanResult> _searchNearby(
    WorkerSearchRequest request,
    String mySessionId,
  ) async {
    final hirerPos = request.hirerPosition!;
    final hirerLat = hirerPos.latitude;
    final hirerLng = hirerPos.longitude;
    final radiusKm = request.radiusKm;

    // Bounding box: lat range (Firestore single-field inequality)
    // 1 degree latitude ≈ 111 km everywhere
    final latDelta = radiusKm / 111.0;
    // 1 degree longitude ≈ 111 km × cos(lat)
    final lngDelta = radiusKm / (111.0 * cos(hirerLat * pi / 180));

    final minLat = hirerLat - latDelta;
    final maxLat = hirerLat + latDelta;

    final pageSize = request.limit;
    const batchSize = 50;
    const maxBatches = 20; // Scan sparse datasets up to 1000 docs per invocation

    final filtered = <UserProfile>[];
    final seenUids = <String>{};
    if (request.excludeUids != null) {
      seenUids.addAll(request.excludeUids!);
    }

    DocumentSnapshot<Map<String, dynamic>>? currentCursor =
        request.cursor as DocumentSnapshot<Map<String, dynamic>>?;
    DocumentSnapshot<Map<String, dynamic>>? lastScannedDoc = currentCursor;
    bool lastBatchWasFull = false;

    for (int batch = 0; batch < maxBatches; batch++) {
      if (_activeSessionId != mySessionId) {
        return _DiscoveryScanResult.stale();
      }

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection(workerCollection);
      if (workerCollection == 'users') {
        q = q.where('role', isEqualTo: 'worker');
      }
      q = q
          .where('accountStatus', isEqualTo: 'approved')
          .where('isAvailable', isEqualTo: true)
          .where('discoveryLat', isGreaterThanOrEqualTo: minLat)
          .where('discoveryLat', isLessThanOrEqualTo: maxLat)
          .orderBy('discoveryLat')
          .limit(batchSize);

      if (request.skillId.isNotEmpty) {
        q = q.where('skills', arrayContains: request.skillId);
      }

      if (currentCursor != null) {
        q = q.startAfterDocument(currentCursor);
      }

      final snap = await q.get();

      if (_activeSessionId != mySessionId) {
        return _DiscoveryScanResult.stale();
      }

      final docs = snap.docs;
      lastBatchWasFull = docs.length == batchSize;
      if (docs.isEmpty) break;

      for (final doc in docs) {
        lastScannedDoc = doc;
        currentCursor = doc;
        final uid = doc.id;
        if (seenUids.contains(uid)) continue;

        final data = doc.data();
        final p = UserProfile.fromMap(doc.id, data);

        // Must have discovery location
        if (p.discoveryLat == null || p.discoveryLng == null) continue;

        // Lng bounding box (lat already filtered by Firestore)
        if ((p.discoveryLng! - hirerLng).abs() > lngDelta) continue;

        // Freshness check
        final freshness =
            WorkerAvailabilityService.checkFreshness(p.discoveryUpdatedAt);
        if (freshness == LocationFreshness.unknown &&
            p.discoveryUpdatedAt == null) {
          continue; // never shared location at all
        }

        // Exact haversine distance
        final distM = Geolocator.distanceBetween(
          hirerLat, hirerLng,
          p.discoveryLat!, p.discoveryLng!,
        );
        if (distM > radiusKm * 1000) continue;

        // Service radius: worker must declare willingness to serve this distance
        if (p.serviceRadiusKm > 0 && distM > p.serviceRadiusKm * 1000.0) continue;

        seenUids.add(uid);
        filtered.add(p);

        // Stop immediately once requested pageSize is reached!
        if (filtered.length >= pageSize) {
          break;
        }
      }

      if (filtered.length >= pageSize || !lastBatchWasFull) {
        break;
      }
    }

    final bool hasMore = filtered.length >= pageSize || lastBatchWasFull;

    return _DiscoveryScanResult.ok(
      profiles: filtered,
      lastScannedDoc: lastScannedDoc,
      hasMore: hasMore,
    );
  }

  // ── Manual area search ────────────────────────────────────────────────

  Future<_DiscoveryScanResult> _searchArea(
    WorkerSearchRequest request,
    String mySessionId,
  ) async {
    final pageSize = request.limit;
    const batchSize = 50;
    const maxBatches = 20; // Scan sparse datasets up to 1000 docs per invocation

    final filtered = <UserProfile>[];
    final seenUids = <String>{};
    if (request.excludeUids != null) {
      seenUids.addAll(request.excludeUids!);
    }

    DocumentSnapshot<Map<String, dynamic>>? currentCursor =
        request.cursor as DocumentSnapshot<Map<String, dynamic>>?;
    DocumentSnapshot<Map<String, dynamic>>? lastScannedDoc = currentCursor;
    bool lastBatchWasFull = false;

    for (int batch = 0; batch < maxBatches; batch++) {
      if (_activeSessionId != mySessionId) {
        return _DiscoveryScanResult.stale();
      }

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection(workerCollection);
      if (workerCollection == 'users') {
        q = q.where('role', isEqualTo: 'worker');
      }
      q = q
          .where('accountStatus', isEqualTo: 'approved')
          .where('isAvailable', isEqualTo: true)
          .where('district', isEqualTo: request.district.trim())
          .limit(batchSize);

      if (currentCursor != null) {
        q = q.startAfterDocument(currentCursor);
      }

      final snap = await q.get();

      if (_activeSessionId != mySessionId) {
        return _DiscoveryScanResult.stale();
      }

      final docs = snap.docs;
      lastBatchWasFull = docs.length == batchSize;
      if (docs.isEmpty) break;

      for (final doc in docs) {
        lastScannedDoc = doc;
        currentCursor = doc;
        final uid = doc.id;
        if (seenUids.contains(uid)) continue;

        final data = doc.data();

        // Taluk filter (client-side, flexible matching)
        if (request.taluk.isNotEmpty) {
          final t = ((data['taluk'] as String?) ?? '').toLowerCase().trim();
          final reqT = request.taluk.toLowerCase().trim();
          if (t.isNotEmpty && t != reqT && !t.contains(reqT) && !reqT.contains(t)) {
            continue;
          }
        }

        // Skill filter (optional, checks skills array and primarySkill)
        if (request.skillId.isNotEmpty) {
          final skills = (data['skills'] as List<dynamic>?)?.cast<String>() ?? [];
          final primary = ((data['primarySkill'] as String?) ?? '').toLowerCase();
          final reqSkill = request.skillId.toLowerCase().trim();
          final matches = skills.any((s) => s.toLowerCase() == reqSkill) || primary == reqSkill;
          if (!matches) {
            continue;
          }
        }

        seenUids.add(uid);
        filtered.add(UserProfile.fromMap(doc.id, data));

        // Stop immediately once requested pageSize is reached!
        if (filtered.length >= pageSize) {
          break;
        }
      }

      if (filtered.length >= pageSize || !lastBatchWasFull) {
        break;
      }
    }

    final bool hasMore = filtered.length >= pageSize || lastBatchWasFull;

    return _DiscoveryScanResult.ok(
      profiles: filtered,
      lastScannedDoc: lastScannedDoc,
      hasMore: hasMore,
    );
  }

  // ── Matrix enrichment ─────────────────────────────────────────────────

  Future<List<WorkerSearchEntry>> _enrichWithMatrix({
    required List<UserProfile> profiles,
    required LatLng? hirerPosition,
    required bool isGpsMode,
    required String mySessionId,
  }) async {
    if (hirerPosition == null) {
      // No hirer GPS — no Matrix, no geo distance
      return profiles
          .map((p) => WorkerSearchEntry(
                profile: p,
                etaNote: 'Road ETA unavailable',
              ))
          .toList();
    }

    // Build geo distances (haversine) for all profiles that have coords
    final geoDistances = <String, double>{};
    final workerLocations = <String, LatLng>{};

    for (final p in profiles) {
      if (p.discoveryLat != null && p.discoveryLng != null) {
        final distM = Geolocator.distanceBetween(
          hirerPosition.latitude, hirerPosition.longitude,
          p.discoveryLat!, p.discoveryLng!,
        );
        geoDistances[p.uid] = distM;
        workerLocations[p.uid] = LatLng(p.discoveryLat!, p.discoveryLng!);
      }
    }

    // MatrixService enrichment (non-fatal)
    Map<String, WorkerDistanceRank> rankMap = {};
    if (workerLocations.isNotEmpty) {
      try {
        final ranks = await MatrixService.instance.rankWorkersByDistance(
          hirerLocation: hirerPosition,
          workerLocations: workerLocations,
        ).timeout(const Duration(milliseconds: 1500), onTimeout: () {
          debugPrint('[WorkerDiscoveryService] MatrixService timeout (1.5s) — fallback to straight-line');
          return const [];
        });
        rankMap = {for (final r in ranks) r.workerId: r};
        debugPrint(
          '[WorkerDiscoveryService] Matrix enriched ${ranks.length}/${profiles.length} workers',
        );
      } catch (e) {
        debugPrint('[WorkerDiscoveryService] MatrixService error (non-fatal): $e');
      }
    }

    // Build entries — each worker gets geo + optional road distance
    return profiles.map((p) {
      final rank = rankMap[p.uid];
      final geoM = geoDistances[p.uid];
      return WorkerSearchEntry(
        profile: p,
        geoDistanceM: geoM,
        roadDistanceM: rank?.roadDistanceM,
        roadDurationSec: rank?.roadDurationSec,
        isActualRoadDistance: rank?.isRoadDistance ?? false,
        etaNote: rank != null
            ? (rank.isRoadDistance
                ? 'Approx. ${(rank.roadDurationSec / 60).ceil()} min'
                : 'ETA estimated')
            : (geoM != null ? '' : 'Road ETA unavailable'),
      );
    }).toList();
  }

  // ── Ranking ───────────────────────────────────────────────────────────
  //
  // Deterministic ranking factors (in order of priority):
  //   1. Road distance (ascending) if available from Matrix
  //   2. Geo distance (ascending) if road distance unavailable
  //   3. Rating (descending)
  //   4. Total jobs (descending)
  //   5. Face verified (true first)
  //   6. Skill verified (true first)

  List<WorkerSearchEntry> _rank(List<WorkerSearchEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      // 1. Road or geo distance (closer = better)
      final aDist = a.roadDistanceM ?? a.geoDistanceM ?? double.maxFinite;
      final bDist = b.roadDistanceM ?? b.geoDistanceM ?? double.maxFinite;
      final distCmp = aDist.compareTo(bDist);
      if (distCmp != 0) return distCmp;

      // Available workers first
      if (a.profile.isAvailable != b.profile.isAvailable) {
        return a.profile.isAvailable ? -1 : 1;
      }

      // 2. Rating (higher = better)
      final ratingCmp = b.profile.rating.compareTo(a.profile.rating);
      if (ratingCmp != 0) return ratingCmp;

      // 3. Total jobs (more = better)
      final jobsCmp = b.profile.totalJobs.compareTo(a.profile.totalJobs);
      if (jobsCmp != 0) return jobsCmp;

      // 4. Face verified first
      if (a.profile.faceVerified != b.profile.faceVerified) {
        return a.profile.faceVerified ? -1 : 1;
      }

      // 5. Skill verified first
      if (a.profile.skillVerified != b.profile.skillVerified) {
        return a.profile.skillVerified ? -1 : 1;
      }

      return 0;
    });
    return sorted;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Get the hirer's current GPS position.
  /// Returns null if permission denied or GPS unavailable. Never throws.
  Future<LatLng?> getHirerPosition() async {
    try {
      final pos = await LocationService.getFastPosition();
      if (pos == null) return null;
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Generate a unique session ID for stale-response protection.
  String newSessionId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(99999)}';

  /// Cancel the current in-flight search.
  void cancel() {
    _activeSessionId = null;
    debugPrint('[WorkerDiscoveryService] Search cancelled');
  }
}

/// Internal immutable result from a batch scan pass in Firestore.
class _DiscoveryScanResult {
  final bool isStale;
  final List<UserProfile> profiles;
  final DocumentSnapshot<Map<String, dynamic>>? lastScannedDoc;
  final bool hasMore;

  const _DiscoveryScanResult({
    required this.isStale,
    this.profiles = const [],
    this.lastScannedDoc,
    this.hasMore = false,
  });

  factory _DiscoveryScanResult.stale() => const _DiscoveryScanResult(isStale: true);

  factory _DiscoveryScanResult.ok({
    required List<UserProfile> profiles,
    DocumentSnapshot<Map<String, dynamic>>? lastScannedDoc,
    required bool hasMore,
  }) =>
      _DiscoveryScanResult(
        isStale: false,
        profiles: profiles,
        lastScannedDoc: lastScannedDoc,
        hasMore: hasMore,
      );
}
