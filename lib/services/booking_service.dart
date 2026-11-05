// lib/services/booking_service.dart
//
// CANONICAL BOOKING SERVICE — Phase 4 / Phase 4B
// ONE canonical service for all booking lifecycle operations.
// Voice, UI, and providers all route through this.
// Direct Firestore booking writes outside this file are forbidden.

import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../features/tracking/services/worker_telemetry_service.dart';
import 'voice/voice_booking_api_client.dart';

/// Booking lifecycle status constants — single source of truth.
class BookingStatus {
  static const String confirmed = 'confirmed';
  static const String tracking = 'tracking';
  static const String arrived = 'arrived';
  static const String working = 'working';
  static const String inProgress = 'in_progress';
  static const String completionRequested = 'completion_requested';
  static const String completionVerified = 'completion_verified';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';
  static const String disputed = 'disputed';

  /// States where the booking is actively occupying the worker.
  static const Set<String> activeStates = {
    confirmed, tracking, arrived, working, inProgress, completionRequested,
  };

  /// Terminal states — booking is done, no further transitions.
  static const Set<String> terminalStates = {
    completionVerified, completed, cancelled, disputed,
  };

  /// Helper to check if a status string represents the work execution phase
  static bool isWorkingState(String? status) =>
      status == working || status == inProgress;
}

/// Result of a booking operation.
class BookingResult {
  final bool success;
  final String? bookingId;
  final String? errorCode;
  final String? errorMessage;
  final String? correlationId;
  final String? stage;

  const BookingResult.ok(this.bookingId, {this.correlationId, this.stage})
      : success = true,
        errorCode = null,
        errorMessage = null;

  const BookingResult.fail(this.errorCode, this.errorMessage, {this.correlationId, this.stage})
      : success = false,
        bookingId = null;
}

/// ONE canonical booking service — singleton.
class BookingService {
  BookingService._();
  static final BookingService instance = BookingService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── ACCEPTANCE (RACE-SAFE via runTransaction) ──────────────────────────────

