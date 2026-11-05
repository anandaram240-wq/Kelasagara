// ================================================================
// KELASAGARA — Skill Assessment Models
// Assessment · AssessmentQuestion · AssessmentStatus
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

// ── Assessment Status State Machine ──────────────────────────────
// Legal transitions enforced by Security Rules and AssessmentService.
enum AssessmentStatus {
  draft,
  scheduled,
  ready,
  inProgress,
  evidenceCollection,
  submitted,
  processing,
  underReview,
  approved,
  rejected,
  reassessmentRequired,
  expired,
  cancelled,
}

extension AssessmentStatusX on AssessmentStatus {
  String get value => switch (this) {
    AssessmentStatus.draft                => 'draft',
    AssessmentStatus.scheduled            => 'scheduled',
    AssessmentStatus.ready                => 'ready',
    AssessmentStatus.inProgress           => 'in_progress',
    AssessmentStatus.evidenceCollection   => 'evidence_collection',
    AssessmentStatus.submitted            => 'submitted',
    AssessmentStatus.processing           => 'processing',
    AssessmentStatus.underReview          => 'under_review',
    AssessmentStatus.approved             => 'approved',
    AssessmentStatus.rejected             => 'rejected',
    AssessmentStatus.reassessmentRequired => 'reassessment_required',
    AssessmentStatus.expired              => 'expired',
    AssessmentStatus.cancelled            => 'cancelled',
  };

  static AssessmentStatus fromString(String? s) => switch (s) {
    'draft'                 => AssessmentStatus.draft,
    'scheduled'             => AssessmentStatus.scheduled,
    'ready'                 => AssessmentStatus.ready,
    'in_progress'           => AssessmentStatus.inProgress,
    'evidence_collection'   => AssessmentStatus.evidenceCollection,
    'submitted'             => AssessmentStatus.submitted,
    'processing'            => AssessmentStatus.processing,
    'under_review'          => AssessmentStatus.underReview,
    'approved'              => AssessmentStatus.approved,
    'rejected'              => AssessmentStatus.rejected,
    'reassessment_required' => AssessmentStatus.reassessmentRequired,
    'expired'               => AssessmentStatus.expired,
    'cancelled'             => AssessmentStatus.cancelled,
    _                       => AssessmentStatus.draft,
  };

  String get displayLabel => switch (this) {
    AssessmentStatus.draft              => 'Not Started',
    AssessmentStatus.inProgress         => 'In Progress',
    AssessmentStatus.evidenceCollection => 'Recording Evidence',
    AssessmentStatus.submitted          => 'Submitted — Under Review',
    AssessmentStatus.underReview        => 'Under Admin Review',
    AssessmentStatus.approved           => 'Approved ✅',
    AssessmentStatus.rejected           => 'Not Passed',
    AssessmentStatus.expired            => 'Session Expired',
    _                                   => value,
  };

  bool get isTerminal => this == AssessmentStatus.approved ||
                         this == AssessmentStatus.rejected ||
                         this == AssessmentStatus.expired ||
                         this == AssessmentStatus.cancelled;

  bool get isActive => this == AssessmentStatus.inProgress ||
                       this == AssessmentStatus.evidenceCollection;
}

// ── Skill Assessment (Firestore: skillAssessments/{assessmentId}) ─
class SkillAssessment {
  final String id;
  final String workerId;
  final String skillId;
  final String assessmentVersion;
  final String standardVersion;
  final int attemptNumber;
  final AssessmentStatus status;

  // ── Scores (only set by admin, never by worker) ────────────────
  final double? knowledgeScore;
  final double? judgmentScore;
  final double? practicalScore;
  final double? safetyScore;
  final Map<String, int> rubricScores; // {surfacePrep: 4, toolHandling: 5, ...}
  final bool? safetyGatePassed;

  // ── Evidence references ────────────────────────────────────────
  final List<String> evidenceIds;

  // ── AI assistance (observations only, not decisions) ──────────
  final Map<String, dynamic>? aiObservations;
  final double? aiConfidence;
  final String? aiModelVersion;

  // ── Human review ──────────────────────────────────────────────
  final bool humanReviewRequired;
  final String humanReviewStatus; // not_required|required|reviewed
  final String? assessorId;
  final String? decision;         // pass|fail|borderline|refer
  final List<String> failureReasons;

  // ── Appeal ────────────────────────────────────────────────────
  final String? appealStatus;     // null|requested|under_review|decided

  // ── Timestamps ────────────────────────────────────────────────
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? expiresAt;

  const SkillAssessment({
    required this.id,
    required this.workerId,
    required this.skillId,
    required this.assessmentVersion,
    required this.standardVersion,
    required this.attemptNumber,
    required this.status,
    this.knowledgeScore,
    this.judgmentScore,
    this.practicalScore,
    this.safetyScore,
    this.rubricScores = const {},
    this.safetyGatePassed,
    this.evidenceIds = const [],
    this.aiObservations,
    this.aiConfidence,
    this.aiModelVersion,
    this.humanReviewRequired = false,
    this.humanReviewStatus = 'not_required',
    this.assessorId,
    this.decision,
    this.failureReasons = const [],
    this.appealStatus,
    required this.createdAt,
    this.startedAt,
    this.submittedAt,
    this.reviewedAt,
    this.expiresAt,
  });

