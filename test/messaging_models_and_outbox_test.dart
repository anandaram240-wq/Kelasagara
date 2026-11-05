// test/messaging_models_and_outbox_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelasagaara/models/messaging/chat_message.dart';
import 'package:kelasagaara/services/messaging/messaging_outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    MessagingOutboxService.instance.cancelPendingRetries();
  });

  group('ChatMessage model tests', () {
    test('Standard text message serialization round-trip', () {
      final msg = ChatMessage(
        clientMessageId: 'msg_1001',
        conversationId: 'conv_123',
        senderId: 'user_a',
        recipientId: 'user_b',
        text: 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?',
        status: MessageStatus.sent,
        sentAt: DateTime(2026, 10, 4, 10, 30),
        seenBy: ['user_a'],
      );

      expect(msg.isMe('user_a'), isTrue);
      expect(msg.isMe('user_b'), isFalse);
      expect(msg.hasReply, isFalse);
      expect(msg.isLocation, isFalse);
      expect(msg.isVoice, isFalse);

      final map = msg.toFirestoreMap();
      expect(map['messageId'], 'msg_1001');
      expect(map['clientMessageId'], 'msg_1001');
      expect(map['conversationId'], 'conv_123');
      expect(map['senderId'], 'user_a');
      expect(map['recipientId'], 'user_b');
      expect(map['text'], 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?');
      expect(map['type'], 'text');
    });

    test('Quoted reply message serialization round-trip', () {
      final msg = ChatMessage(
        clientMessageId: 'msg_1002',
        conversationId: 'conv_123',
        senderId: 'user_b',
        recipientId: 'user_a',
        text: 'ಹೌದು, ನಾನು ತಲುಪಿದ್ದೇನೆ',
        status: MessageStatus.sent,
        sentAt: DateTime(2026, 10, 4, 10, 31),
        seenBy: ['user_b'],
        replyToId: 'msg_1001',
        replyToText: 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?',
        replyToSenderId: 'user_a',
      );

      expect(msg.hasReply, isTrue);
      expect(msg.replyToId, 'msg_1001');
      expect(msg.replyToText, 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?');
      expect(msg.replyToSenderId, 'user_a');

      final map = msg.toFirestoreMap();
      expect(map['replyToId'], 'msg_1001');
      expect(map['replyToText'], 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?');
      expect(map['replyToSenderId'], 'user_a');

      // Deserialization via fromDoc
      final restored = ChatMessage.fromDoc('msg_1002', {
        ...map,
        'sentAt': Timestamp.fromDate(msg.sentAt),
      });

      expect(restored.clientMessageId, 'msg_1002');
      expect(restored.hasReply, isTrue);
      expect(restored.replyToId, 'msg_1001');
      expect(restored.replyToText, 'ನಮಸ್ಕಾರ, ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದ್ದೀರಾ?');
      expect(restored.replyToSenderId, 'user_a');
      expect(restored.text, 'ಹೌದು, ನಾನು ತಲುಪಿದ್ದೇನೆ');
    });

    test('Location message serialization round-trip', () {
      final msg = ChatMessage(
        clientMessageId: 'msg_1003',
        conversationId: 'conv_123',
        senderId: 'user_a',
        recipientId: 'user_b',
        text: '📍 Shared Location',
        type: 'location',
        status: MessageStatus.sent,
        sentAt: DateTime(2026, 10, 4, 10, 32),
        seenBy: ['user_a'],
        locationLat: 13.0068,
        locationLng: 76.0996,
        locationAddress: 'Hassan Bus Stand',
      );

      expect(msg.isLocation, isTrue);
      expect(msg.locationLat, closeTo(13.0068, 0.0001));
      expect(msg.locationLng, closeTo(76.0996, 0.0001));

      final map = msg.toFirestoreMap();
      expect(map['type'], 'location');
      expect(map['locationLat'], 13.0068);
      expect(map['locationLng'], 76.0996);
      expect(map['locationAddress'], 'Hassan Bus Stand');

      final restored = ChatMessage.fromDoc('msg_1003', {
        ...map,
        'sentAt': Timestamp.fromDate(msg.sentAt),
      });

      expect(restored.isLocation, isTrue);
      expect(restored.locationLat, closeTo(13.0068, 0.0001));
      expect(restored.locationLng, closeTo(76.0996, 0.0001));
      expect(restored.locationAddress, 'Hassan Bus Stand');
    });

    test('Status transitions: sent -> delivered -> read', () {
      final now = DateTime.now();
      final sentMsg = ChatMessage(
        clientMessageId: 'msg_1004',
        conversationId: 'c1',
        senderId: 'u1',
        recipientId: 'u2',
        text: 'Hello',
        status: MessageStatus.sent,
        sentAt: now,
        seenBy: ['u1'],
      );

      expect(sentMsg.isDelivered, isFalse);
      expect(sentMsg.isRead, isFalse);

      final deliveredMsg = sentMsg.copyWith(
        status: MessageStatus.delivered,
        deliveredAt: now.add(const Duration(seconds: 1)),
      );
      expect(deliveredMsg.isDelivered, isTrue);
      expect(deliveredMsg.isRead, isFalse);

      final readMsg = deliveredMsg.copyWith(
        status: MessageStatus.read,
        readAt: now.add(const Duration(seconds: 2)),
        seenBy: ['u1', 'u2'],
      );
      expect(readMsg.isDelivered, isTrue);
      expect(readMsg.isRead, isTrue);
    });
  });

  group('MessagingOutboxService tests', () {
    test('enqueueMessage produces optimistic ChatMessage with unique ID and replies', () async {
      final outbox = MessagingOutboxService.instance;

      final msg = await outbox.enqueueMessage(
        myUid: 'worker_ramesh',
        recipientUid: 'hirer_suresh',
        convId: 'conv_worker_hirer_1',
        text: 'ಸ್ಥಳಕ್ಕೆ ತಲುಪಿದ್ದೇನೆ',
        replyToId: 'msg_prev_99',
        replyToText: 'ಎಷ್ಟು ಹೊತ್ತಿಗೆ ಬರುತ್ತೀರಿ?',
        replyToSenderId: 'hirer_suresh',
      );

      expect(msg.clientMessageId, startsWith('msg_'));
      expect(msg.senderId, 'worker_ramesh');
      expect(msg.recipientId, 'hirer_suresh');
      expect(msg.conversationId, 'conv_worker_hirer_1');
      expect(msg.status, MessageStatus.sending);
      expect(msg.hasReply, isTrue);
      expect(msg.replyToId, 'msg_prev_99');
      expect(msg.replyToText, 'ಎಷ್ಟು ಹೊತ್ತಿಗೆ ಬರುತ್ತೀರಿ?');
      expect(msg.replyToSenderId, 'hirer_suresh');

      // Verify message appears in conversation pending queue
      final pending = outbox.getPendingForConversation('conv_worker_hirer_1');
      expect(pending.any((m) => m.clientMessageId == msg.clientMessageId), isTrue);

      // Acknowledge committed to clean up
      await outbox.acknowledgeServerCommitted(msg.clientMessageId);
      final remaining = outbox.getPendingForConversation('conv_worker_hirer_1');
      expect(remaining.any((m) => m.clientMessageId == msg.clientMessageId), isFalse);
    });

    test('enqueueMessage location sharing queues correctly', () async {
      final outbox = MessagingOutboxService.instance;

      final msg = await outbox.enqueueMessage(
        myUid: 'worker_ramesh',
        recipientUid: 'hirer_suresh',
        convId: 'conv_loc_test',
        text: '📍 Shared Location',
        type: 'location',
        locationLat: 12.9716,
        locationLng: 77.5946,
      );

      expect(msg.isLocation, isTrue);
      expect(msg.locationLat, closeTo(12.9716, 0.0001));
      expect(msg.locationLng, closeTo(77.5946, 0.0001));

      await outbox.acknowledgeServerCommitted(msg.clientMessageId);
    });
  });
}
