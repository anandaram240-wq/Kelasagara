import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service managing debounced typing indicators and online presence.
class PresenceTypingService {
  final FirebaseFirestore? _customFirestore;
  Timer? _typingTimer;

  PresenceTypingService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  static final PresenceTypingService instance = PresenceTypingService();

  /// Sets typing status for [myUid] in [convId] with automatic 3s timeout.
  void setTyping({
    required String convId,
    required String myUid,
    required bool isTyping,
  }) {
    _typingTimer?.cancel();

    _updateTypingDoc(convId, myUid, isTyping);

    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _updateTypingDoc(convId, myUid, false);
      });
    }
  }

  void _updateTypingDoc(String convId, String myUid, bool isTyping) {
    try {
      _firestore.collection('conversations').doc(convId).update({
        'typing.$myUid': isTyping,
      }).catchError((e) {
        debugPrint('[PresenceTypingService] Non-fatal typing update error: $e');
      });
    } catch (e) {
      debugPrint('[PresenceTypingService] Non-fatal typing update error: $e');
    }
  }

  /// Listen to whether [otherUid] is typing in [convId].
  Stream<bool> listenTyping({
    required String convId,
    required String otherUid,
  }) {
    try {
      return _firestore
          .collection('conversations')
          .doc(convId)
          .snapshots()
          .map((snap) {
        if (!snap.exists) return false;
        final typingMap = snap.data()?['typing'] as Map<String, dynamic>?;
        return typingMap?[otherUid] == true;
      });
    } catch (e) {
      debugPrint('[PresenceTypingService] Non-fatal typing listen error: $e');
      return Stream.value(false);
    }
  }

  void dispose() {
    _typingTimer?.cancel();
  }
}
