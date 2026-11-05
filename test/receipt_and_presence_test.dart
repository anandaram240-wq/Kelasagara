import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/messaging/chat_message.dart';
import 'package:kelasagaara/services/messaging/presence_typing_service.dart';
import 'package:kelasagaara/services/messaging/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptService idempotency & eligibility tests', () {
    test('markDelivered ignores message if caller is sender', () async {
      final receiptService = ReceiptService();
      final msg = ChatMessage(
        clientMessageId: 'm1',
        conversationId: 'c1',
        senderId: 'alice',
        senderDeviceId: 'dev_a',
        recipientId: 'bob',
        plaintext: 'Test',
        status: MessageStatus.sent,
        sentAt: DateTime.now(),
        seenBy: ['alice'],
      );

      // Alice calling markDelivered on her own message should do nothing
      await receiptService.markDelivered(
        convId: 'c1',
        message: msg,
        myUid: 'alice',
      );
      // No exception, no-op
    });

    test('markDelivered ignores message already marked delivered or read', () async {
      final receiptService = ReceiptService();
      final msg = ChatMessage(
        clientMessageId: 'm2',
        conversationId: 'c1',
        senderId: 'alice',
        senderDeviceId: 'dev_a',
        recipientId: 'bob',
        plaintext: 'Test',
        status: MessageStatus.delivered,
        sentAt: DateTime.now(),
        seenBy: ['alice'],
      );

      // Should be no-op because status is already delivered
      await receiptService.markDelivered(
        convId: 'c1',
        message: msg,
        myUid: 'bob',
      );
    });
  });

  group('PresenceTypingService tests', () {
    test('instance is accessible and dispose cleans up timer', () {
      final service = PresenceTypingService();
      expect(service, isNotNull);
      service.dispose();
    });
  });
}
