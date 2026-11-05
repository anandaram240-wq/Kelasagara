// lib/services/worker_registration_service.dart
// Worker registration evidence service.
// Worker can submit; admin can update status.
// IMPORTANT: verified registration != skill verified.

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/worker_registration.dart';
import '../models/verification_audit_log.dart';

class WorkerRegistrationService {
  WorkerRegistrationService._();
  static final WorkerRegistrationService instance = WorkerRegistrationService._();

  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // ── Worker: submit registration evidence ─────────────────────────────────
  Future<void> submitRegistration({
    required String workerId,
    required RegistrationType type,
    required String referenceNumber,
    required String declaredOccupation,
    File? documentFile,           // optional document image
  }) async {
    String? storagePath;
    String? downloadUrl;

    // Upload document to Firebase Storage if provided
    if (documentFile != null) {
      final fileName = 'reg_\${workerId}_\${DateTime.now().millisecondsSinceEpoch}.jpg';
      storagePath    = 'worker_registration_docs/\$workerId/\$fileName';
      final ref      = _storage.ref(storagePath);
      await ref.putFile(documentFile, SettableMetadata(contentType: 'image/jpeg'));
      downloadUrl    = await ref.getDownloadURL();
    }

    final reg = WorkerRegistration(
      workerId:           workerId,
      registrationType:   type,
      status:             RegistrationStatus.submitted,
      referenceNumber:    referenceNumber,
      declaredOccupation: declaredOccupation,
      documentStoragePath:storagePath,
      documentDownloadUrl:downloadUrl,
      submittedAt:        DateTime.now(),
    );

    // Use workerId as doc ID — one registration record per worker (latest wins)
    await _db.collection('workerRegistrations').doc(workerId).set(
      reg.toFirestoreCreate(),
      SetOptions(merge: false),
    );
    debugPrint('[WorkerReg] Submitted registration for \$workerId (type: \${type.firestoreValue})');
  }

  // ── Worker: stream own registration ──────────────────────────────────────
  Stream<WorkerRegistration?> streamRegistration(String workerId) =>
      _db.collection('workerRegistrations').doc(workerId)
          .snapshots()
          .map((snap) => snap.exists ? WorkerRegistration.fromFirestore(snap) : null);

  // ── Admin: update registration status ────────────────────────────────────
  // This must only be called from admin-authenticated context.
  Future<void> adminUpdateStatus({
    required String workerId,
    required RegistrationStatus newStatus,
    required String adminId,
    String? sourceUrl,
    String? reviewNotes,
    String? rejectionReason,
  }) async {
    // Read current status for audit log
    final snap    = await _db.collection('workerRegistrations').doc(workerId).get();
    final current = snap.exists ? WorkerRegistration.fromFirestore(snap) : null;
    final prevStatus = current?.status.firestoreValue ?? 'unknown';

    final batch = _db.batch();

    // Update registration
    final regRef = _db.collection('workerRegistrations').doc(workerId);
    final updateData = <String, dynamic>{
      'status':      newStatus.firestoreValue,
      'reviewedBy':  adminId,
      'reviewedAt':  FieldValue.serverTimestamp(),
      'updatedAt':   FieldValue.serverTimestamp(),
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      if (reviewNotes != null) 'reviewNotes': reviewNotes,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
    batch.update(regRef, updateData);

    // Audit log
    AuditAction action;
    switch (newStatus) {
      case RegistrationStatus.verified:
        action = AuditAction.registrationVerified;
      case RegistrationStatus.sourceChecked:
        action = AuditAction.registrationReviewed;
      case RegistrationStatus.rejected:
        action = AuditAction.registrationRejected;
      default:
        action = AuditAction.registrationReviewed;
    }

    final logRef = _db.collection('verificationAuditLogs').doc();
    final log = VerificationAuditLog(
      logId:             logRef.id,
      workerId:          workerId,
      actorId:           adminId,
      actorRole:         'admin',
      action:            action,
      targetCollection:  'workerRegistrations',
      targetDocId:       workerId,
      previousStatus:    prevStatus,
      newStatus:         newStatus.firestoreValue,
      evidenceStrength:  newStatus == RegistrationStatus.verified ? 'source_checked' : 'document_reviewed',
      sourceUrl:         sourceUrl,
      notes:             reviewNotes,
      timestamp:         DateTime.now(),
    );
    batch.set(logRef, log.toFirestoreCreate());

    await batch.commit();
    debugPrint('[WorkerReg] Admin \$adminId updated \$workerId to \${newStatus.firestoreValue}');
  }

  // ── Admin: list pending registrations ────────────────────────────────────
  Stream<List<WorkerRegistration>> streamPendingRegistrations() =>
      _db.collection('workerRegistrations')
          .where('status', whereIn: [
            RegistrationStatus.submitted.firestoreValue,
            RegistrationStatus.underReview.firestoreValue,
          ])
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(WorkerRegistration.fromFirestore).toList());
}
