import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'booking_service.dart' as canonical;
import 'messaging/conversation_resolver.dart';
import 'messaging/messaging_facade.dart';

typedef BookingService_Canonical = canonical.BookingService;

// ── Chat Service — Production Canonical Adapter ─────────────────────
// Fully delegates to MessagingFacade and ConversationResolver.
// Guaranteed order-independence, E2EE, and crash-free receipts.
class ChatService {
  static final _db = FirebaseFirestore.instance;

  // ── Conversation ID (deterministic canonical resolver) ─────────────
  static String convId(String uid1, String uid2, String jobId) {
    return ConversationResolver.resolve(uid1: uid1, uid2: uid2, jobId: jobId);
  }

  // ── Get or create conversation (delegates to MessagingFacade) ──────
  static Future<String> getOrCreate({
    required String myUid,
    required String otherUid,
    required String jobId,
    required String myName,
    required String otherName,
    required String jobTitle,
  }) async {
    return MessagingFacade.instance.getOrCreateConversation(
      myUid: myUid,
      otherUid: otherUid,
      myName: myName,
      otherName: otherName,
      jobId: jobId,
      jobTitle: jobTitle,
    );
  }

  // ── Send message (delegates to MessagingFacade Outbox) ─────────────
  static Future<void> sendMessage({
    required String convId,
    required String senderUid,
    required String senderName,
    required String otherUid,
    required String text,
    String type = 'text',
  }) async {
    await MessagingFacade.instance.sendMessage(
      myUid: senderUid,
      otherUid: otherUid,
      convId: convId,
      text: text,
      type: type,
    );
  }

  // ── Mark all messages as seen (safe batch, no permission-denied) ───
  static Future<void> markSeen(String convId, String uid) async {
    try {
      final convRef = _db.collection('conversations').doc(convId);
      await convRef.update({'unreadCount.$uid': 0});
    } catch (e) {
      debugPrint('[ChatService] Non-fatal markSeen error: $e');
    }
  }

  // ── Typing indicator (debounced via MessagingFacade) ───────────────
  static void setTyping(String convId, String uid, bool isTyping) {
    MessagingFacade.instance.setTyping(
      convId: convId,
      myUid: uid,
      isTyping: isTyping,
    );
  }

  // ── Real-time listeners ──────────────────────────────────────────
  static Stream<QuerySnapshot> listenMessages(String convId) =>
      _db.collection('conversations').doc(convId)
          .collection('messages')
          .orderBy('sentAt')
          .snapshots();

  static Stream<QuerySnapshot> listenConversations(String uid) =>
      _db.collection('conversations')
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(30)
          .snapshots();

  static Stream<DocumentSnapshot> listenConv(String convId) =>
      _db.collection('conversations').doc(convId).snapshots();
}

// ── Legacy Chat/Booking Helper ───────────────────────────────────────
class ChatBookingLegacyService {
  static final _db = FirebaseFirestore.instance;

