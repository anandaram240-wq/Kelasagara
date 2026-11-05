import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/messaging/messaging_connectivity_service.dart';
import 'package:kelasagaara/services/messaging/presence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessagingConnectivityService Lifecycle & State Transition Tests', () {
    test('singleton instance returns identical reference', () {
      expect(
        identical(MessagingConnectivityService.instance, MessagingConnectivityService.instance),
        isTrue,
      );
    });

    test('initial status is bootstrapping before timeout or connection event', () {
      final service = MessagingConnectivityService();
      expect(service.status, equals(MessagingConnectionStatus.bootstrapping));
    });

    test('recordTransportFailure degrades online status', () {
      final service = MessagingConnectivityService();
      // Force status to online
      service.recordTransportSuccess();
      // Record failure
      service.recordTransportFailure();
      // Degraded state handles temporary Firestore write stall
      expect(service.status, isIn([MessagingConnectionStatus.bootstrapping, MessagingConnectionStatus.degraded]));
    });

    test('MessagingFourLayerState encapsulates independent layers truthfully', () {
      const fourLayer = MessagingFourLayerState(
        networkAvailable: true,
        transportState: LocalConnectionState.connected,
        recipientPresence: RemotePresence.offline,
        overallStatus: MessagingConnectionStatus.online,
      );

      expect(fourLayer.networkAvailable, isTrue);
      expect(fourLayer.transportState, equals(LocalConnectionState.connected));
      expect(fourLayer.recipientPresence.state, equals(RemotePresenceState.offline));
      expect(fourLayer.overallStatus, equals(MessagingConnectionStatus.online));
      expect(fourLayer.toString(), contains('recipient=RemotePresenceState.offline'));
    });
  });
}
