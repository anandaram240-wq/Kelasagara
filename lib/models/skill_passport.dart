// ================================================================
// KELASAGARA — Skill Passport Models
// WorkerSkill · SkillStatus · OccupationStandard · SkillReputation
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'date_parser.dart';

// ── Skill Status Enum ─────────────────────────────────────────────
// Represents the full lifecycle of a worker's skill claim.
// IMPORTANT: These are Kelasagara marketplace labels only.
// They do NOT represent government qualification levels.
enum SkillStatus {
  claimed,               // Just selected — no assessment done
  assessmentRequired,    // Admin/system triggered reassessment
  assessmentInProgress,  // Worker has started assessment
  underReview,           // Submitted — waiting for admin review
  basicAssessed,         // Knowledge assessment passed (Level 1)
  practicalVerified,     // Practical assessment approved (Level 2)
  experienced,           // practical_verified + 10+ verified jobs (Level 3)
  advanced,              // practical_verified + 25+ verified jobs (Level 4)
  reassessmentRequired,  // Triggered by quality failure / expiry
  suspended,             // Skill suspended — separate from account
  rejected,              // Failed assessment, cannot reattempt without review
}

extension SkillStatusX on SkillStatus {
  String get firestoreValue => switch (this) {
    SkillStatus.claimed               => 'claimed',
    SkillStatus.assessmentRequired    => 'assessment_required',
    SkillStatus.assessmentInProgress  => 'assessment_in_progress',
    SkillStatus.underReview           => 'under_review',
    SkillStatus.basicAssessed         => 'basic_assessed',
    SkillStatus.practicalVerified     => 'practical_verified',
    SkillStatus.experienced           => 'experienced',
    SkillStatus.advanced              => 'advanced',
    SkillStatus.reassessmentRequired  => 'reassessment_required',
    SkillStatus.suspended             => 'suspended',
    SkillStatus.rejected              => 'rejected',
  };

  static SkillStatus fromString(String? s) => switch (s) {
    'claimed'               => SkillStatus.claimed,
    'assessment_required'   => SkillStatus.assessmentRequired,
    'assessment_in_progress'=> SkillStatus.assessmentInProgress,
    'under_review'          => SkillStatus.underReview,
    'basic_assessed'        => SkillStatus.basicAssessed,
    'practical_verified'    => SkillStatus.practicalVerified,
    'experienced'           => SkillStatus.experienced,
    'advanced'              => SkillStatus.advanced,
    'reassessment_required' => SkillStatus.reassessmentRequired,
    'suspended'             => SkillStatus.suspended,
    'rejected'              => SkillStatus.rejected,
    _                       => SkillStatus.claimed,
  };

  // ── Display label (Kelasagara marketplace language) ────────────
  String get displayLabel => switch (this) {
    SkillStatus.claimed               => 'Skill Claimed — Not Assessed',
    SkillStatus.assessmentRequired    => 'Assessment Required',
    SkillStatus.assessmentInProgress  => 'Assessment In Progress',
    SkillStatus.underReview           => 'Under Review',
    SkillStatus.basicAssessed         => 'Basic Knowledge Assessed',
    SkillStatus.practicalVerified     => 'Kelasagara Practical Skill Verified',
    SkillStatus.experienced           => 'Experienced — Kelasagara Verified',
    SkillStatus.advanced              => 'Advanced — Kelasagara Verified',
    SkillStatus.reassessmentRequired  => 'Reassessment Required',
    SkillStatus.suspended             => 'Skill Suspended',
    SkillStatus.rejected              => 'Not Assessed',
  };

  String get displayLabelKn => switch (this) {
    SkillStatus.claimed               => 'ಕೌಶಲ ಹೇಳಿದ್ದಾರೆ — ಮೌಲ್ಯಮಾಪನ ಆಗಿಲ್ಲ',
    SkillStatus.practicalVerified     => 'ಕೆಲಸಗಾರ ಪ್ರಾಯೋಗಿಕ ಕೌಶಲ ಪರಿಶೀಲಿಸಿದ',
    SkillStatus.underReview           => 'ಪರಿಶೀಲನೆಯಲ್ಲಿದೆ',
    SkillStatus.suspended             => 'ಕೌಶಲ ಅಮಾನತ್ತು',
    _                                 => displayLabel,
  };

