import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/messaging/chat_message.dart';
import 'conversation_resolver.dart';
import 'message_repository.dart';
import 'messaging_outbox_service.dart';
import 'presence_typing_service.dart';
import 'receipt_service.dart';

/// The canonical unified entry point for all messaging operations in Kelasagara.
/// Coordinates ConversationResolver, MessagingOutboxService, MessageRepository,
/// ReceiptService, and PresenceTypingService in a fast, Firebase-native architecture.
class MessagingFacade {
  final FirebaseFirestore? _customFirestore;
  final MessagingOutboxService _outboxService;
  final MessageRepository _repository;
  final ReceiptService _receiptService;
  final PresenceTypingService _presenceService;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  MessagingFacade({
    FirebaseFirestore? firestore,
    MessagingOutboxService? outboxService,
    MessageRepository? repository,
    ReceiptService? receiptService,
    PresenceTypingService? presenceService,
  })  : _customFirestore = firestore,
        _outboxService = outboxService ?? MessagingOutboxService.instance,
        _repository = repository ?? MessageRepository.instance,
        _receiptService = receiptService ?? ReceiptService.instance,
        _presenceService = presenceService ?? PresenceTypingService.instance;

  static final MessagingFacade instance = MessagingFacade();

  /// Initialize messaging subsystem for current logged-in user.
  Future<void> initialize(String myUid) async {
    try {
      await _outboxService.loadPersistedOutbox(myUid);
    } catch (e) {
      debugPrint('[MessagingFacade] Initialization warning: $e');
    }
  }

  /// Get or create a conversation using the canonical conversation ID resolver.
  Future<String> getOrCreateConversation({
    required String myUid,
    required String otherUid,
    required String myName,
    required String otherName,
    String? jobId,
    String? jobTitle,
  }) async {
    final convId = ConversationResolver.resolve(
      uid1: myUid,
      uid2: otherUid,
      jobId: jobId,
    );

    try {
      final convRef = _firestore.collection('conversations').doc(convId);
      await convRef.set({
        'conversationId': convId,
        'id': convId,
        'participants': [myUid, otherUid],
        'participantNames': {myUid: myName, otherUid: otherName},
        'jobId': jobId ?? 'direct',
        'jobTitle': jobTitle ?? 'Direct Chat',
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount': {myUid: 0, otherUid: 0},
        'typing': {myUid: false, otherUid: false},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[MessagingFacade] Non-fatal upsert conversation error: $e');
    }

    return convId;
  }

  /// Send message: enqueues into Outbox for immediate optimistic UI (<10ms)
  /// and reliable background delivery with automatic retry.
  Future<ChatMessage> sendMessage({
    required String myUid,
    required String otherUid,
    required String convId,
    required String text,
    String type = 'text',
    String? replyToId,
    String? replyToText,
    String? replyToSenderId,
    double? locationLat,
    double? locationLng,
    String? locationAddress,
    String? mediaUrl,
    int? mediaDurationMs,
  }) async {
    return _outboxService.enqueueMessage(
      myUid: myUid,
      recipientUid: otherUid,
      convId: convId,
      text: text,
      type: type,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      locationLat: locationLat,
      locationLng: locationLng,
      locationAddress: locationAddress,
      mediaUrl: mediaUrl,
      mediaDurationMs: mediaDurationMs,
    );
  }

  /// Stream messages for conversation with real-time Firestore updates and outbox merge.
  Stream<List<ChatMessage>> streamMessages({
    required String convId,
    required String myUid,
    required String otherUid,
  }) {
    return _repository.streamConversationMessages(
      convId: convId,
      myUid: myUid,
      otherUid: otherUid,
    );
  }

  /// Mark conversation read (seen ticks).
  Future<void> markConversationRead({
    required String convId,
    required String myUid,
    required List<ChatMessage> messages,
  }) async {
    await _receiptService.markConversationRead(
      convId: convId,
      myUid: myUid,
      messages: messages,
    );
  }

  /// Set typing status.
  void setTyping({
    required String convId,
    required String myUid,
    required bool isTyping,
  }) {
    _presenceService.setTyping(
      convId: convId,
      myUid: myUid,
      isTyping: isTyping,
    );
  }

  /// Stream whether other user is typing.
  Stream<bool> streamTyping({
    required String convId,
    required String otherUid,
  }) {
    return _presenceService.listenTyping(
      convId: convId,
      otherUid: otherUid,
    );
  }

  /// Retry sending a failed message.
  void retryMessage(String clientMessageId) {
    _outboxService.retryMessage(clientMessageId);
  }

  /// Clear in-memory caches on logout.
  void clearOnLogout() {
    _repository.clearCache();
    _receiptService.clear();
    _presenceService.dispose();
  }
}
