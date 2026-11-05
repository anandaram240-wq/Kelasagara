// ================================================================
// KELASAGARA — Verified Work Record Models
// Only real Kelasagara bookings generate verified work records.
// These are distinct from assessment evidence.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

class VerifiedWorkRecord {
  final String id;
  final String workerId;
  final String jobId;
  final String bookingId;
  final String skillId;          // The skill under which work was performed
  final String workStatus;       // completed|abandoned|disputed

  // ── Hirer confirmation ─────────────────────────────────────────
  final bool hirerConfirmation;

  // ── Skill-specific ratings (1.0–5.0) ──────────────────────────
  // These are separate dimensions — not collapsed into one number.
  final double? qualityScore;
  final double? punctualityScore;
  final double? safetyScore;
  final double? taskCompletionScore;
  final double? communicationScore;
  final double? professionalBehaviorScore;

  // ── Hirer review ──────────────────────────────────────────────
  final bool? wouldHireAgain;
  final String reviewComments;

  // ── Status ────────────────────────────────────────────────────
  final String reviewStatus;    // pending|verified|disputed

  final DateTime createdAt;

  const VerifiedWorkRecord({
    required this.id,
    required this.workerId,
    required this.jobId,
    required this.bookingId,
    required this.skillId,
    required this.workStatus,
    required this.hirerConfirmation,
    this.qualityScore,
    this.punctualityScore,
    this.safetyScore,
    this.taskCompletionScore,
    this.communicationScore,
    this.professionalBehaviorScore,
    this.wouldHireAgain,
    this.reviewComments = '',
    this.reviewStatus = 'pending',
    required this.createdAt,
  });

  double get overallScore {
    final scores = [
      qualityScore, punctualityScore, safetyScore,
      taskCompletionScore, communicationScore,
    ].whereType<double>().toList();
    if (scores.isEmpty) return 0;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  factory VerifiedWorkRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return VerifiedWorkRecord(
      id:                       doc.id,
      workerId:                 d['workerId'] ?? '',
      jobId:                    d['jobId'] ?? '',
      bookingId:                d['bookingId'] ?? '',
      skillId:                  d['skillId'] ?? '',
      workStatus:               d['workStatus'] ?? 'completed',
      hirerConfirmation:        d['hirerConfirmation'] == true,
      qualityScore:             (d['qualityScore'] as num?)?.toDouble(),
      punctualityScore:         (d['punctualityScore'] as num?)?.toDouble(),
      safetyScore:              (d['safetyScore'] as num?)?.toDouble(),
      taskCompletionScore:      (d['taskCompletionScore'] as num?)?.toDouble(),
      communicationScore:       (d['communicationScore'] as num?)?.toDouble(),
      professionalBehaviorScore:(d['professionalBehaviorScore'] as num?)?.toDouble(),
      wouldHireAgain:           d['wouldHireAgain'] as bool?,
      reviewComments:           d['reviewComments'] ?? '',
      reviewStatus:             d['reviewStatus'] ?? 'pending',
      createdAt:                DateParser.parseOrDefault(d['createdAt']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':         workerId,
    'jobId':            jobId,
    'bookingId':        bookingId,
    'skillId':          skillId,
    'workStatus':       workStatus,
    'hirerConfirmation':hirerConfirmation,
    'reviewStatus':     'pending',
    'createdAt':        FieldValue.serverTimestamp(),
  };
}

// ── Hirer Work Review (what hirer submits after job completion) ────
class WorkReviewSubmission {
  final String bookingId;
  final String workerId;
  final String skillId;
  final double qualityScore;
  final double punctualityScore;
  final double safetyScore;
  final double taskCompletionScore;
  final double communicationScore;
  final bool wouldHireAgain;
  final String comments;

  const WorkReviewSubmission({
    required this.bookingId,
    required this.workerId,
    required this.skillId,
    required this.qualityScore,
    required this.punctualityScore,
    required this.safetyScore,
    required this.taskCompletionScore,
    required this.communicationScore,
    required this.wouldHireAgain,
    this.comments = '',
  });

  Map<String, dynamic> toMap() => {
    'qualityScore':         qualityScore,
    'punctualityScore':     punctualityScore,
    'safetyScore':          safetyScore,
    'taskCompletionScore':  taskCompletionScore,
    'communicationScore':   communicationScore,
    'wouldHireAgain':       wouldHireAgain,
    'reviewComments':       comments,
    'reviewStatus':         'verified',
  };
}