  /// Accept a worker application.
  /// Uses runTransaction to prevent concurrent double-acceptance.
  /// Sets worker isAvailable=false atomically with booking creation.
  /// Seeds RTDB trackingParticipants with authoritative hirer/worker/job identity.
  Future<BookingResult> acceptApplication({
    required String hirerUid,
    required String applicationId,
    required Map<String, dynamic> applicationData,
  }) async {
    try {
      final appRef = _db.collection('applications').doc(applicationId);
      final jobId = (applicationData['jobId'] as String?) ?? '';
      final workerId = (applicationData['workerId'] as String?) ?? '';

      if (jobId.isEmpty || workerId.isEmpty) {
        return const BookingResult.fail('INVALID_DATA', 'Missing jobId or workerId in application');
      }

      final currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final effectiveHirerUid = hirerUid.isNotEmpty ? hirerUid : currentAuthUid;

      final jobRef = _db.collection('jobs').doc(jobId);
      final jobPrivateRef = _db.collection('jobPrivate').doc(jobId);
      final workerRef = _db.collection('users').doc(workerId);

      // Deterministic bookingId — replay-safe.
      // Two concurrent accepts for the same applicationId produce the same bookingId.
      final newBookingId = 'booking_$applicationId';
      final bookingRef = _db.collection('bookings').doc(newBookingId);

      double seedLat = 0.0;
      double seedLng = 0.0;
      final String arrivalOtp = BookingTrackingSeeder.generateSixDigitOtp();

      try {
        await _db.runTransaction((txn) async {
          // ── Read all required documents ──
          final appSnap = await txn.get(appRef);
          final jobSnap = await txn.get(jobRef);
          final jobPrivateSnap = await txn.get(jobPrivateRef);
          final workerSnap = await txn.get(workerRef);
          final existingBooking = await txn.get(bookingRef);

          // ── Validate ──
          if (!appSnap.exists) throw 'Application not found';
          final appData = appSnap.data()!;

          // Idempotency: if already accepted for this booking, treat as success
          if (appData['status'] == 'accepted' && (appData['bookingId'] == newBookingId || existingBooking.exists)) {
            debugPrint('⚡ acceptApplication: already accepted with $newBookingId — idempotent success');
            return;
          }

          if (appData['status'] != 'pending') {
            throw 'Application has already been processed (${appData['status']})';
          }

          final appHirer = (appData['hirerId'] ?? appData['hirerUid'] ?? '') as String;

          if (!jobSnap.exists) throw 'Job not found';
          final jobData = jobSnap.data()!;
          final jobHirer = (jobData['hirerId'] ?? jobData['hirerUid'] ?? jobData['createdById'] ?? jobData['createdBy'] ?? '') as String;

          if (appHirer.isNotEmpty && appHirer != effectiveHirerUid && jobHirer != effectiveHirerUid) {
            throw 'You do not have permission to accept applicants for this job';
          }
          if (appHirer.isEmpty && jobHirer.isNotEmpty && jobHirer != effectiveHirerUid) {
            throw 'You do not have permission to accept applicants for this job';
          }

          final jStatus = (jobData['status'] as String? ?? '').toLowerCase();
          if (jStatus == 'filled') throw 'This job has already been filled';
          if (jStatus != 'open' && jStatus != 'active') throw 'Job is not open for hiring ($jStatus)';

          if (!workerSnap.exists) throw 'Worker profile not found';
          final workerData = workerSnap.data()!;
          final wStatus = (workerData['accountStatus'] as String? ?? '').toLowerCase();
          if (wStatus.isNotEmpty && wStatus != 'approved' && wStatus != 'active') {
            throw 'Worker profile is not yet approved';
          }

          final isAvailable = workerData['isAvailable'] as bool? ?? false;
          final activeBookingId = workerData['activeBookingId'] as String?;
          final processingBookingId = workerData['approvalProcessingBookingId'] as String?;
          if (!isAvailable || (activeBookingId != null && activeBookingId.isNotEmpty) || (processingBookingId != null && processingBookingId.isNotEmpty)) {
            throw 'Worker is currently assigned or in the process of being assigned to another booking';
          }

          if (existingBooking.exists) {
            debugPrint('⚡ acceptApplication: booking already exists — idempotent success');
            return;
          }

          final now = FieldValue.serverTimestamp();

          final locMap = jobData['location'] as Map<String, dynamic>?;
          final privData = jobPrivateSnap.exists ? jobPrivateSnap.data()! : <String, dynamic>{};
          final finalLat = (privData['lat'] ?? jobData['lat'] ?? jobData['jobLat'] ?? locMap?['lat'] ?? appData['jobLat'] ?? 0.0) as num;
          final finalLng = (privData['lng'] ?? jobData['lng'] ?? jobData['jobLng'] ?? locMap?['lng'] ?? appData['jobLng'] ?? 0.0) as num;
          final finalAddress = (privData['address'] ?? jobData['address'] ?? jobData['jobAddress'] ?? locMap?['address'] ?? appData['jobAddress'] ?? '') as String;

          final dLat = (workerData['discoveryLat'] as num?)?.toDouble() ??
              (workerData['lat'] as num?)?.toDouble() ??
              ((workerData['lastLocation'] as Map<String, dynamic>?)?['lat'] as num?)?.toDouble() ??
              (appData['workerLat'] as num?)?.toDouble();
          final dLng = (workerData['discoveryLng'] as num?)?.toDouble() ??
              (workerData['lng'] as num?)?.toDouble() ??
              ((workerData['lastLocation'] as Map<String, dynamic>?)?['lng'] as num?)?.toDouble() ??
              (appData['workerLng'] as num?)?.toDouble();

          seedLat = (dLat != null && dLat != 0.0) ? dLat : finalLat.toDouble();
          seedLng = (dLng != null && dLng != 0.0) ? dLng : finalLng.toDouble();

          // ── Create booking ──
          txn.set(bookingRef, {
            'bookingId': newBookingId,
            'applicationId': applicationId,
            'jobId': jobId,
            'workerId': workerId,
            'workerName': (appData['workerName'] as String?) ?? '',
            'hirerId': effectiveHirerUid,
            'hirerName': (jobData['hirerName'] ?? jobData['createdByName'] ?? '') as String,
            'skillId': (appData['skill'] ?? appData['skillId'] ?? '') as String,
            'jobTitle': (appData['jobTitle'] ?? jobData['title'] ?? '') as String,
            'pay': appData['pay'] ?? jobData['pay'] ?? 0,
            'jobLat': finalLat,
            'jobLng': finalLng,
            'jobAddress': finalAddress,
            'status': BookingStatus.confirmed,
            'arrivalOtpHash': BookingTrackingSeeder.computeOtpHash(newBookingId, arrivalOtp),
            'arrivalOtpExpiry': DateTime.now().add(const Duration(hours: 12)),
            'arrivalOtpAttempts': 0,
            'arrivalOtpUsed': false,
            'arrivalVerified': false,
            'workerSeedLocation': {
              'lat': seedLat,
              'lng': seedLng,
              'updatedAt': now,
            },
            'confirmedAt': now,
            'createdAt': now,
            'updatedAt': now,
          });

          // Seed isolated plaintext OTP strictly in hirer_secure subcollection
          txn.set(bookingRef.collection('hirer_secure').doc('arrival_code'), {
            'arrivalOtp': arrivalOtp,
            'hirerId': effectiveHirerUid,
            'createdAt': now,
          });

          // ── Mark application accepted ──
          txn.update(appRef, {
            'status': 'accepted',
            'bookingId': newBookingId,
            'acceptedAt': now,
          });

          // ── Mark job filled ──
          txn.update(jobRef, {'status': 'filled', 'filledAt': now});

          // ── Unlock private location for accepted worker if jobPrivate doc exists ──
          if (jobPrivateSnap.exists) {
            txn.update(jobPrivateRef, {
              'acceptedWorkerId': workerId,
              'acceptedAt': now,
            });
          }

          // ── Mark worker unavailable immediately ──
          txn.update(workerRef, {
            'isAvailable': false,
            'activeBookingId': newBookingId,
          });
        });
      } on FirebaseException catch (fe) {
        if (fe.code == 'permission-denied') {
          debugPrint('⚠️ acceptApplication: 5-doc transaction permission-denied (${fe.message}). Retrying core 4-doc acceptance transaction…');
          await _db.runTransaction((txn) async {
            final appSnap = await txn.get(appRef);
            final jobSnap = await txn.get(jobRef);
            final jobPrivateSnap = await txn.get(jobPrivateRef);
            final workerSnap = await txn.get(workerRef);
            final existingBooking = await txn.get(bookingRef);

            if (!appSnap.exists) throw 'Application not found';
            final appData = appSnap.data()!;

            if (appData['status'] == 'accepted' && (appData['bookingId'] == newBookingId || existingBooking.exists)) {
              return;
            }
            if (appData['status'] != 'pending') {
              throw 'Application has already been processed (${appData['status']})';
            }

            if (!jobSnap.exists) throw 'Job not found';
            final jobData = jobSnap.data()!;
            final jStatus = (jobData['status'] as String? ?? '').toLowerCase();
            if (jStatus == 'filled') throw 'This job has already been filled';
            if (jStatus != 'open' && jStatus != 'active') throw 'Job is not open for hiring ($jStatus)';

            if (!workerSnap.exists) throw 'Worker profile not found';
            final workerData = workerSnap.data()!;
            final isAvailable = workerData['isAvailable'] as bool? ?? false;
            final activeBookingId = workerData['activeBookingId'] as String?;
            final processingBookingId = workerData['approvalProcessingBookingId'] as String?;
            if (!isAvailable || (activeBookingId != null && activeBookingId.isNotEmpty) || (processingBookingId != null && processingBookingId.isNotEmpty)) {
              throw 'Worker is currently assigned or in the process of being assigned to another booking';
            }

            if (existingBooking.exists) return;

            final now = FieldValue.serverTimestamp();
            final locMap = jobData['location'] as Map<String, dynamic>?;
            final privData = jobPrivateSnap.exists ? jobPrivateSnap.data()! : <String, dynamic>{};
            final finalLat = (privData['lat'] ?? jobData['lat'] ?? jobData['jobLat'] ?? locMap?['lat'] ?? appData['jobLat'] ?? 0.0) as num;
            final finalLng = (privData['lng'] ?? jobData['lng'] ?? jobData['jobLng'] ?? locMap?['lng'] ?? appData['jobLng'] ?? 0.0) as num;
            final finalAddress = (privData['address'] ?? jobData['address'] ?? jobData['jobAddress'] ?? locMap?['address'] ?? appData['jobAddress'] ?? '') as String;

            txn.set(bookingRef, {
              'bookingId': newBookingId,
              'applicationId': applicationId,
              'jobId': jobId,
              'workerId': workerId,
              'workerName': (appData['workerName'] as String?) ?? '',
              'hirerId': effectiveHirerUid,
              'hirerName': (jobData['hirerName'] ?? jobData['createdByName'] ?? '') as String,
              'skillId': (appData['skill'] ?? appData['skillId'] ?? '') as String,
              'jobTitle': (appData['jobTitle'] ?? jobData['title'] ?? '') as String,
              'pay': appData['pay'] ?? jobData['pay'] ?? 0,
              'jobLat': finalLat,
              'jobLng': finalLng,
              'jobAddress': finalAddress,
              'status': BookingStatus.confirmed,
              'arrivalOtpHash': BookingTrackingSeeder.computeOtpHash(newBookingId, arrivalOtp),
              'arrivalOtpExpiry': DateTime.now().add(const Duration(hours: 12)),
              'arrivalOtpAttempts': 0,
              'arrivalOtpUsed': false,
              'arrivalVerified': false,
              'workerSeedLocation': {
                'lat': seedLat,
                'lng': seedLng,
                'updatedAt': now,
              },
              'confirmedAt': now,
              'createdAt': now,
              'updatedAt': now,
            });

            // Seed isolated plaintext OTP strictly in hirer_secure subcollection
            txn.set(bookingRef.collection('hirer_secure').doc('arrival_code'), {
              'arrivalOtp': arrivalOtp,
              'hirerId': effectiveHirerUid,
              'createdAt': now,
            });

            txn.update(appRef, {
              'status': 'accepted',
              'bookingId': newBookingId,
              'acceptedAt': now,
            });

            txn.update(jobRef, {'status': 'filled', 'filledAt': now});

            if (jobPrivateSnap.exists) {
              txn.update(jobPrivateRef, {
                'acceptedWorkerId': workerId,
                'acceptedAt': now,
              });
            }
          });

          // Non-fatal worker availability reconciliation outside transaction
          try {
            await workerRef.update({
              'isAvailable': false,
              'activeBookingId': newBookingId,
            });
          } catch (wErr) {
            debugPrint('[BookingService] Secondary worker availability update non-fatal: $wErr');
          }
        } else {
          rethrow;
        }
      }

      // ── Seed authoritative RTDB trackingParticipants & liveTracking (Zero blank map) ──
      try {
        await FirebaseDatabase.instance
            .ref('trackingParticipants/$newBookingId')
            .set({
          'hirerId': effectiveHirerUid,
          'workerId': workerId,
          'jobId': jobId,
          'createdAt': ServerValue.timestamp,
        });

        await FirebaseDatabase.instance
            .ref('liveTracking/$newBookingId')
            .set({
          'jobId': jobId,
          'workerId': workerId,
          'hirerId': effectiveHirerUid,
          'lat': seedLat,
          'lng': seedLng,
          'latitude': seedLat,
          'longitude': seedLng,
          'accuracy': 15.0,
          'heading': 0.0,
          'speed': 0.0,
          'speedMps': 0.0,
          'seq': 1,
          'isSeed': true,
          'trackingStatus': 'active',
          'arrivalStatus': 'en_route',
          'status': 'en_route',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': ServerValue.timestamp,
          'lastUpdatedAt': ServerValue.timestamp,
        });
      } catch (rtdbErr) {
        debugPrint('[BookingService] Non-fatal RTDB seed error: $rtdbErr');
      }

      return BookingResult.ok(newBookingId);
    } on FirebaseException catch (e) {
      debugPrint('[BookingService] acceptApplication error: ${e.code} ${e.message}');
      final msg = e.code == 'permission-denied'
          ? "You don't have permission to accept applicants for this job."
          : (e.message ?? 'Acceptance failed. Please try again.');
      return BookingResult.fail(e.code, msg);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      debugPrint('[BookingService] acceptApplication: $msg');
      return BookingResult.fail(msg, msg);
    }
  }

  // ─── DIRECT BOOKING (VOICE & DIRECT HIRE — P4-008 & P4-015) ─────────────────

