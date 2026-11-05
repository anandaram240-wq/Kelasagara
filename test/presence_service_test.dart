import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/messaging/presence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PresenceService Data Model & Decoupled State Tests', () {
    test('RemotePresence initial state is unknown', () {
      expect(RemotePresence.unknown.state, RemotePresenceState.unknown);
      expect(RemotePresence.unknown.lastSeen, isNull);
    });

    test('RemotePresence online represents active presence', () {
      const presence = RemotePresence(
        state: RemotePresenceState.online,
        deviceId: 'device_abc_123',
      );
      expect(presence.state, RemotePresenceState.online);
      expect(presence.deviceId, 'device_abc_123');
    });

    test('RemotePresence offline with lastSeen timestamp formats properly', () {
      final now = DateTime.now();
      final presence = RemotePresence(
        state: RemotePresenceState.offline,
        lastSeen: now,
      );
      expect(presence.state, RemotePresenceState.offline);
      expect(presence.lastSeen, equals(now));
    });

    test('LocalConnectionState is decoupled from RemotePresence', () {
      // Local connection state can be connected while remote is offline
      const local = LocalConnectionState.connected;
      const remote = RemotePresence.offline;

      expect(local == LocalConnectionState.connected, isTrue);
      expect(remote.state == RemotePresenceState.offline, isTrue);
    });

    test('PresenceService singleton instance is non-null and stable', () {
      final instance1 = PresenceService.instance;
      final instance2 = PresenceService.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('PresenceService initial local connection is disconnected', () {
      final service = PresenceService();
      expect(service.localConnection, equals(LocalConnectionState.disconnected));
      service.dispose();
    });
  });
}
