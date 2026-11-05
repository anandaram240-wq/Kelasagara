// test/legacy_worker_auth_routing_test.dart
// Production verification that existing/old workers signing in with Gmail
// are NEVER asked for registration again.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';

void main() {
  group('Legacy Worker Auth & Profile Invariant Tests', () {
    test('Old worker with skills and district but no userId parses safely as approved with fallback userId', () {
      final legacyWorkerData = <String, dynamic>{
        'displayName': 'Ramesh Kumar',
        'email': 'ramesh.worker@gmail.com',
        'phone': '9876543210',
        'role': 'worker',
        'district': 'Hassan',
        'taluk': 'Channarayapatna',
        'skills': ['carpenter', 'mason'],
        // Note: userId and accountStatus are absent in older Firestore docs
      };

      final profile = UserProfile.fromMap('uid_ramesh_12345', legacyWorkerData);

      expect(profile.uid, equals('uid_ramesh_12345'));
      expect(profile.displayName, equals('Ramesh Kumar'));
      expect(profile.skills, contains('carpenter'));
      expect(profile.district, equals('Hassan'));
      // Fallback userId generated from displayName without spaces
      expect(profile.userId, isNotEmpty);
      expect(profile.userId, equals('ramesh_kumar'));
      // Auto-recovered account status is approved
      expect(profile.accountStatus, equals(AccountStatus.approved));
      expect(profile.isApproved, isTrue);
      expect(profile.onboardingComplete, isTrue);
    });

    test('Old worker with only email and skills receives safe sanitized fallback userId', () {
      final legacyData = <String, dynamic>{
        'email': 'ananda.electrician@gmail.com',
        'skills': ['electrician'],
        'district': 'Bengaluru Urban',
        'role': 'worker',
      };

      final profile = UserProfile.fromMap('uid_anand_789', legacyData);

      expect(profile.userId, equals('ananda_electrician'));
      expect(profile.accountStatus, equals(AccountStatus.approved));
      expect(profile.onboardingComplete, isTrue);
    });

    test('Old worker without accountStatus field is recognized as existing registered worker', () {
      final legacyData = <String, dynamic>{
        'displayName': 'Manjunath',
        'role': 'worker',
        'skills': ['plumber'],
        'district': 'Mysuru',
        'faceVerified': true,
      };

      final profile = UserProfile.fromMap('uid_manju_456', legacyData);

      expect(profile.isApproved, isTrue);
      expect(profile.accountStatus, equals(AccountStatus.approved));
    });

    test('Brand new user without skills or district remains pendingProfile', () {
      final newUserData = <String, dynamic>{
        'displayName': 'New Visitor',
        'email': 'newvisitor@gmail.com',
        'role': 'worker',
        'accountStatus': 'pending_profile',
        'skills': <String>[],
        'district': '',
      };

      final profile = UserProfile.fromMap('uid_new_999', newUserData);

      expect(profile.accountStatus, equals(AccountStatus.pendingProfile));
      expect(profile.isApproved, isFalse);
      expect(profile.onboardingComplete, isFalse);
    });
  });
}
