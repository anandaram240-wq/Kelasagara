import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus {
  queued,
  sending,
  sent,
  delivered,
  read,
  failed,
}

/// Firebase-native message model for fast, reliable real-time messaging.
class ChatMessage {
  final String clientMessageId;
  final String conversationId;
  final String senderId;
  final String recipientId; // receiverId
  final String text;
  final MessageStatus status;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final List<String> seenBy;
  final String type; // 'text' | 'voice'
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final double? locationLat;
  final double? locationLng;
  final String? locationAddress;
  final String? mediaUrl;
  final int? mediaDurationMs;
  final String? errorReason;
  final String? errorCode;

  ChatMessage({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    String? text,
    String? plaintext,
    required this.status,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
    required this.seenBy,
    this.type = 'text',
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
    this.mediaUrl,
    this.mediaDurationMs,
    this.errorReason,
    this.errorCode,
    String? senderDeviceId,
    Map<String, dynamic>? envelope,
    int? version,
  }) : text = text ?? plaintext ?? '';

  // Convenience accessors & backward compatibility aliases
  String get messageId => clientMessageId;
  String get receiverId => recipientId;
  String get plaintext => text;
  String get senderDeviceId => 'mobile';
  int get version => 0;
  Map<String, dynamic>? get envelope => null;

  bool isMe(String myUid) => senderId == myUid;
  bool get isDelivered => status == MessageStatus.delivered || status == MessageStatus.read || deliveredAt != null;
  bool get isRead => status == MessageStatus.read || readAt != null;
  bool get hasReply => replyToId != null && replyToId!.isNotEmpty;
  bool get isLocation => type == 'location';
  bool get isVoice => type == 'voice';
  bool get isImage => type == 'image';

  ChatMessage copyWith({
    String? text,
    String? plaintext,
    MessageStatus? status,
    DateTime? deliveredAt,
    DateTime? readAt,
    List<String>? seenBy,
    String? type,
    String? replyToId,
    String? replyToText,
    String? replyToSenderId,
    double? locationLat,
    double? locationLng,
    String? locationAddress,
    String? mediaUrl,
    int? mediaDurationMs,
    String? errorReason,
    String? errorCode,
  }) {
    return ChatMessage(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderId: senderId,
      recipientId: recipientId,
      text: text ?? plaintext ?? this.text,
      status: status ?? this.status,
      sentAt: sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      seenBy: seenBy ?? this.seenBy,
      type: type ?? this.type,
      replyToId: replyToId ?? this.replyToId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      locationAddress: locationAddress ?? this.locationAddress,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      errorReason: errorReason ?? this.errorReason,
      errorCode: errorCode ?? this.errorCode,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'messageId': clientMessageId,
      'clientMessageId': clientMessageId,
      'conversationId': conversationId,
      'senderId': senderId,
      'receiverId': recipientId,
      'recipientId': recipientId,
      'text': text,
      'type': type,
      'status': status.name,
      'sentAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      if (deliveredAt != null) 'deliveredAt': Timestamp.fromDate(deliveredAt!),
      if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),
      'seenBy': seenBy,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (locationLat != null) 'locationLat': locationLat,
      if (locationLng != null) 'locationLng': locationLng,
      if (locationAddress != null) 'locationAddress': locationAddress,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaDurationMs != null) 'mediaDurationMs': mediaDurationMs,
    };
  }

  static ChatMessage fromDoc(String docId, Map<String, dynamic> data, {String? decryptedText}) {
    final senderId = data['senderId'] as String? ?? '';
    final seenBy = List<String>.from(data['seenBy'] as List<dynamic>? ?? []);
    final statusStr = data['status'] as String? ?? 'sent';

    MessageStatus parsedStatus;
    switch (statusStr) {
      case 'queued':
        parsedStatus = MessageStatus.queued;
        break;
      case 'sending':
        parsedStatus = MessageStatus.sending;
        break;
      case 'delivered':
        parsedStatus = MessageStatus.delivered;
        break;
      case 'read':
        parsedStatus = MessageStatus.read;
        break;
      case 'failed':
        parsedStatus = MessageStatus.failed;
        break;
      case 'sent':
      default:
        parsedStatus = MessageStatus.sent;
        break;
    }

    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final rawText = (data['text'] as String?) ??
        (data['plaintext'] as String?) ??
        decryptedText ??
        '';

    return ChatMessage(
      clientMessageId: data['clientMessageId'] as String? ?? data['messageId'] as String? ?? docId,
      conversationId: data['conversationId'] as String? ?? '',
      senderId: senderId,
      recipientId: (data['receiverId'] as String?) ?? (data['recipientId'] as String?) ?? '',
      text: rawText,
      status: parsedStatus,
      sentAt: parseTimestamp(data['sentAt'] ?? data['createdAt']),
      deliveredAt: data['deliveredAt'] != null ? parseTimestamp(data['deliveredAt']) : null,
      readAt: data['readAt'] != null ? parseTimestamp(data['readAt']) : null,
      seenBy: seenBy,
      type: data['type'] as String? ?? 'text',
      replyToId: data['replyToId'] as String?,
      replyToText: data['replyToText'] as String?,
      replyToSenderId: data['replyToSenderId'] as String?,
      locationLat: (data['locationLat'] as num?)?.toDouble(),
      locationLng: (data['locationLng'] as num?)?.toDouble(),
      locationAddress: data['locationAddress'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
      mediaDurationMs: (data['mediaDurationMs'] as num?)?.toInt(),
      errorReason: data['errorReason'] as String?,
      errorCode: data['errorCode'] as String?,
    );
  }
}
