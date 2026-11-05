// lib/services/skill_verification_engine.dart
// ================================================================
// KELASAGARA — Skill Verification Engine
// Determines whether a worker's skill can be marked VERIFIED
// based on accepted evidence routes.
//
// ROUTE A: Identity verified + recognized credential issuer-confirmed
// ROUTE B: Identity verified + authorized assessor approved assessment
//
// RULES (non-negotiable):
// - e-Shram verified alone does NOT produce skill verified
// - Completed jobs alone do NOT produce skill verified
// - Document submitted alone does NOT produce skill verified
// - AI analysis alone does NOT produce skill verified
// - Only Route A or Route B creates SKILL_VERIFIED
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/credential_record.dart';
import '../models/skill_badge.dart';
import '../models/verification_audit_log.dart';

class SkillVerificationResult {
  final bool      canVerify;
  final String?   route;           // 'credential' | 'assessment' | null
  final String?   evidenceId;      // credentialId or assessmentId
  final String?   reason;          // why canVerify is false

  const SkillVerificationResult({
    required this.canVerify,
    this.route,
    this.evidenceId,
    this.reason,
  });
}

class SkillVerificationEngine {
  SkillVerificationEngine._();
  static final SkillVerificationEngine instance = SkillVerificationEngine._();

  final _db = FirebaseFirestore.instance;

  // ── Evaluate whether a worker's skill can be set to VERIFIED ─────────────
  // Called by admin after reviewing credential or approving assessment.
  // Returns SkillVerificationResult with route and evidence reference.
  Future<SkillVerificationResult> evaluate({
    required String workerId,
    required String skillId,
  }) async {
    // Check identity verified (face verification done + account approved)
    final userSnap = await _db.collection('users').doc(workerId).get();
    if (!userSnap.exists) {
      return const SkillVerificationResult(
        canVerify: false, reason: 'USER_NOT_FOUND');
    }
    final userData = userSnap.data()!;
    if (userData['accountStatus'] != 'approved') {
      return const SkillVerificationResult(
        canVerify: false, reason: 'IDENTITY_NOT_VERIFIED: account not approved');
    }
    if (userData['faceVerified'] != true) {
      return const SkillVerificationResult(
        canVerify: false, reason: 'IDENTITY_NOT_VERIFIED: face not verified');
    }

    // ROUTE A: Check for issuer-confirmed or credential-verified credential
    final credSnap = await _db.collection('professionalCredentials')
        .where('workerId', isEqualTo: workerId)
        .where('skillId',  isEqualTo: skillId)
        .where('status', whereIn: [
          CredentialStatus.issuerConfirmed.firestoreValue,
          CredentialStatus.credentialVerified.firestoreValue,
        ])
        .limit(1)
        .get();

    if (credSnap.docs.isNotEmpty) {
      final cred = CredentialRecord.fromFirestore(credSnap.docs.first);
      debugPrint('[SkillVerify] Route A eligible: credential \${cred.credentialId}');
      return SkillVerificationResult(
        canVerify:  true,
        route:      'credential',
        evidenceId: cred.credentialId,
      );
    }

    // ROUTE B: Check for passed assessment with authorized assessor decision
    final assSnap = await _db.collection('skillAssessments')
        .where('workerId', isEqualTo: workerId)
        .where('skillId',  isEqualTo: skillId)
        .where('decision', isEqualTo: 'PASS')
        .where('assessorDecisionAt', isNull: false)
        .limit(1)
        .get();

    if (assSnap.docs.isNotEmpty) {
      final assId = assSnap.docs.first.id;
      final assData = assSnap.docs.first.data();
      final assessorId = assData['assessorId'] as String? ?? '';
      debugPrint('[SkillVerify] Route B eligible: assessment \$assId assessor \$assessorId');
      return SkillVerificationResult(
        canVerify:  true,
        route:      'assessment',
        evidenceId: assId,
      );
    }

    return const SkillVerificationResult(
      canVerify: false,
      reason:    'NO_ACCEPTED_EVIDENCE: no issuer-confirmed credential or passed assessment found',
    );
  }

