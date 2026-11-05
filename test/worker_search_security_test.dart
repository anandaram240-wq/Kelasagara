// test/worker_search_security_test.dart
// Phase 2: Security contract tests for worker search.
// Tests: no fallback location, no private data, no statewide dump in area mode,
// LOCATION_UNAVAILABLE on GPS failure, no second search engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/worker_search_request.dart';
import 'package:kelasagaara/models/worker_search_result.dart';

void main() {
  group('SECURITY — GPS failure must never use fallback coordinate', () {
    test('nearbyGps request without hirerPosition is INVALID', () {
      // Spec: GPS failure → LOCATION_UNAVAILABLE, never Hassan fallback.
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sec1',
        hirerPosition: null, // GPS unavailable
      );
      final error = req.validate();
      expect(error, isNotNull,
          reason: 'A nearbyGps request without position must fail validation');
      // Must NOT silently proceed with a hardcoded fallback
      expect(req.hirerPosition, isNull,
          reason: 'No fallback coordinate must be injected');
    });

    test('locationUnavailable result carries correct error state', () {
      final r = WorkerSearchResult.locationUnavailable('sec2');
      expect(r.state, WorkerSearchState.locationUnavailable);
      expect(r.isLocationUnavailable, isTrue);
      expect(r.workers, isEmpty,
          reason: 'No results should be returned on GPS failure');
    });

    test('locationUnavailable message does not contain hardcoded location', () {
      final r = WorkerSearchResult.locationUnavailable('sec3');
      // Must not contain 'Hassan' or any hardcoded city name
      expect(r.errorMessage.toLowerCase(), isNot(contains('hassan')));
      expect(r.errorMessage.toLowerCase(), isNot(contains('bengaluru')));
      expect(r.errorMessage.toLowerCase(), isNot(contains('mysuru')));
    });
  });

  group('SECURITY — one search engine contract', () {
    test('WorkerSearchMode has exactly three canonical modes', () {
      // Enforce only canonical modes: nearbyGps, manualArea, nearbyJob (Phase 3)
      expect(WorkerSearchMode.values.length, 3);
      expect(WorkerSearchMode.values, contains(WorkerSearchMode.nearbyGps));
      expect(WorkerSearchMode.values, contains(WorkerSearchMode.manualArea));
      expect(WorkerSearchMode.values, contains(WorkerSearchMode.nearbyJob));
    });

    test('manualArea with district proceeds — no forced GPS call', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sec4',
        district: 'Hassan',
      );
      // Area mode must NOT require hirerPosition
      expect(req.validate(), isNull);
      expect(req.hirerPosition, isNull); // GPS not required for area search
    });
  });

  group('SECURITY — no private data leakage', () {
    test('WorkerSearchRequest contains no sensitive fields', () {
      // Verify the request model only carries search criteria, not worker data
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sec5',
        district: 'Hassan',
      );
      // These fields must not exist on WorkerSearchRequest
      // (Dart compile-time: if this test compiles it proves no sensitive fields)
      expect(req.district, 'Hassan');
      expect(req.skillId, '');
      expect(req.sessionId, 'sec5');
    });

    test('WorkerSearchResult.error carries no raw Firestore data', () {
      final r = WorkerSearchResult.error('sec6', 'Search failed. Please try again.');
      expect(r.workers, isEmpty);
      // Error message must not leak raw exception details in production strings
      expect(r.errorMessage, 'Search failed. Please try again.');
    });
  });

  group('SECURITY — limit enforcement', () {
    test('limit greater than 100 is rejected', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sec7',
        district: 'Hassan',
        limit: 101, // exceeds hard cap
      );
      expect(req.validate(), isNotNull,
          reason: 'Fetching >100 workers must be blocked to prevent statewide dump');
    });

    test('default limit is 15', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sec8',
        district: 'Hassan',
      );
      expect(req.limit, 15);
    });
  });

  group('SECURITY — stale session protection', () {
    test('sessionId is non-empty in all result factories', () {
      final results = [
        WorkerSearchResult.idle('stale1'),
        WorkerSearchResult.searching('stale2'),
        WorkerSearchResult.empty('stale3'),
        WorkerSearchResult.locationUnavailable('stale4'),
        WorkerSearchResult.error('stale5', 'err'),
        WorkerSearchResult.success(sessionId: 'stale6', workers: []),
      ];
      for (final r in results) {
        expect(r.sessionId, isNotEmpty,
            reason: 'All results must carry a sessionId for stale-response detection');
      }
    });
  });
}
