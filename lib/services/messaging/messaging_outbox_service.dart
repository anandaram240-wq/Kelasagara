import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/messaging/chat_message.dart';
import 'messaging_connectivity_service.dart';

/// Firebase-native offline outbox managing optimistic message delivery,
/// idempotency, automatic retries, and local queue persistence.
class MessagingOutboxService {
  final FirebaseFirestore? _customFirestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  final Map<String, ChatMessage> _outbox = {}; // clientMessageId -> ChatMessage
  final Map<String, int> _retryAttempts = {}; // clientMessageId -> attemptCount

  final StreamController<List<ChatMessage>> _outboxController =
      StreamController<List<ChatMessage>>.broadcast();

  bool _isProcessing = false;
  static const int maxRetries = 5;
  static const String _prefsKey = 'kelasagara_messaging_outbox_v2';
  final Random _random = Random();
  StreamSubscription? _connectivitySub;
  Timer? _retryTimer;

  void cancelPendingRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  MessagingOutboxService({FirebaseFirestore? firestore})
      : _customFirestore = firestore {
    _listenConnectivity();
  }

  static final MessagingOutboxService instance = MessagingOutboxService();

  Stream<List<ChatMessage>> get outboxStream => _outboxController.stream;

  int get queuedCount =>
      _outbox.values.where((m) => m.status == MessageStatus.queued || m.status == MessageStatus.sending).length;
  int get failedCount => _outbox.values.where((m) => m.status == MessageStatus.failed).length;
  int get totalPendingCount => _outbox.length;

  void _listenConnectivity() {
    try {
      _connectivitySub?.cancel();
      _connectivitySub = MessagingConnectivityService.instance.statusStream.listen((status) {
        if (status == MessagingConnectionStatus.online || status == MessagingConnectionStatus.recovering) {
          debugPrint('[MessagingOutboxService] Connectivity active ($status) — flushing outbox');
          _triggerProcess();
        }
      });
    } catch (_) {}
  }

