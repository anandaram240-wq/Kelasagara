// lib/models/user_profile.dart
// Production-grade User Profile & Identity Foundation
// Strict separation of Auth Identity, App User ID, Display Name, and Role (Change 2)

import 'package:flutter/material.dart';
import 'date_parser.dart';

// ── Account Status State Machine ────────────────────────────────────────────
// pending_profile  → new user, hasn't completed registration form yet
// pending_face     → registration done, face verification not completed
// pending_review   → face done, waiting for admin approval
// approved         → admin approved, full marketplace access
// rejected         → admin rejected, shown rejection reason
// suspended        → access suspended, shown suspension reason
// blocked          → permanent ban

enum AccountStatus {
  pendingProfile,
  pendingFace,
  pendingReview,
  approved,
  rejected,
  suspended,
  blocked,
  unknown;

  static AccountStatus fromString(String? s) => switch (s) {
    'pending_profile' => pendingProfile,
    'pending_face'    => pendingFace,
    'pending_review'  => pendingReview,
    'approved'        => approved,
    'rejected'        => rejected,
    'suspended'       => suspended,
    'blocked'         => blocked,
    _                 => unknown,
  };

  String get value => switch (this) {
    pendingProfile => 'pending_profile',
    pendingFace    => 'pending_face',
    pendingReview  => 'pending_review',
    approved       => 'approved',
    rejected       => 'rejected',
    suspended      => 'suspended',
    blocked        => 'blocked',
    unknown        => 'unknown',
  };

  String get displayLabel => switch (this) {
    pendingProfile => 'Pending Profile Setup',
    pendingFace    => 'Identity Verification Required',
    pendingReview  => 'Under Review',
    approved       => 'Approved & Active',
    rejected       => 'Application Rejected',
    suspended      => 'Account Suspended',
    blocked        => 'Account Blocked',
    unknown        => 'Status Unknown',
  };

  String get displayLabelKn => switch (this) {
    pendingProfile => 'ಪ್ರೊಫೈಲ್ ಅಪೂರ್ಣ',
    pendingFace    => 'ಮುಖ ದೃಢೀಕರಣ ಬಾಕಿ',
    pendingReview  => 'ಪರಿಶೀಲನೆಯಲ್ಲಿದೆ',
    approved       => 'ಅನುಮೋದಿಸಲಾಗಿದೆ',
    rejected       => 'ತಿರಸ್ಕರಿಸಲಾಗಿದೆ',
    suspended      => 'ಅಮಾನತುಗೊಳಿಸಲಾಗಿದೆ',
    blocked        => 'ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ',
    unknown        => 'ಅಪರಿಚಿತ ಸ್ಥಿತಿ',
  };
}

class MissingProfileItem {
  final String key;
  final String label;
  final String labelKn;
  final IconData icon;
  final int weight;

  const MissingProfileItem({
    required this.key,
    required this.label,
    required this.labelKn,
    required this.icon,
    required this.weight,
  });
}

class ProfileCompletionResult {
  final int percentage;
  final List<MissingProfileItem> missingItems;

  const ProfileCompletionResult({
    required this.percentage,
    required this.missingItems,
  });

  bool get isComplete => percentage >= 100;
}

// ── User Profile Model ───────────────────────────────────────────────────────
class UserProfile {
  final String uid;                   // Firebase Auth UID (Private internal)
  final String userId;                // Public Kelasagara User ID (e.g. ravi_painter)
  final String normalizedUserId;      // Canonical lowercase index
  final String displayName;           // User display name (English, Kannada, etc.)
  final String phone;
  final String email;
  final String role;                  // 'worker' | 'hirer' | 'admin'
  final String photoUrl;              // Profile avatar URL
  final String district;
  final String taluk;
  final String village;
  final String bio;                   // Short biography/introduction
  final List<String> languages;        // Languages spoken (e.g. Kannada, English)
  final List<String> skills;          // Selected occupational skill IDs
  final double rating;
  final int totalJobs;
  final bool isAvailable;             // Worker availability toggle
  final bool faceVerified;            // Identity / liveness verified (Face)
  final bool skillVerified;           // Occupational skill assessed / certified
  final String facePhotoUrl;          // Liveness capture reference
  final AccountStatus accountStatus;
  final String rejectionReason;
  final String suspensionReason;
  final int dailyRate;
  final String fcmToken;
  final bool onboardingComplete;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ── Experience & Rating Breakdown ──────────────────────────────────────────
  final int experienceYears;          // e.g. 5
  final String experienceLevel;       // e.g. '5-10 years'
  final int totalRatings;             // Count of reviews received
  final double ratingSum;             // Sum of star ratings received

