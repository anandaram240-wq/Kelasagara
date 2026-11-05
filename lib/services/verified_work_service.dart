// lib/services/verified_work_service.dart
// Work completion and verification adapter for Kelasagara.
//
// Delegates authoritative transactions to canonical BookingService:
//   Worker side:   requestCompletion(bookingId) → BookingService.instance.requestCompletion
//   Hirer side:    confirmCompletion(...)       → BookingService.instance.confirmCompletion
//   Hirer side:    disputeCompletion(...)       → sets status=disputed
//
// Only HIRER confirmation completes the booking and issues verified work attributes.
// Worker CANNOT self-issue verified work badges.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'booking_service.dart';

class VerifiedWorkService {
  VerifiedWorkService._();
  static final VerifiedWorkService instance = VerifiedWorkService._();

  final _db = FirebaseFirestore.instance;

  // ── Worker: request work completion ────────────────────────────────────────
  Future<({bool success, String error})> requestCompletion({
    required String bookingId,
    required String workerId,
  }) async {
    final result = await BookingService.instance.requestCompletion(
      workerUid: workerId,
      bookingId: bookingId,
    );
    return (
      success: result.success,
      error: result.errorMessage ?? '',
    );
  }

  // ── Hirer: confirm work completion ─────────────────────────────────────────
  // Delegates to canonical BookingService.confirmCompletion which executes
  // an authoritative runTransaction updating booking, worker totalJobs, and rating.
  Future<({bool success, String error, String? verifiedWorkId})> confirmCompletion({
    required String bookingId,
    required String workerId,
    required String hirerId,
    required String jobId,
    required String skillId,
    required double qualityScore,
    required double punctualityScore,
    required double safetyScore,
    required double taskCompletionScore,
    required double communicationScore,
    required bool wouldHireAgain,
    String comments = '',
  }) async {
    final result = await BookingService.instance.confirmCompletion(
      hirerUid: hirerId,
      bookingId: bookingId,
      ratingData: {
        'qualityScore':        qualityScore,
        'punctualityScore':    punctualityScore,
        'safetyScore':         safetyScore,
        'taskCompletionScore': taskCompletionScore,
        'communicationScore':  communicationScore,
        'wouldHireAgain':      wouldHireAgain,
        'reviewComments':      comments,
      },
    );

    if (result.success) {
      return (
        success: true,
        error: '',
        verifiedWorkId: 'vwr_$bookingId',
      );
    } else {
      return (
        success: false,
        error: result.errorMessage ?? 'Completion failed',
        verifiedWorkId: null,
      );
    }
  }

  // ── Hirer: dispute completion ───────────────────────────────────────────────
  Future<bool> disputeCompletion({
    required String bookingId,
    required String hirerId,
    required String reason,
  }) async {
    try {
      final snap = await _db.collection('bookings').doc(bookingId).get();
      if (!snap.exists || snap.data()?['hirerId'] != hirerId) return false;
      await _db.collection('bookings').doc(bookingId).update({
        'status':        'disputed',
        'disputedAt':    FieldValue.serverTimestamp(),
        'disputeReason': reason,
        'disputedBy':    hirerId,
      });
      return true;
    } catch (e) {
      debugPrint('[VerifiedWork] dispute error: $e');
      return false;
    }
  }

  // ── Stream worker verified records ─────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> streamVerifiedWork(String workerId) {
    return _db
        .collection('verifiedWorkRecords')
        .where('workerId', isEqualTo: workerId)
        .where('reviewStatus', isEqualTo: 'verified')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
