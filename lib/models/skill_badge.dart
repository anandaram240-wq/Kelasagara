// lib/models/skill_badge.dart
// Skill badges — backend controlled only.
// Client CANNOT create or modify badges.
// Every badge must reference its evidence source.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'date_parser.dart';

enum BadgeType {
  identityVerified,
  workerRegistrationVerified,
  credentialVerified,
  skillVerifiedCredential,
  skillVerifiedAssessment,
  experienceJobs,         // n verified jobs in occupation
  licenseVerified;

  String get firestoreValue => name;

  String get displayName => switch (this) {
    identityVerified          => 'Phone Number Verified',
    workerRegistrationVerified=> 'Kelasagara Account Approved',
    credentialVerified        => 'External Certificate Verified',
    skillVerifiedCredential   => 'External Certificate Verified',
    skillVerifiedAssessment   => 'Kelasagara Assessed Skill Record',
    experienceJobs            => 'Verified Work Experience',
    licenseVerified           => 'Trade License Verified',
  };

  // Whether the badge represents professional competency
  // (not just identity or registration)
  bool get isCompetencyBadge => this == skillVerifiedCredential || this == skillVerifiedAssessment;

  static BadgeType fromString(String? s) {
    try { return BadgeType.values.firstWhere((e) => e.name == s); }
    catch (_) { return BadgeType.identityVerified; }
  }
}

enum BadgeStatus {
  active,
  suspended,
  expired,
  revoked;

  String get firestoreValue => name;
  static BadgeStatus fromString(String? s) {
    try { return BadgeStatus.values.firstWhere((e) => e.name == s); }
    catch (_) { return BadgeStatus.active; }
  }
}

class SkillBadge {
  final String     badgeId;
  final String     workerId;
  final String?    skillId;          // null for non-skill badges
  final BadgeType  type;
  final BadgeStatus status;

  // Evidence references — every badge must have at least one
  final String?    credentialVerificationId;
  final String?    assessmentId;
  final String?    assessorId;
  final String?    registrationId;

  // Assessment metadata for competency badges
  final String?    standardVersion;
  final String?    assessmentVersion;
  final String?    verificationBasis; // 'credential' | 'assessment' | 'registration'

  // Experience badge metadata
  final int?       jobCount;
  final int?       jobCountThreshold; // 1, 5, 10, 25

  // Validity
  final DateTime   earnedAt;
  final DateTime?  expiresAt;
  final bool       revocable;

  const SkillBadge({
    required this.badgeId,
    required this.workerId,
    this.skillId,
    required this.type,
    required this.status,
    this.credentialVerificationId,
    this.assessmentId,
    this.assessorId,
    this.registrationId,
    this.standardVersion,
    this.assessmentVersion,
    this.verificationBasis,
    this.jobCount,
    this.jobCountThreshold,
    required this.earnedAt,
    this.expiresAt,
    required this.revocable,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isActive  => status == BadgeStatus.active && !isExpired;

  factory SkillBadge.fromMap(String id, Map<String, dynamic> d) {
    return SkillBadge(
      badgeId:                   id,
      workerId:                  d['workerId'] ?? '',
      skillId:                   d['skillId'],
      type:                      BadgeType.fromString(d['type'] ?? 'identityVerified'),
      status:                    BadgeStatus.fromString(d['status'] ?? 'active'),
      credentialVerificationId:  d['credentialVerificationId'],
      assessmentId:              d['assessmentId'],
      assessorId:                d['assessorId'],
      registrationId:            d['registrationId'],
      standardVersion:           d['standardVersion'],
      assessmentVersion:         d['assessmentVersion'],
      verificationBasis:         d['verificationBasis'],
      jobCount:                  d['jobCount'] as int?,
      jobCountThreshold:         d['jobCountThreshold'] as int?,
      earnedAt:                  DateParser.parseOrDefault(d['earnedAt']),
      expiresAt:                 DateParser.parse(d['expiresAt']),
      revocable:                 d['revocable'] == true,
    );
  }

  factory SkillBadge.fromFirestore(DocumentSnapshot doc) {
    return SkillBadge.fromMap(doc.id, (doc.data() as Map<String, dynamic>?) ?? {});
  }

  // Describes why this skill was verified
  String get verificationExplanation {
    switch (type) {
      case BadgeType.skillVerifiedCredential:
        return 'Basis: Credential Verification\n'
               'Credential ID: ${credentialVerificationId ?? "—"}\n'
               'Standard: ${standardVersion ?? "—"}';
      case BadgeType.skillVerifiedAssessment:
        return 'Basis: Practical Competency Assessment\n'
               'Assessment ID: ${assessmentId ?? "—"}\n'
               'Assessor: ${assessorId ?? "—"}\n'
               'Standard: ${standardVersion ?? "—"}\n'
               'Version: ${assessmentVersion ?? "—"}';
      case BadgeType.workerRegistrationVerified:
        return 'Basis: Worker Registration Verification\n'
               'Registration ID: ${registrationId ?? "—"}';
      case BadgeType.experienceJobs:
        return 'Basis: Verified Kelasagara Work\n'
               '${jobCount ?? 0} verified jobs in occupation';
      default:
        return 'Basis: ${verificationBasis ?? type.displayName}';
    }
  }

  Color get badgeColor => switch (type) {
    BadgeType.skillVerifiedCredential  => const Color(0xFF10B981), // emerald
    BadgeType.skillVerifiedAssessment  => const Color(0xFF10B981),
    BadgeType.credentialVerified       => const Color(0xFF3B82F6), // blue
    BadgeType.identityVerified         => const Color(0xFF8B5CF6), // purple
    BadgeType.workerRegistrationVerified => const Color(0xFFF59E0B), // amber
    BadgeType.experienceJobs           => const Color(0xFFEC4899), // pink
    BadgeType.licenseVerified          => const Color(0xFF06B6D4), // cyan
  };
}
