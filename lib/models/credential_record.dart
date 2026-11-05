// lib/models/credential_record.dart
// Professional credential evidence — DGT/NTC, SSC certificate, etc.
// IMPORTANT: Document submitted != Credential Verified.
// Verification requires source checking.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

// Evidence Strength Levels (Part 73)
enum EvidenceStrength {
  selfDeclared,      // Level 0
  documentSubmitted, // Level 1
  documentReviewed,  // Level 2
  publicSourceChecked, // Level 3
  issuerConfirmed,   // Level 4
  authorizedDigitalVerification; // Level 5

  int get level => index;

  String get displayLabel => switch (this) {
    selfDeclared      => 'Level 0 — Self Declared',
    documentSubmitted => 'Level 1 — Document Submitted',
    documentReviewed  => 'Level 2 — Document Reviewed',
    publicSourceChecked => 'Level 3 — Public Source Checked',
    issuerConfirmed   => 'Level 4 — Issuer Confirmed',
    authorizedDigitalVerification => 'Level 5 — Authorized Digital Verification',
  };

  String get firestoreValue => switch (this) {
    selfDeclared      => 'self_declared',
    documentSubmitted => 'document_submitted',
    documentReviewed  => 'document_reviewed',
    publicSourceChecked => 'public_source_checked',
    issuerConfirmed   => 'issuer_confirmed',
    authorizedDigitalVerification => 'authorized_digital_verification',
  };

  static EvidenceStrength fromString(String? s) => switch (s) {
    'document_submitted'  => documentSubmitted,
    'document_reviewed'   => documentReviewed,
    'public_source_checked' => publicSourceChecked,
    'issuer_confirmed'    => issuerConfirmed,
    'authorized_digital_verification' => authorizedDigitalVerification,
    _                     => selfDeclared,
  };
}

// Credential Status (Part 35)
enum CredentialStatus {
  documentSubmitted,
  documentReviewed,
  sourceChecked,
  issuerConfirmed,
  credentialVerified,
  expired,
  revoked,
  rejected,
  unableToVerify;

  String get firestoreValue => switch (this) {
    documentSubmitted  => 'document_submitted',
    documentReviewed   => 'document_reviewed',
    sourceChecked      => 'source_checked',
    issuerConfirmed    => 'issuer_confirmed',
    credentialVerified => 'credential_verified',
    expired            => 'expired',
    revoked            => 'revoked',
    rejected           => 'rejected',
    unableToVerify     => 'unable_to_verify',
  };

  String get displayLabel => switch (this) {
    documentSubmitted  => 'Document Submitted',
    documentReviewed   => 'Document Reviewed',
    sourceChecked      => 'Source Checked',
    issuerConfirmed    => 'Issuer Confirmed',
    credentialVerified => 'Credential Verified',
    expired            => 'Expired',
    revoked            => 'Revoked',
    rejected           => 'Rejected',
    unableToVerify     => 'Unable to Verify',
  };

  bool get isVerified => this == credentialVerified || this == issuerConfirmed;
  bool get isPending  => this == documentSubmitted || this == documentReviewed || this == sourceChecked;

  static CredentialStatus fromString(String? s) => switch (s) {
    'document_submitted'  => documentSubmitted,
    'document_reviewed'   => documentReviewed,
    'source_checked'      => sourceChecked,
    'issuer_confirmed'    => issuerConfirmed,
    'credential_verified' => credentialVerified,
    'expired'             => expired,
    'revoked'             => revoked,
    'rejected'            => rejected,
    'unable_to_verify'    => unableToVerify,
    _                     => documentSubmitted,
  };
}

// Credential type
enum CredentialType {
  dgtNtc,              // DGT/ITI National Trade Certificate
  sscCertificate,      // Sector Skill Council certificate
  ncvetQualification,  // NCVET-aligned qualification
  apprenticeship,      // Apprenticeship completion
  tradeCredential,     // Other recognized trade credential
  other;

  String get displayName => switch (this) {
    dgtNtc             => 'DGT/ITI National Trade Certificate (NTC)',
    sscCertificate     => 'Sector Skill Council Certificate',
    ncvetQualification => 'NCVET-aligned Qualification',
    apprenticeship     => 'Apprenticeship Completion',
    tradeCredential    => 'Other Trade Credential',
    other              => 'Other',
  };

  String get firestoreValue => switch (this) {
    dgtNtc             => 'dgt_ntc',
    sscCertificate     => 'ssc_certificate',
    ncvetQualification => 'ncvet_qualification',
    apprenticeship     => 'apprenticeship',
    tradeCredential    => 'trade_credential',
    other              => 'other',
  };

