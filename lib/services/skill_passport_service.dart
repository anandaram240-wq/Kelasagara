// ================================================================
// KELASAGARA — Skill Passport Service
// Reads/creates workerSkills/ documents.
// All writes are constrained by Firestore Security Rules.
// Only admin can update authoritative fields.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/skill_passport.dart';
import '../core/constants/job_categories.dart';

class SkillPassportService {
  SkillPassportService._();
  static final SkillPassportService instance = SkillPassportService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Skill Passport doc ID convention ─────────────────────────
  static String docId(String uid, String skillId) => '${uid}_$skillId';

  // ── Stream all skills for a worker ────────────────────────────
  Stream<List<WorkerSkill>> streamWorkerSkills(String workerId) {
    return _db
      .collection('workerSkills')
      .where('workerId', isEqualTo: workerId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((doc) => WorkerSkill.fromFirestore(doc))
            .toList();
        list.sort((a, b) => b.skillLevel.compareTo(a.skillLevel));
        return list;
      });
  }

  // ── Get a single worker skill ──────────────────────────────────
  Future<WorkerSkill?> getWorkerSkill(String workerId, String skillId) async {
    final doc = await _db
      .collection('workerSkills')
      .doc(docId(workerId, skillId))
      .get();
    if (!doc.exists) return null;
    return WorkerSkill.fromFirestore(doc);
  }

  // ── Claim a new skill (status=claimed, level=0) ────────────────
  // Security Rules enforce: worker can only create at status=claimed, level=0.
  Future<WorkerSkill?> claimSkill({
    required String workerId,
    required String skillId,
  }) async {
    final category = kGetCategory(skillId);
    if (category == null) throw ArgumentError('Unknown skillId: $skillId');

    final ref = _db.collection('workerSkills').doc(docId(workerId, skillId));

    // Check if already claimed
    final existing = await ref.get();
    if (existing.exists) return WorkerSkill.fromFirestore(existing);

    final data = {
      'workerId':          workerId,
      'skillId':           skillId,
      'canonicalName':     category.label,
      'localizedName':     category.labelKn,
      'emoji':             category.emoji,
      'color':             category.color,
      'status':            'claimed',
      'skillLevel':        0,
      'riskLevel':         category.riskLevel,
      'assessmentVersion': category.assessmentVersion,
      'evidenceCount':     0,
      'credentialStatus':  'none',
      'reassessmentRequired': false,
      'suspensionStatus':  'active',
      'createdAt':         FieldValue.serverTimestamp(),
      'updatedAt':         FieldValue.serverTimestamp(),
    };

    await ref.set(data, SetOptions(merge: true));
    final created = await ref.get();
    return WorkerSkill.fromFirestore(created);
  }

  // ── Migrate existing users.skills list to workerSkills/ ───────
  // Called once from admin migration screen.
  // Sets all existing skills to status=claimed, level=0.
  // Does NOT set any verification status.
  Future<void> migrateUserSkills({
    required String workerId,
    required List<String> skills,
  }) async {
    final batch = _db.batch();
    for (final skillId in skills) {
      final category = kGetCategory(skillId);
      if (category == null) continue;

      final ref = _db.collection('workerSkills').doc(docId(workerId, skillId));
      batch.set(ref, {
        'workerId':          workerId,
        'skillId':           skillId,
        'canonicalName':     category.label,
        'localizedName':     category.labelKn,
        'emoji':             category.emoji,
        'color':             category.color,
        'status':            'claimed',    // Migration NEVER sets verified
        'skillLevel':        0,            // Migration NEVER sets level > 0
        'riskLevel':         category.riskLevel,
        'assessmentVersion': category.assessmentVersion,
        'evidenceCount':     0,
        'credentialStatus':  'none',
        'reassessmentRequired': false,
        'suspensionStatus':  'active',
        'createdAt':         FieldValue.serverTimestamp(),
        'updatedAt':         FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // merge: won't overwrite existing assessments
    }
    await batch.commit();
  }

  // ── Get occupation standard ────────────────────────────────────
  Future<OccupationStandard?> getOccupationStandard(String skillId) async {
    final doc = await _db.collection('occupationStandards').doc(skillId).get();
    if (!doc.exists) return null;
    return OccupationStandard.fromFirestore(doc);
  }

  // ── Update reputation (after verified work records aggregate) ──
  // Called after new verifiedWorkRecord is created for this worker+skill.
  Future<void> refreshSkillReputation({
    required String workerId,
    required String skillId,
  }) async {
    final records = await _db
      .collection('verifiedWorkRecords')
      .where('workerId', isEqualTo: workerId)
      .where('skillId', isEqualTo: skillId)
      .where('reviewStatus', isEqualTo: 'verified')
      .get();

    if (records.docs.isEmpty) return;

    double qualitySum = 0, punctualitySum = 0, safetySum = 0,
           completionSum = 0, commSum = 0;
    int reviewCount = 0;
    int wouldHireCount = 0;

    for (final doc in records.docs) {
      final d = doc.data();
      final q = (d['qualityScore'] as num?)?.toDouble();
      if (q != null) {
        qualitySum     += q;
        punctualitySum += (d['punctualityScore'] as num?)?.toDouble() ?? q;
        safetySum      += (d['safetyScore']       as num?)?.toDouble() ?? q;
        completionSum  += (d['taskCompletionScore'] as num?)?.toDouble() ?? q;
        commSum        += (d['communicationScore'] as num?)?.toDouble() ?? q;
        reviewCount++;
        if (d['wouldHireAgain'] == true) wouldHireCount++;
      }
    }

    if (reviewCount == 0) return;

    await _db.collection('workerSkills').doc(docId(workerId, skillId)).update({
      'reputation': {
        'qualityAvg':             qualitySum / reviewCount,
        'punctualityAvg':         punctualitySum / reviewCount,
        'safetyAvg':              safetySum / reviewCount,
        'completionAvg':          completionSum / reviewCount,
        'communicationAvg':       commSum / reviewCount,
        'verifiedJobCount':       records.docs.length,
        'reviewCount':            reviewCount,
        'wouldHireAgainMajority': wouldHireCount > reviewCount / 2,
        'recentTrend':            0.0, // computed separately
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Auto-promote level 2 → level 3 (Experienced) at 10 jobs
    // Auto-promote level 3 → level 4 (Advanced) at 25 jobs
    final currentDoc = await _db.collection('workerSkills')
      .doc(docId(workerId, skillId)).get();
    final currentLevel = (currentDoc.data()?['skillLevel'] ?? 0) as int;
    final currentStatus = currentDoc.data()?['status'] ?? '';

    if (currentStatus == 'practical_verified') {
      if (records.docs.length >= 25 && currentLevel < 4) {
        await _db.collection('workerSkills').doc(docId(workerId, skillId)).update({
          'skillLevel': 4,
          'status': 'advanced',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (records.docs.length >= 10 && currentLevel < 3) {
        await _db.collection('workerSkills').doc(docId(workerId, skillId)).update({
          'skillLevel': 3,
          'status': 'experienced',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}
