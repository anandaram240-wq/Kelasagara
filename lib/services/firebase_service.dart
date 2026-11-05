import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_service.dart';

class FirebaseService {
  static bool isAvailable = false;
  static FirebaseFirestore? _db;

  static Future<void> init() async {
    try {
      _db = FirebaseFirestore.instance;
      // Do NOT check _health collection — it has no security rule → always fails.
      // If Firebase.initializeApp() succeeded (which it did to reach this line),
      // Firestore is available.
      isAvailable = true;
    } catch (_) {
      isAvailable = false;
    }
  }

  // ── USERS ───────────────────────────────────────────────────────────────
  static Future<void> createUser(String uid, Map<String, dynamic> data) async {
    if (!isAvailable) return;
    await _db!.collection('users').doc(uid).set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'rating': 0.0, 'totalJobs': 0,
      'ratingSum': 0, 'totalRatings': 0, 'isAvailable': true,
    }, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>?> getUser(String uid) async {
    if (!isAvailable) return null;
    try {
      final doc = await _db!.collection('users').doc(uid).get();
      return doc.exists ? doc.data() : null;
    } catch (_) { return null; }
  }

  static Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    if (!isAvailable) return;
    try { await _db!.collection('users').doc(uid).update(data); } catch (_) {}
  }

  static Stream<DocumentSnapshot> userStream(String uid) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('users').doc(uid).snapshots();
  }

  // ── JOBS ────────────────────────────────────────────────────────────────
  static Future<String> postJob(Map<String, dynamic> data) async {
    if (!isAvailable) return 'local_${DateTime.now().millisecondsSinceEpoch}';
    final ref = await _db!.collection('jobs').add({
      ...data, 'status': 'open', 'applicants': 0,
      'postedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<QuerySnapshot> getJobsStream({String? skill, String? district, String? taluk}) {
    if (!isAvailable) return const Stream.empty();
    Query q = _db!.collection('jobs').where('status', isEqualTo: 'open');
    if (skill != null && skill.isNotEmpty) q = q.where('skill', isEqualTo: skill);
    if (district != null && district.isNotEmpty) q = q.where('district', isEqualTo: district);
    return q.orderBy('postedAt', descending: true).limit(50).snapshots();
  }

  static Future<void> updateJobStatus(String jobId, String status) async {
    if (!isAvailable) return;
    try { await _db!.collection('jobs').doc(jobId).update({'status': status}); } catch (_) {}
  }

  // ── APPLICATIONS ─────────────────────────────────────────────────────────
  static Future<String> applyToJob({required String jobId, required String workerId, required String workerName, required String hirerId, String message = ''}) async {
    if (!isAvailable) return 'local_app_${DateTime.now().millisecondsSinceEpoch}';
    final ref = await _db!.collection('applications').add({
      'jobId': jobId, 'workerId': workerId, 'workerName': workerName,
      'hirerId': hirerId, 'message': message,
      'status': 'pending', 'appliedAt': FieldValue.serverTimestamp(),
    });
    await _db!.collection('jobs').doc(jobId).update({'applicants': FieldValue.increment(1)});
    return ref.id;
  }

  static Stream<QuerySnapshot> getApplicationsForJob(String jobId) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('applications').where('jobId', isEqualTo: jobId).orderBy('appliedAt', descending: true).snapshots();
  }

  static Stream<QuerySnapshot> getApplicationsForWorker(String workerId) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('applications').where('workerId', isEqualTo: workerId).orderBy('appliedAt', descending: true).snapshots();
  }

  static Future<String> acceptApplication(String applicationId, {required String workerId, required String hirerId, required String jobId}) async {
    final res = await BookingService.instance.acceptApplication(
      hirerUid: hirerId,
      applicationId: applicationId,
      applicationData: {
        'jobId': jobId,
        'workerId': workerId,
        'hirerId': hirerId,
        'status': 'pending',
      },
    );
    if (!res.success) throw Exception(res.errorMessage ?? 'Acceptance failed');
    return res.bookingId!;
  }

  static Future<void> rejectApplication(String id) async {
    if (!isAvailable) return;
    try { await _db!.collection('applications').doc(id).update({'status': 'rejected'}); } catch (_) {}
  }

  // ── BOOKINGS ─────────────────────────────────────────────────────────────
  static Stream<DocumentSnapshot> bookingStream(String bookingId) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('bookings').doc(bookingId).snapshots();
  }

  static Stream<QuerySnapshot> getBookingsForUser(String uid, String role) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('bookings').where(role == 'worker' ? 'workerId' : 'hirerId', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots();
  }

  static Future<void> updateBookingStatus(String bookingId, String status) async {
    if (!isAvailable) return;
    try { await _db!.collection('bookings').doc(bookingId).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()}); } catch (_) {}
  }

  static Future<bool> verifyOTP(String bookingId, String enteredOtp) async {
    if (!isAvailable) return false; // Never accept any OTP without Firebase
    try {
      final res = await BookingService.instance.verifyArrivalOtp(
        bookingId: bookingId,
        enteredOtp: enteredOtp,
      );
      return res.success;
    } catch (_) { return false; } // Fail securely — never accept without real verification
  }

  // ── REALTIME LOCATION (Firestore-based) ─────────────────────────────────
  static Future<void> updateWorkerLocation(String bookingId, double lat, double lng, double heading) async {
    if (!isAvailable) return;
    try {
      await _db!.collection('bookings').doc(bookingId).update({
        'workerLat': lat, 'workerLng': lng, 'workerHeading': heading,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Stream<DocumentSnapshot> workerLocationStream(String bookingId) {
    if (!isAvailable) return const Stream.empty();
    return _db!.collection('bookings').doc(bookingId).snapshots();
  }

  // ── CHAT (DEPRECATED: Use MessagingFacade for E2EE) ────────────────────────
  @Deprecated('Use MessagingFacade and ConversationResolver')
  static String getChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @Deprecated('Use MessagingFacade.sendMessage() to ensure E2EE ciphertext envelope')
  static Future<void> sendMessage({required String chatId, required String senderId, required String text, bool isVoice = false}) async {
    throw UnsupportedError('Legacy plaintext sendMessage is deprecated and removed for security. Use MessagingFacade.');
  }

  @Deprecated('Use MessagingFacade.streamMessages() to ensure E2EE decryption')
  static Stream<QuerySnapshot> getMessages(String chatId) {
    return const Stream.empty();
  }

  // ── RATINGS ───────────────────────────────────────────────────────────────
  static Future<void> submitRating({required String bookingId, required String workerId, required String hirerId, required int stars, String comment = ''}) async {
    final res = await BookingService.instance.confirmCompletion(
      hirerUid: hirerId,
      bookingId: bookingId,
      ratingData: {
        'stars': stars.toDouble(),
        'qualityScore': stars.toDouble(),
        'punctualityScore': stars.toDouble(),
        'safetyScore': stars.toDouble(),
        'taskCompletionScore': stars.toDouble(),
        'communicationScore': stars.toDouble(),
        'reviewComments': comment,
      },
    );
    if (!res.success) throw Exception(res.errorMessage ?? 'Rating submission failed');
  }

  static Future<double> getWorkerRating(String workerId) async {
    if (!isAvailable) return 4.5;
    try {
      final doc = await _db!.collection('users').doc(workerId).get();
      if (!doc.exists) return 0;
      final data = doc.data()!;
      final sum = (data['ratingSum'] ?? 0) as num;
      final cnt = (data['totalRatings'] ?? 1) as num;
      return cnt > 0 ? sum / cnt : 0;
    } catch (_) { return 0; }
  }

  static Future<void> saveFCMToken(String uid, String token) async {
    if (!isAvailable) return;
    try { await _db!.collection('users').doc(uid).update({'fcmToken': token}); } catch (_) {}
  }
}
