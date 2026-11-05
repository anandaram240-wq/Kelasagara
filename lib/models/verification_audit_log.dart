// lib/models/verification_audit_log.dart
// Immutable audit log for all verification actions.
// Every admin action on credential/registration must create one.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

enum AuditAction {
  registrationSubmitted,
  registrationReviewed,
  registrationVerified,
  registrationRejected,
  credentialSubmitted,
  credentialReviewed,
  credentialSourceChecked,
  credentialIssuerConfirmed,
  credentialVerified,
  credentialRejected,
  assessmentSubmitted,
  assessmentPassed,
  assessmentFailed,
  assessmentEscalated,
  badgeIssued,
  badgeRevoked,
  skillVerified,
  skillSuspended;

  String get firestoreValue => name;
  static AuditAction fromString(String? s) {
    try { return AuditAction.values.firstWhere((e) => e.name == s); }
    catch (_) { return AuditAction.credentialReviewed; }
  }
}

class VerificationAuditLog {
  final String      logId;
  final String      workerId;
  final String      actorId;          // who performed the action (admin UID)
  final String      actorRole;        // 'admin' | 'assessor' | 'super_admin'
  final AuditAction action;
  final String      targetCollection; // 'workerRegistrations' | 'professionalCredentials' | etc.
  final String      targetDocId;
  final String      previousStatus;
  final String      newStatus;
  final String      evidenceStrength;
  final String?     sourceUrl;        // URL used for verification
  final String?     notes;
  final String?     standardVersion;
  final String?     assessmentVersion;
  final DateTime    timestamp;

  const VerificationAuditLog({
    required this.logId,
    required this.workerId,
    required this.actorId,
    required this.actorRole,
    required this.action,
    required this.targetCollection,
    required this.targetDocId,
    required this.previousStatus,
    required this.newStatus,
    required this.evidenceStrength,
    this.sourceUrl,
    this.notes,
    this.standardVersion,
    this.assessmentVersion,
    required this.timestamp,
  });

  factory VerificationAuditLog.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return VerificationAuditLog(
      logId:             doc.id,
      workerId:          d['workerId'] ?? '',
      actorId:           d['actorId'] ?? '',
      actorRole:         d['actorRole'] ?? 'admin',
      action:            AuditAction.fromString(d['action']),
      targetCollection:  d['targetCollection'] ?? '',
      targetDocId:       d['targetDocId'] ?? '',
      previousStatus:    d['previousStatus'] ?? '',
      newStatus:         d['newStatus'] ?? '',
      evidenceStrength:  d['evidenceStrength'] ?? '',
      sourceUrl:         d['sourceUrl'],
      notes:             d['notes'],
      standardVersion:   d['standardVersion'],
      assessmentVersion: d['assessmentVersion'],
      timestamp:         DateParser.parseOrDefault(d['timestamp']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':          workerId,
    'actorId':           actorId,
    'actorRole':         actorRole,
    'action':            action.firestoreValue,
    'targetCollection':  targetCollection,
    'targetDocId':       targetDocId,
    'previousStatus':    previousStatus,
    'newStatus':         newStatus,
    'evidenceStrength':  evidenceStrength,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (notes != null) 'notes': notes,
    if (standardVersion != null) 'standardVersion': standardVersion,
    if (assessmentVersion != null) 'assessmentVersion': assessmentVersion,
    'timestamp':         FieldValue.serverTimestamp(),
  };
}
