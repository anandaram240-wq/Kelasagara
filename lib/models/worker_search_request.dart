// lib/models/worker_search_request.dart
// ONE canonical search request model for WorkerDiscoveryService.
// Voice AI and Hirer UI both use this — no second model ever.

import 'package:latlong2/latlong.dart';

/// Search mode — how the search is geographically scoped.
enum WorkerSearchMode {
  /// GPS mode: hirer's current GPS location is available.
  /// Results are shown with distance if possible.
  nearbyGps,

  /// Manual area mode: hirer selected district/taluk explicitly.
  manualArea,

  /// Job-origin mode: the search origin is a job's location, not hirer's GPS.
  /// hirerPosition holds the job's LatLng. Mode otherwise behaves like nearbyGps.
  nearbyJob,
}

/// ONE canonical model for all worker discovery requests.
/// Used by both hirer UI and voice AI.
class WorkerSearchRequest {
  /// Search mode (GPS or manual area).
  final WorkerSearchMode mode;

  /// Hirer's GPS position. Required when mode == nearbyGps.
  /// Null when mode == manualArea or GPS unavailable.
  final LatLng? hirerPosition;

  /// District filter. Required when mode == manualArea.
  /// Optional when mode == nearbyGps (can restrict search to a district).
  final String district;

  /// Taluk filter. Optional.
  final String taluk;

  /// Skill ID filter. Empty string means all skills.
  final String skillId;

  /// Maximum number of results to return. Default 15.
  final int limit;

  /// Cursor for pagination (last document snapshot).
  /// Null for first page.
  final Object? cursor; // DocumentSnapshot compatible

  /// Set of UIDs already displayed in previous pages, for deduplication across pagination boundaries.
  final Set<String>? excludeUids;

  /// Search radius in km. Only used when mode is nearbyGps or nearbyJob.
  /// Default 10 km. Max 100 km.
  final double radiusKm;

  /// Session ID for stale-response protection.
  /// Each new search generates a new session ID.
  final String sessionId;

  const WorkerSearchRequest({
    required this.mode,
    required this.sessionId,
    this.hirerPosition,
    this.district = '',
    this.taluk = '',
    this.skillId = '',
    this.limit = 15,
    this.cursor,
    this.excludeUids,
    this.radiusKm = 10.0,
  });

  /// Validate the request. Returns null if valid, error string if invalid.
  String? validate() {
    if (mode == WorkerSearchMode.manualArea && district.isEmpty) {
      return 'District is required for manual area search';
    }
    if (mode == WorkerSearchMode.nearbyGps && hirerPosition == null) {
      return 'GPS position unavailable';
    }
    if (mode == WorkerSearchMode.nearbyJob && hirerPosition == null) {
      return 'Job position unavailable';
    }
    if (limit < 1 || limit > 100) {
      return 'Limit must be 1–100';
    }
    if ((mode == WorkerSearchMode.nearbyGps || mode == WorkerSearchMode.nearbyJob) &&
        (radiusKm < 0.5 || radiusKm > 100.0)) {
      return 'Search radius must be 0.5–100 km';
    }
    return null;
  }
}