  // ── Visual properties ──────────────────────────────────────────
  Color get color => switch (this) {
    SkillStatus.practicalVerified ||
    SkillStatus.experienced       ||
    SkillStatus.advanced          => const Color(0xFF22C55E),   // green
    SkillStatus.basicAssessed     => const Color(0xFF3B82F6),   // blue
    SkillStatus.underReview       ||
    SkillStatus.assessmentInProgress => const Color(0xFFF59E0B), // amber
    SkillStatus.suspended         ||
    SkillStatus.rejected          => const Color(0xFFEF4444),   // red
    SkillStatus.reassessmentRequired => const Color(0xFFF97316), // orange
    _                             => const Color(0xFF94A3B8),   // grey (claimed)
  };

  bool get isVerified => this == SkillStatus.practicalVerified ||
                         this == SkillStatus.experienced ||
                         this == SkillStatus.advanced;

  bool get canApplyForJobs => isVerified && this != SkillStatus.suspended;

  bool get needsAction => this == SkillStatus.claimed ||
                          this == SkillStatus.assessmentRequired ||
                          this == SkillStatus.reassessmentRequired;
}

// ── Skill Reputation (aggregated from verifiedWorkRecords) ────────
class SkillReputation {
  final double qualityAvg;
  final double punctualityAvg;
  final double safetyAvg;
  final double completionAvg;
  final double communicationAvg;
  final int verifiedJobCount;
  final int reviewCount;
  final bool wouldHireAgainMajority;
  final double recentTrend; // last 5 jobs avg vs overall — positive/negative

  const SkillReputation({
    this.qualityAvg = 0,
    this.punctualityAvg = 0,
    this.safetyAvg = 0,
    this.completionAvg = 0,
    this.communicationAvg = 0,
    this.verifiedJobCount = 0,
    this.reviewCount = 0,
    this.wouldHireAgainMajority = false,
    this.recentTrend = 0,
  });

  double get overallAvg => reviewCount == 0
    ? 0
    : (qualityAvg + punctualityAvg + safetyAvg + completionAvg + communicationAvg) / 5;

  String get evidenceStrength => switch (verifiedJobCount) {
    0     => 'No verified jobs yet',
    1     => '1 verified job',
    <= 4  => '$verifiedJobCount verified jobs',
    <= 9  => '$verifiedJobCount verified jobs',
    <= 19 => '$verifiedJobCount verified jobs · Experienced',
    _     => '$verifiedJobCount verified jobs · Advanced',
  };

  factory SkillReputation.fromMap(Map<String, dynamic> m) => SkillReputation(
    qualityAvg:           (m['qualityAvg']       ?? 0).toDouble(),
    punctualityAvg:       (m['punctualityAvg']   ?? 0).toDouble(),
    safetyAvg:            (m['safetyAvg']         ?? 0).toDouble(),
    completionAvg:        (m['completionAvg']     ?? 0).toDouble(),
    communicationAvg:     (m['communicationAvg']  ?? 0).toDouble(),
    verifiedJobCount:     (m['verifiedJobCount']  ?? 0).toInt(),
    reviewCount:          (m['reviewCount']        ?? 0).toInt(),
    wouldHireAgainMajority: m['wouldHireAgainMajority'] == true,
    recentTrend:          (m['recentTrend']        ?? 0).toDouble(),
  );
}

// ── Worker Skill (Skill Passport entry) ───────────────────────────
// One per worker per skill. Doc ID: {uid}_{skillId}
class WorkerSkill {
  final String id;              // Firestore doc ID: uid_skillId
  final String workerId;
  final String skillId;         // matches JobCategory.id
  final String canonicalName;   // from JobCategory.label
  final String localizedName;   // from JobCategory.labelKn
  final String emoji;
  final String color;
  final SkillStatus status;
  final int skillLevel;         // 0–4
  final String riskLevel;       // low|medium|high|critical
  final String assessmentVersion;