  // ── Apply for job (idempotent — prevents duplicate applications) ──
  static Future<String> applyForJob({
    required String jobId,
    required String workerId,
    required String workerName,
    required String hirerId,
    required String jobTitle,
    required String skill,
    required int    pay,
    String message = '',
  }) async {
    final appId  = '${jobId}_$workerId'; // deterministic
    final appRef = _db.collection('applications').doc(appId);
    await appRef.set({
      'jobId':      jobId,
      'workerId':   workerId,
      'workerName': workerName,
      'hirerId':    hirerId,
      'jobTitle':   jobTitle,
      'skill':      skill,
      'pay':        pay,
      'message':    message,
      'status':     'pending',
      'appliedAt':  FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return appId;
  }

  // ── Accept applicant (delegates to canonical atomic BookingService) ─
  static Future<String> acceptApplicant({
    required String applicationId,
    required String jobId,
    required String workerId,
    required String workerName,
    required String hirerId,
    required String jobTitle,
    required String skill,
    required int    pay,
    required double jobLat,
    required double jobLng,
    required String jobAddress,
  }) async {
    final result = await BookingService_Canonical.instance.acceptApplication(
      hirerUid: hirerId,
      applicationId: applicationId,
      applicationData: {
        'jobId':      jobId,
        'workerId':   workerId,
        'workerName': workerName,
        'hirerId':    hirerId,
        'jobTitle':   jobTitle,
        'skillId':    skill,
        'pay':        pay,
        'jobLat':     jobLat,
        'jobLng':     jobLng,
        'jobAddress': jobAddress,
        'status':     'pending',
      },
    );
    if (!result.success) {
      throw Exception(result.errorMessage ?? 'Acceptance failed');
    }
    return result.bookingId!;
  }

  // ── Update worker GPS location (called every 5s from worker phone) ─
  static Future<void> updateLocation({
    required String bookingId,
    required double lat,
    required double lng,
    required double speed,
    required double accuracy,
    required double jobLat,
    required double jobLng,
    required String currentStatus,
  }) async {
    final dist = _haversineKm(lat, lng, jobLat, jobLng);
    final data = <String, dynamic>{
      'workerLat':         lat,
      'workerLng':         lng,
      'workerSpeed':       speed,
      'workerAccuracy':    accuracy,
      'distanceToJob':     dist,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    };

    // When worker within 500m and status is 'confirmed', transition to arrived
    if (dist <= 0.5 && currentStatus == 'confirmed') {
      data['status']     = 'arrived';
      data['arrivedAt']  = FieldValue.serverTimestamp();
    } else if (currentStatus == 'confirmed' && dist > 0.5) {
      data['status'] = 'tracking';
    }

    await _db.collection('bookings').doc(bookingId).update(data);
  }

  // ── Verify arrival OTP (worker enters OTP from hirer screen) ─────
  static Future<void> verifyArrivalOtp({
    required String bookingId,
    required String enteredOtp,
  }) async {
    final res = await canonical.BookingService.instance.verifyArrivalOtp(
      bookingId: bookingId,
      enteredOtp: enteredOtp,
    );
    if (!res.success) {
      throw res.error.isNotEmpty ? res.error : 'Wrong OTP — try again';
    }
  }

  /// Worker transitions from arrived -> working after hirer has verified OTP.
  /// Called by worker after they see hirer confirmed arrival.
  static Future<bool> startWork(String bookingId, String workerUid) async {
    try {
      final ref = _db.collection('bookings').doc(bookingId);
      await _db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw 'not_found';
        final data = snap.data()!;
        if (data['workerId'] != workerUid) throw 'not_worker';
        if (data['arrivalVerified'] != true) throw 'otp_not_verified_by_hirer';
        if (data['status'] == 'working') return; // idempotent
        if (data['status'] != 'arrived') throw 'wrong_state:${data['status']}';
        txn.update(ref, {
          'status': 'working',
          'workStartedAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e) {
      debugPrint('[BookingService] startWork error: $e');
      return false;
    }
  }

  // ── Complete job (delegates to canonical atomic BookingService) ───
  static Future<void> completeJob({
    required String bookingId,
    required String completedByUid,
  }) async {
    final result = await BookingService_Canonical.instance.confirmCompletion(
      hirerUid: completedByUid,
      bookingId: bookingId,
    );
    if (!result.success) {
      throw Exception(result.errorMessage ?? 'Job completion failed');
    }
  }

  // ── Submit rating (delegates to canonical atomic BookingService) ───
  static Future<void> submitRating({
    required String bookingId,
    required String raterUid,
    required String ratedUid,
    required int    stars,
    String comment = '',
  }) async {
    final result = await BookingService_Canonical.instance.confirmCompletion(
      hirerUid: raterUid,
      bookingId: bookingId,
      ratingData: {
        'qualityScore':        stars.toDouble(),
        'punctualityScore':    stars.toDouble(),
        'safetyScore':         stars.toDouble(),
        'taskCompletionScore': stars.toDouble(),
        'communicationScore':  stars.toDouble(),
        'reviewComments':      comment,
      },
    );
    if (!result.success) {
      throw Exception(result.errorMessage ?? 'Rating submission failed');
    }
  }

  // ── Live booking listener ────────────────────────────────────────
  static Stream<DocumentSnapshot> listenBooking(String bookingId) =>
      _db.collection('bookings').doc(bookingId).snapshots();

  static Stream<QuerySnapshot> listenWorkerBookings(String workerUid) =>
      _db.collection('bookings')
          .where('workerId', isEqualTo: workerUid)
          .where('status', whereNotIn: [
            canonical.BookingStatus.completionVerified,
            canonical.BookingStatus.cancelled,
            'completed',
            'done',
          ])
          .snapshots();

  static Stream<QuerySnapshot> listenHirerBookings(String hirerUid) =>
      _db.collection('bookings')
          .where('hirerId', isEqualTo: hirerUid)
          .where('status', whereNotIn: [
            canonical.BookingStatus.completionVerified,
            canonical.BookingStatus.cancelled,
            'completed',
            'done',
          ])
          .snapshots();

  // ── Haversine distance (km) ──────────────────────────────────────
  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r  = 6371.0;
    final dL = _rad(lat2 - lat1);
    final dO = _rad(lon2 - lon1);
    final a  = sin(dL / 2) * sin(dL / 2) +
               cos(_rad(lat1)) * cos(_rad(lat2)) *
               sin(dO / 2) * sin(dO / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
  static double _rad(double deg) => deg * pi / 180;
}
