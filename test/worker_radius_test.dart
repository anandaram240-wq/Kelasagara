// test/worker_radius_test.dart
// Tests for WorkerSearchRequest radius validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/worker_search_request.dart';

void main() {
  const pos = LatLng(13.0068, 76.0996);

  group('WorkerSearchRequest radius validation', () {
    test('default radius is 10.0 km', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
      );
      expect(req.radiusKm, 10.0);
    });

    test('valid radius 5 km passes validation', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
        radiusKm: 5.0,
      );
      expect(req.validate(), isNull);
    });

    test('valid radius 50 km passes validation', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
        radiusKm: 50.0,
      );
      expect(req.validate(), isNull);
    });

    test('valid radius 100 km passes validation', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
        radiusKm: 100.0,
      );
      expect(req.validate(), isNull);
    });

    test('radius 150 km fails validation', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
        radiusKm: 150.0,
      );
      expect(req.validate(), isNotNull);
    });

    test('radius 0.1 km fails validation', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'sess1',
        hirerPosition: pos,
        radiusKm: 0.1,
      );
      expect(req.validate(), isNotNull);
    });

    test('manualArea mode ignores radius', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.manualArea,
        sessionId: 'sess1',
        district: 'Hassan',
        radiusKm: 100.0, // Would fail for GPS mode
      );
      expect(req.validate(), isNull); // manualArea doesn't check radius
    });
  });

  group('WorkerSearchMode nearbyJob', () {
    test('nearbyJob requires hirerPosition', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyJob,
        sessionId: 's',
        // no hirerPosition
      );
      expect(req.validate(), isNotNull);
    });

    test('nearbyJob with position and valid radius passes', () {
      final req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyJob,
        sessionId: 's',
        hirerPosition: pos,
        radiusKm: 15.0,
      );
      expect(req.validate(), isNull);
    });
  });
}