  // ── Phase 3: Discovery Location ─────────────────────────────────────────────
  // SEPARATE from district/taluk (profile location) and liveTracking (active job).
  // Only populated when worker explicitly enables Available Now.
  // See docs/kelasagara_location_discovery_contract.md
  final double? discoveryLat;         // GPS lat when worker is available (null if not set)
  final double? discoveryLng;         // GPS lng when worker is available (null if not set)
  final DateTime? discoveryUpdatedAt; // When discovery location was last written by WorkerAvailabilityService
  final String discoverySessionId;    // Availability session token (multi-device ownership)
  final double discoveryAccuracy;     // GPS accuracy at last update (metres; 0.0 if not set)
  final int serviceRadiusKm;          // Worker's declared service radius (km, default 15)
  final bool isSeedData;              // Gate 3 Quarantine: synthetic benchmark data flag

  const UserProfile({
    required this.uid,
    this.userId = '',
    this.normalizedUserId = '',
    this.displayName = '',
    this.phone = '',
    this.email = '',
    this.role = 'worker',
    this.photoUrl = '',
    this.district = '',
    this.taluk = '',
    this.village = '',
    this.bio = '',
    this.languages = const ['Kannada', 'English'],
    this.skills = const [],
    this.rating = 0.0,
    this.totalJobs = 0,
    this.isAvailable = true,
    this.faceVerified = false,
    this.skillVerified = false,
    this.facePhotoUrl = '',
    this.accountStatus = AccountStatus.pendingProfile,
    this.rejectionReason = '',
    this.suspensionReason = '',
    this.dailyRate = 700,
    this.fcmToken = '',
    this.onboardingComplete = false,
    this.createdAt,
    this.updatedAt,
    this.experienceYears = 0,
    this.experienceLevel = '',
    this.totalRatings = 0,
    this.ratingSum = 0.0,
    this.discoveryLat,
    this.discoveryLng,
    this.discoveryUpdatedAt,
    this.discoverySessionId = '',
    this.discoveryAccuracy = 0.0,
    this.serviceRadiusKm = 15,
    this.isSeedData = false,
  });

  // Alias for backward compatibility with old code referencing `name`
  String get name => displayName;

  // Gate 3 Quarantine: Identify synthetic test fixtures
  bool get isSynthetic => uid.startsWith('seed_') || isSeedData;

  // Convenience getters for skill & experience hierarchy
  String get primarySkillId => skills.isNotEmpty ? skills.first : '';
  List<String> get secondarySkillIds =>
      skills.length > 1 ? skills.sublist(1) : const [];

  String get experienceDisplay {
    if (experienceLevel.isNotEmpty) return experienceLevel;
    if (experienceYears > 0) return '$experienceYears+ years';
    return '';
  }