  // ── Mark skill as verified (called after admin evaluates and confirms) ────
  // Creates SkillBadge, updates workerSkills entry, writes audit log.
  Future<void> markSkillVerified({
    required String workerId,
    required String skillId,
    required SkillVerificationResult result,
    required String adminId,
    String? standardVersion,
    String? assessmentVersion,
  }) async {
    if (!result.canVerify) {
      throw StateError('Cannot mark skill verified: \${result.reason}');
    }

    final batch = _db.batch();
    final now   = DateTime.now();

    // Determine badge type
    final badgeType = result.route == 'credential'
        ? BadgeType.skillVerifiedCredential
        : BadgeType.skillVerifiedAssessment;

    // Create badge
    final badgeRef = _db.collection('skillBadges').doc();
    final badge = SkillBadge(
      badgeId:                  badgeRef.id,
      workerId:                 workerId,
      skillId:                  skillId,
      type:                     badgeType,
      status:                   BadgeStatus.active,
      credentialVerificationId: result.route == 'credential' ? result.evidenceId : null,
      assessmentId:             result.route == 'assessment' ? result.evidenceId : null,
      assessorId:               null, // read from assessment if needed
      verificationBasis:        result.route,
      standardVersion:          standardVersion,
      assessmentVersion:        assessmentVersion,
      earnedAt:                 now,
      revocable:                true,
    );
    batch.set(badgeRef, {
      'workerId':                 badge.workerId,
      'skillId':                  badge.skillId,
      'type':                     badge.type.firestoreValue,
      'status':                   badge.status.firestoreValue,
      if (badge.credentialVerificationId != null) 'credentialVerificationId': badge.credentialVerificationId,
      if (badge.assessmentId != null) 'assessmentId': badge.assessmentId,
      'verificationBasis':        badge.verificationBasis,
      if (standardVersion != null) 'standardVersion': standardVersion,
      if (assessmentVersion != null) 'assessmentVersion': assessmentVersion,
      'earnedAt':                 FieldValue.serverTimestamp(),
      'revocable':                true,
    });

    // Update workerSkills
    final skillRef = _db.collection('workerSkills').doc('\${workerId}_\$skillId');
    batch.set(skillRef, {
      'workerId':     workerId,
      'skillId':      skillId,
      'skillVerified':true,
      'verifiedAt':   FieldValue.serverTimestamp(),
      'verifiedBy':   adminId,
      'badgeId':      badgeRef.id,
      'route':        result.route,
      if (standardVersion != null) 'standardVersion': standardVersion,
    }, SetOptions(merge: true));

    // Audit log
    final logRef = _db.collection('verificationAuditLogs').doc();
    final log = VerificationAuditLog(
      logId:            logRef.id,
      workerId:         workerId,
      actorId:          adminId,
      actorRole:        'admin',
      action:           AuditAction.skillVerified,
      targetCollection: 'workerSkills',
      targetDocId:      '\${workerId}_\$skillId',
      previousStatus:   'under_review',
      newStatus:        'skill_verified',
      evidenceStrength: result.route == 'credential' ? 'issuer_confirmed' : 'authorized_assessment',
      standardVersion:  standardVersion,
      assessmentVersion:assessmentVersion,
      timestamp:        now,
    );
    batch.set(logRef, log.toFirestoreCreate());

    await batch.commit();
    debugPrint('[SkillVerify] Skill \$skillId verified for worker \$workerId via \${result.route}');
  }

  // ── Check experience badges ───────────────────────────────────────────────
  // Experience badges are separate from competency badges.
  // They track verified work count but do NOT replace skill verification.
  Future<void> checkAndIssueExperienceBadge({
    required String workerId,
    required String skillId,
    required int    verifiedJobCount,
  }) async {
    const thresholds = [1, 5, 10, 25, 50];
    for (final threshold in thresholds) {
      if (verifiedJobCount < threshold) break;

      // Check if badge already exists
      final existing = await _db.collection('skillBadges')
          .where('workerId', isEqualTo: workerId)
          .where('skillId',  isEqualTo: skillId)
          .where('type',     isEqualTo: BadgeType.experienceJobs.firestoreValue)
          .where('jobCountThreshold', isEqualTo: threshold)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        await _db.collection('skillBadges').doc().set({
          'workerId':          workerId,
          'skillId':           skillId,
          'type':              BadgeType.experienceJobs.firestoreValue,
          'status':            BadgeStatus.active.firestoreValue,
          'jobCount':          verifiedJobCount,
          'jobCountThreshold': threshold,
          'verificationBasis': 'verified_work',
          'earnedAt':          FieldValue.serverTimestamp(),
          'revocable':         false,
        });
        debugPrint('[SkillVerify] Experience badge issued: \$threshold jobs for \$workerId/\$skillId');
      }
    }
  }
}
