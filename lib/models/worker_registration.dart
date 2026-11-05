// lib/models/worker_registration.dart
// Evidence of worker registration (e-Shram, Karnataka BOCW, other).
// IMPORTANT: Worker registration DOES NOT equal occupational competency.
// This verifies registration evidence ONLY.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_parser.dart';

enum RegistrationType {
  eShram,
  karnatakaBocw,
  other;

  String get firestoreValue => switch (this) {
    eShram         => 'e_shram',
    karnatakaBocw => 'karnataka_bocw',
    other          => 'other',
  };

  String get displayName => switch (this) {
    eShram         => 'e-Shram Registration',
    karnatakaBocw => 'Karnataka BOCW Registration',
    other          => 'Other Registration',
  };

  static RegistrationType fromString(String? s) => switch (s) {
    'e_shram'        => eShram,
    'karnataka_bocw' => karnatakaBocw,
    _                => other,
  };
}

enum RegistrationStatus {
  notSubmitted,
  submitted,
  underReview,
  sourceChecked,
  verified,
  rejected,
  expired,
  unableToVerify;

  String get firestoreValue => switch (this) {
    notSubmitted    => 'not_submitted',
    submitted       => 'submitted',
    underReview     => 'under_review',
    sourceChecked   => 'source_checked',
    verified        => 'verified',
    rejected        => 'rejected',
    expired         => 'expired',
    unableToVerify  => 'unable_to_verify',
  };

  String get displayLabel => switch (this) {
    notSubmitted    => 'Not Submitted',
    submitted       => 'Submitted — Pending Review',
    underReview     => 'Under Review',
    sourceChecked   => 'Source Checked',
    verified        => 'Registration Verified',
    rejected        => 'Rejected',
    expired         => 'Expired',
    unableToVerify  => 'Unable to Verify',
  };

  bool get isPositive => this == verified || this == sourceChecked;
  bool get isPending  => this == submitted || this == underReview;

  static RegistrationStatus fromString(String? s) => switch (s) {
    'not_submitted'   => notSubmitted,
    'submitted'       => submitted,
    'under_review'    => underReview,
    'source_checked'  => sourceChecked,
    'verified'        => verified,
    'rejected'        => rejected,
    'expired'         => expired,
    'unable_to_verify'=> unableToVerify,
    _                 => notSubmitted,
  };
}

class WorkerRegistration {
  final String           workerId;
  final RegistrationType registrationType;
  final RegistrationStatus status;

  // Worker-provided reference (UAN, card number, etc.)
  final String referenceNumber;

  // Occupation as declared on the registration card
  // IMPORTANT: This is the occupation on the registration only.
  // It does NOT represent verified professional skill.
  final String declaredOccupation;

  // Firebase Storage path to uploaded document image
  final String? documentStoragePath;
  final String? documentDownloadUrl;

  // Admin review fields — only admin can write these
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? sourceUrl;          // URL admin used to verify
  final String? reviewNotes;
  final String? rejectionReason;

  final DateTime submittedAt;
  final DateTime? updatedAt;

  const WorkerRegistration({
    required this.workerId,
    required this.registrationType,
    required this.status,
    required this.referenceNumber,
    required this.declaredOccupation,
    this.documentStoragePath,
    this.documentDownloadUrl,
    this.reviewedBy,
    this.reviewedAt,
    this.sourceUrl,
    this.reviewNotes,
    this.rejectionReason,
    required this.submittedAt,
    this.updatedAt,
  });

  factory WorkerRegistration.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WorkerRegistration(
      workerId:             d['workerId'] ?? doc.id,
      registrationType:     RegistrationType.fromString(d['registrationType']),
      status:               RegistrationStatus.fromString(d['status']),
      referenceNumber:      d['referenceNumber'] ?? '',
      declaredOccupation:   d['declaredOccupation'] ?? '',
      documentStoragePath:  d['documentStoragePath'],
      documentDownloadUrl:  d['documentDownloadUrl'],
      reviewedBy:           d['reviewedBy'],
      reviewedAt:           DateParser.parse(d['reviewedAt']),
      sourceUrl:            d['sourceUrl'],
      reviewNotes:          d['reviewNotes'],
      rejectionReason:      d['rejectionReason'],
      submittedAt:          DateParser.parseOrDefault(d['submittedAt']),
      updatedAt:            DateParser.parse(d['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
    'workerId':           workerId,
    'registrationType':   registrationType.firestoreValue,
    'status':             RegistrationStatus.submitted.firestoreValue,
    'referenceNumber':    referenceNumber,
    'declaredOccupation': declaredOccupation,
    if (documentStoragePath != null) 'documentStoragePath': documentStoragePath,
    if (documentDownloadUrl != null) 'documentDownloadUrl': documentDownloadUrl,
    'submittedAt':        FieldValue.serverTimestamp(),
    'updatedAt':          FieldValue.serverTimestamp(),
  };
}
