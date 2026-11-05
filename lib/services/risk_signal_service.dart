// lib/services/risk_signal_service.dart
// Risk signal detection for verification fraud prevention.
// Signals are recorded for human admin review only.
// Workers are NOT automatically penalised by signals.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum RiskLevel { low, medium, high, critical }

enum RiskSignalType {
  duplicateCredentialNumber,
  credentialNumberAcrossAccounts,
  nameMismatchCredential,
  expiredCredentialSubmitted,
  impossibleAssessmentTiming,
  qrMismatch,
}

class RiskSignalService {
  RiskSignalService._();
  static final RiskSignalService instance = RiskSignalService._();

  final _db = FirebaseFirestore.instance;

  Future<void> recordSignal({
    required String workerId,
    required RiskSignalType type,
    required RiskLevel level,
    required String description,
    String? relatedDocId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _db.collection('riskSignals').doc().set({
        'workerId':    workerId,
        'type':        type.name,
        'level':       level.name,
        'description': description,
        'reviewed':    false,
        if (relatedDocId != null) 'relatedDocId': relatedDocId,
        if (metadata != null) 'metadata': metadata,
        'createdAt':   FieldValue.serverTimestamp(),
      });
      debugPrint('[RiskSignal] Recorded \${level.name} for \$workerId: \$description');
    } catch (e) {
      debugPrint('[RiskSignal] Error: \$e');
    }
  }

  Future<bool> checkDuplicateCredentialNumber({
    required String credentialNumber,
    required String workerId,
  }) async {
    if (credentialNumber.isEmpty) return false;
    final snap = await _db.collection('professionalCredentials')
        .where('credentialNumber', isEqualTo: credentialNumber)
        .where('workerId', isNotEqualTo: workerId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> checkAndRecordDuplicateCredential({
    required String credentialNumber,
    required String workerId,
    required String credentialId,
  }) async {
    final isDuplicate = await checkDuplicateCredentialNumber(
      credentialNumber: credentialNumber, workerId: workerId);
    if (isDuplicate) {
      await recordSignal(
        workerId:    workerId,
        type:        RiskSignalType.duplicateCredentialNumber,
        level:       RiskLevel.high,
        description: 'Credential number \$credentialNumber already exists for another worker',
        relatedDocId:credentialId,
        metadata:    {'credentialNumber': credentialNumber},
      );
    }
  }
}