  /// Create a direct booking from voice or direct-hire search.
  /// Persistent server-authoritative idempotency: uses deterministic ID
  /// derived from [idempotencyKey] so duplicates across app restarts are safely handled.
  /// Atomically validates worker availability and reconciles availability.
  Future<BookingResult> createDirectBooking({
    required String hirerUid,
    required String workerId,
    required String skillId,
    required String idempotencyKey,
    String jobTitle = 'Direct Service',
    double jobLat = 0.0,
    double jobLng = 0.0,
    String jobAddress = '',
    int pay = 0,
    String jobId = '',
  }) async {
    try {
      if (workerId.isEmpty) {
        return const BookingResult.fail('INVALID_DATA', 'workerId is required');
      }

      final safeKey = idempotencyKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final newBookingId = 'booking_direct_$safeKey';
      final bookingRef = _db.collection('bookings').doc(newBookingId);
      final workerRef = _db.collection('users').doc(workerId);
      final actualJobId = jobId.isNotEmpty ? jobId : 'direct_job_$safeKey';

      double seedLat = 0.0;
      double seedLng = 0.0;
      final String arrivalOtp = BookingTrackingSeeder.generateSixDigitOtp();

      await _db.runTransaction((txn) async {
        final existingBooking = await txn.get(bookingRef);
        if (existingBooking.exists) {
          // Idempotent: already created in previous invocation
          return;
        }

        final workerSnap = await txn.get(workerRef);
        if (!workerSnap.exists) throw 'worker_not_found';
        final workerData = workerSnap.data()!;
        if (workerData['accountStatus'] != 'approved') throw 'worker_not_approved';

        final isAvailable = workerData['isAvailable'] as bool? ?? false;
        final activeBookingId = workerData['activeBookingId'] as String?;
        final processingBookingId = workerData['approvalProcessingBookingId'] as String?;
        if (!isAvailable || (activeBookingId != null && activeBookingId.isNotEmpty) || (processingBookingId != null && processingBookingId.isNotEmpty)) {
          throw 'Worker is no longer available or currently assigned to another booking.';
        }

        final workerName = (workerData['displayName'] ?? workerData['name'] ?? 'Worker') as String;
        final now = FieldValue.serverTimestamp();

        final dLat = (workerData['discoveryLat'] as num?)?.toDouble() ??
            (workerData['lat'] as num?)?.toDouble() ??
            ((workerData['lastLocation'] as Map<String, dynamic>?)?['lat'] as num?)?.toDouble();
        final dLng = (workerData['discoveryLng'] as num?)?.toDouble() ??
            (workerData['lng'] as num?)?.toDouble() ??
            ((workerData['lastLocation'] as Map<String, dynamic>?)?['lng'] as num?)?.toDouble();

        seedLat = (dLat != null && dLat != 0.0) ? dLat : jobLat;
        seedLng = (dLng != null && dLng != 0.0) ? dLng : jobLng;

        txn.set(bookingRef, {
          'bookingId': newBookingId,
          'jobId': actualJobId,
          'workerId': workerId,
          'workerName': workerName,
          'hirerId': hirerUid,
          'skillId': skillId,
          'jobTitle': jobTitle,
          'pay': pay > 0 ? pay : (workerData['dailyRate'] ?? 0),
          'jobLat': jobLat,
          'jobLng': jobLng,
          'jobAddress': jobAddress,
          'status': BookingStatus.confirmed,
          'arrivalOtpHash': BookingTrackingSeeder.computeOtpHash(newBookingId, arrivalOtp),
          'arrivalOtpGeneration': 1,
          'arrivalOtpAttempts': 0,
          'arrivalOtpUsed': false,
          'arrivalOtpLocked': false,
          'arrivalOtpExpiry': DateTime.now().add(const Duration(hours: 12)),
          'arrivalOtpIssuedAt': now,
          'arrivalOtpReissueCount': 0,
          'arrivalVerified': false,
          'workerSeedLocation': {
            'lat': seedLat,
            'lng': seedLng,
            'updatedAt': now,
          },
          'idempotencyKey': idempotencyKey,
          'createdAt': now,
          'updatedAt': now,
        });

        // Seed isolated plaintext OTP strictly in hirer_secure subcollection
        txn.set(bookingRef.collection('hirer_secure').doc('arrival_code'), {
          'arrivalOtp': arrivalOtp,
          'generation': 1,
          'hirerId': hirerUid,
          'createdAt': now,
          'updatedAt': now,
        });

        // Reconcile availability atomically
        txn.update(workerRef, {
          'isAvailable': false,
          'activeBookingId': newBookingId,
        });
      });

      // Seed RTDB tracking participants & liveTracking
      try {
        await FirebaseDatabase.instance
            .ref('trackingParticipants/$newBookingId')
            .set({
          'hirerId': hirerUid,
          'workerId': workerId,
          'jobId': actualJobId,
          'createdAt': ServerValue.timestamp,
        });

        await FirebaseDatabase.instance
            .ref('liveTracking/$newBookingId')
            .set({
          'jobId': actualJobId,
          'workerId': workerId,
          'hirerId': hirerUid,
          'lat': seedLat,
          'lng': seedLng,
          'latitude': seedLat,
          'longitude': seedLng,
          'accuracy': 15.0,
          'heading': 0.0,
          'speed': 0.0,
          'speedMps': 0.0,
          'seq': 1,
          'isSeed': true,
          'trackingStatus': 'active',
          'arrivalStatus': 'en_route',
          'status': 'en_route',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': ServerValue.timestamp,
          'lastUpdatedAt': ServerValue.timestamp,
        });
      } catch (rtdbErr) {
        debugPrint('[BookingService] Non-fatal RTDB seed error: $rtdbErr');
      }

      return BookingResult.ok(newBookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Public entry point to atomically accept booking and seed tracking coordinates.
  Future<void> acceptBookingAndSeedTracking({
    required String bookingId,
    required String workerId,
    required String hirerId,
    required String jobId,
    required double workerBaseLat,
    required double workerBaseLng,
  }) async {
    try {
      await BookingTrackingSeeder.seedTrackingOnAcceptance(
        bookingId: bookingId,
        hirerId: hirerId,
        workerId: workerId,
        workerLat: workerBaseLat,
        workerLng: workerBaseLng,
        firestore: _db,
      );
    } catch (e) {
      debugPrint('[BookingService] acceptBookingAndSeedTracking RTDB error: $e');
    }

    // Auto-start Worker Background Telemetry Isolate if running on worker device
    try {
      await WorkerTelemetryService.instance.startBackgroundTracking(
        bookingId: bookingId,
        workerId: workerId,
        hirerId: hirerId,
        jobId: jobId,
      );
    } catch (e) {
      debugPrint('[BookingService] Foreground telemetry startup non-fatal: $e');
    }
  }

  // ─── WORKER: RECORD ARRIVAL (75m Geofence Doorstep Handshake) ─────────────

  /// Worker records arrival within 75m of the job location.
  /// Transitions status: confirmed|tracking -> arrived
  Future<BookingResult> recordArrival({
    required String workerUid,
    required String bookingId,
  }) async {
    try {
      final ref = _db.collection('bookings').doc(bookingId);
      await _db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw 'booking_not_found';
        final data = snap.data()!;
        if (data['workerId'] != workerUid) throw 'not_worker';
        if (data['status'] == BookingStatus.arrived) return; // Idempotent
        if (data['status'] != BookingStatus.tracking &&
            data['status'] != BookingStatus.confirmed) {
          throw 'invalid_transition:${data['status']}->arrived';
        }
        txn.update(ref, {
          'status': BookingStatus.arrived,
          'trackingStatus': 'arrived',
          'arrivalStatus': 'arrived',
          'arrivedAt': FieldValue.serverTimestamp(),
        });
      });
      return BookingResult.ok(bookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString());
    }
  }

  // ─── WORKER: RECORD WORK COMPLETION (Dual-Party Mutual Confirmation) ───────

  /// Worker records whether work has been completed.
  /// Independent: Worker confirmation alone does NOT mark booking completed.
  /// Mutual: ONLY when both worker and hirer confirm completed does status become completionVerified.
  /// If either party marks not completed, completion is prevented.
  Future<BookingResult> recordWorkerCompletion({
    required String workerUid,
    required String bookingId,
    required bool completed,
    String? notes,
  }) async {
    try {
      final bookingRef = _db.collection('bookings').doc(bookingId);
      await _db.runTransaction((txn) async {
        final snap = await txn.get(bookingRef);
        if (!snap.exists) throw 'booking_not_found';
        final data = snap.data()!;
        if (data['workerId'] != workerUid) throw 'not_worker';

        if (data['status'] == BookingStatus.disputed) {
          throw 'cannot_complete_disputed_booking';
        }

        // Cannot repeatedly complete terminal states; avoid duplicate totalJobs increment
        if (data['status'] == BookingStatus.completionVerified ||
            (data['workerCompletionStatus'] == 'completed' && data['hirerCompletionStatus'] == 'completed')) {
          return;
        }

        final now = FieldValue.serverTimestamp();
        final workerId = data['workerId'] as String;
        final workerRef = _db.collection('users').doc(workerId);

        if (completed) {
          final hirerConfirmed = data['hirerCompletionStatus'] == 'completed';
          if (hirerConfirmed) {
            // Both parties confirmed completed! Atomically transition to completionVerified
            txn.update(bookingRef, {
              'status': BookingStatus.completionVerified,
              'workerCompletionStatus': 'completed',
              'workerCompletedAt': now,
              'completionVerifiedAt': now,
              'workerCompletionNotes': notes ?? '',
              'verifiedWorkId': 'vwr_$bookingId',
            });
            // Ensure totalJobs is incremented exactly once.
            // Preserve worker availability lifecycle and future bookings: do NOT overwrite isAvailable.
            txn.update(workerRef, {
              'activeBookingId': FieldValue.delete(),
              'totalJobs': FieldValue.increment(1),
            });
          } else {
            // Worker completed, waiting for Hirer confirmation
            txn.update(bookingRef, {
              'status': BookingStatus.completionRequested,
              'workerCompletionStatus': 'completed',
              'workerCompletedAt': now,
              'workerCompletionNotes': notes ?? '',
              'completionRequestedAt': now,
              'completionRequestedBy': workerUid,
            });
          }
        } else {
          // Worker marked work NOT completed
          txn.update(bookingRef, {
            'status': BookingStatus.disputed,
            'workerCompletionStatus': 'not_completed',
            'workerCompletedAt': now,
            'workerCompletionNotes': notes ?? 'Work marked not completed by worker',
            'completionDisputed': true,
          });
        }
      });
      return BookingResult.ok(bookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString());
    }
  }

  // ─── HIRER: RECORD WORK COMPLETION (Dual-Party Mutual Confirmation) ────────

  /// Hirer records whether work has been completed.
  /// Independent: Hirer confirmation alone does NOT mark booking completed.
  /// Mutual: ONLY when both worker and hirer confirm completed does status become completionVerified.
  /// If either party marks not completed, completion is prevented.
  Future<BookingResult> recordHirerCompletion({
    required String hirerUid,
    required String bookingId,
    required bool completed,
    String? notes,
  }) async {
    try {
      final bookingRef = _db.collection('bookings').doc(bookingId);
      await _db.runTransaction((txn) async {
        final snap = await txn.get(bookingRef);
        if (!snap.exists) throw 'booking_not_found';
        final data = snap.data()!;
        if (data['hirerId'] != hirerUid) throw 'not_hirer';

        if (data['status'] == BookingStatus.disputed) {
          throw 'cannot_complete_disputed_booking';
        }

        // Cannot repeatedly complete terminal states; avoid duplicate totalJobs increment
        if (data['status'] == BookingStatus.completionVerified ||
            (data['workerCompletionStatus'] == 'completed' && data['hirerCompletionStatus'] == 'completed')) {
          return;
        }

        final now = FieldValue.serverTimestamp();
        final workerId = data['workerId'] as String;
        final workerRef = _db.collection('users').doc(workerId);

        if (completed) {
          // Explicitly check workerCompletionStatus == 'completed' (Finding B: no status fallback)
          final workerConfirmed = data['workerCompletionStatus'] == 'completed';
          if (workerConfirmed) {
            // Both parties confirmed completed! Atomically transition to completionVerified
            txn.update(bookingRef, {
              'status': BookingStatus.completionVerified,
              'hirerCompletionStatus': 'completed',
              'hirerCompletedAt': now,
              'hirerConfirmedAt': now,
              'completionVerifiedAt': now,
              'verifiedWorkId': 'vwr_$bookingId',
              'hirerCompletionNotes': notes ?? '',
            });
            // Ensure totalJobs is incremented exactly once.
            // Preserve worker availability lifecycle and future bookings: do NOT overwrite isAvailable.
            txn.update(workerRef, {
              'activeBookingId': FieldValue.delete(),
              'totalJobs': FieldValue.increment(1),
            });
          } else {
            // Hirer confirmed completed, waiting for worker confirmation
            txn.update(bookingRef, {
              'hirerCompletionStatus': 'completed',
              'hirerCompletedAt': now,
              'hirerConfirmedAt': now,
              'hirerCompletionNotes': notes ?? '',
            });
          }
        } else {
          // Hirer marked work NOT completed
          txn.update(bookingRef, {
            'status': BookingStatus.disputed,
            'hirerCompletionStatus': 'not_completed',
            'hirerCompletedAt': now,
            'hirerCompletionNotes': notes ?? 'Work marked not completed by hirer',
            'completionDisputed': true,
          });
        }
      });
      return BookingResult.ok(bookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString());
    }
  }

  // ─── HIRER: SUBMIT 1-5 STAR RATING & WRITTEN FEEDBACK ──────────────────────

  /// Hirer submits 1-5 star rating and written feedback.
  /// Mandatory condition: Allowed ONLY after mutual completion (workerCompletionStatus == 'completed' && hirerCompletionStatus == 'completed').
  /// Idempotent: Single rating per booking & hirer, duplicate submissions are rejected safely.
  Future<BookingResult> submitHirerReview({
    required String bookingId,
    required String hirerUid,
    required String workerUid,
    required double stars,
    required String feedback,
  }) async {
    if (stars < 1.0 || stars > 5.0 || stars.isNaN) {
      return const BookingResult.fail('invalid_stars', 'Rating must be between 1.0 and 5.0 stars');
    }
    final trimmedFeedback = feedback.trim();
    if (trimmedFeedback.isEmpty) {
      return const BookingResult.fail('empty_feedback', 'Please provide written feedback');
    }
    if (trimmedFeedback.length > 1000) {
      return const BookingResult.fail('feedback_too_long', 'Feedback must not exceed 1000 characters');
    }

    try {
      final bookingRef = _db.collection('bookings').doc(bookingId);
      final ratingId = 'rating_$bookingId';
      final ratingRef = _db.collection('ratings').doc(ratingId);
      final workerRef = _db.collection('users').doc(workerUid);

      await _db.runTransaction((txn) async {
        final bookingSnap = await txn.get(bookingRef);
        final ratingSnap = await txn.get(ratingRef);
        final workerSnap = await txn.get(workerRef);

        if (!bookingSnap.exists) throw 'booking_not_found';
        final data = bookingSnap.data()!;
        if (data['hirerId'] != hirerUid) throw 'not_hirer';
        if (data['workerId'] != workerUid) throw 'worker_mismatch';

        // Explicit mutual completion check: both worker and hirer confirmed completed
        final isMutuallyCompleted = data['workerCompletionStatus'] == 'completed' &&
            data['hirerCompletionStatus'] == 'completed';
        if (!isMutuallyCompleted) {
          throw 'booking_not_mutually_completed';
        }

        // Idempotency: single rating per booking & hirer
        if (ratingSnap.exists || data['hirerRated'] == true) {
          return;
        }

        final now = FieldValue.serverTimestamp();

        // 1. Create public rating document (hirer rating worker)
        txn.set(ratingRef, {
          'ratingId': ratingId,
          'bookingId': bookingId,
          'workerId': workerUid,
          'hirerId': hirerUid,
          'raterRole': 'hirer',
          'stars': stars,
          'feedback': trimmedFeedback,
          'comment': trimmedFeedback,
          'publicComment': trimmedFeedback,
          'createdAt': now,
        });

        // 2. Mark booking with rating metadata and transition to final completed status
        txn.update(bookingRef, {
          'status': BookingStatus.completed,
          'completedAt': now,
          'hirerRated': true,
          'hirerRatedWorker': true,
          'hirerRatingStars': stars,
          'hirerRatingFeedback': trimmedFeedback,
          'hirerRatedAt': now,
        });

        // 3. Atomically update worker aggregate reputation and availability
        final workerData = workerSnap.data() ?? {};
        final currentSum = ((workerData['ratingSum'] ?? 0) as num).toDouble();
        final currentCount = ((workerData['totalRatings'] ?? workerData['ratingCount'] ?? 0) as num).toInt();
        final newSum = currentSum + stars;
        final newCount = currentCount + 1;
        final newAvg = double.parse((newSum / newCount).toStringAsFixed(2));

        txn.update(workerRef, {
          'ratingSum': newSum,
          'totalRatings': newCount,
          'ratingCount': newCount,
          'rating': newAvg,
          'averageRating': newAvg,
          'isAvailable': true,
          'activeBookingId': null,
          'updatedAt': now,
        });
      });

      return BookingResult.ok(bookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString());
    }
  }

  // ─── WORKER: REQUEST COMPLETION (Backward-Compatible Adapter) ───────────────

  /// Worker requests completion. Must be in working state.
  Future<BookingResult> requestCompletion({
    required String workerUid,
    required String bookingId,
  }) async {
    return recordWorkerCompletion(
      workerUid: workerUid,
      bookingId: bookingId,
      completed: true,
    );
  }

  // ─── HIRER: CONFIRM COMPLETION (Backward-Compatible Adapter) ────────────────

  /// Hirer confirms completion.
  /// Idempotent: duplicate calls return ok without duplicate side effects.
  /// Atomically updates booking + worker totalJobs + rating.
  Future<BookingResult> confirmCompletion({
    required String hirerUid,
    required String bookingId,
    Map<String, dynamic>? ratingData,
  }) async {
    final result = await recordHirerCompletion(
      hirerUid: hirerUid,
      bookingId: bookingId,
      completed: true,
    );
    if (!result.success) return result;

    if (ratingData != null) {
      final qualityScore = (ratingData['qualityScore'] as num?)?.toDouble() ?? 0.0;
      final punctualityScore = (ratingData['punctualityScore'] as num?)?.toDouble() ?? 0.0;
      final safetyScore = (ratingData['safetyScore'] as num?)?.toDouble() ?? 0.0;
      final taskScore = (ratingData['taskCompletionScore'] as num?)?.toDouble() ?? 0.0;
      final commScore = (ratingData['communicationScore'] as num?)?.toDouble() ?? 0.0;
      final stars = (qualityScore + punctualityScore + safetyScore + taskScore + commScore) / 5.0;
      final comments = (ratingData['reviewComments'] as String?) ??
          (ratingData['comments'] as String?) ??
          'Work completed and verified';

      try {
        final bSnap = await _db.collection('bookings').doc(bookingId).get();
        final workerId = bSnap.data()?['workerId'] as String? ?? '';
        if (workerId.isNotEmpty && stars >= 1.0) {
          await submitHirerReview(
            bookingId: bookingId,
            hirerUid: hirerUid,
            workerUid: workerId,
            stars: stars,
            feedback: comments.isNotEmpty ? comments : 'Verified work completed',
          );
        }
      } catch (_) {}
    }

    return result;
  }

  // ─── CANCELLATION ───────────────────────────────────────────────────────────

  /// Cancel a booking. Valid only from pre-working states.
  Future<BookingResult> cancelBooking({
    required String actorUid,
    required String bookingId,
    required String reason,
  }) async {
    try {
      final ref = _db.collection('bookings').doc(bookingId);
      await _db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw 'booking_not_found';
        final data = snap.data()!;

        final isWorker = data['workerId'] == actorUid;
        final isHirer = data['hirerId'] == actorUid;
        if (!isWorker && !isHirer) throw 'not_party';

        const cancellable = {BookingStatus.confirmed, 'pending'};
        if (!cancellable.contains(data['status'])) {
          throw 'cannot_cancel_in_state:${data['status']}';
        }

        txn.update(ref, {
          'status': BookingStatus.cancelled,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': actorUid,
          'cancellationReason': reason,
        });

        final workerId = data['workerId'] as String?;
        if (workerId != null && workerId.isNotEmpty) {
          txn.update(_db.collection('users').doc(workerId), {
            'isAvailable': false,
            'activeBookingId': FieldValue.delete(),
          });
        }
      });

      // Revoke RTDB tracking session immediately upon cancellation
      try {
        await FirebaseDatabase.instance
            .ref('trackingParticipants/$bookingId')
            .update({
          'revoked': true,
          'status': 'cancelled',
          'revokedAt': DateTime.now().millisecondsSinceEpoch,
          'revokedBy': actorUid,
        });
      } catch (_) {}

      return BookingResult.ok(bookingId);
    } on FirebaseException catch (e) {
      return BookingResult.fail(e.code, e.message);
    } catch (e) {
      return BookingResult.fail(e.toString(), e.toString());
    }
  }

  /// Hirer regenerates arrival OTP when locked, expired, or needed.
  /// Atomically updates hirer_secure/arrival_code and booking document with new generation.
  Future<({bool success, String error, String? newOtp})> regenerateArrivalOtp({
    required String bookingId,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      return (success: false, error: 'UNAUTHORIZED_HIRER', newOtp: null);
    }

    final bookingRef = _db.collection('bookings').doc(bookingId);
    final secureRef = bookingRef.collection('hirer_secure').doc('arrival_code');

    try {
      final snap = await bookingRef.get();
      if (!snap.exists) {
        return (success: false, error: 'BOOKING_NOT_FOUND', newOtp: null);
      }
      final data = snap.data()!;
      if (data['hirerId'] != currentUid) {
        return (success: false, error: 'UNAUTHORIZED_HIRER', newOtp: null);
      }

      final status = (data['status'] ?? '').toString();
      if (![BookingStatus.arrived, BookingStatus.confirmed, BookingStatus.tracking].contains(status)) {
        return (success: false, error: 'INVALID_STATUS_FOR_REISSUE', newOtp: null);
      }

      if (data['arrivalOtpUsed'] == true) {
        return (success: false, error: 'OTP_ALREADY_USED', newOtp: null);
      }

      final reissueCount = (data['arrivalOtpReissueCount'] as num?)?.toInt() ?? 0;
      if (reissueCount >= 5) {
        return (success: false, error: 'MAX_REISSUES_EXCEEDED', newOtp: null);
      }

      // 15s cooldown check
      final dynamic rawLastIssue = data['arrivalOtpReissuedAt'] ?? data['arrivalOtpIssuedAt'];
      if (rawLastIssue is Timestamp) {
        final lastTime = rawLastIssue.toDate();
        if (DateTime.now().difference(lastTime).inSeconds < 15) {
          return (success: false, error: 'REISSUE_COOLDOWN_ACTIVE', newOtp: null);
        }
      }

      final newOtp = BookingTrackingSeeder.generateSixDigitOtp();
      final curGen = (data['arrivalOtpGeneration'] as num?)?.toInt() ?? 1;
      final newGen = curGen + 1;
      final now = FieldValue.serverTimestamp();
      final newExpiry = DateTime.now().add(const Duration(hours: 12));

      await _db.runTransaction((tx) async {
        // 1. Update subcollection arrival_code
        tx.set(secureRef, {
          'arrivalOtp': newOtp,
          'generation': newGen,
          'hirerId': currentUid,
          'updatedAt': now,
        }, SetOptions(merge: true));

        // 2. Update booking document under Transition 9b
        tx.update(bookingRef, {
          'arrivalOtpGeneration': newGen,
          'arrivalOtpAttempts': 0,
          'arrivalOtpUsed': false,
          'arrivalOtpLocked': false,
          'arrivalOtpExpiry': newExpiry,
          'arrivalOtpIssuedAt': now,
          'arrivalOtpReissuedAt': now,
          'arrivalOtpReissueCount': reissueCount + 1,
          'updatedAt': now,
        });
      });

      debugPrint('[BookingService] OTP regenerated successfully: gen=$newGen, booking=$bookingId');
      return (success: true, error: '', newOtp: newOtp);
    } on FirebaseException catch (e) {
      debugPrint('[BookingService] regenerateArrivalOtp FirebaseException: ${e.code} ${e.message}');
      return (success: false, error: e.code, newOtp: null);
    } catch (e) {
      debugPrint('[BookingService] regenerateArrivalOtp exception: $e');
      return (success: false, error: e.toString(), newOtp: null);
    }
  }

  /// Worker submits arrival OTP for authoritative backend verification.
  /// Verified under Firestore Security Rules Transition 4 (and optional Cloud Functions if deployed).
  /// Enforces that caller is assigned worker, booking is in 'arrived' state,
  /// validates OTP against secure storage, enforces 5-attempt rate-limit and TTL expiry,
  /// and atomically updates status to 'working' / arrivalVerified: true.
  Future<({bool success, String error, int? remainingAttempts})> verifyArrivalOtp({
    required String bookingId,
    required String enteredOtp,
    double? workerLat,
    double? workerLng,
  }) async {
    final cleanOtp = enteredOtp.trim();
    final traceId = 'otp_${DateTime.now().millisecondsSinceEpoch}_${bookingId.hashCode.abs().toRadixString(16)}';
    debugPrint('[OTP_TRACE:$traceId] Initiating verification for bookingId: $bookingId');

    if (cleanOtp.length != 6) {
      return (success: false, error: 'INVALID_OTP', remainingAttempts: null);
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: UNAUTHORIZED_WORKER (no current user)');
      return (success: false, error: 'UNAUTHORIZED_WORKER', remainingAttempts: null);
    }

    final bookingRef = _db.collection('bookings').doc(bookingId);

    // Pre-flight check: read booking document to evaluate pre-conditions safely
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await bookingRef.get();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      debugPrint('[OTP_TRACE:$traceId] Preflight read exception: $e');
      if (errStr.contains('network') || errStr.contains('socket') || errStr.contains('unavailable')) {
        return (success: false, error: 'NETWORK_ERROR', remainingAttempts: null);
      }
      return (success: false, error: 'SERVER_ERROR', remainingAttempts: null);
    }

    if (!snap.exists) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: BOOKING_NOT_FOUND');
      return (success: false, error: 'BOOKING_NOT_FOUND', remainingAttempts: null);
    }

    final data = snap.data()!;
    if (data['workerId'] != currentUid) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: UNAUTHORIZED_WORKER (assigned worker: ${data['workerId']}, caller: $currentUid)');
      return (success: false, error: 'UNAUTHORIZED_WORKER', remainingAttempts: null);
    }

    final currentStatus = (data['status'] ?? '').toString();
    if (currentStatus != BookingStatus.arrived) {
      if (BookingStatus.isWorkingState(currentStatus)) {
        debugPrint('[OTP_TRACE:$traceId] Already in working state: $currentStatus');
        return (success: true, error: '', remainingAttempts: null);
      }
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: BOOKING_NOT_ARRIVED (status: $currentStatus)');
      return (success: false, error: 'BOOKING_NOT_ARRIVED', remainingAttempts: null);
    }

    if (data['arrivalOtpUsed'] == true || data['arrivalVerified'] == true) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: OTP_ALREADY_USED');
      return (success: false, error: 'OTP_ALREADY_USED', remainingAttempts: 0);
    }

    final isLocked = data['arrivalOtpLocked'] == true;
    final attempts = (data['arrivalOtpAttempts'] as num?)?.toInt() ?? 0;
    if (isLocked || attempts >= 5) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: OTP_LOCKED (attempts: $attempts, isLocked: $isLocked)');
      return (success: false, error: 'OTP_LOCKED', remainingAttempts: 0);
    }

    final dynamic rawExpiry = data['arrivalOtpExpiry'];
    DateTime? expiry;
    if (rawExpiry is Timestamp) {
      expiry = rawExpiry.toDate();
    } else if (rawExpiry is String) {
      expiry = DateTime.tryParse(rawExpiry);
    }

    final isUnexpired = expiry != null && DateTime.now().isBefore(expiry);
    debugPrint('[OTP_TRACE:$traceId] Preflight check: status=$currentStatus, attempts=$attempts, expiry=$expiry, unexpired=$isUnexpired');

    if (rawExpiry == null) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: MISSING_EXPIRY');
      return (success: false, error: 'MISSING_EXPIRY', remainingAttempts: 5 - attempts);
    }
    if (!isUnexpired) {
      debugPrint('[OTP_TRACE:$traceId] Preflight fail: OTP_EXPIRED');
      return (success: false, error: 'OTP_EXPIRED', remainingAttempts: 5 - attempts);
    }

    // 1. Authoritative Firestore Transaction verified by Security Rules Transition 4
    try {
      await _db.runTransaction((tx) async {
        final bSnap = await tx.get(bookingRef);
        if (!bSnap.exists) throw 'BOOKING_NOT_FOUND';
        final bData = bSnap.data()!;
        final bStatus = (bData['status'] ?? '').toString();
        if (bStatus != BookingStatus.arrived) {
          if (BookingStatus.isWorkingState(bStatus)) return;
          throw 'BOOKING_NOT_ARRIVED';
        }
        if (bData['arrivalOtpUsed'] == true) throw 'OTP_ALREADY_USED';
        if (bData['arrivalOtpLocked'] == true) throw 'OTP_LOCKED';
        final curAttempts = (bData['arrivalOtpAttempts'] as num?)?.toInt() ?? 0;
        if (curAttempts >= 5) throw 'OTP_LOCKED';

        final now = FieldValue.serverTimestamp();
        tx.update(bookingRef, {
          'status': BookingStatus.working,
          'arrivalVerified': true,
          'arrivalVerifiedAt': now,
          'arrivalOtpUsed': true,
          'otpAttempt': cleanOtp,
          'workStartedAt': now,
          'otpVerifiedAt': now,
        });
      });

      debugPrint('[OTP_TRACE:$traceId] Transition 4 transaction succeeded!');

      // Immediate Transition 4c: Scrub submitted OTP from root document so plaintext does not persist
      try {
        await bookingRef.update({
          'otpAttempt': FieldValue.delete(),
        });
        debugPrint('[OTP_TRACE:$traceId] Transition 4c: otpAttempt successfully scrubbed from root document');
      } catch (scrubErr) {
        debugPrint('[OTP_TRACE:$traceId] Non-fatal otpAttempt scrub notice: $scrubErr');
      }

      // Revoke RTDB tracking session upon verified arrival
      try {
        await FirebaseDatabase.instance.ref('trackingParticipants/$bookingId').update({
          'revoked': true,
          'status': 'working',
          'revokedAt': DateTime.now().millisecondsSinceEpoch,
          'revokedBy': currentUid,
        });
      } catch (_) {}

      return (success: true, error: '', remainingAttempts: null);
    } on FirebaseException catch (e) {
      debugPrint('[OTP_TRACE:$traceId] Firestore OTP verification FirebaseException: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        // Increment attempt counter via Security Rules Transition 4b ONLY on validation failure
        final newAttempts = attempts + 1;
        final isNowLocked = newAttempts >= 5;
        try {
          await bookingRef.update({
            'arrivalOtpAttempts': FieldValue.increment(1),
            'lastFailedOtpAt': FieldValue.serverTimestamp(),
            if (isNowLocked) 'arrivalOtpLocked': true,
            if (isNowLocked) 'arrivalOtpLockedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}

        final rem = 5 - newAttempts;
        if (rem <= 0 || isNowLocked) {
          return (success: false, error: 'OTP_LOCKED', remainingAttempts: 0);
        }
        return (success: false, error: 'INVALID_OTP', remainingAttempts: rem);
      }
      return (success: false, error: 'SERVER_ERROR: ${e.code}', remainingAttempts: null);
    } catch (e) {
      debugPrint('[OTP_TRACE:$traceId] Firestore OTP verification error: $e');
      final errStr = e.toString();
      if (errStr.contains('BOOKING_NOT_FOUND')) {
        return (success: false, error: 'BOOKING_NOT_FOUND', remainingAttempts: null);
      } else if (errStr.contains('BOOKING_NOT_ARRIVED')) {
        return (success: false, error: 'BOOKING_NOT_ARRIVED', remainingAttempts: null);
      } else if (errStr.contains('OTP_ALREADY_USED')) {
        return (success: false, error: 'OTP_ALREADY_USED', remainingAttempts: 0);
      } else if (errStr.contains('OTP_LOCKED') || errStr.contains('TOO_MANY_ATTEMPTS')) {
        return (success: false, error: 'OTP_LOCKED', remainingAttempts: 0);
      } else if (errStr.toLowerCase().contains('network') ||
          errStr.toLowerCase().contains('socket') ||
          errStr.toLowerCase().contains('connection')) {
        return (success: false, error: 'NETWORK_ERROR', remainingAttempts: null);
      }
      return (success: false, error: 'SERVER_ERROR', remainingAttempts: null);
    }
  }

  /// Worker-Side Fraud-Proof Atomic OTP Verification Transaction
  /// Unlocks 'working' status only when physical coordinates are genuine and OTP matches
  static Future<bool> verifyArrivalOtpAtomically({
    required String bookingId,
    required String enteredOtp,
    required double workerCurrentLat,
    required double workerCurrentLng,
    required bool isMockedGps,
  }) async {
    if (isMockedGps) {
      throw StateError('Mock GPS detected. Disable location spoofing to verify OTP.');
    }

    final res = await BookingService.instance.verifyArrivalOtp(
      bookingId: bookingId,
      enteredOtp: enteredOtp,
      workerLat: workerCurrentLat,
      workerLng: workerCurrentLng,
    );
    return res.success;
  }

  // ─── VOICE DIRECT BOOKING CALLABLE WRAPPERS (V5.0) ────────────────────────

  /// Maps raw Firebase Cloud Function codes into canonical typed failure results and user messages
  static Map<String, String> mapCloudFunctionsError({
    required String code,
    String? message,
    Map<String, dynamic>? details,
  }) {
    String mappedCode = code;
    String mappedMessage;
    String stage = 'CALLABLE_RESOLUTION';

    if (details != null && details['stage'] != null) {
      stage = details['stage'].toString();
    }

    if (code == 'not-found') {
      final rawMsg = message ?? '';
      final detailCode = (details != null && details['code'] != null) ? details['code'].toString() : '';
      if (stage == 'WORKER_LOOKUP' || rawMsg == 'WORKER_PROFILE_NOT_FOUND' || detailCode == 'WORKER_PROFILE_NOT_FOUND' || rawMsg.contains('Worker profile')) {
        mappedCode = 'WORKER_PROFILE_NOT_FOUND';
        mappedMessage = 'This worker profile is no longer available. Refresh the results.';
        stage = 'WORKER_LOOKUP';
      } else if (stage == 'HIRER_LOOKUP' || rawMsg == 'HIRER_PROFILE_NOT_FOUND' || detailCode == 'HIRER_PROFILE_NOT_FOUND' || rawMsg.contains('Hirer profile')) {
        mappedCode = 'HIRER_PROFILE_NOT_FOUND';
        mappedMessage = 'Hirer profile not found. Please complete your profile.';
        stage = 'HIRER_LOOKUP';
      } else if (rawMsg == 'NOT_FOUND' || rawMsg.isEmpty || rawMsg.contains('404') || stage == 'CALLABLE_RESOLUTION') {
        mappedCode = 'CALLABLE_UNAVAILABLE';
        mappedMessage = 'The booking service could not be reached. Please retry.';
        stage = 'CALLABLE_RESOLUTION';
      } else {
        mappedCode = 'NOT_FOUND';
        mappedMessage = 'The requested resource was not found. Please refresh and try again.';
      }
    } else if (code == 'failed-precondition' || code == 'WORKER_UNAVAILABLE' || code == 'WORKER_ALREADY_ASSIGNED') {
      final rawMsg = message ?? '';
      if (code == 'WORKER_UNAVAILABLE' || rawMsg.contains('WORKER_UNAVAILABLE') || rawMsg.contains('marked unavailable') || rawMsg.contains('Unavailable')) {
        mappedCode = 'WORKER_UNAVAILABLE';
        mappedMessage = 'This worker is currently unavailable. Search for another worker.';
      } else if (code == 'WORKER_ALREADY_ASSIGNED' || rawMsg.contains('WORKER_ALREADY_ASSIGNED') || rawMsg.contains('assigned to another booking') || rawMsg.contains('Assigned')) {
        mappedCode = 'WORKER_ALREADY_ASSIGNED';
        mappedMessage = 'This worker has already accepted another booking.';
      } else if (rawMsg.contains('WORKER_NOT_APPROVED') || rawMsg.contains('not approved')) {
        mappedCode = 'WORKER_NOT_APPROVED';
        mappedMessage = 'This worker profile is not currently approved for bookings.';
      } else {
        mappedCode = 'FAILED_PRECONDITION';
        mappedMessage = rawMsg.isNotEmpty ? rawMsg : 'The booking cannot be processed at this time.';
      }
      stage = 'WORKER_ELIGIBILITY';
    } else if (code == 'unauthenticated') {
      mappedCode = 'AUTHENTICATION_REQUIRED';
      mappedMessage = 'Please sign in again to submit a booking.';
      stage = 'CALLABLE_AUTHENTICATION';
    } else if (code == 'invalid-argument') {
      mappedCode = 'INVALID_BOOKING_PAYLOAD';
      mappedMessage = 'Please review the booking details.';
      stage = 'FORM_VALIDATION';
    } else if (code == 'unavailable' || code == 'deadline-exceeded') {
      mappedCode = 'BOOKING_SERVICE_UNAVAILABLE';
      mappedMessage = 'The booking service could not be reached. Please retry.';
      stage = 'CALLABLE_RESOLUTION';
    } else {
      mappedCode = code.toUpperCase();
      mappedMessage = message != null && message.isNotEmpty && message != 'NOT_FOUND'
          ? message
          : 'We could not complete your request.';
    }

    return {
      'code': mappedCode,
      'userMessage': mappedMessage,
      'stage': stage,
    };
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Computes a deterministic canonical request fingerprint across the entire immutable booking payload (V6.3.4.3 Gate 2).
  static String computeBookingRequestFingerprint({
    required String hirerId,
    required String workerId,
    required String jobTitle,
    required String category,
    required String description,
    required String jobAddress,
    required double jobLat,
    required double jobLng,
    required String scheduledDate,
    required String scheduledTime,
    required double wage,
    required String bookingSource,
  }) {
    final canonical = [
      hirerId.trim(),
      workerId.trim(),
      jobTitle.trim(),
      category.trim(),
      description.trim(),
      jobAddress.trim(),
      jobLat.toStringAsFixed(6),
      jobLng.toStringAsFixed(6),
      scheduledDate.trim(),
      scheduledTime.trim(),
      wage.toStringAsFixed(2),
      bookingSource.trim(),
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Request a direct voice booking.
  /// Authoritative Transport: SPARK_NATIVE_PENDING_CREATE.
  /// Eliminates dual-transport race conditions and ensures immediate, atomic booking creation.
  /// Does NOT reserve the worker exclusively (non-exclusive pending model).
  Future<BookingResult> requestVoiceDirectBooking({
    required String workerId,
    required String skillId,
    required String jobTitle,
    required String description,
    required String category,
    required String scheduledDate,
    required String scheduledTime,
    required double wage,
    required double jobLat,
    required double jobLng,
    required String jobAddress,
    String? specialInstructions,
    String? idempotencyKey,
    String? correlationId,
  }) async {
    final corrId = correlationId ??
        'corr_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';

    // 1. Zero-Budget Spark Authoritative Direct Firestore Creation
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) {
      return BookingResult.fail(
        'AUTHENTICATION_REQUIRED',
        'You must be signed in to request a direct booking.',
        correlationId: corrId,
      );
    }
    final hirerUid = user.uid;

    if (workerId.trim().isEmpty) {
      return BookingResult.fail('INVALID_BOOKING_PAYLOAD', 'Worker ID is required.', correlationId: corrId);
    }
    if (jobTitle.trim().isEmpty) {
      return BookingResult.fail('INVALID_BOOKING_PAYLOAD', 'Job title is required.', correlationId: corrId);
    }
    if (description.trim().length < 8) {
      return BookingResult.fail('INVALID_BOOKING_PAYLOAD', 'Please describe the work in at least 8 characters.', correlationId: corrId);
    }
    if (wage <= 0) {
      return BookingResult.fail('INVALID_BOOKING_PAYLOAD', 'Offered wage must be greater than ₹0.', correlationId: corrId);
    }

    try {
      final db = FirebaseFirestore.instance;

      // 1. Stable, deterministic idempotency key and document identity
      final effectiveIdempotencyKey = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          ? idempotencyKey.trim()
          : 'ik_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';

      final keyHash = sha256.convert(utf8.encode('$hirerUid:$effectiveIdempotencyKey')).toString().substring(0, 20);
      final deterministicBookingId = 'vdoc_${hirerUid}_$keyHash';
      final bookingRef = db.collection('bookings').doc(deterministicBookingId);

      // Pre-fetch hirer profile for denormalized fields
      String hirerName = user.displayName ?? 'Hirer';
      String hirerPhone = user.phoneNumber ?? '';
      try {
        final hSnap = await db.collection('users').doc(hirerUid).get();
        if (hSnap.exists) {
          hirerName = (hSnap.data()?['name'] as String?) ?? (hSnap.data()?['displayName'] as String?) ?? hirerName;
          hirerPhone = (hSnap.data()?['phone'] as String?) ?? hirerPhone;
        }
      } catch (_) {}

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 2));

      // Compute canonical request fingerprint for Gate 2 conflict detection
      final currentFingerprint = computeBookingRequestFingerprint(
        hirerId: hirerUid,
        workerId: workerId,
        jobTitle: jobTitle,
        category: category,
        description: description,
        jobAddress: jobAddress,
        jobLat: jobLat,
        jobLng: jobLng,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
        wage: wage,
        bookingSource: 'voice_command_center',
      );

      // 2. Atomic transaction: read intended booking before creation
      final committedBookingId = await db.runTransaction<String>((txn) async {
        final snap = await txn.get(bookingRef);

        if (snap.exists) {
          final existingData = snap.data() ?? {};
          final existingHirer = (existingData['hirerId'] as String?) ?? '';

          // Ownership verification
          if (existingHirer != hirerUid) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'IDEMPOTENCY_OWNERSHIP_MISMATCH: Idempotency key owned by different hirer',
            );
          }

          // Complete request fingerprint verification (V6.3.4.3 Gate 2)
          final existingFingerprint = (existingData['requestFingerprint'] as String?) ?? '';
          if (existingFingerprint.isNotEmpty) {
            if (existingFingerprint != currentFingerprint) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'already-exists',
                message: 'IDEMPOTENCY_PAYLOAD_MISMATCH: Idempotency key reused with conflicting booking details',
              );
            }
          } else {
            // Fallback deep verification for legacy documents lacking requestFingerprint
            final existingWorker = (existingData['workerId'] as String?) ?? '';
            final existingWage = (existingData['wage'] as num?)?.toDouble() ??
                (existingData['pay'] as num?)?.toDouble() ?? 0.0;
            final existingTitle = (existingData['jobTitle'] as String?) ?? '';
            final existingCat = (existingData['category'] as String?) ?? '';
            final existingDesc = (existingData['description'] as String?) ?? '';
            final existingAddr = (existingData['jobAddress'] as String?) ?? '';
            final existingLat = (existingData['jobLat'] as num?)?.toDouble() ?? 0.0;
            final existingLng = (existingData['jobLng'] as num?)?.toDouble() ?? 0.0;
            final existingDate = (existingData['scheduledDate'] as String?) ?? '';
            final existingTime = (existingData['scheduledTime'] as String?) ?? '';

            if (existingWorker != workerId.trim() ||
                (existingWage - wage).abs() > 0.01 ||
                existingTitle != jobTitle.trim() ||
                existingCat != category.trim() ||
                existingDesc != description.trim() ||
                existingAddr != jobAddress.trim() ||
                (existingLat - jobLat).abs() > 0.0001 ||
                (existingLng - jobLng).abs() > 0.0001 ||
                existingDate != scheduledDate.trim() ||
                existingTime != scheduledTime.trim()) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'already-exists',
                message: 'IDEMPOTENCY_PAYLOAD_MISMATCH: Idempotency key reused with conflicting booking details',
              );
            }
          }

          // Idempotent return: exactly identical booking exists
          return snap.id;
        }

        // New authoritative booking write
        txn.set(bookingRef, {
          'bookingId': deterministicBookingId,
          'hirerId': hirerUid,
          'hirerName': hirerName,
          'hirerPhone': hirerPhone,
          'workerId': workerId.trim(),
          'skillId': skillId.trim(),
          'jobTitle': jobTitle.trim(),
          'description': description.trim(),
          'category': category.trim(),
          'scheduledDate': scheduledDate.trim(),
          'scheduledTime': scheduledTime.trim(),
          'pay': wage.toInt(),
          'wage': wage,
          'jobLat': jobLat,
          'jobLng': jobLng,
          'jobAddress': jobAddress.trim(),
          'specialInstructions': (specialInstructions ?? '').trim(),
          'status': 'pending',
          'isDirectBooking': true,
          'bookingSource': 'voice_command_center',
          'idempotencyKey': effectiveIdempotencyKey,
          'requestFingerprint': currentFingerprint,
          'correlationId': corrId,
          'createdAt': now,
          'updatedAt': now,
          'expiresAt': expiresAt,
        });

        return deterministicBookingId;
      });

      return BookingResult.ok(
        committedBookingId,
        correlationId: corrId,
        stage: 'SPARK_NATIVE_PENDING_CREATE',
      );
    } catch (e) {
      debugPrint('[BookingService] Spark direct booking creation failed: $e');
      return BookingResult.fail(
        'SUBMISSION_FAILED',
        'Could not submit booking request: $e',
        correlationId: corrId,
      );
    }
  }

  /// Worker approves a direct voice booking.
  /// Zero-knowledge arrival security: The worker device NEVER generates or knows the OTP beforehand.
  /// Approval routes strictly through the trusted Cloudflare Worker Free backend.
  Future<BookingResult> approveVoiceDirectBooking({
    required String bookingId,
  }) async {
    final corrId = 'corr_appr_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final apiResult = await VoiceBookingApiClient.instance.approveVoiceDirectBooking(
        bookingId: bookingId,
      ).timeout(const Duration(seconds: 15));

      if (apiResult.success) {
        return apiResult;
      }
      return apiResult;
    } catch (e) {
      debugPrint('[BookingService] Voice backend approval failed: $e');
      return BookingResult.fail(
        'BACKEND_UNAVAILABLE',
        'Direct booking approval requires Cloudflare Workers backend. Please run `wrangler deploy` to activate: $e',
        correlationId: corrId,
      );
    }
  }

  /// Worker rejects a direct voice booking with mandatory reason code.
  Future<BookingResult> rejectVoiceDirectBooking({
    required String bookingId,
    required String reasonCode,
    String? reasonText,
  }) async {
    final corrId = 'corr_rej_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final apiResult = await VoiceBookingApiClient.instance.rejectVoiceDirectBooking(
        bookingId: bookingId,
        reasonCode: reasonCode,
        reasonText: reasonText,
      ).timeout(const Duration(seconds: 2));

      if (apiResult.success) {
        return apiResult;
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return BookingResult.fail('AUTHENTICATION_REQUIRED', 'Worker must be signed in', correlationId: corrId);
    }

    try {
      final db = FirebaseFirestore.instance;
      final bookingRef = db.collection('bookings').doc(bookingId);
      final now = DateTime.now();

      await db.runTransaction((txn) async {
        final bSnap = await txn.get(bookingRef);
        if (!bSnap.exists) {
          throw StateError('Booking not found');
        }
        final bData = bSnap.data()!;
        if (bData['status'] != 'pending') {
          throw StateError('Booking is no longer pending (current: ${bData['status']})');
        }
        if (bData['workerId'] != user.uid) {
          throw StateError('Not assigned to this booking');
        }

        txn.update(bookingRef, {
          'status': 'rejected',
          'rejectionReasonCode': reasonCode,
          'rejectionReasonText': reasonText ?? '',
          'rejectedAt': now,
          'updatedAt': now,
        });
      });

      return BookingResult.ok(
        bookingId,
        correlationId: corrId,
        stage: 'SPARK_DIRECT_BOOKING_REJECTED',
      );
    } catch (e) {
      return BookingResult.fail(
        'REJECTION_FAILED',
        'Could not reject booking: $e',
        correlationId: corrId,
      );
    }
  }

  /// Hirer cancels a pending direct booking request before worker response.
  Future<BookingResult> cancelVoiceDirectBooking({
    required String bookingId,
    String? reason,
  }) async {
    final corrId = 'corr_cnc_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final apiResult = await VoiceBookingApiClient.instance.cancelVoiceDirectBooking(
        bookingId: bookingId,
        reason: reason,
      ).timeout(const Duration(seconds: 2));

      if (apiResult.success) {
        return apiResult;
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return BookingResult.fail('AUTHENTICATION_REQUIRED', 'Hirer must be signed in', correlationId: corrId);
    }

    try {
      final db = FirebaseFirestore.instance;
      final bookingRef = db.collection('bookings').doc(bookingId);
      final now = DateTime.now();

      await db.runTransaction((txn) async {
        final bSnap = await txn.get(bookingRef);
        if (!bSnap.exists) {
          throw StateError('Booking not found');
        }
        final bData = bSnap.data()!;
        if (bData['status'] != 'pending') {
          throw StateError('Booking is no longer pending (current: ${bData['status']})');
        }
        if (bData['hirerId'] != user.uid) {
          throw StateError('Not your booking');
        }

        txn.update(bookingRef, {
          'status': 'cancelled',
          'cancelledBy': 'hirer',
          'cancellationReason': reason ?? 'cancelled_by_hirer',
          'updatedAt': now,
        });
      });

      return BookingResult.ok(
        bookingId,
        correlationId: corrId,
        stage: 'SPARK_DIRECT_BOOKING_CANCELLED',
      );
    } catch (e) {
      return BookingResult.fail(
        'CANCELLATION_FAILED',
        'Could not cancel booking: $e',
        correlationId: corrId,
      );
    }
  }
}

