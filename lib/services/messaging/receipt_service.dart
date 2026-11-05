import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/messaging/chat_message.dart';

/// Handles dispatching delivery and read receipts safely without violating message immutability.
class ReceiptService {
  final FirebaseFirestore? _customFirestore;

  ReceiptService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  static final ReceiptService instance = ReceiptService();

  final Set<String> _deliveredAcknowledged = {};
  final Set<String> _readAcknowledged = {};

  /// Mark message as delivered to [myUid].
  Future<void> markDelivered({
    required String convId,
    required ChatMessage message,
    required String myUid,
  }) async {
    if (message.senderId == myUid) return; // Sender doesn't deliver to self
    if (message.status != MessageStatus.sent) return; // Already delivered or read
    if (_deliveredAcknowledged.contains(message.clientMessageId)) return;

    _deliveredAcknowledged.add(message.clientMessageId);

    try {
      final docRef = _firestore
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .doc(message.clientMessageId);

      await docRef.update({
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ReceiptService] Error marking delivered: $e');
      _deliveredAcknowledged.remove(message.clientMessageId);
    }
  }

  /// Mark conversation messages as read by [myUid].
  Future<void> markConversationRead({
    required String convId,
    required String myUid,
    required List<ChatMessage> messages,
  }) async {
    final unreadMessages = messages.where((m) =>
        m.senderId != myUid &&
        m.status != MessageStatus.read &&
        !_readAcknowledged.contains(m.clientMessageId)).toList();

    if (unreadMessages.isEmpty) {
      // Just ensure unread count on conversation is 0
      try {
        await _firestore.collection('conversations').doc(convId).update({
          'unreadCount.$myUid': 0,
        });
      } catch (_) {}
      return;
    }

    for (final m in unreadMessages) {
      _readAcknowledged.add(m.clientMessageId);
    }

    try {
      final batch = _firestore.batch();
      final convRef = _firestore.collection('conversations').doc(convId);

      // Reset unread count
      batch.update(convRef, {'unreadCount.$myUid': 0});

      for (final m in unreadMessages.take(20)) {
        final msgRef = convRef.collection('messages').doc(m.clientMessageId);
        batch.update(msgRef, {
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
          'seenBy': FieldValue.arrayUnion([myUid]),
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('[ReceiptService] Error marking conversation read: $e');
      for (final m in unreadMessages) {
        _readAcknowledged.remove(m.clientMessageId);
      }
    }
  }

  /// Clear caches on conversation close.
  void clear() {
    _deliveredAcknowledged.clear();
    _readAcknowledged.clear();
  }
}
