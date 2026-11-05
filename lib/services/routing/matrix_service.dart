// lib/services/routing/matrix_service.dart
// V400 Matrix Routing Service for Kelasagara.
//
// Provides multi-point distance/duration matrix for worker ranking.
// Used by Voice AI and hirer UI to rank workers by real road distance
// instead of straight-line haversine.
//
// Provider priority:
//   1. Valhalla /sources_to_targets (if configured)
//   2. OSRM /table/v1/driving (public, free)
//   3. Haversine fallback with 1.4× road factor

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'routing_provider.dart';
import 'routing_orchestrator.dart';

/// Result of a worker distance ranking.
class WorkerDistanceRank {
  final String workerId;
  final LatLng workerLocation;
  final double roadDistanceM;
  final int roadDurationSec;
  final bool isRoadDistance; // false if haversine fallback

  const WorkerDistanceRank({
    required this.workerId,
    required this.workerLocation,
    required this.roadDistanceM,
    required this.roadDurationSec,
    this.isRoadDistance = true,
  });
}

/// V400 Matrix Service for multi-worker distance ranking.
///
/// Given a hirer's location and a list of worker locations, returns
/// workers ranked by real road distance (not straight-line).
class MatrixService {
  MatrixService._();
  static final MatrixService instance = MatrixService._();

  /// Rank workers by road distance from hirer location.
  ///
  /// Returns workers sorted by ascending road distance.
  /// Falls back to haversine × 1.4 if no matrix provider is available.
  Future<List<WorkerDistanceRank>> rankWorkersByDistance({
    required LatLng hirerLocation,
    required Map<String, LatLng> workerLocations,
  }) async {
    if (workerLocations.isEmpty) return const [];

    final workerIds = workerLocations.keys.toList();
    final workerCoords = workerLocations.values.toList();

    // Try matrix routing via orchestrator
    try {
      final matrixResult = await RoutingOrchestrator.instance.getMatrix(
        sources: [hirerLocation],
        targets: workerCoords,
      );

      if (matrixResult != null &&
          matrixResult.distances.isNotEmpty &&
          matrixResult.distances[0].length == workerCoords.length) {
        final ranks = <WorkerDistanceRank>[];
        for (int i = 0; i < workerIds.length; i++) {
          final dist = matrixResult.distances[0][i];
          final dur = matrixResult.durations[0][i];
          if (dist != null && dur != null) {
            ranks.add(WorkerDistanceRank(
              workerId: workerIds[i],
              workerLocation: workerCoords[i],
              roadDistanceM: dist,
              roadDurationSec: dur,
              isRoadDistance: true,
            ));
          } else {
            // Fallback for this specific worker
            ranks.add(_haversineFallback(
              workerIds[i], workerCoords[i], hirerLocation,
            ));
          }
        }
        ranks.sort((a, b) => a.roadDistanceM.compareTo(b.roadDistanceM));
        debugPrint('[MatrixService] Ranked ${ranks.length} workers by road distance');
        return ranks;
      }
    } catch (e) {
      debugPrint('[MatrixService] Matrix failed: $e — using haversine fallback');
    }

    // Haversine fallback with 1.4× road distance factor
    final ranks = workerIds.asMap().entries.map((entry) {
      return _haversineFallback(
        entry.value, workerCoords[entry.key], hirerLocation,
      );
    }).toList();

    ranks.sort((a, b) => a.roadDistanceM.compareTo(b.roadDistanceM));
    debugPrint('[MatrixService] Ranked ${ranks.length} workers by haversine (fallback)');
    return ranks;
  }

  /// Haversine distance with 1.4× road factor.
  /// 1.4 is the typical road-to-straight-line ratio for Indian cities.
  WorkerDistanceRank _haversineFallback(
    String workerId, LatLng worker, LatLng hirer,
  ) {
    final straightLine = Geolocator.distanceBetween(
      hirer.latitude, hirer.longitude,
      worker.latitude, worker.longitude,
    );
    const roadFactor = 1.4;
    final estimatedRoadDist = straightLine * roadFactor;
    // Estimate duration at 25 km/h average city speed
    final estimatedDurationSec = (estimatedRoadDist / (25000 / 3600)).round();
    return WorkerDistanceRank(
      workerId: workerId,
      workerLocation: worker,
      roadDistanceM: estimatedRoadDist,
      roadDurationSec: estimatedDurationSec,
      isRoadDistance: false,
    );
  }
}
