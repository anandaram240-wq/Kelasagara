// test/worker_search_request_test.dart
// Phase 2: WorkerSearchRequest model tests.
// Tests: validation, mode logic, field defaults, session ID.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/worker_search_request.dart';

void main() {
  group('WorkerSearchRequest — construction', () {
    test('default values are correct', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sess1',
        district: 'Hassan',
      );
      expect(req.taluk, '');
      expect(req.skillId, '');
      expect(req.limit, 15);
      expect(req.cursor, isNull);
      expect(req.hirerPosition, isNull);
    });

    test('all fields round-trip correctly', () {
      const pos = LatLng(13.1, 76.1);
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'abc123',
        hirerPosition: pos,
        district: 'Hassan',
        taluk: 'Belur',
        skillId: 'mason',
        limit: 10,
      );
      expect(req.mode, WorkerSearchMode.nearbyGps);
      expect(req.sessionId, 'abc123');
      expect(req.hirerPosition, pos);
      expect(req.district, 'Hassan');
      expect(req.taluk, 'Belur');
      expect(req.skillId, 'mason');
      expect(req.limit, 10);
    });
  });

  group('WorkerSearchRequest — validation', () {
    test('manualArea with district: valid', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 's1',
        district: 'Mysuru',
      );
      expect(req.validate(), isNull);
    });

    test('manualArea without district: error', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 's2',
      );
      expect(req.validate(), isNotNull);
      expect(req.validate(), contains('District'));
    });

    test('nearbyGps with position: valid', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 's3',
        hirerPosition: const LatLng(12.9, 77.5),
      );
      expect(req.validate(), isNull);
    });

    test('nearbyGps without position: error — LOCATION_UNAVAILABLE', () {
      // GPS failure must return location error, not a fallback coordinate.
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 's4',
        hirerPosition: null,
      );
      expect(req.validate(), isNotNull);
      expect(req.validate(), contains('unavailable'));
    });

    test('limit < 1: error', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 's5',
        district: 'Hassan',
        limit: 0,
      );
      expect(req.validate(), isNotNull);
    });

    test('limit > 30: error', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 's6',
        district: 'Hassan',
        limit: 31,
      );
      expect(req.validate(), isNotNull);
    });

    test('limit 30: valid', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 's7',
        district: 'Hassan',
        limit: 30,
      );
      expect(req.validate(), isNull);
    });
  });
}
