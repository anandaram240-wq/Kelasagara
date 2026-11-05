// test/registration_security_contract_test.dart
//
// Formal security contract verification for Kelasagara registration and onboarding:
// 1. Worker Profile Submit Transition: pending_profile → pending_face
// 2. Hirer Profile Submit Transition: pending_profile → approved
// 3. Face Enrollment Transition: pending_face → pending_review (requires faceVerified=true)
// 4. Attack Prevention:
//    - Worker cannot self-assign accountStatus='approved'
//    - User cannot self-assign role='admin'
//    - Unapproved worker cannot set isAvailable=true or publish discoveryLat/discoveryLng
//    - User cannot fabricate rating, totalJobs, or verifiedWorkCount
//    - Username claimed by one user cannot be stolen or updated by another user

import 'package:flutter_test/flutter_test.dart';

enum AccountStatusContract {
  pendingProfile,
  pendingFace,
  pendingReview,
  approved,
  rejected,
  suspended,
  blocked,
  unknown,
}

class FirestoreUpdateSimulation {
  static bool evaluateUserUpdate({
    required String callerUid,
    required String targetUid,
    required bool callerIsAdmin,
    required Map<String, dynamic> existingData,
    required Map<String, dynamic> updateData,
  }) {
    if (callerIsAdmin) return true;
    if (callerUid != targetUid) return false; // not owner

    final existingStatus = existingData['accountStatus'] as String?;
    final requestedStatus = updateData.containsKey('accountStatus')
        ? updateData['accountStatus'] as String?
        : existingStatus;

    final existingRole = existingData['role'] as String?;
    final requestedRole = updateData.containsKey('role')
        ? updateData['role'] as String?
        : existingRole;

    final existingFaceVer = existingData['faceVerified'] as bool? ?? false;
    final requestedFaceVer = updateData.containsKey('faceVerified')
        ? updateData['faceVerified'] as bool? ?? false
        : existingFaceVer;

    final affectedKeys = updateData.keys.where((k) => updateData[k] != existingData[k]).toSet();

    // Check locked authority fields
    final lockedAlways = [
      'approvedBy', 'approvedAt', 'rejectedBy', 'verifiedWorkCount',
      'rating', 'ratingSum', 'totalRatings', 'totalJobs'
    ];
    if (affectedKeys.any((k) => lockedAlways.contains(k))) return false;

    // ── Branch 1: Normal profile update ──
    if (!affectedKeys.contains('accountStatus') &&
        !affectedKeys.contains('role') &&
        !affectedKeys.contains('faceVerified') &&
        !affectedKeys.contains('skillVerified')) {
      final discoveryFields = [
        'discoveryLat', 'discoveryLng', 'discoveryUpdatedAt',
        'discoverySessionId', 'discoveryAccuracy', 'isAvailable'
      ];
      final isApproved = existingStatus == 'approved';
      if (affectedKeys.any((k) => discoveryFields.contains(k)) && !isApproved) {
        return false;
      }
      return true;
    }

    // ── Branch 2A: Worker profile completion (pending_profile → pending_face) ──
    if (existingStatus == 'pending_profile' &&
        requestedStatus == 'pending_face' &&
        requestedRole == 'worker' &&
        !affectedKeys.contains('faceVerified') &&
        !affectedKeys.contains('skillVerified')) {
      final discoveryFields = [
        'discoveryLat', 'discoveryLng', 'discoveryUpdatedAt',
        'discoverySessionId', 'discoveryAccuracy', 'isAvailable'
      ];
      if (affectedKeys.any((k) => discoveryFields.contains(k))) {
        if (updateData['isAvailable'] != false) return false;
      }
      return true;
    }

    // ── Branch 2B: Hirer auto-approval (pending_profile → approved) ──
    if ((existingStatus == 'pending_profile' || existingStatus == 'pending_face') &&
        requestedStatus == 'approved' &&
        requestedRole == 'hirer' &&
        !affectedKeys.contains('faceVerified') &&
        !affectedKeys.contains('skillVerified')) {
      return true;
    }

    // ── Branch 2C: Face verification (pending_face → pending_review) ──
    if (existingStatus == 'pending_face' &&
        requestedStatus == 'pending_review' &&
        requestedFaceVer == true &&
        !affectedKeys.contains('role')) {
      return true;
    }

    return false;
  }