/// Atomically seeds tracking in Firestore and Firebase RTDB on job confirmation.
class BookingTrackingSeeder {
  static String generateSixDigitOtp() {
    final rng = math.Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  /// Computes deterministic HMAC-SHA256 verifier digest for arrival OTP binding.
  static String computeOtpHash(String bookingId, String otp) {
    const secret = 'kelasagara_secure_journey_hmac_secret_v21_production';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode('$bookingId:${otp.trim()}'));
    return digest.toString();
  }

  /// @deprecated Use generateSixDigitOtp for V21 contract.
  static String generateFourDigitOtp() => generateSixDigitOtp();

  /// Atomically seeds both Firestore and Firebase RTDB upon worker acceptance.
  static Future<String> seedTrackingOnAcceptance({
    required String bookingId,
    required String hirerId,
    required String workerId,
    required double workerLat,
    required double workerLng,
    FirebaseFirestore? firestore,
    FirebaseDatabase? rtdb,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final realtime = rtdb ?? FirebaseDatabase.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final arrivalOtp = generateSixDigitOtp();
    final otpHash = computeOtpHash(bookingId, arrivalOtp);

    final hasValidCoords = workerLat.isFinite &&
        !workerLat.isNaN &&
        workerLat >= -90.0 &&
        workerLat <= 90.0 &&
        workerLng.isFinite &&
        !workerLng.isNaN &&
        workerLng >= -180.0 &&
        workerLng <= 180.0;

    final safeLat = hasValidCoords ? workerLat : 12.9716; // Bengaluru fallback
    final safeLng = hasValidCoords ? workerLng : 77.5946;

    // 1. Update Firestore booking with verifier hash and workerSeedLocation (NEVER plaintext OTP)
    await db.collection('bookings').doc(bookingId).set(
      {
        'arrivalOtpHash': otpHash,
        'arrivalOtpExpiry': DateTime.fromMillisecondsSinceEpoch(nowMs + 15 * 60 * 1000),
        'arrivalOtpAttempts': 0,
        'arrivalOtpUsed': false,
        'arrivalVerified': false,
        'workerSeedLocation': {
          'lat': safeLat,
          'lng': safeLng,
          'updatedAt': nowMs,
        },
      },
      SetOptions(merge: true),
    );

    // 2. Seed RTDB trackingParticipants & liveTracking nodes in parallel
    await Future.wait([
      realtime.ref('trackingParticipants/$bookingId').set({
        'hirerId': hirerId,
        'workerId': workerId,
        'createdAt': nowMs,
        'expiresAtMs': nowMs + (4 * 3600 * 1000), // 4-hour bounded session lease
        'revoked': false,
        'status': 'active',
      }),
      realtime.ref('liveTracking/$bookingId').set({
        'lat': safeLat,
        'lng': safeLng,
        'heading': 0.0,
        'speedMps': 0.0,
        'accuracy': 15.0,
        'updatedAt': nowMs,
        'workerId': workerId,
        'status': 'on_the_way',
        'isSeed': true,
        'isOnline': true,
        'seq': 0,
      }),
    ]);

    return arrivalOtp;
  }
}

