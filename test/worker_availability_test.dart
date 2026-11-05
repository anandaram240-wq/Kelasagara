// test/worker_availability_test.dart
// Tests for WorkerAvailabilityService freshness and constants.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/worker_availability_service.dart';

void main() {
  group('WorkerAvailabilityService.checkFreshness', () {
    test('fresh: updated 5 minutes ago', () {
      final updatedAt = DateTime.now().subtract(const Duration(minutes: 5));
      expect(
        WorkerAvailabilityService.checkFreshness(updatedAt),
        LocationFreshness.fresh,
      );
    });

    test('fresh: updated 1 minute ago', () {
      final updatedAt = DateTime.now().subtract(const Duration(minutes: 1));
      expect(
        WorkerAvailabilityService.checkFreshness(updatedAt),
        LocationFreshness.fresh,
      );
    });

    test('recent: updated 15 minutes ago', () {
      final updatedAt = DateTime.now().subtract(const Duration(minutes: 15));
      expect(
        WorkerAvailabilityService.checkFreshness(updatedAt),
        LocationFreshness.recent,
      );
    });

    test('stale: updated 35 minutes ago', () {
      final updatedAt = DateTime.now().subtract(const Duration(minutes: 35));
      expect(
        WorkerAvailabilityService.checkFreshness(updatedAt),
        LocationFreshness.stale,
      );
    });

    test('stale: updated 2 hours ago', () {
      final updatedAt = DateTime.now().subtract(const Duration(hours: 2));
      expect(
        WorkerAvailabilityService.checkFreshness(updatedAt),
        LocationFreshness.stale,
      );
    });

    test('unknown: null updatedAt', () {
      expect(
        WorkerAvailabilityService.checkFreshness(null),
        LocationFreshness.unknown,
      );
    });

    test('boundary: exactly 10 minutes is fresh', () {
      final updatedAt = DateTime.now().subtract(WorkerAvailabilityService.kFreshThreshold);
      // Allow 1 second tolerance for test execution time
      final f = WorkerAvailabilityService.checkFreshness(updatedAt);
      expect(f == LocationFreshness.fresh || f == LocationFreshness.recent, isTrue);
    });

    test('boundary: exactly 30 minutes is recent or stale', () {
      final updatedAt = DateTime.now().subtract(WorkerAvailabilityService.kRecentThreshold);
      final f = WorkerAvailabilityService.checkFreshness(updatedAt);
      expect(f == LocationFreshness.recent || f == LocationFreshness.stale, isTrue);
    });

    test('singleton is same instance', () {
      expect(
        identical(WorkerAvailabilityService.instance, WorkerAvailabilityService.instance),
        isTrue,
      );
    });

    test('isSessionActive is false initially', () {
      // Fresh singleton, no session started
      expect(WorkerAvailabilityService.instance.currentSessionId, isNull);
    });
  });

  group('Constants', () {
    test('kFreshThreshold is 10 minutes', () {
      expect(WorkerAvailabilityService.kFreshThreshold.inMinutes, 10);
    });
    test('kRecentThreshold is 30 minutes', () {
      expect(WorkerAvailabilityService.kRecentThreshold.inMinutes, 30);
    });
    test('kStaleAfter is 30 minutes', () {
      expect(WorkerAvailabilityService.kStaleAfter.inMinutes, 30);
    });
    test('kMinMovementMeters is 50', () {
      expect(WorkerAvailabilityService.kMinMovementMeters, 50.0);
    });
    test('kHeartbeatInterval is 10 minutes', () {
      expect(WorkerAvailabilityService.kHeartbeatInterval.inMinutes, 10);
    });
  });
}
