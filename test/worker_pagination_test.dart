// test/worker_pagination_test.dart
// Tests for pagination in WorkerSearchResult.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';
import 'package:kelasagaara/models/worker_search_result.dart';

UserProfile _fakeProfile(String uid) => UserProfile(uid: uid);

void main() {
  group('WorkerSearchResult pagination', () {
    test('nextCursor is null when hasMore is false', () {
      final result = WorkerSearchResult.success(
        sessionId: 's1',
        workers: [WorkerSearchEntry(profile: _fakeProfile('uid1'))],
        hasMore: false,
        nextCursor: null,
      );
      expect(result.hasMore, isFalse);
      expect(result.nextCursor, isNull);
    });

    test('nextCursor is non-null when hasMore is true', () {
      // Simulate passing a cursor object
      final fakeCursor = Object();
      final result = WorkerSearchResult.success(
        sessionId: 's1',
        workers: [WorkerSearchEntry(profile: _fakeProfile('uid1'))],
        hasMore: true,
        nextCursor: fakeCursor,
      );
      expect(result.hasMore, isTrue);
      expect(result.nextCursor, same(fakeCursor));
    });

    test('isSearching returns true for searching state', () {
      final result = WorkerSearchResult.searching('s1');
      expect(result.isSearching, isTrue);
    });

    test('hasResults returns true for success with workers', () {
      final result = WorkerSearchResult.success(
        sessionId: 's1',
        workers: [WorkerSearchEntry(profile: _fakeProfile('uid1'))],
      );
      expect(result.hasResults, isTrue);
    });

    test('hasResults is false for empty state', () {
      expect(WorkerSearchResult.empty('s1').hasResults, isFalse);
    });

    test('locationUnavailable has correct errorMessage', () {
      final r = WorkerSearchResult.locationUnavailable('s1');
      expect(r.state, WorkerSearchState.locationUnavailable);
      expect(r.errorMessage, isNotEmpty);
    });
  });

  group('WorkerSearchEntry distance accessors', () {
    test('geoDistanceKm converts metres to km', () {
      final entry = WorkerSearchEntry(
        profile: _fakeProfile('u1'),
        geoDistanceM: 3500.0,
      );
      expect(entry.geoDistanceKm, closeTo(3.5, 0.01));
    });

    test('distanceKm from roadDistanceM', () {
      final entry = WorkerSearchEntry(
        profile: _fakeProfile('u1'),
        roadDistanceM: 5200.0,
      );
      expect(entry.distanceKm, closeTo(5.2, 0.01));
    });

    test('bestDistanceKm prefers road over geo', () {
      final entry = WorkerSearchEntry(
        profile: _fakeProfile('u1'),
        geoDistanceM: 3000.0,
        roadDistanceM: 4500.0,
      );
      // bestDistanceKm = distanceKm ?? geoDistanceKm
      // distanceKm = roadDistanceM/1000 = 4.5
      expect(entry.bestDistanceKm, closeTo(4.5, 0.01));
    });

    test('etaMinutes converts seconds to minutes ceil', () {
      final entry = WorkerSearchEntry(
        profile: _fakeProfile('u1'),
        roadDurationSec: 490, // 8.17 min → ceil → 9
      );
      expect(entry.etaMinutes, 9);
    });
  });
}
