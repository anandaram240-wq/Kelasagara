// lib/models/worker_search_result.dart
// ONE canonical search result model for WorkerDiscoveryService.

import 'user_profile.dart';

/// State of a worker search operation.
enum WorkerSearchState {
  /// Idle — no search has been run yet.
  idle,

  /// Search is in progress.
  searching,

  /// Search completed with results.
  success,

  /// Search completed with zero results.
  empty,

  /// GPS position unavailable (permission denied or timeout).
  locationUnavailable,

  /// Firestore or network error.
  error,
}

/// A single worker in the search results, enriched with optional ETA data.
class WorkerSearchEntry {
  final UserProfile profile;

  /// Road distance in meters. Null if no GPS or MatrixService failed.
  final double? roadDistanceM;

  /// Road duration in seconds. Null if no GPS or MatrixService failed.
  final int? roadDurationSec;

  /// True if road distance was from actual matrix API (not haversine estimate).
  final bool isActualRoadDistance;

  /// Note shown to user about ETA status.
  final String etaNote;

  /// Straight-line (haversine) distance from hirer to worker in metres.
  /// Populated for GPS-mode searches. Null for area-mode searches.
  final double? geoDistanceM;

  const WorkerSearchEntry({
    required this.profile,
    this.roadDistanceM,
    this.roadDurationSec,
    this.isActualRoadDistance = false,
    this.etaNote = '',
    this.geoDistanceM,
  });

  /// Convenience: distance in km, rounded to 1 decimal.
  double? get distanceKm =>
      roadDistanceM != null ? roadDistanceM! / 1000 : null;

  /// Convenience: ETA in minutes.
  int? get etaMinutes =>
      roadDurationSec != null ? (roadDurationSec! / 60).ceil() : null;

  /// Straight-line distance in km, rounded to 1 decimal.
  double? get geoDistanceKm =>
      geoDistanceM != null ? geoDistanceM! / 1000 : null;

  /// Display distance: road if available, else haversine straight-line.
  double? get bestDistanceKm => distanceKm ?? geoDistanceKm;

  /// Whether the displayed distance is a road distance (not haversine).
  bool get isRoadDistance => isActualRoadDistance && roadDistanceM != null;
}

/// The complete result of a worker discovery search.
class WorkerSearchResult {
  final WorkerSearchState state;
  final List<WorkerSearchEntry> workers;
  final String errorMessage;
  final String sessionId;

  /// Whether more results are available (for pagination).
  final bool hasMore;

  /// Cursor for next page (defaults to lastScannedDocumentCursor).
  final Object? nextCursor;

  /// Raw document snapshot where scanning physically halted in Firestore.
  final Object? lastScannedDocumentCursor;

  /// Last candidate entry yielded to caller in the current page.
  final WorkerSearchEntry? lastReturnedCandidate;

  const WorkerSearchResult({
    required this.state,
    required this.sessionId,
    this.workers = const [],
    this.errorMessage = '',
    this.hasMore = false,
    this.nextCursor,
    this.lastScannedDocumentCursor,
    this.lastReturnedCandidate,
  });

  factory WorkerSearchResult.idle(String sessionId) =>
      WorkerSearchResult(state: WorkerSearchState.idle, sessionId: sessionId);

  factory WorkerSearchResult.searching(String sessionId) =>
      WorkerSearchResult(state: WorkerSearchState.searching, sessionId: sessionId);

  factory WorkerSearchResult.success({
    required String sessionId,
    required List<WorkerSearchEntry> workers,
    bool hasMore = false,
    Object? nextCursor,
    Object? lastScannedDocumentCursor,
    WorkerSearchEntry? lastReturnedCandidate,
  }) {
    final effectiveScanCursor = lastScannedDocumentCursor ?? nextCursor;
    final effectiveCandidate = lastReturnedCandidate ?? (workers.isNotEmpty ? workers.last : null);
    return WorkerSearchResult(
      state: WorkerSearchState.success,
      sessionId: sessionId,
      workers: workers,
      hasMore: hasMore,
      nextCursor: nextCursor ?? effectiveScanCursor,
      lastScannedDocumentCursor: effectiveScanCursor,
      lastReturnedCandidate: effectiveCandidate,
    );
  }

  factory WorkerSearchResult.empty(String sessionId) =>
      WorkerSearchResult(state: WorkerSearchState.empty, sessionId: sessionId);

  factory WorkerSearchResult.locationUnavailable(String sessionId) =>
      WorkerSearchResult(
        state: WorkerSearchState.locationUnavailable,
        sessionId: sessionId,
        errorMessage: 'GPS location unavailable. Switch to manual area search.',
      );

  factory WorkerSearchResult.error(String sessionId, String message) =>
      WorkerSearchResult(
        state: WorkerSearchState.error,
        sessionId: sessionId,
        errorMessage: message,
      );

  bool get isSearching => state == WorkerSearchState.searching;
  bool get hasResults => state == WorkerSearchState.success && workers.isNotEmpty;
  bool get isLocationUnavailable => state == WorkerSearchState.locationUnavailable;
}
