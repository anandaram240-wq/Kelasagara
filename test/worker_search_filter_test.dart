// test/worker_search_filter_test.dart
// Phase 2: WorkerSearchResult + WorkerSearchEntry model tests.
// Tests: state machines, factory constructors, entry accessors.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/worker_search_result.dart';
import 'package:kelasagaara/models/user_profile.dart';

UserProfile _fakeWorker({String uid = 'w1', String district = 'Hassan'}) =>
    UserProfile(
      uid: uid,
      userId: 'worker_$uid',
      displayName: 'Worker $uid',
      district: district,
      taluk: 'Belur',
      skills: const ['mason'],
      rating: 4.5,
      totalJobs: 12,
      isAvailable: true,
      role: 'worker',
      dailyRate: 700,
      accountStatus: AccountStatus.approved,
    );

void main() {
  group('WorkerSearchResult — factory constructors', () {
    test('idle: correct state', () {
      final r = WorkerSearchResult.idle('s1');
      expect(r.state, WorkerSearchState.idle);
      expect(r.workers, isEmpty);
      expect(r.errorMessage, '');
      expect(r.sessionId, 's1');
    });

    test('searching: correct state', () {
      final r = WorkerSearchResult.searching('s2');
      expect(r.state, WorkerSearchState.searching);
      expect(r.isSearching, isTrue);
    });

    test('success: correct state, workers, hasMore', () {
      final entry = WorkerSearchEntry(profile: _fakeWorker());
      final r = WorkerSearchResult.success(
        sessionId: 's3',
        workers: [entry],
        hasMore: true,
      );
      expect(r.state, WorkerSearchState.success);
      expect(r.hasResults, isTrue);
      expect(r.workers.length, 1);
      expect(r.hasMore, isTrue);
    });

    test('empty: correct state', () {
      final r = WorkerSearchResult.empty('s4');
      expect(r.state, WorkerSearchState.empty);
      expect(r.hasResults, isFalse);
      expect(r.workers, isEmpty);
    });

    test('locationUnavailable: correct state and message', () {
      final r = WorkerSearchResult.locationUnavailable('s5');
      expect(r.state, WorkerSearchState.locationUnavailable);
      expect(r.isLocationUnavailable, isTrue);
      // Must never fallback to Hassan or any coordinate
      expect(r.errorMessage, isNotEmpty);
      expect(r.errorMessage.toLowerCase(), contains('unavailable'));
    });

    test('error: correct state and message', () {
      final r = WorkerSearchResult.error('s6', 'Firestore timeout');
      expect(r.state, WorkerSearchState.error);
      expect(r.errorMessage, 'Firestore timeout');
    });
  });

  group('WorkerSearchEntry — accessors', () {
    test('distanceKm is null when no road distance', () {
      final e = WorkerSearchEntry(profile: _fakeWorker());
      expect(e.roadDistanceM, isNull);
      expect(e.distanceKm, isNull);
      expect(e.etaMinutes, isNull);
    });

    test('distanceKm converts correctly', () {
      final e = WorkerSearchEntry(
        profile: _fakeWorker(),
        roadDistanceM: 5000,
        roadDurationSec: 600,
        isActualRoadDistance: true,
      );
      expect(e.distanceKm, closeTo(5.0, 0.01));
      expect(e.etaMinutes, 10);
    });

    test('etaMinutes rounds up', () {
      final e = WorkerSearchEntry(
        profile: _fakeWorker(),
        roadDistanceM: 1000,
        roadDurationSec: 61, // 1m 1s → ceil to 2 min
      );
      expect(e.etaMinutes, 2);
    });

    test('etaNote set when no road data', () {
      final e = WorkerSearchEntry(
        profile: _fakeWorker(),
        etaNote: 'Road ETA unavailable',
      );
      expect(e.etaNote, 'Road ETA unavailable');
    });
  });

  group('WorkerSearchResult — bool helpers', () {
    test('isSearching true only for searching state', () {
      expect(WorkerSearchResult.searching('x').isSearching, isTrue);
      expect(WorkerSearchResult.idle('x').isSearching, isFalse);
      expect(WorkerSearchResult.empty('x').isSearching, isFalse);
    });

    test('hasResults only true when success with workers', () {
      final entry = WorkerSearchEntry(profile: _fakeWorker());
      expect(WorkerSearchResult.success(sessionId: 'x', workers: [entry]).hasResults, isTrue);
      expect(WorkerSearchResult.success(sessionId: 'x', workers: []).hasResults, isFalse);
      expect(WorkerSearchResult.empty('x').hasResults, isFalse);
    });
  });
}