  // ── Assessment scores (only set after admin decision) ──────────
  final double? knowledgeScore;
  final double? judgmentScore;
  final double? practicalScore;
  final double? safetyScore;
  final double? overallScore;
  final bool? safetyGatePassed;

  // ── Evidence and verification ──────────────────────────────────
  final int evidenceCount;
  final String credentialStatus; // none|submitted|verified|rejected
  final String? assessorId;
  final DateTime? assessedAt;
  final DateTime? validUntil;

  // ── Status flags ───────────────────────────────────────────────
  final bool reassessmentRequired;
  final String suspensionStatus;  // active|suspended
  final String? suspensionReason;

  // ── Reputation (aggregated, may be null until first job) ───────
  final SkillReputation? reputation;

  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkerSkill({
    required this.id,
    required this.workerId,
    required this.skillId,
    required this.canonicalName,
    required this.localizedName,
    required this.emoji,
    required this.color,
    required this.status,
    required this.skillLevel,
    required this.riskLevel,
    required this.assessmentVersion,
    this.knowledgeScore,
    this.judgmentScore,
    this.practicalScore,
    this.safetyScore,
    this.overallScore,
    this.safetyGatePassed,
    this.evidenceCount = 0,
    this.credentialStatus = 'none',
    this.assessorId,
    this.assessedAt,
    this.validUntil,
    this.reassessmentRequired = false,
    this.suspensionStatus = 'active',
    this.suspensionReason,
    this.reputation,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── UI Helpers ─────────────────────────────────────────────────
  bool get isActive => suspensionStatus == 'active';
  bool get isEligibleForJobs => status.canApplyForJobs && isActive;
  bool get isVerified => status.isVerified;
  String get skillName => canonicalName;
  int get jobsCompleted => reputation?.verifiedJobCount ?? 0;

  String get skillLevelLabel => switch (skillLevel) {
    0 => 'Level 0 · Claimed',
    1 => 'Level 1 · Basic Assessed',
    2 => 'Level 2 · Practical Verified',
    3 => 'Level 3 · Experienced',
    4 => 'Level 4 · Advanced',
    _ => 'Level $skillLevel',
  };

  // ── Firestore serialization ────────────────────────────────────
  factory WorkerSkill.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WorkerSkill(
      id:                 doc.id,
      workerId:           d['workerId'] ?? '',
      skillId:            d['skillId'] ?? '',
      canonicalName:      d['canonicalName'] ?? d['skillId'] ?? '',
      localizedName:      d['localizedName'] ?? '',
      emoji:              d['emoji'] ?? '🔧',
      color:              d['color'] ?? '#3B82F6',
      status:             SkillStatusX.fromString(d['status']),
      skillLevel:         (d['skillLevel'] ?? 0).toInt(),
      riskLevel:          d['riskLevel'] ?? 'low',
      assessmentVersion:  d['assessmentVersion'] ?? 'V1.0',
      knowledgeScore:     (d['knowledgeScore'] as num?)?.toDouble(),
      judgmentScore:      (d['judgmentScore'] as num?)?.toDouble(),
      practicalScore:     (d['practicalScore'] as num?)?.toDouble(),
      safetyScore:        (d['safetyScore'] as num?)?.toDouble(),
      overallScore:       (d['overallScore'] as num?)?.toDouble(),
      safetyGatePassed:   d['safetyGatePassed'] as bool?,
      evidenceCount:      (d['evidenceCount'] ?? 0).toInt(),
      credentialStatus:   d['credentialStatus'] ?? 'none',
      assessorId:         d['assessorId'] as String?,
      assessedAt:         DateParser.parse(d['assessedAt']),
      validUntil:         DateParser.parse(d['validUntil']),
      reassessmentRequired: d['reassessmentRequired'] == true,
      suspensionStatus:   d['suspensionStatus'] ?? 'active',
      suspensionReason:   d['suspensionReason'] as String?,
      reputation: d['reputation'] != null
        ? SkillReputation.fromMap(Map<String, dynamic>.from(d['reputation']))
        : null,
      createdAt:  DateParser.parseOrDefault(d['createdAt']),
      updatedAt:  DateParser.parseOrDefault(d['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':          workerId,
    'skillId':           skillId,
    'canonicalName':     canonicalName,
    'localizedName':     localizedName,
    'emoji':             emoji,
    'color':             color,
    'status':            'claimed',       // ALWAYS claimed on create
    'skillLevel':        0,               // ALWAYS 0 on create
    'riskLevel':         riskLevel,
    'assessmentVersion': assessmentVersion,
    'evidenceCount':     0,
    'credentialStatus':  'none',
    'reassessmentRequired': false,
    'suspensionStatus':  'active',
    'createdAt':         FieldValue.serverTimestamp(),
    'updatedAt':         FieldValue.serverTimestamp(),
  };
}

// ── Occupation Standard (from Firestore occupationStandards/{id}) ─
class OccupationStandard {
  final String id;
  final String canonicalName;
  final String localizedName;
  final String emoji;
  final String riskLevel;
  final String standardAuthority;
  final String standardReference;
  final String standardVersion;
  final String assessmentVersion;
  final int safetyThreshold;
  final int knowledgePassMark;   // percentage
  final int practicalPassMark;   // percentage
  final List<String> competencyUnits;
  final List<PracticalTask> practicalTasks;

  const OccupationStandard({
    required this.id,
    required this.canonicalName,
    required this.localizedName,
    required this.emoji,
    required this.riskLevel,
    required this.standardAuthority,
    required this.standardReference,
    required this.standardVersion,
    required this.assessmentVersion,
    required this.safetyThreshold,
    required this.knowledgePassMark,
    required this.practicalPassMark,
    required this.competencyUnits,
    required this.practicalTasks,
  });

  factory OccupationStandard.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final tasks = (d['practicalTasks'] as List? ?? [])
      .map((t) => PracticalTask.fromMap(Map<String, dynamic>.from(t)))
      .toList();
    return OccupationStandard(
      id:                 doc.id,
      canonicalName:      d['canonicalName'] ?? '',
      localizedName:      d['localizedName'] ?? '',
      emoji:              d['emoji'] ?? '',
      riskLevel:          d['riskLevel'] ?? 'low',
      standardAuthority:  d['standardAuthority'] ?? 'Kelasagara',
      standardReference:  d['standardReference'] ?? '',
      standardVersion:    d['standardVersion'] ?? '1.0',
      assessmentVersion:  d['assessmentVersion'] ?? 'V1.0',
      safetyThreshold:    (d['safetyThreshold'] ?? 4).toInt(),
      knowledgePassMark:  (d['knowledgePassMark'] ?? 60).toInt(),
      practicalPassMark:  (d['practicalPassMark'] ?? 65).toInt(),
      competencyUnits:    List<String>.from(d['competencyUnits'] ?? []),
      practicalTasks:     tasks,
    );
  }
}

class PracticalTask {
  final String taskId;
  final String name;
  final String nameKn;
  final String description;
  final int durationMinutes;
  final int maxSizeMb;

  const PracticalTask({
    required this.taskId,
    required this.name,
    required this.nameKn,
    required this.description,
    required this.durationMinutes,
    required this.maxSizeMb,
  });

  factory PracticalTask.fromMap(Map<String, dynamic> m) => PracticalTask(
    taskId:          m['taskId'] ?? '',
    name:            m['name'] ?? '',
    nameKn:          m['nameKn'] ?? '',
    description:     m['description'] ?? '',
    durationMinutes: (m['durationMinutes'] ?? 4).toInt(),
    maxSizeMb:       (m['maxSizeMb'] ?? 100).toInt(),
  );
}
