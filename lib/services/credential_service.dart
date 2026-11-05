// lib/services/credential_service.dart
// Professional credential submission and admin verification service.
// Worker submits; admin reviews and marks source checked / issuer confirmed.
// IMPORTANT: document submitted != credential verified.

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/credential_record.dart';
import '../models/verification_audit_log.dart';

class CredentialService {
  CredentialService._();
  static final CredentialService instance = CredentialService._();

  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // ── Worker: submit credential ─────────────────────────────────────────────
  Future<String> submitCredential({
    required String          workerId,
    required String          skillId,
    required CredentialType  credentialType,
    required String          issuer,
    required String          issuerType,
    required String          credentialName,
    required String          qualificationCode,
    required String          credentialNumber,
    required String          holderName,
    DateTime?                issueDate,
    DateTime?                expiryDate,
    String?                  qrPayload,
    String?                  verificationUrl,
    File?                    documentFile,
  }) async {
    String? storagePath;
    String? downloadUrl;

    if (documentFile != null) {
      final fileName = 'cred_\${workerId}_\${DateTime.now().millisecondsSinceEpoch}.jpg';
      storagePath    = 'credential_docs/\$workerId/\$fileName';
      final ref      = _storage.ref(storagePath);
      await ref.putFile(documentFile, SettableMetadata(contentType: 'image/jpeg'));
      downloadUrl    = await ref.getDownloadURL();
    }

    final docRef = _db.collection('professionalCredentials').doc();
    final record = CredentialRecord(
      credentialId:      docRef.id,
      workerId:          workerId,
      skillId:           skillId,
      credentialType:    credentialType,
      status:            CredentialStatus.documentSubmitted,
      evidenceStrength:  EvidenceStrength.documentSubmitted,
      issuer:            issuer,
      issuerType:        issuerType,
      credentialName:    credentialName,
      qualificationCode: qualificationCode,
      credentialNumber:  credentialNumber,
      holderName:        holderName,
      issueDate:         issueDate,
      expiryDate:        expiryDate,
      qrPayload:         qrPayload,
      verificationUrl:   verificationUrl,
      documentStoragePath: storagePath,
      documentDownloadUrl: downloadUrl,
      submittedAt:       DateTime.now(),
    );

    await docRef.set(record.toFirestoreCreate());
    debugPrint('[CredentialSvc] Submitted credential \${docRef.id} for worker \$workerId skill \$skillId');
    return docRef.id;
  }

  // ── Worker: stream own credentials ───────────────────────────────────────
  Stream<List<CredentialRecord>> streamCredentials(String workerId) =>
      _db.collection('professionalCredentials')
          .where('workerId', isEqualTo: workerId)
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(CredentialRecord.fromFirestore).toList());

  // ── Worker: stream credentials for a specific skill ──────────────────────
  Stream<List<CredentialRecord>> streamCredentialsForSkill(String workerId, String skillId) =>
      _db.collection('professionalCredentials')
          .where('workerId', isEqualTo: workerId)
          .where('skillId', isEqualTo: skillId)
          .snapshots()
          .map((snap) => snap.docs.map(CredentialRecord.fromFirestore).toList());

  // ── Admin: update credential status ──────────────────────────────────────
  Future<void> adminUpdateCredentialStatus({
    required String            credentialId,
    required String            workerId,
    required CredentialStatus  newStatus,
    required EvidenceStrength  newStrength,
    required String            adminId,
    String?                    verificationMethod,
    String?                    verificationSource,
    String?                    reviewNotes,
    String?                    rejectionReason,
    String?                    standardVersion,
  }) async {
    final snap    = await _db.collection('professionalCredentials').doc(credentialId).get();
    final current = snap.exists ? CredentialRecord.fromFirestore(snap) : null;
    final prevStatus = current?.status.firestoreValue ?? 'unknown';

    final batch = _db.batch();

    final credRef = _db.collection('professionalCredentials').doc(credentialId);
    final updateData = <String, dynamic>{
      'status':             newStatus.firestoreValue,
      'evidenceStrength':   newStrength.firestoreValue,
      'verifiedBy':         adminId,
      'verifiedAt':         FieldValue.serverTimestamp(),
      if (verificationMethod != null) 'verificationMethod': verificationMethod,
      if (verificationSource != null) 'verificationSource': verificationSource,
      if (reviewNotes != null) 'reviewNotes': reviewNotes,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (standardVersion != null) 'standardVersion': standardVersion,
    };
    batch.update(credRef, updateData);

    AuditAction action;
    switch (newStatus) {
      case CredentialStatus.sourceChecked:
        action = AuditAction.credentialSourceChecked;
      case CredentialStatus.issuerConfirmed:
        action = AuditAction.credentialIssuerConfirmed;
      case CredentialStatus.credentialVerified:
        action = AuditAction.credentialVerified;
      case CredentialStatus.rejected:
        action = AuditAction.credentialRejected;
      default:
        action = AuditAction.credentialReviewed;
    }

    final logRef = _db.collection('verificationAuditLogs').doc();
    final log = VerificationAuditLog(
      logId:            logRef.id,
      workerId:         workerId,
      actorId:          adminId,
      actorRole:        'admin',
      action:           action,
      targetCollection: 'professionalCredentials',
      targetDocId:      credentialId,
      previousStatus:   prevStatus,
      newStatus:        newStatus.firestoreValue,
      evidenceStrength: newStrength.firestoreValue,
      sourceUrl:        verificationSource,
      notes:            reviewNotes,
      standardVersion:  standardVersion,
      timestamp:        DateTime.now(),
    );
    batch.set(logRef, log.toFirestoreCreate());

    await batch.commit();
    debugPrint('[CredentialSvc] Admin \$adminId updated \$credentialId to \${newStatus.firestoreValue}');
  }

  // ── Admin: list pending credentials ──────────────────────────────────────
  Stream<List<CredentialRecord>> streamPendingCredentials() =>
      _db.collection('professionalCredentials')
          .where('status', whereIn: [
            CredentialStatus.documentSubmitted.firestoreValue,
            CredentialStatus.documentReviewed.firestoreValue,
          ])
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(CredentialRecord.fromFirestore).toList());

  // ── Get credential for specific worker+skill ──────────────────────────────
  Future<CredentialRecord?> getBestCredential(String workerId, String skillId) async {
    final snap = await _db.collection('professionalCredentials')
        .where('workerId', isEqualTo: workerId)
        .where('skillId', isEqualTo: skillId)
        .where('status', whereIn: [
          CredentialStatus.issuerConfirmed.firestoreValue,
          CredentialStatus.credentialVerified.firestoreValue,
        ])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty ? CredentialRecord.fromFirestore(snap.docs.first) : null;
  }
}