  bool get isPassed => decision == 'pass';
  bool get isFailed => decision == 'fail';

  factory SkillAssessment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rubric = Map<String, dynamic>.from(d['rubricScores'] ?? {});
    return SkillAssessment(
      id:                   doc.id,
      workerId:             d['workerId'] ?? '',
      skillId:              d['skillId'] ?? '',
      assessmentVersion:    d['assessmentVersion'] ?? 'V1.0',
      standardVersion:      d['standardVersion'] ?? '1.0',
      attemptNumber:        (d['attemptNumber'] ?? 1).toInt(),
      status:               AssessmentStatusX.fromString(d['status']),
      knowledgeScore:       (d['knowledgeScore'] as num?)?.toDouble(),
      judgmentScore:        (d['judgmentScore'] as num?)?.toDouble(),
      practicalScore:       (d['practicalScore'] as num?)?.toDouble(),
      safetyScore:          (d['safetyScore'] as num?)?.toDouble(),
      rubricScores:         rubric.map((k, v) => MapEntry(k, (v as num).toInt())),
      safetyGatePassed:     d['safetyGatePassed'] as bool?,
      evidenceIds:          List<String>.from(d['evidenceIds'] ?? []),
      aiObservations:       d['aiObservations'] != null
                              ? Map<String, dynamic>.from(d['aiObservations'])
                              : null,
      aiConfidence:         (d['aiConfidence'] as num?)?.toDouble(),
      aiModelVersion:       d['aiModelVersion'] as String?,
      humanReviewRequired:  d['humanReviewRequired'] == true,
      humanReviewStatus:    d['humanReviewStatus'] ?? 'not_required',
      assessorId:           d['assessorId'] as String?,
      decision:             d['decision'] as String?,
      failureReasons:       List<String>.from(d['failureReasons'] ?? []),
      appealStatus:         d['appealStatus'] as String?,
      createdAt:            DateParser.parseOrDefault(d['createdAt']),
      startedAt:            DateParser.parse(d['startedAt']),
      submittedAt:          DateParser.parse(d['submittedAt']),
      reviewedAt:           DateParser.parse(d['reviewedAt']),
      expiresAt:            DateParser.parse(d['expiresAt']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':          workerId,
    'skillId':           skillId,
    'assessmentVersion': assessmentVersion,
    'standardVersion':   standardVersion,
    'attemptNumber':     attemptNumber,
    'status':            'draft',
    'evidenceIds':       [],
    'rubricScores':      {},
    'failureReasons':    [],
    'humanReviewRequired': false,
    'humanReviewStatus': 'not_required',
    'createdAt':         FieldValue.serverTimestamp(),
    'expiresAt':         Timestamp.fromDate(
                           DateTime.now().add(const Duration(days: 7))),
  };
}

// ── Assessment Question ────────────────────────────────────────────
class AssessmentQuestion {
  final String id;
  final String skillId;
  final String type;             // 'knowledge' | 'judgment'
  final int level;               // 1–4
  final String questionText;
  final String questionTextKn;
  final List<QuestionOption> options;
  final bool safetyRelated;
  final bool mandatoryPass;      // if true, wrong = automatic fail
  final String assessmentVersion;

  const AssessmentQuestion({
    required this.id,
    required this.skillId,
    required this.type,
    required this.level,
    required this.questionText,
    required this.questionTextKn,
    required this.options,
    required this.safetyRelated,
    required this.mandatoryPass,
    required this.assessmentVersion,
  });

  QuestionOption? get correctOption =>
    options.firstWhereOrNull((o) => o.isCorrect);

  factory AssessmentQuestion.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AssessmentQuestion(
      id:                 doc.id,
      skillId:            d['skillId'] ?? '',
      type:               d['type'] ?? 'knowledge',
      level:              (d['level'] ?? 1).toInt(),
      questionText:       d['questionText'] ?? '',
      questionTextKn:     d['questionTextKn'] ?? '',
      options:            (d['options'] as List? ?? [])
                            .map((o) => QuestionOption.fromMap(Map<String, dynamic>.from(o)))
                            .toList(),
      safetyRelated:      d['safetyRelated'] == true,
      mandatoryPass:      d['mandatoryPass'] == true,
      assessmentVersion:  d['assessmentVersion'] ?? 'V1.0',
    );
  }
}

class QuestionOption {
  final String id;
  final String text;
  final String textKn;
  final bool isCorrect;
  final String explanation;

  const QuestionOption({
    required this.id,
    required this.text,
    required this.textKn,
    required this.isCorrect,
    required this.explanation,
  });

  factory QuestionOption.fromMap(Map<String, dynamic> m) => QuestionOption(
    id:          m['id'] ?? '',
    text:        m['text'] ?? '',
    textKn:      m['textKn'] ?? '',
    isCorrect:   m['isCorrect'] == true,
    explanation: m['explanation'] ?? '',
  );
}

// ── Extension helper ───────────────────────────────────────────────
extension _ListFirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}
