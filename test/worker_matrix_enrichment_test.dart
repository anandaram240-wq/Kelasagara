// test/worker_matrix_enrichment_test.dart
// Phase 2: MatrixService integration contract tests.
// Tests: enrichment path, ETA note on unavailability, fallback behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/worker_search_result.dart';
import 'package:kelasagaara/models/user_profile.dart';

UserProfile _worker(String uid) => UserProfile(
      uid: uid,
      userId: 'w_$uid',
      displayName: 'Worker $uid',
      district: 'Hassan',
      taluk: 'Belur',
      skills: const ['mason'],
      rating: 4.2,
      totalJobs: 5,
      isAvailable: true,
      role: 'worker',
      dailyRate: 800,
      accountStatus: AccountStatus.approved,
    );

void main() {
  group('MatrixService enrichment — WorkerSearchEntry contract', () {
    test('entry with no coordinates has null roadDistanceM', () {
      // Workers currently have no lat/lng — MatrixService cannot enrich them.
      // Entries must carry null distance, not a fake 0 or hardcoded value.
      final e = WorkerSearchEntry(
        profile: _worker('w1'),
        roadDistanceM: null,
        roadDurationSec: null,
        isActualRoadDistance: false,
        etaNote: 'Road ETA unavailable',
      );
      expect(e.roadDistanceM, isNull);
      expect(e.roadDurationSec, isNull);
      expect(e.distanceKm, isNull);
      expect(e.etaMinutes, isNull);
      expect(e.etaNote, 'Road ETA unavailable');
      expect(e.isActualRoadDistance, isFalse);
    });

    test('entry with MatrixService road distance has correct values', () {
      // When workers gain lat/lng, MatrixService provides real road distance.
      final e = WorkerSearchEntry(
        profile: _worker('w2'),
        roadDistanceM: 3500.0, // 3.5 km road distance
        roadDurationSec: 420,  // 7 minutes
        isActualRoadDistance: true,
        etaNote: '',
      );
      expect(e.roadDistanceM, 3500.0);
      expect(e.distanceKm, closeTo(3.5, 0.01));
      expect(e.roadDurationSec, 420);
      expect(e.etaMinutes, 7);
      expect(e.isActualRoadDistance, isTrue);
    });

    test('entry with haversine fallback carries isActualRoadDistance=false', () {
      // MatrixService haversine fallback (1.4× road factor):
      // still valid, but marked as estimated.
      final e = WorkerSearchEntry(
        profile: _worker('w3'),
        roadDistanceM: 7000.0,
        roadDurationSec: 1008,
        isActualRoadDistance: false, // haversine fallback
        etaNote: 'ETA estimated',
      );
      expect(e.isActualRoadDistance, isFalse);
      expect(e.etaNote, 'ETA estimated');
      expect(e.distanceKm, closeTo(7.0, 0.01));
    });

    test('MatrixService failure — workers still appear in results', () {
      // Spec: Matrix failure is non-fatal. Workers appear with etaNote.
      final entries = [
        WorkerSearchEntry(
          profile: _worker('w4'),
          etaNote: 'Road ETA unavailable',
        ),
        WorkerSearchEntry(
          profile: _worker('w5'),
          etaNote: 'Road ETA unavailable',
        ),
      ];
      final result = WorkerSearchResult.success(
        sessionId: 'mat1',
        workers: entries,
      );
      expect(result.hasResults, isTrue);
      expect(result.workers.length, 2);
      for (final e in result.workers) {
        expect(e.roadDistanceM, isNull);
        expect(e.etaNote, 'Road ETA unavailable');
      }
    });

    test('road distance vs geographic distance are separate fields', () {
      // Spec: "Road distance separated from geographic (straight-line) distance."
      final e = WorkerSearchEntry(
        profile: _worker('w6'),
        roadDistanceM: 8400.0, // road (includes detours)
        // There is no straightLineM field — geographic is computed separately if needed
      );
      expect(e.roadDistanceM, 8400.0);
      // geographic distance is NOT stored in WorkerSearchEntry — only road distance
    });
  });

  group('MatrixService enrichment — multiple workers ranking', () {
    test('workers can be sorted by roadDistanceM', () {
      final entries = [
        WorkerSearchEntry(
          profile: _worker('far'),
          roadDistanceM: 15000.0,
          roadDurationSec: 1800,
          isActualRoadDistance: true,
        ),
        WorkerSearchEntry(
          profile: _worker('near'),
          roadDistanceM: 2000.0,
          roadDurationSec: 300,
          isActualRoadDistance: true,
        ),
        WorkerSearchEntry(
          profile: _worker('mid'),
          roadDistanceM: 7500.0,
          roadDurationSec: 900,
          isActualRoadDistance: true,
        ),
      ];

      final sorted = [...entries]
        ..sort((a, b) =>
            (a.roadDistanceM ?? double.infinity)
                .compareTo(b.roadDistanceM ?? double.infinity));

      expect(sorted[0].profile.uid, 'near');
      expect(sorted[1].profile.uid, 'mid');
      expect(sorted[2].profile.uid, 'far');
    });
  });
}
