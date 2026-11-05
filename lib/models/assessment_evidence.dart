// ================================================================
// KELASAGARA — Assessment Evidence Models
// Evidence · EvidenceStatus · local upload state
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

// ── Evidence Status State Machine ─────────────────────────────────
enum EvidenceStatus {
  created,           // Firestore record created, no upload yet
  uploadAuthorized,  // CF Worker issued presigned URL
  uploading,         // Upload in progress
  uploaded,          // Object confirmed in R2 by CF Worker
  integrityCheck,    // Backend checking object
  processing,        // Thumbnail / metadata generation
  reviewReady,       // Available for assessor review
  accepted,          // Assessor accepted this evidence
  rejected,          // Assessor rejected — needs retake
  superseded,        // Replaced by newer evidence for same task
  deleted,           // Retention policy deletion
}

extension EvidenceStatusX on EvidenceStatus {
  String get value => switch (this) {
    EvidenceStatus.created          => 'created',
    EvidenceStatus.uploadAuthorized => 'upload_authorized',
    EvidenceStatus.uploading        => 'uploading',
    EvidenceStatus.uploaded         => 'uploaded',
    EvidenceStatus.integrityCheck   => 'integrity_check',
    EvidenceStatus.processing       => 'processing',
    EvidenceStatus.reviewReady      => 'review_ready',
    EvidenceStatus.accepted         => 'accepted',
    EvidenceStatus.rejected         => 'rejected',
    EvidenceStatus.superseded       => 'superseded',
    EvidenceStatus.deleted          => 'deleted',
  };

  static EvidenceStatus fromString(String? s) => switch (s) {
    'created'          => EvidenceStatus.created,
    'upload_authorized'=> EvidenceStatus.uploadAuthorized,
    'uploading'        => EvidenceStatus.uploading,
    'uploaded'         => EvidenceStatus.uploaded,
    'integrity_check'  => EvidenceStatus.integrityCheck,
    'processing'       => EvidenceStatus.processing,
    'review_ready'     => EvidenceStatus.reviewReady,
    'accepted'         => EvidenceStatus.accepted,
    'rejected'         => EvidenceStatus.rejected,
    'superseded'       => EvidenceStatus.superseded,
    'deleted'          => EvidenceStatus.deleted,
    _                  => EvidenceStatus.created,
  };

  String get displayLabel => switch (this) {
    EvidenceStatus.created          => '📱 Saved locally',
    EvidenceStatus.uploadAuthorized => '🔐 Upload authorized',
    EvidenceStatus.uploading        => '⬆️ Uploading...',
    EvidenceStatus.uploaded         => '✅ Uploaded securely',
    EvidenceStatus.integrityCheck   => '🔍 Verifying...',
    EvidenceStatus.processing       => '⚙️ Processing...',
    EvidenceStatus.reviewReady      => '👁 Ready for review',
    EvidenceStatus.accepted         => '✅ Evidence accepted',
    EvidenceStatus.rejected         => '❌ Evidence not accepted — retake required',
    EvidenceStatus.superseded       => 'Replaced',
    EvidenceStatus.deleted          => 'Removed',
  };

  bool get isUploadable => this == EvidenceStatus.created ||
                           this == EvidenceStatus.uploadAuthorized;
  bool get isUploading  => this == EvidenceStatus.uploading;
  bool get isDone       => this == EvidenceStatus.uploaded ||
                           this == EvidenceStatus.reviewReady ||
                           this == EvidenceStatus.accepted;
  bool get hasFailed    => this == EvidenceStatus.rejected;
}

// ── Assessment Evidence (Firestore: assessmentEvidence/{evidenceId}) ─
class AssessmentEvidence {
  final String id;
  final String assessmentId;
  final String workerId;
  final String skillId;
  final String taskId;
  final int attemptNumber;
  final EvidenceStatus status;

  // ── Storage ────────────────────────────────────────────────────
  final String? storageKey;      // R2 object key — set by CF Worker on confirm
  final double? fileSizeMb;
  final int? durationSeconds;
  final String? mimeType;
  final String? sha256Checksum;
  final String? perceptualHash;  // For duplicate detection

  // ── Timestamps ────────────────────────────────────────────────
  final DateTime? uploadAuthorizedAt;
  final DateTime? uploadedAt;
  final DateTime? integrityVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── AI observations (assistance only, not decisions) ───────────
  final String aiStatus;         // pending|processing|complete|failed|unavailable
  final Map<String, dynamic>? aiObservations;
  final double? aiConfidence;
  final String? aiModelVersion;

  // ── Human review ──────────────────────────────────────────────
  final String reviewStatus;     // pending|accepted|rejected
  final String? reviewerNotes;

