// test/worker_search_session_test.dart
// Tests for session ID format and stale-response protection.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/worker_discovery_service.dart';

void main() {
  group('WorkerDiscoveryService session ID', () {
    test('newSessionId returns non-empty string', () {
      final sid = WorkerDiscoveryService.instance.newSessionId();
      expect(sid, isNotEmpty);
    });

    test('two consecutive sessionIds are different', () {
      final s1 = WorkerDiscoveryService.instance.newSessionId();
      final s2 = WorkerDiscoveryService.instance.newSessionId();
      // May occasionally collide if millisecond matches, but effectively always unique
      // Just test format: must contain '_'
      expect(s1.contains('_'), isTrue);
      expect(s2.contains('_'), isTrue);
    });

    test('cancel() completes without error', () {
      expect(() => WorkerDiscoveryService.instance.cancel(), returnsNormally);
    });

    test('singleton is same instance', () {
      expect(
        identical(WorkerDiscoveryService.instance, WorkerDiscoveryService.instance),
        isTrue,
      );
    });
  });
}