  bool get hasReviews => totalRatings > 0;
  bool get isApproved => accountStatus == AccountStatus.approved;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> d) {
    final ratingSum = ((d['ratingSum'] ?? 0) as num).toDouble();
    final totalRatings = ((d['totalRatings'] ?? 0) as num).toInt();
    final computedRating = totalRatings > 0 ? ratingSum / totalRatings : ((d['rating'] ?? 0.0) as num).toDouble();

    DateTime? parseDate(dynamic v) => DateParser.parse(v);

    final photo = (d['photoUrl'] ?? d['facePhotoUrl'] ?? '').toString();
    final displayName = (d['displayName'] ?? d['name'] ?? '').toString();
    final email = (d['email'] ?? '').toString();

    // Deterministic fallback for userId if not present in legacy doc
    String resolvedUserId = (d['userId'] ?? '').toString().trim();
    String resolvedNormalizedUserId = (d['normalizedUserId'] ?? '').toString().trim();
    if (resolvedUserId.isEmpty) {
      if (displayName.isNotEmpty) {
        resolvedUserId = displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        resolvedUserId = resolvedUserId.replaceAll(RegExp(r'^_+|_+$'), '');
        if (resolvedUserId.length < 3) resolvedUserId = '${resolvedUserId}worker';
      } else if (email.isNotEmpty && email.contains('@')) {
        resolvedUserId = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        resolvedUserId = resolvedUserId.replaceAll(RegExp(r'^_+|_+$'), '');
        if (resolvedUserId.length < 3) resolvedUserId = '${resolvedUserId}worker';
      } else {
        final shortUid = uid.length >= 6 ? uid.substring(0, 6).toLowerCase() : uid.toLowerCase();
        resolvedUserId = 'user_$shortUid';
      }
      resolvedNormalizedUserId = resolvedUserId.toLowerCase();
    }

    final rawStatus = d['accountStatus'] as String?;
    AccountStatus status = AccountStatus.fromString(rawStatus);

    final rawSkills = List<String>.from(d['skills'] ?? []);
    final rawDistrict = (d['district'] ?? '').toString().trim();
    final isExplicitOnboardingDone = d['onboardingComplete'] == true;
    final isFaceDone = d['faceVerified'] == true;

    // Backward compatibility: If an old worker has skills, district, or onboardingComplete,
    // they are an existing registered user and must NEVER be treated as pendingProfile!
    if (status == AccountStatus.unknown || status == AccountStatus.pendingProfile) {
      if (rawSkills.isNotEmpty || rawDistrict.isNotEmpty || isExplicitOnboardingDone) {
        if (isFaceDone || isExplicitOnboardingDone) {
          status = AccountStatus.approved;
        } else if (d['facePhotoUrl'] != null && d['facePhotoUrl'].toString().isNotEmpty) {
          status = AccountStatus.pendingReview;
        } else {
          status = AccountStatus.approved; // Default legacy registered workers to approved
        }
      }
    }

    return UserProfile(
      uid: uid,
      userId: resolvedUserId,
      normalizedUserId: resolvedNormalizedUserId,
      displayName: displayName,
      phone: (d['phone'] ?? '').toString(),
      email: email,
      role: (d['role'] ?? 'worker').toString(),
      photoUrl: photo,
      district: rawDistrict,
      taluk: (d['taluk'] ?? '').toString(),
      village: (d['village'] ?? '').toString(),
      bio: (d['bio'] ?? '').toString(),
      languages: (d['languages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (d['language'] != null && d['language'].toString().isNotEmpty
              ? [d['language'].toString()]
              : const ['Kannada', 'English']),
      skills: rawSkills,
      rating: computedRating,
      totalJobs: ((d['totalJobs'] ?? 0) as num).toInt(),
      isAvailable: d['isAvailable'] ?? true,
      faceVerified: isFaceDone,
      skillVerified: d['skillVerified'] ?? false,
      facePhotoUrl: (d['facePhotoUrl'] ?? photo).toString(),
      accountStatus: status,
      rejectionReason: (d['rejectionReason'] ?? '').toString(),
      suspensionReason: (d['suspensionReason'] ?? '').toString(),
      dailyRate: ((d['dailyRate'] ?? 700) as num).toInt(),
      fcmToken: (d['fcmToken'] ?? '').toString(),
      onboardingComplete: isExplicitOnboardingDone || (status == AccountStatus.approved) || rawSkills.isNotEmpty,
      createdAt: parseDate(d['createdAt']),
      updatedAt: parseDate(d['updatedAt']),
      experienceYears: ((d['experienceYears'] ?? 0) as num).toInt(),
      experienceLevel: (d['experienceLevel'] ?? '').toString(),
      totalRatings: totalRatings,
      ratingSum: ratingSum,
      discoveryLat: (d['discoveryLat'] as num?)?.toDouble() ?? (d['lat'] as num?)?.toDouble(),
      discoveryLng: (d['discoveryLng'] as num?)?.toDouble() ?? (d['lng'] as num?)?.toDouble(),
      discoveryUpdatedAt: parseDate(d['discoveryUpdatedAt']),
      discoverySessionId: (d['discoverySessionId'] ?? '').toString(),
      discoveryAccuracy: ((d['discoveryAccuracy'] ?? 0.0) as num).toDouble(),
      serviceRadiusKm: ((d['serviceRadiusKm'] ?? 15) as num).toInt(),
      isSeedData: d['isSeedData'] == true || uid.startsWith('seed_'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'userId': userId,
      'normalizedUserId': normalizedUserId,
      'displayName': displayName,
      'name': displayName, // Maintain compatibility
      'phone': phone,
      'email': email,
      'role': role,
      'photoUrl': photoUrl,
      'district': district,
      'taluk': taluk,
      'village': village,
      'bio': bio,
      'languages': languages,
      'skills': skills,
      'rating': rating,
      'totalJobs': totalJobs,
      'isAvailable': isAvailable,
      'faceVerified': faceVerified,
      'skillVerified': skillVerified,
      'facePhotoUrl': facePhotoUrl,
      'accountStatus': accountStatus.value,
      'rejectionReason': rejectionReason,
      'suspensionReason': suspensionReason,
      'dailyRate': dailyRate,
      'experienceYears': experienceYears,
      'experienceLevel': experienceLevel,
      'totalRatings': totalRatings,
      'ratingSum': ratingSum,
      'fcmToken': fcmToken,
      'onboardingComplete': onboardingComplete,
      if (discoveryLat != null) 'discoveryLat': discoveryLat,
      if (discoveryLng != null) 'discoveryLng': discoveryLng,
      if (discoveryUpdatedAt != null) 'discoveryUpdatedAt': discoveryUpdatedAt,
      'discoverySessionId': discoverySessionId,
      'discoveryAccuracy': discoveryAccuracy,
      'serviceRadiusKm': serviceRadiusKm,
    };
  }

  /// Calculates profile completion percentage based on concrete required fields (Section 34 & 70)
  ProfileCompletionResult calculateProfileCompletion() {
    final missing = <MissingProfileItem>[];
    int score = 0;

    // Display Name (15 pts)
    if (displayName.trim().isNotEmpty) {
      score += 15;
    } else {
      missing.add(const MissingProfileItem(
        key: 'displayName',
        label: 'Add Display Name',
        labelKn: 'ಹೆಸರನ್ನು ಸೇರಿಸಿ',
        icon: Icons.person_outline,
        weight: 15,
      ));
    }

    // Unique User ID (15 pts)
    if (userId.trim().isNotEmpty) {
      score += 15;
    } else {
      missing.add(const MissingProfileItem(
        key: 'userId',
        label: 'Choose @User ID',
        labelKn: 'ಬಳಕೆದಾರ ಐಡಿ ಆಯ್ಕೆಮಾಡಿ',
        icon: Icons.alternate_email,
        weight: 15,
      ));
    }

    // Location: District & Taluk (20 pts)
    if (district.trim().isNotEmpty) {
      score += 10;
      if (taluk.trim().isNotEmpty) {
        score += 10;
      } else {
        missing.add(const MissingProfileItem(
          key: 'taluk',
          label: 'Select Taluk',
          labelKn: 'ತಾಲ್ಲೂಕು ಆಯ್ಕೆಮಾಡಿ',
          icon: Icons.location_on_outlined,
          weight: 10,
        ));
      }
    } else {
      missing.add(const MissingProfileItem(
        key: 'location',
        label: 'Set Service Area',
        labelKn: 'ಸೇವಾ ಪ್ರದೇಶವನ್ನು ಹೊಂದಿಸಿ',
        icon: Icons.location_on_outlined,
        weight: 20,
      ));
    }

    // Role-specific evaluation
    if (role == 'worker') {
      // Skills (20 pts)
      if (skills.isNotEmpty) {
        score += 20;
      } else {
        missing.add(const MissingProfileItem(
          key: 'skills',
          label: 'Add Occupational Skills',
          labelKn: 'ಕೌಶಲ್ಯಗಳನ್ನು ಆಯ್ಕೆಮಾಡಿ',
          icon: Icons.build_outlined,
          weight: 20,
        ));
      }

      // Bio (10 pts)
      if (bio.trim().isNotEmpty) {
        score += 10;
      } else {
        missing.add(const MissingProfileItem(
          key: 'bio',
          label: 'Write Short Work Bio',
          labelKn: 'ಕಿರು ವಿವರಣೆ ಬರೆಯಿರಿ',
          icon: Icons.description_outlined,
          weight: 10,
        ));
      }

      // Work Experience (10 pts) - reallocated from photo
      if (experienceYears > 0 || experienceLevel.trim().isNotEmpty) {
        score += 10;
      } else {
        missing.add(const MissingProfileItem(
          key: 'experience',
          label: 'Add Work Experience',
          labelKn: 'ಅನುಭವದ ವಿವರ ನಮೂದಿಸಿ',
          icon: Icons.work_history_outlined,
          weight: 10,
        ));
      }

      // Phone Number Verified (SMS OTP Authentication) (10 pts)
      if (phone.trim().isNotEmpty) {
        score += 10;
      } else {
        missing.add(const MissingProfileItem(
          key: 'phone',
          label: 'Verify Phone Number',
          labelKn: 'ಮೊಬೈಲ್ ಸಂಖ್ಯೆ ದೃಢೀಕರಿಸಿ',
          icon: Icons.phone_android_outlined,
          weight: 10,
        ));
      }
    } else {
      // Hirer evaluation
      // Bio / Business description (25 pts)
      if (bio.trim().isNotEmpty) {
        score += 25;
      } else {
        missing.add(const MissingProfileItem(
          key: 'bio',
          label: 'Add Business/Home Bio',
          labelKn: 'ವಿವರಣೆ ಸೇರಿಸಿ',
          icon: Icons.description_outlined,
          weight: 25,
        ));
      }

      // Contact phone/email verified (25 pts)
      if (phone.trim().isNotEmpty || email.trim().isNotEmpty) {
        score += 25;
      } else {
        missing.add(const MissingProfileItem(
          key: 'contact',
          label: 'Add Contact Details',
          labelKn: 'ಸಂಪರ್ಕ ವಿವರ ಸೇರಿಸಿ',
          icon: Icons.phone_outlined,
          weight: 25,
        ));
      }
    }

    if (score > 100) score = 100;
    return ProfileCompletionResult(
      percentage: score,
      missingItems: missing,
    );
  }

  UserProfile copyWith({
    String? userId,
    String? normalizedUserId,
    String? displayName,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? photoUrl,
    String? district,
    String? taluk,
    String? village,
    String? bio,
    List<String>? languages,
    List<String>? skills,
    double? rating,
    int? totalJobs,
    bool? isAvailable,
    bool? faceVerified,
    bool? skillVerified,
    String? facePhotoUrl,
    AccountStatus? accountStatus,
    String? rejectionReason,
    String? suspensionReason,
    int? dailyRate,
    String? fcmToken,
    bool? onboardingComplete,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? experienceYears,
    String? experienceLevel,
    int? totalRatings,
    double? ratingSum,
    double? discoveryLat,
    double? discoveryLng,
    DateTime? discoveryUpdatedAt,
    String? discoverySessionId,
    double? discoveryAccuracy,
    int? serviceRadiusKm,
  }) {
    return UserProfile(
      uid: uid,
      userId: userId ?? this.userId,
      normalizedUserId: normalizedUserId ?? this.normalizedUserId,
      displayName: displayName ?? name ?? this.displayName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      district: district ?? this.district,
      taluk: taluk ?? this.taluk,
      village: village ?? this.village,
      bio: bio ?? this.bio,
      languages: languages ?? this.languages,
      skills: skills ?? this.skills,
      rating: rating ?? this.rating,
      totalJobs: totalJobs ?? this.totalJobs,
      isAvailable: isAvailable ?? this.isAvailable,
      faceVerified: faceVerified ?? this.faceVerified,
      skillVerified: skillVerified ?? this.skillVerified,
      facePhotoUrl: facePhotoUrl ?? this.facePhotoUrl,
      accountStatus: accountStatus ?? this.accountStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      suspensionReason: suspensionReason ?? this.suspensionReason,
      dailyRate: dailyRate ?? this.dailyRate,
      experienceYears: experienceYears ?? this.experienceYears,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      totalRatings: totalRatings ?? this.totalRatings,
      ratingSum: ratingSum ?? this.ratingSum,
      fcmToken: fcmToken ?? this.fcmToken,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      discoveryLat: discoveryLat ?? this.discoveryLat,
      discoveryLng: discoveryLng ?? this.discoveryLng,
      discoveryUpdatedAt: discoveryUpdatedAt ?? this.discoveryUpdatedAt,
      discoverySessionId: discoverySessionId ?? this.discoverySessionId,
      discoveryAccuracy: discoveryAccuracy ?? this.discoveryAccuracy,
      serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
    );
  }
}