  static CredentialType fromString(String? s) => switch (s) {
    'dgt_ntc'           => dgtNtc,
    'ssc_certificate'   => sscCertificate,
    'ncvet_qualification'=> ncvetQualification,
    'apprenticeship'    => apprenticeship,
    'trade_credential'  => tradeCredential,
    _                   => other,
  };
}

class CredentialRecord {
  final String          credentialId;
  final String          workerId;
  final String          skillId;           // occupation this credential relates to
  final CredentialType  credentialType;
  final CredentialStatus status;
  final EvidenceStrength evidenceStrength;

  // Credential details (worker-provided)
  final String issuer;                     // Issuing body name
  final String issuerType;                 // 'DGT' | 'SSC' | 'NCVET' | 'other'
  final String credentialName;
  final String qualificationCode;          // Official code if applicable
  final String credentialNumber;           // Certificate number
  final String holderName;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? qrPayload;                 // QR code content
  final String? verificationUrl;           // Official verification URL

  // Document evidence
  final String? documentStoragePath;
  final String? documentDownloadUrl;
  final String? documentHash;              // SHA-256 of uploaded file

  // Admin review fields — client CANNOT write these
  final String?   verificationMethod;      // 'public_source' | 'issuer_direct' | 'qr_scan' | 'manual'
  final String?   verificationSource;      // URL admin checked
  final String?   verifiedBy;
  final DateTime? verifiedAt;
  final String?   standardVersion;
  final String?   reviewNotes;
  final String?   rejectionReason;

  final DateTime submittedAt;

  const CredentialRecord({
    required this.credentialId,
    required this.workerId,
    required this.skillId,
    required this.credentialType,
    required this.status,
    required this.evidenceStrength,
    required this.issuer,
    required this.issuerType,
    required this.credentialName,
    required this.qualificationCode,
    required this.credentialNumber,
    required this.holderName,
    this.issueDate,
    this.expiryDate,
    this.qrPayload,
    this.verificationUrl,
    this.documentStoragePath,
    this.documentDownloadUrl,
    this.documentHash,
    this.verificationMethod,
    this.verificationSource,
    this.verifiedBy,
    this.verifiedAt,
    this.standardVersion,
    this.reviewNotes,
    this.rejectionReason,
    required this.submittedAt,
  });

  factory CredentialRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CredentialRecord(
      credentialId:       doc.id,
      workerId:           d['workerId'] ?? '',
      skillId:            d['skillId'] ?? '',
      credentialType:     CredentialType.fromString(d['credentialType']),
      status:             CredentialStatus.fromString(d['status']),
      evidenceStrength:   EvidenceStrength.fromString(d['evidenceStrength']),
      issuer:             d['issuer'] ?? '',
      issuerType:         d['issuerType'] ?? '',
      credentialName:     d['credentialName'] ?? '',
      qualificationCode:  d['qualificationCode'] ?? '',
      credentialNumber:   d['credentialNumber'] ?? '',
      holderName:         d['holderName'] ?? '',
      issueDate:          DateParser.parse(d['issueDate']),
      expiryDate:         DateParser.parse(d['expiryDate']),
      qrPayload:          d['qrPayload'],
      verificationUrl:    d['verificationUrl'],
      documentStoragePath:d['documentStoragePath'],
      documentDownloadUrl:d['documentDownloadUrl'],
      documentHash:       d['documentHash'],
      verificationMethod: d['verificationMethod'],
      verificationSource: d['verificationSource'],
      verifiedBy:         d['verifiedBy'],
      verifiedAt:         DateParser.parse(d['verifiedAt']),
      standardVersion:    d['standardVersion'],
      reviewNotes:        d['reviewNotes'],
      rejectionReason:    d['rejectionReason'],
      submittedAt:        DateParser.parseOrDefault(d['submittedAt']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':         workerId,
    'skillId':          skillId,
    'credentialType':   credentialType.firestoreValue,
    'status':           CredentialStatus.documentSubmitted.firestoreValue,
    'evidenceStrength': EvidenceStrength.documentSubmitted.firestoreValue,
    'issuer':           issuer,
    'issuerType':       issuerType,
    'credentialName':   credentialName,
    'qualificationCode':qualificationCode,
    'credentialNumber': credentialNumber,
    'holderName':       holderName,
    if (issueDate != null)  'issueDate':  Timestamp.fromDate(issueDate!),
    if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate!),
    if (qrPayload != null)  'qrPayload':  qrPayload,
    if (verificationUrl != null) 'verificationUrl': verificationUrl,
    if (documentStoragePath != null) 'documentStoragePath': documentStoragePath,
    if (documentDownloadUrl != null) 'documentDownloadUrl': documentDownloadUrl,
    if (documentHash != null) 'documentHash': documentHash,
    'submittedAt':      FieldValue.serverTimestamp(),
  };
}
