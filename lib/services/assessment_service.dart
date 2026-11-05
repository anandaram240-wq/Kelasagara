// ================================================================
// KELASAGARA — Assessment Service
// Creates assessments, records knowledge scores, submits assessments.
// CRITICAL: Score fields are written by this service but
// Security Rules prevent workers from writing them directly.
// Decision (pass/fail) is ONLY set by admin via admin screen.
// Safety gate is enforced before any decision is accepted.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/skill_assessment.dart';
import '../core/constants/job_categories.dart';

// ── Assessment Answer (stored locally during test, submitted together) ─
class AssessmentAnswer {
  final String questionId;
  final String selectedOptionId;
  final bool isCorrect;
  final bool safetyRelated;

  const AssessmentAnswer({
    required this.questionId,
    required this.selectedOptionId,
    required this.isCorrect,
    required this.safetyRelated,
  });
}

// ── Assessment Service ─────────────────────────────────────────────
class AssessmentService {
  AssessmentService._();
  static final AssessmentService instance = AssessmentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Create new assessment (status=draft) ──────────────────────
  Future<SkillAssessment?> createAssessment({
    required String skillId,
  }) async {
    final category = kGetCategory(skillId);
    if (category == null) throw ArgumentError('Unknown skillId: $skillId');

    // Check for existing active assessment for this skill
    final existing = await _db.collection('skillAssessments')
      .where('workerId', isEqualTo: _uid)
      .where('skillId', isEqualTo: skillId)
      .where('status', whereIn: ['draft','in_progress','evidence_collection'])
      .limit(1)
      .get();

    if (existing.docs.isNotEmpty) {
      return SkillAssessment.fromFirestore(existing.docs.first);
    }

    // Count previous attempts
    final prevAttempts = await _db.collection('skillAssessments')
      .where('workerId', isEqualTo: _uid)
      .where('skillId', isEqualTo: skillId)
      .count()
      .get();
    final attemptNumber = (prevAttempts.count ?? 0) + 1;

    final ref = _db.collection('skillAssessments').doc();
    await ref.set({
      'workerId':           _uid,
      'skillId':            skillId,
      'assessmentVersion':  category.assessmentVersion,
      'standardVersion':    '1.0',
      'attemptNumber':      attemptNumber,
      'status':             'draft',
      'evidenceIds':        [],
      'rubricScores':       {},
      'failureReasons':     [],
      'humanReviewRequired':false,
      'humanReviewStatus':  'not_required',
      'createdAt':          FieldValue.serverTimestamp(),
      'expiresAt':          Timestamp.fromDate(
                              DateTime.now().add(const Duration(days: 7))),
    });

    // Update workerSkill status to assessment_in_progress
    await _db.collection('workerSkills')
      .doc('${_uid}_$skillId')
      .update({
        'status':    'assessment_in_progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });

    final created = await ref.get();
    return SkillAssessment.fromFirestore(created);
  }

  // ── Start assessment session ───────────────────────────────────
  Future<void> startAssessment(String assessmentId) async {
    await _db.collection('skillAssessments').doc(assessmentId).update({
      'status':    'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Load questions for a skill ─────────────────────────────────
  // Randomizes order. Returns a subset for the timed test.
  Future<List<AssessmentQuestion>> loadQuestions({
    required String skillId,
    int count = 15,
  }) async {
    final snap = await _db
      .collection('assessmentQuestions')
      .doc(skillId)
      .collection('questions')
      .get();

    final all = snap.docs
      .map((d) => AssessmentQuestion.fromFirestore(d))
      .toList();

    // Shuffle for anti-cheating — different order each attempt
    all.shuffle();

    // Always include at least 2 safety questions
    final safety = all.where((q) => q.safetyRelated).take(3).toList();
    final other  = all.where((q) => !q.safetyRelated).take(count - safety.length).toList();

    final selected = [...safety, ...other];
    selected.shuffle();
    return selected.take(count).toList();
  }

  // ── Submit knowledge assessment answers ───────────────────────
  // Calculates scores locally, writes to assessment.
  // NOTE: Admin can override these scores during review.
  // The worker cannot change these scores after submission.
  Future<void> submitKnowledgeAnswers({
    required String assessmentId,
    required String skillId,
    required List<AssessmentAnswer> answers,
    required Duration timeTaken,
  }) async {
    final total = answers.length;
    if (total == 0) return;

    final correct = answers.where((a) => a.isCorrect).length;
    final safetyTotal = answers.where((a) => a.safetyRelated).length;
    final safetyCorrect = answers.where((a) => a.safetyRelated && a.isCorrect).length;

    final knowledgeScore = (correct / total * 100).roundToDouble();
    final safetyScore    = safetyTotal > 0
      ? (safetyCorrect / safetyTotal * 5).roundToDouble() // out of 5
      : null;

    await _db.collection('skillAssessments').doc(assessmentId).update({
      'status':          'evidence_collection',
      'knowledgeScore':  knowledgeScore,
      if (safetyScore != null) 'safetyScore': safetyScore,
      'knowledgeTimeSec': timeTaken.inSeconds,
      'updatedAt':       FieldValue.serverTimestamp(),
    });
  }

  // ── Submit full assessment for review ─────────────────────────
  // Called when all evidence is uploaded.
  // Sets status=submitted — admin is notified.
  Future<void> submitForReview(String assessmentId) async {
    // Verify assessment belongs to current user before submitting
    final doc = await _db.collection('skillAssessments').doc(assessmentId).get();
    if (!doc.exists) throw StateError('Assessment not found');
    if (doc.data()?['workerId'] != _uid) throw StateError('Not your assessment');

    final evidenceIds = List<String>.from(doc.data()?['evidenceIds'] ?? []);
    if (evidenceIds.isEmpty) {
      throw StateError('Cannot submit without practical evidence. '
          'Please record and upload at least one task video.');
    }

    await _db.collection('skillAssessments').doc(assessmentId).update({
      'status':      'submitted',
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt':   FieldValue.serverTimestamp(),
    });

    // Update worker skill status
    final skillId = doc.data()?['skillId'] ?? '';
    if (skillId.isNotEmpty) {
      await _db.collection('workerSkills').doc('${_uid}_$skillId').update({
        'status':    'under_review',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Stream assessments for current worker ─────────────────────
  Stream<List<SkillAssessment>> streamMyAssessments() {
    return _db.collection('skillAssessments')
      .where('workerId', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(SkillAssessment.fromFirestore).toList());
  }

  // ── Stream assessments pending review (ADMIN only) ────────────
  Stream<List<SkillAssessment>> streamPendingReviews() {
    return _db.collection('skillAssessments')
      .where('status', whereIn: ['submitted', 'under_review'])
      .orderBy('submittedAt')
      .snapshots()
      .map((s) => s.docs.map(SkillAssessment.fromFirestore).toList());
  }

  // ── Admin: Submit assessment decision ─────────────────────────
  // SAFETY GATE enforced here — cannot approve if safety < threshold.
  // This is the ONLY path to set decision + skill level.
  Future<void> submitAssessorDecision({
    required String assessmentId,
    required String decision,          // pass|fail|borderline|refer
    required Map<String, int> rubricScores,
    required List<String> failureReasons,
    String? assessorNotes,
  }) async {
    final doc = await _db.collection('skillAssessments').doc(assessmentId).get();
    if (!doc.exists) throw StateError('Assessment not found');

    final data = doc.data()!;
    final skillId  = data['skillId'] as String? ?? '';
    final workerId = data['workerId'] as String? ?? '';

    // ── Safety gate check ──────────────────────────────────────
    final category = kGetCategory(skillId);
    final safetyThreshold = category?.safetyThreshold ?? 4;
    final safetyScore = rubricScores['safety'] ?? 0;
    final safetyGatePassed = safetyScore >= safetyThreshold;

    // If safety gate fails, override decision to fail
    final finalDecision = (!safetyGatePassed && decision == 'pass')
      ? 'fail' : decision;
    final finalFailureReasons = (!safetyGatePassed && decision == 'pass')
      ? [...failureReasons, 'Safety gate not met (score $safetyScore/$safetyThreshold required)']
      : failureReasons;

    // Calculate practical score from rubric
    final rubricValues = rubricScores.values.toList();
    final practicalScore = rubricValues.isEmpty ? 0.0
      : rubricValues.reduce((a, b) => a + b) / rubricValues.length / 5 * 100;

    // Write assessment decision
    await _db.collection('skillAssessments').doc(assessmentId).update({
      'status':           finalDecision == 'pass' ? 'approved' : 'rejected',
      'decision':         finalDecision,
      'rubricScores':     rubricScores,
      'practicalScore':   practicalScore,
      'safetyScore':      safetyScore.toDouble(),
      'safetyGatePassed': safetyGatePassed,
      'failureReasons':   finalFailureReasons,
      'assessorId':       _uid,
      if (assessorNotes != null) 'assessorNotes': assessorNotes,
      'humanReviewStatus':'reviewed',
      'reviewedAt':       FieldValue.serverTimestamp(),
      'updatedAt':        FieldValue.serverTimestamp(),
    });

    // Write to workerSkill — only if passed
    if (finalDecision == 'pass') {
      final knowledgeScore = (data['knowledgeScore'] as num?)?.toDouble() ?? 0;
      final overallScore = (knowledgeScore + practicalScore) / 2;

      await _db.collection('workerSkills').doc('${workerId}_$skillId').update({
        'status':           'practical_verified',
        'skillLevel':       2,
        'knowledgeScore':   knowledgeScore,
        'practicalScore':   practicalScore,
        'safetyScore':      safetyScore.toDouble(),
        'overallScore':     overallScore,
        'safetyGatePassed': safetyGatePassed,
        'assessorId':       _uid,
        'assessedAt':       FieldValue.serverTimestamp(),
        'validUntil':       Timestamp.fromDate(
                              DateTime.now().add(const Duration(days: 365 * 2))),
        'updatedAt':        FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('workerSkills').doc('${workerId}_$skillId').update({
        'status':    'claimed', // Back to claimed — can attempt again
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Write audit log
    await _db.collection('auditLogs').add({
      'eventType':    'assessment_decision',
      'actorId':      _uid,
      'actorRole':    'admin',
      'workerId':     workerId,
      'assessmentId': assessmentId,
      'skillId':      skillId,
      'result':       finalDecision,
      'safetyGate':   safetyGatePassed,
      'reason':       finalFailureReasons.join('; '),
      'systemVersion': data['assessmentVersion'] ?? '',
      'timestamp':    FieldValue.serverTimestamp(),
    });
  }
}