  /// Load pending outbox messages from local preferences (called on startup).
  Future<void> loadPersistedOutbox(String myUid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;

      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        if (map['senderId'] == myUid) {
          final msg = ChatMessage.fromDoc(
            map['clientMessageId'] as String,
            map,
          );
          _outbox[msg.clientMessageId] = msg;
        }
      }
      _notify();
      _triggerProcess();
    } catch (e) {
      debugPrint('[MessagingOutboxService] Error loading persisted outbox: $e');
    }
  }

  /// Persist current outbox to SharedPreferences.
  Future<void> _persistOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _outbox.values.map((msg) => {
        'clientMessageId': msg.clientMessageId,
        'conversationId': msg.conversationId,
        'senderId': msg.senderId,
        'recipientId': msg.recipientId,
        'receiverId': msg.recipientId,
        'text': msg.text,
        'type': msg.type,
        'replyToId': msg.replyToId,
        'replyToText': msg.replyToText,
        'replyToSenderId': msg.replyToSenderId,
        'locationLat': msg.locationLat,
        'locationLng': msg.locationLng,
        'locationAddress': msg.locationAddress,
        'mediaUrl': msg.mediaUrl,
        'mediaDurationMs': msg.mediaDurationMs,
        'sentAt': msg.sentAt.toIso8601String(),
        'status': msg.status.name,
        'seenBy': msg.seenBy,
        'errorCode': msg.errorCode,
        'errorReason': msg.errorReason,
      }).toList();
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('[MessagingOutboxService] Error persisting outbox: $e');
    }
  }

  /// Enqueue a new message for sending. Returns optimistic ChatMessage immediately (<10ms).
  Future<ChatMessage> enqueueMessage({
    required String myUid,
    required String recipientUid,
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
    final clientMessageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999999)}';

    final message = ChatMessage(
      clientMessageId: clientMessageId,
      conversationId: convId,
      senderId: myUid,
      recipientId: recipientUid,
      text: text,
      status: MessageStatus.sending,
      sentAt: DateTime.now(),
      seenBy: [myUid],
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

    _outbox[clientMessageId] = message;
    _retryAttempts[clientMessageId] = 0;
    _notify();
    await _persistOutbox();

    _triggerProcess();
    return message;
  }

  /// Retry a failed message manually using the exact same clientMessageId.
  void retryMessage(String clientMessageId) {
    final msg = _outbox[clientMessageId];
    if (msg == null) return;

    _outbox[clientMessageId] = msg.copyWith(status: MessageStatus.sending, errorReason: null);
    _retryAttempts[clientMessageId] = 0;
    _notify();
    _triggerProcess();
  }

  /// Reconcile remote receipt: cleans message from outbox once confirmed on server.
  Future<void> acknowledgeServerCommitted(String clientMessageId) async {
    if (_outbox.containsKey(clientMessageId)) {
      _outbox.remove(clientMessageId);
      _retryAttempts.remove(clientMessageId);
      await _persistOutbox();
      _notify();
    }
  }

  /// Trigger outbox processing asynchronously.
  void _triggerProcess() {
    if (_isProcessing) return;
    _processOutboxQueue();
  }

  Future<void> _processOutboxQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queuedEntries = _outbox.entries
          .where((e) =>
              e.value.status == MessageStatus.queued ||
              e.value.status == MessageStatus.sending)
          .toList();

      for (final entry in queuedEntries) {
        final msg = entry.value;

        try {
          // Prepare Firestore batch write
          final convRef = _firestore.collection('conversations').doc(msg.conversationId);
          final msgRef = convRef.collection('messages').doc(msg.clientMessageId);

          final batch = _firestore.batch();

          String previewText = msg.text;
          if (msg.type == 'location') {
            previewText = '📍 Shared Location';
          } else if (msg.type == 'voice') {
            previewText = '🎤 Voice message';
          } else if (msg.type == 'image') {
            previewText = '📷 Photo';
          }

          final firestoreData = {
            'messageId': msg.clientMessageId,
            'clientMessageId': msg.clientMessageId,
            'conversationId': msg.conversationId,
            'senderId': msg.senderId,
            'receiverId': msg.recipientId,
            'recipientId': msg.recipientId,
            'text': msg.text,
            'type': msg.type,
            'sentAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'status': 'sent',
            'seenBy': [msg.senderId],
            if (msg.replyToId != null) 'replyToId': msg.replyToId,
            if (msg.replyToText != null) 'replyToText': msg.replyToText,
            if (msg.replyToSenderId != null) 'replyToSenderId': msg.replyToSenderId,
            if (msg.locationLat != null) 'locationLat': msg.locationLat,
            if (msg.locationLng != null) 'locationLng': msg.locationLng,
            if (msg.locationAddress != null) 'locationAddress': msg.locationAddress,
            if (msg.mediaUrl != null) 'mediaUrl': msg.mediaUrl,
            if (msg.mediaDurationMs != null) 'mediaDurationMs': msg.mediaDurationMs,
          };

          batch.set(msgRef, firestoreData, SetOptions(merge: true));

          batch.set(convRef, {
            'conversationId': msg.conversationId,
            'id': msg.conversationId,
            'participants': [msg.senderId, msg.recipientId],
            'lastMessage': previewText,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMessageSenderId': msg.senderId,
            'unreadCount': {msg.recipientId: FieldValue.increment(1)},
            'updatedAt': FieldValue.serverTimestamp(),
            'typing': {msg.senderId: false},
          }, SetOptions(merge: true));

          await batch.commit();

          MessagingConnectivityService.instance.recordTransportSuccess();

          // Mark sent locally and reconcile
          _outbox[msg.clientMessageId] = msg.copyWith(status: MessageStatus.sent);
          _notify();

          _outbox.remove(msg.clientMessageId);
          _retryAttempts.remove(msg.clientMessageId);
          await _persistOutbox();
          _notify();
        } catch (e) {
          debugPrint('[MessagingOutboxService] Failed to send ${msg.clientMessageId}: $e');
          MessagingConnectivityService.instance.recordTransportFailure();

          final isPermError = e.toString().contains('permission-denied') ||
              e.toString().contains('PERMISSION_DENIED');

          String errCode = 'UNKNOWN';
          String errMsg = e.toString();
          if (e is FirebaseException) {
            errCode = e.code;
            errMsg = e.message ?? e.code;
          }

          final attempts = (_retryAttempts[msg.clientMessageId] ?? 0) + 1;
          _retryAttempts[msg.clientMessageId] = attempts;

          if (isPermError) {
            _outbox[msg.clientMessageId] = msg.copyWith(
              status: MessageStatus.failed,
              errorCode: errCode,
              errorReason: 'Permission Denied: $errMsg',
            );
            await _persistOutbox();
            _notify();
          } else if (attempts >= maxRetries) {
            _outbox[msg.clientMessageId] = msg.copyWith(
              status: MessageStatus.failed,
              errorCode: errCode,
              errorReason: 'Message failed. Tap to retry.',
            );
            await _persistOutbox();
            _notify();
          } else {
            final delayMs = min(15000, (pow(2, min(attempts, 4)) * 1000).toInt()) + _random.nextInt(300);
            _outbox[msg.clientMessageId] = msg.copyWith(
              status: MessageStatus.sending,
              errorCode: errCode,
              errorReason: 'Retrying ($attempts)...',
            );
            _notify();

            _retryTimer?.cancel();
            _retryTimer = Timer(Duration(milliseconds: delayMs), () {
              _triggerProcess();
            });
            break;
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Get pending outbox messages for a specific conversation.
  List<ChatMessage> getPendingForConversation(String convId) {
    return _outbox.values.where((m) => m.conversationId == convId).toList();
  }

  void _notify() {
    if (!_outboxController.isClosed) {
      _outboxController.add(_outbox.values.toList());
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _outboxController.close();
  }
}
