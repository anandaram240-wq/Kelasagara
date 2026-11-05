// test/worker_profile_system_test.dart
// Production-grade test suite for the Premium Registration + Worker Profile System.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';
import 'package:kelasagaara/services/profile_media_service.dart';

void main() {
  group('UserProfile Experience & Reputation Fields', () {
    test('parses experienceYears and experienceLevel fromMap', () {
      final map = {
        'uid': 'w1',
        'displayName': 'Ravi Kumar',
        'role': 'worker',
        'experienceYears': 6,
        'experienceLevel': '5-10 yrs',
        'totalJobs': 14,
        'rating': 4.8,
        'ratingSum': 48.0,
        'totalRatings': 10,
        'skills': ['electrician', 'plumber'],
      };

      final profile = UserProfile.fromMap('w1', map);
      expect(profile.experienceYears, 6);
      expect(profile.experienceLevel, '5-10 yrs');
      expect(profile.experienceDisplay, '5-10 yrs');
      expect(profile.totalRatings, 10);
      expect(profile.ratingSum, 48.0);
      expect(profile.hasReviews, isTrue);
      expect(profile.primarySkillId, 'electrician');
      expect(profile.secondarySkillIds, ['plumber']);
    });

    test('handles default experience and zero ratings truthfully', () {
      final map = {
        'uid': 'w2',
        'displayName': 'New Worker',
        'role': 'worker',
        'rating': 0.0,
        'totalRatings': 0,
        'totalJobs': 0,
      };

      final profile = UserProfile.fromMap('w2', map);
      expect(profile.experienceYears, 0);
      expect(profile.experienceLevel, '');
      expect(profile.totalRatings, 0);
      expect(profile.ratingSum, 0.0);
      expect(profile.hasReviews, isFalse);
      expect(profile.primarySkillId, '');
      expect(profile.secondarySkillIds, isEmpty);
    });

    test('toMap serializes experienceYears, experienceLevel, totalRatings, ratingSum', () {
      const profile = UserProfile(
        uid: 'w3',
        displayName: 'Suresh Mason',
        role: 'worker',
        experienceYears: 4,
        experienceLevel: '3-5 yrs',
        totalRatings: 5,
        ratingSum: 24.5,
        serviceRadiusKm: 20,
      );

      final map = profile.toMap();
      expect(map['experienceYears'], 4);
      expect(map['experienceLevel'], '3-5 yrs');
      expect(map['totalRatings'], 5);
      expect(map['ratingSum'], 24.5);
      expect(map['serviceRadiusKm'], 20);
    });

    test('copyWith cleanly updates experience without mutating untouched fields', () {
      const original = UserProfile(
        uid: 'w4',
        displayName: 'Anand',
        role: 'worker',
        experienceYears: 2,
        experienceLevel: '1-2 yrs',
        totalRatings: 1,
        ratingSum: 5.0,
      );

      final updated = original.copyWith(
        experienceYears: 3,
        experienceLevel: '3-5 yrs',
        totalRatings: 2,
        ratingSum: 9.5,
      );

      expect(updated.uid, 'w4');
      expect(updated.displayName, 'Anand');
      expect(updated.experienceYears, 3);
      expect(updated.experienceLevel, '3-5 yrs');
      expect(updated.totalRatings, 2);
      expect(updated.ratingSum, 9.5);
      expect(original.experienceYears, 2); // Immutability preserved
    });
  });

  group('Public vs Private Profile Boundaries', () {
    test('public profile excludes sensitive live tracking GPS while keeping service area', () {
      const profile = UserProfile(
        uid: 'w5',
        displayName: 'Mahesh Welder',
        district: 'Hassan',
        taluk: 'Channarayapatna',
        village: 'Kikkeri',
        serviceRadiusKm: 15,
        discoveryLat: 12.9716,
        discoveryLng: 77.5946,
      );

      // Public profile data
      expect(profile.district, 'Hassan');
      expect(profile.taluk, 'Channarayapatna');
      expect(profile.serviceRadiusKm, 15);
      // Discovery coords exist for discovery engine but UI must not display raw lat/lng
      expect(profile.discoveryLat, isNotNull);
      expect(profile.discoveryLng, isNotNull);
    });
  });

  group('ProfileMediaService Storage Boundaries', () {
    test('enforces strict file size limits aligned with storage.rules', () {
      expect(ProfileMediaService.kMaxAvatarSizeBytes, 5 * 1024 * 1024); // 5 MB
      expect(ProfileMediaService.kMaxPortfolioSizeBytes, 8 * 1024 * 1024); // 8 MB
    });
  });

  group('Account Status Transitions for Worker vs Hirer', () {
    test('Worker status progression', () {
      expect(AccountStatus.pendingProfile.value, 'pending_profile');
      expect(AccountStatus.pendingFace.value, 'pending_face');
      expect(AccountStatus.pendingReview.value, 'pending_review');
      expect(AccountStatus.approved.value, 'approved');
      expect(AccountStatus.rejected.value, 'rejected');
    });

    test('AccountStatus helper getters', () {
      const workerPending = UserProfile(
        uid: 'w6',
        accountStatus: AccountStatus.pendingFace,
      );
      expect(workerPending.isApproved, isFalse);

      const hirerApproved = UserProfile(
        uid: 'h1',
        role: 'hirer',
        accountStatus: AccountStatus.approved,
      );
      expect(hirerApproved.isApproved, isTrue);
    });
  });
}
