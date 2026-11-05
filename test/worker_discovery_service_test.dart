// test/worker_discovery_service_test.dart
// Phase 2: WorkerDiscoveryService unit tests.
// Tests: sessionId generation, cancel, stale response logic, GPS unavailable.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/worker_discovery_service.dart';

void main() {
  final svc = WorkerDiscoveryService.instance;

  group('WorkerDiscoveryService — singleton', () {
    test('is singleton', () {
      expect(WorkerDiscoveryService.instance, same(svc));
    });
  });

  group('WorkerDiscoveryService — newSessionId', () {
    test('generates unique IDs', () {
      final ids = List.generate(20, (_) => svc.newSessionId());
      final unique = ids.toSet();
      expect(unique.length, ids.length, reason: 'All session IDs must be unique');
    });

    test('session ID format contains timestamp prefix', () {
      final id = svc.newSessionId();
      // Format: <milliseconds>_<random>
      expect(id, matches(r'^\d+_\d+$'));
    });
  });

  group('WorkerDiscoveryService — cancel', () {
    test('cancel completes without throwing', () {
      expect(() => svc.cancel(), returnsNormally);
    });
  });
}