  static bool evaluateUsernameClaim({
    required String callerUid,
    required Map<String, dynamic>? existingDoc,
    required Map<String, dynamic> writeDoc,
  }) {
    if (existingDoc == null) {
      // Create
      return writeDoc['uid'] == callerUid &&
          (writeDoc['createdAt'] != null || writeDoc['claimedAt'] != null);
    } else {
      // Update
      return existingDoc['uid'] == callerUid && writeDoc['uid'] == callerUid;
    }
  }
}

void main() {
  group('Worker Registration & Onboarding Security Contract', () {
    const workerUid = 'worker_uid_123';

    final initialGoogleWorkerDoc = {
      'uid': workerUid,
      'displayName': 'Ramesh Kumar',
      'email': 'ramesh@example.com',
      'role': 'worker',
      'accountStatus': 'pending_profile',
      'faceVerified': false,
      'skillVerified': false,
      'isAvailable': false,
      'totalJobs': 0,
      'ratingSum': 0,
      'totalRatings': 0,
      'dailyRate': 700,
      'skills': <String>[],
    };

    test('LEGITIMATE: Worker advances from pending_profile to pending_face on profile submit', () {
      final update = {
        'displayName': 'Ramesh Kumar',
        'name': 'Ramesh Kumar',
        'role': 'worker',
        'district': 'Hassan',
        'taluk': 'Hassan',
        'village': 'Kandali',
        'skills': ['mason', 'carpenter'],
        'dailyRate': 850,
        'experienceYears': 5,
        'experienceLevel': '3-5 yrs',
        'serviceRadiusKm': 20,
        'userId': 'ramesh_mason',
        'normalizedUserId': 'ramesh_mason',
        'bio': 'Skilled bricklayer with 5 years experience',
        'photoUrl': 'https://storage.googleapis.com/profile-photos/ramesh.jpg',
        'accountStatus': 'pending_face',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: update,
      );

      expect(allowed, isTrue, reason: 'Worker must be allowed to complete profile and advance to pending_face');
    });

    test('ATTACK: Worker attempts to self-approve on profile submit (accountStatus=approved)', () {
      final maliciousUpdate = {
        'role': 'worker',
        'accountStatus': 'approved', // Attacker attempts to skip verification & review
        'skills': ['mason'],
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'Worker cannot self-approve; must go through face verification');
    });

    test('ATTACK: Worker attempts to self-assign role=admin', () {
      final maliciousUpdate = {
        'role': 'admin',
        'accountStatus': 'pending_face',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'User cannot self-promote to admin');
    });

    test('ATTACK: Unapproved worker attempts to set isAvailable=true', () {
      final maliciousUpdate = {
        'accountStatus': 'pending_face',
        'role': 'worker',
        'isAvailable': true, // Attacker attempts to broadcast availability while unapproved
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'Unapproved worker cannot set isAvailable=true');
    });

    test('ATTACK: Worker attempts to inflate ratings or job count', () {
      final maliciousUpdate = {
        'accountStatus': 'pending_face',
        'role': 'worker',
        'rating': 5.0,
        'totalJobs': 50,
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'Worker cannot self-assign ratings or total jobs');
    });

    test('ATTACK: Worker attempts to claim faceVerified=true during profile submit', () {
      final maliciousUpdate = {
        'accountStatus': 'pending_face',
        'role': 'worker',
        'faceVerified': true, // Attacker attempts to forge face verification
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: initialGoogleWorkerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'Worker cannot set faceVerified during profile submit');
    });
  });

  group('Hirer Onboarding Security Contract', () {
    const hirerUid = 'hirer_uid_456';

    final initialGoogleHirerDoc = {
      'uid': hirerUid,
      'displayName': 'Suresh Gowda',
      'email': 'suresh@example.com',
      'role': 'worker', // Google sign-in default
      'accountStatus': 'pending_profile',
      'faceVerified': false,
      'skillVerified': false,
      'isAvailable': false,
      'totalJobs': 0,
      'ratingSum': 0,
      'totalRatings': 0,
    };

    test('LEGITIMATE: Hirer completes onboarding and auto-approves', () {
      final hirerUpdate = {
        'displayName': 'Suresh Gowda',
        'name': 'Suresh Gowda',
        'role': 'hirer',
        'district': 'Mysuru',
        'taluk': 'Mysuru',
        'userId': 'suresh_builder',
        'normalizedUserId': 'suresh_builder',
        'accountStatus': 'approved',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: hirerUid,
        targetUid: hirerUid,
        callerIsAdmin: false,
        existingData: initialGoogleHirerDoc,
        updateData: hirerUpdate,
      );

      expect(allowed, isTrue, reason: 'Hirers are auto-approved upon completing profile');
    });

    test('ATTACK: Hirer attempts to set admin role during onboarding', () {
      final maliciousUpdate = {
        'role': 'admin',
        'accountStatus': 'approved',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: hirerUid,
        targetUid: hirerUid,
        callerIsAdmin: false,
        existingData: initialGoogleHirerDoc,
        updateData: maliciousUpdate,
      );

      expect(allowed, isFalse, reason: 'Hirer cannot set role to admin');
    });
  });

  group('Face Verification Transition Contract', () {
    const workerUid = 'worker_uid_789';

    final pendingFaceWorkerDoc = {
      'uid': workerUid,
      'role': 'worker',
      'accountStatus': 'pending_face',
      'faceVerified': false,
    };

    test('LEGITIMATE: Worker advances from pending_face to pending_review after face verification', () {
      final faceDoneUpdate = {
        'faceVerified': true,
        'accountStatus': 'pending_review',
        'verificationStatus': 'face_done',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: pendingFaceWorkerDoc,
        updateData: faceDoneUpdate,
      );

      expect(allowed, isTrue, reason: 'Face verification must advance worker to pending_review');
    });

    test('ATTACK: Worker attempts to jump directly from pending_face to approved', () {
      final bypassUpdate = {
        'faceVerified': true,
        'accountStatus': 'approved', // Attacker attempts to skip admin review
      };

      final allowed = FirestoreUpdateSimulation.evaluateUserUpdate(
        callerUid: workerUid,
        targetUid: workerUid,
        callerIsAdmin: false,
        existingData: pendingFaceWorkerDoc,
        updateData: bypassUpdate,
      );

      expect(allowed, isFalse, reason: 'Face verification cannot grant approved status; must be pending_review');
    });
  });

  group('Username Collection Security Contract', () {
    const userA = 'user_aaa';
    const userB = 'user_bbb';

    test('LEGITIMATE: User claims unoccupied username', () {
      final claim = {
        'uid': userA,
        'userId': 'anand_mason',
        'normalizedUserId': 'anand_mason',
        'createdAt': DateTime.now().toIso8601String(),
        'claimedAt': DateTime.now().toIso8601String(),
      };

      final allowed = FirestoreUpdateSimulation.evaluateUsernameClaim(
        callerUid: userA,
        existingDoc: null, // does not exist yet
        writeDoc: claim,
      );

      expect(allowed, isTrue);
    });

    test('LEGITIMATE: Same user refreshes their claimed username', () {
      final existing = {
        'uid': userA,
        'userId': 'anand_mason',
        'normalizedUserId': 'anand_mason',
      };
      final update = {
        'uid': userA,
        'userId': 'anand_mason',
        'normalizedUserId': 'anand_mason',
        'claimedAt': DateTime.now().toIso8601String(),
      };

      final allowed = FirestoreUpdateSimulation.evaluateUsernameClaim(
        callerUid: userA,
        existingDoc: existing,
        writeDoc: update,
      );

      expect(allowed, isTrue, reason: 'Owner must be able to refresh/re-set their own username');
    });

    test('ATTACK: User B attempts to hijack User A username', () {
      final existingOwnedByA = {
        'uid': userA,
        'userId': 'anand_mason',
        'normalizedUserId': 'anand_mason',
      };
      final hijackAttempt = {
        'uid': userB,
        'userId': 'anand_mason',
        'normalizedUserId': 'anand_mason',
      };

      final allowed = FirestoreUpdateSimulation.evaluateUsernameClaim(
        callerUid: userB,
        existingDoc: existingOwnedByA,
        writeDoc: hijackAttempt,
      );

      expect(allowed, isFalse, reason: 'User B cannot steal User A username');
    });
  });
}
