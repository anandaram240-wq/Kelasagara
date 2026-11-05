import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/messaging/chat_message.dart';
import 'messaging_outbox_service.dart';
import 'receipt_service.dart';

/// Single source of truth for messages in an active conversation.
/// Streams messages directly from Firestore snapshots, merges optimistic
/// local outbox items, and triggers delivery receipts upon message arrival.
class MessageRepository {
  final FirebaseFirestore? _customFirestore;
  final MessagingOutboxService _outboxService;
  final ReceiptService _receiptService;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  MessageRepository({
    FirebaseFirestore? firestore,
    MessagingOutboxService? outboxService,
    ReceiptService? receiptService,
  })  : _customFirestore = firestore,
        _outboxService = outboxService ?? MessagingOutboxService.instance,
        _receiptService = receiptService ?? ReceiptService.instance;

  static final MessageRepository instance = MessageRepository();

  /// Create stream of messages for [convId], merged with optimistic Outbox.
  Stream<List<ChatMessage>> streamConversationMessages({
    required String convId,
    required String myUid,
    required String otherUid,
  }) {
    late StreamController<List<ChatMessage>> controller;
    StreamSubscription? firestoreSub;
    StreamSubscription? outboxSub;

    List<ChatMessage> lastRemoteMessages = [];

    void emitMerged() {
      if (controller.isClosed) return;
      final pending = _outboxService.getPendingForConversation(convId);
      final remoteIds = lastRemoteMessages.map((m) => m.clientMessageId).toSet();

      // Filter out pending messages that already appear in remote list
      final effectivePending = pending.where((p) => !remoteIds.contains(p.clientMessageId)).toList();

      final combined = [...lastRemoteMessages, ...effectivePending];
      combined.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      controller.add(combined);
    }

    controller = StreamController<List<ChatMessage>>(
      onListen: () {
        emitMerged();
        try {
          firestoreSub = _firestore
              .collection('conversations')
              .doc(convId)
              .collection('messages')
              .orderBy('sentAt')
              .snapshots()
              .listen((snap) {
            final parsed = <ChatMessage>[];

            for (final doc in snap.docs) {
              final data = doc.data();
              final msg = ChatMessage.fromDoc(doc.id, data);
              parsed.add(msg);

              // Acknowledge outbox removal once remote snapshot confirms presence
              if (msg.senderId == myUid) {
                unawaited(_outboxService.acknowledgeServerCommitted(msg.clientMessageId));
              }

              // If message is addressed to us and not yet delivered, dispatch delivery receipt
              if (msg.recipientId == myUid && (msg.deliveredAt == null || msg.status == MessageStatus.sent)) {
                _receiptService.markDelivered(
                  convId: convId,
                  message: msg,
                  myUid: myUid,
                );
              }
            }

            lastRemoteMessages = parsed;
            emitMerged();
          }, onError: (e) {
            debugPrint('[MessageRepository] Firestore listen error: $e');
            if (!controller.isClosed) controller.addError(e);
          });
        } catch (e) {
          debugPrint('[MessageRepository] Non-fatal Firestore subscription setup note: $e');
        }

        try {
          outboxSub = _outboxService.outboxStream.listen((_) {
            emitMerged();
          });
        } catch (e) {
          debugPrint('[MessageRepository] Outbox stream listen note: $e');
        }
      },
      onCancel: () {
        firestoreSub?.cancel();
        outboxSub?.cancel();
      },
    );

    return controller.stream;
  }

  void clearCache() {
    // No-op for Firebase-native architecture
  }
}