  // ── Local-only state (not persisted to Firestore) ─────────────
  final String? localFilePath;   // path_provider temp path during upload
  final double uploadProgress;   // 0.0–1.0 during active upload

  const AssessmentEvidence({
    required this.id,
    required this.assessmentId,
    required this.workerId,
    required this.skillId,
    required this.taskId,
    required this.attemptNumber,
    required this.status,
    this.storageKey,
    this.fileSizeMb,
    this.durationSeconds,
    this.mimeType,
    this.sha256Checksum,
    this.perceptualHash,
    this.uploadAuthorizedAt,
    this.uploadedAt,
    this.integrityVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
    this.aiStatus = 'pending',
    this.aiObservations,
    this.aiConfidence,
    this.aiModelVersion,
    this.reviewStatus = 'pending',
    this.reviewerNotes,
    this.localFilePath,
    this.uploadProgress = 0,
  });

  factory AssessmentEvidence.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AssessmentEvidence(
      id:                   doc.id,
      assessmentId:         d['assessmentId'] ?? '',
      workerId:             d['workerId'] ?? '',
      skillId:              d['skillId'] ?? '',
      taskId:               d['taskId'] ?? '',
      attemptNumber:        (d['attemptNumber'] ?? 1).toInt(),
      status:               EvidenceStatusX.fromString(d['status']),
      storageKey:           d['storageKey'] as String?,
      fileSizeMb:           (d['fileSizeMb'] as num?)?.toDouble(),
      durationSeconds:      (d['durationSeconds'] as num?)?.toInt(),
      mimeType:             d['mimeType'] as String?,
      sha256Checksum:       d['sha256Checksum'] as String?,
      perceptualHash:       d['perceptualHash'] as String?,
      uploadAuthorizedAt:   DateParser.parse(d['uploadAuthorizedAt']),
      uploadedAt:           DateParser.parse(d['uploadedAt']),
      integrityVerifiedAt:  DateParser.parse(d['integrityVerifiedAt']),
      createdAt:            DateParser.parseOrDefault(d['createdAt']),
      updatedAt:            DateParser.parseOrDefault(d['updatedAt']),
      aiStatus:             d['aiStatus'] ?? 'pending',
      aiObservations:       d['aiObservations'] != null
                              ? Map<String, dynamic>.from(d['aiObservations'])
                              : null,
      aiConfidence:         (d['aiConfidence'] as num?)?.toDouble(),
      aiModelVersion:       d['aiModelVersion'] as String?,
      reviewStatus:         d['reviewStatus'] ?? 'pending',
      reviewerNotes:        d['reviewerNotes'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'assessmentId':   assessmentId,
    'workerId':       workerId,
    'skillId':        skillId,
    'taskId':         taskId,
    'attemptNumber':  attemptNumber,
    'status':         'created',
    'aiStatus':       'pending',
    'reviewStatus':   'pending',
    'createdAt':      FieldValue.serverTimestamp(),
    'updatedAt':      FieldValue.serverTimestamp(),
  };

  AssessmentEvidence copyWith({
    EvidenceStatus? status,
    String? localFilePath,
    double? uploadProgress,
    String? storageKey,
    DateTime? uploadedAt,
  }) => AssessmentEvidence(
    id: id, assessmentId: assessmentId, workerId: workerId,
    skillId: skillId, taskId: taskId, attemptNumber: attemptNumber,
    status: status ?? this.status,
    storageKey: storageKey ?? this.storageKey,
    fileSizeMb: fileSizeMb, durationSeconds: durationSeconds,
    mimeType: mimeType, sha256Checksum: sha256Checksum,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    createdAt: createdAt, updatedAt: DateTime.now(),
    aiStatus: aiStatus, reviewStatus: reviewStatus,
    localFilePath: localFilePath ?? this.localFilePath,
    uploadProgress: uploadProgress ?? this.uploadProgress,
  );
}

// ── Upload Authorization Response (from CF Worker) ────────────────
class UploadAuthorization {
  final String uploadUrl;      // presigned PUT URL (15 min)
  final String storageKey;     // R2 object key
  final String evidenceId;
  final int expiresIn;         // seconds
  final int maxSizeMb;

  const UploadAuthorization({
    required this.uploadUrl,
    required this.storageKey,
    required this.evidenceId,
    required this.expiresIn,
    required this.maxSizeMb,
  });

  factory UploadAuthorization.fromJson(Map<String, dynamic> j) =>
    UploadAuthorization(
      uploadUrl:  j['uploadUrl'] ?? '',
      storageKey: j['storageKey'] ?? '',
      evidenceId: j['evidenceId'] ?? '',
      expiresIn:  (j['expiresIn'] ?? 900).toInt(),
      maxSizeMb:  (j['maxSizeMb'] ?? 200).toInt(),
    );
}
