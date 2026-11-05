enum MarketplaceRole {
  worker,
  hirer,
}

enum AccountBiometricLifecycleStatus {
  faceNotEnrolledLegacy, // Journey C: "Set up face verification / ಮುಖ ಪರಿಶೀಲನೆ ಸಕ್ರಿಯಗೊಳಿಸಿ"
  faceEnrollmentRequired, // Journey A: New registration
  enrolledActive, // Journey D: 1:1 verification ready
  potentialExistingRegistration, // Journey B: Step-up or review required
  reenrollmentInProgress, // Journey E: Phone replacement / template update
  alternateKycPendingOrActive, // Journey F: Non-biometric KYC path
  templateRevokedOrDeleted,
}

class MaskedAccountHintV19 {
  final String referenceCode;
  final List<MarketplaceRole> existingRoles;

  const MaskedAccountHintV19({
    required this.referenceCode,
    required this.existingRoles,
  });

  factory MaskedAccountHintV19.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawRoles =
        (json['existingRoles'] as List<dynamic>?) ?? const <dynamic>[];
    return MaskedAccountHintV19(
      referenceCode: (json['referenceCode'] as String?) ?? 'KLS-REV-PENDING',
      existingRoles: rawRoles
          .map((dynamic r) =>
              r == 'HIRER' ? MarketplaceRole.hirer : MarketplaceRole.worker)
          .toList(growable: false),
    );
  }
}

class PotentialExistingRegistrationDtoV19 {
  final String disclosureStage;
  final List<String> nextSteps;
  final MaskedAccountHintV19? maskedAccountHint;
  final String reviewCaseId;

  const PotentialExistingRegistrationDtoV19({
    required this.disclosureStage,
    required this.nextSteps,
    required this.reviewCaseId,
    this.maskedAccountHint,
  });

  bool get requiresStepUpBeforeShowingHint =>
      disclosureStage == 'STEP_UP_REQUIRED_NO_PII' || maskedAccountHint == null;

  bool get canLinkSecondMarketplaceRole =>
      disclosureStage == 'DUAL_ROLE_LINK_ELIGIBLE';

  factory PotentialExistingRegistrationDtoV19.fromJson(
    Map<String, dynamic> json,
  ) {
    final Map<String, dynamic>? rawHint =
        json['maskedAccountHint'] as Map<String, dynamic>?;
    return PotentialExistingRegistrationDtoV19(
      disclosureStage:
          (json['disclosureStage'] as String?) ?? 'STEP_UP_REQUIRED_NO_PII',
      nextSteps: ((json['nextSteps'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      maskedAccountHint:
          rawHint != null ? MaskedAccountHintV19.fromJson(rawHint) : null,
      reviewCaseId: (json['reviewCaseId'] as String?) ?? '',
    );
  }
}
