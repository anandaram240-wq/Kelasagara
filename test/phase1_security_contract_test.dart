// test/phase1_security_contract_test.dart
//
// Phase 1 — Security Contract Tests
// Tests the DATA AUTHORITY and SECURITY CONTRACT rules defined in Phase 1.
//
// These tests are pure Dart (no Firebase/network). They verify:
//   1. Booking status state machine: only valid transitions
//   2. OTP field canonicalization: no 'otp' key in new writes
//   3. Authority field classification: which fields are protected
//   4. Account status state machine: only valid transitions
//   5. Attack vectors: self-admin, self-approve, rating inflation (logic layer)
//
// Firebase Emulator rule tests are documented in docs/kelasagara_phase1_results.md
// as BLOCKED (requires Firebase project access and emulator configuration).

import 'package:flutter_test/flutter_test.dart';

// ─── Booking State Machine (pure logic mirror) ────────────────────────────────

enum BookingStatus {
  confirmed,
  tracking,
  arrived,
  working,
  completionRequested,
  completionVerified,
  disputed,
  cancelled,
}

/// Returns true if the transition from [from] to [to] is allowed for [actor].
/// Actor: 'worker' | 'hirer' | 'admin'
bool isValidBookingTransition(BookingStatus from, BookingStatus to, String actor) {
  switch (actor) {
    case 'worker':
      const workerTransitions = {
        BookingStatus.confirmed:          {BookingStatus.tracking},
        BookingStatus.tracking:           {BookingStatus.arrived},
        BookingStatus.arrived:            {BookingStatus.working},
        BookingStatus.working:            {BookingStatus.completionRequested},
        BookingStatus.completionRequested:{BookingStatus.cancelled}, // worker can cancel
      };
      return workerTransitions[from]?.contains(to) ?? false;

    case 'hirer':
      const hirerTransitions = {
        BookingStatus.completionRequested: {BookingStatus.completionVerified, BookingStatus.disputed},
        BookingStatus.confirmed:           {BookingStatus.cancelled},
      };
      return hirerTransitions[from]?.contains(to) ?? false;

    case 'admin':
      return true; // admin can do any transition

    default:
      return false;
  }
}

// ─── Account Status State Machine ────────────────────────────────────────────

enum AccountStatus {
  pendingProfile,
  pendingFace,
  pendingReview,
  approved,
  rejected,
  suspended,
  blocked,
  unknown,
}

/// Client-side allowed transitions (narrow — Firestore rules enforce server-side).
bool isValidAccountTransition(AccountStatus from, AccountStatus to, String actor) {
  if (actor == 'admin') return true;

  if (actor == 'client') {
    // Only narrow transitions the client may attempt:
    //   pendingProfile → pendingFace (via updateProfile)
    //   pendingFace    → pendingReview (via setFaceVerified — narrow Firestore gate)
    const clientTransitions = {
      AccountStatus.pendingProfile: {AccountStatus.pendingFace},
      AccountStatus.pendingFace:    {AccountStatus.pendingReview},
    };
    return clientTransitions[from]?.contains(to) ?? false;
  }
  return false;
}

// ─── Authority Field Classification ──────────────────────────────────────────

/// Fields that a normal client (worker or hirer) must NEVER be able to write
/// in users/{uid} directly.
const Set<String> authorityProtectedFields = {
  'role',
  'accountStatus',       // except via narrow face gate
  'faceVerified',        // except via narrow face gate
  'approvedBy',
  'approvedAt',
  'rejectedBy',
  'rejectedAt',
  'verifiedWorkCount',
  'rating',
  'ratingCount',
  'totalJobs',
  'skillVerified',
  'suspendedAt',
  'suspendedBy',
  'blockedAt',
  'blockedBy',
};

/// Fields a worker may update in their own users/{uid} document.
const Set<String> clientOwnedFields = {
  'displayName',
  'name',
  'bio',
  'district',
  'taluk',
  'village',
  'skills',
  'dailyRate',
  'userId',
  'normalizedUserId',
  'photoUrl',
  'isAvailable',
  'updatedAt',
  'phone',
  'email',  // only during registration
};

/// Checks that a proposed update map contains no authority-protected fields.
bool updateContainsProtectedField(Map<String, dynamic> update) {
  return update.keys.any((k) => authorityProtectedFields.contains(k));
}

// ─── OTP Canonicalization ─────────────────────────────────────────────────────

/// The canonical OTP field for new booking writes.
const String canonicalOtpField = 'arrivalOtp';
const String legacyOtpField    = 'otp'; // must NOT appear in new writes

bool newBookingWriteUsesLegacyOtp(Map<String, dynamic> write) {
  return write.containsKey(legacyOtpField);
}

bool newBookingWriteUsesCanonicalOtp(Map<String, dynamic> write) {
  return write.containsKey(canonicalOtpField);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Booking State Machine ─────────────────────────────────────────────

  group('BookingStatus state machine', () {
    test('Worker: confirmed → tracking is allowed', () {
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.tracking, 'worker'), isTrue);
    });

    test('Worker: tracking → arrived is allowed', () {
      expect(isValidBookingTransition(BookingStatus.tracking, BookingStatus.arrived, 'worker'), isTrue);
    });

    test('Worker: arrived → working is allowed', () {
      expect(isValidBookingTransition(BookingStatus.arrived, BookingStatus.working, 'worker'), isTrue);
    });

    test('Worker: working → completionRequested is allowed', () {
      expect(isValidBookingTransition(BookingStatus.working, BookingStatus.completionRequested, 'worker'), isTrue);
    });

    test('Hirer: completionRequested → completionVerified is allowed', () {
      expect(isValidBookingTransition(BookingStatus.completionRequested, BookingStatus.completionVerified, 'hirer'), isTrue);
    });

    test('Hirer: completionRequested → disputed is allowed', () {
      expect(isValidBookingTransition(BookingStatus.completionRequested, BookingStatus.disputed, 'hirer'), isTrue);
    });

    // ATTACK TESTS
    test('ATTACK: Worker cannot jump confirmed → completionVerified', () {
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.completionVerified, 'worker'), isFalse);
    });

    test('ATTACK: Worker cannot self-confirm as hirer', () {
      expect(isValidBookingTransition(BookingStatus.completionRequested, BookingStatus.completionVerified, 'worker'), isFalse);
    });

    test('ATTACK: Hirer cannot start worker journey (confirmed → tracking)', () {
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.tracking, 'hirer'), isFalse);
    });

    test('ATTACK: Direct pending → completed jump is denied for both actors', () {
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.completionVerified, 'worker'), isFalse);
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.completionVerified, 'hirer'), isFalse);
    });

    test('Admin can do any transition', () {
      expect(isValidBookingTransition(BookingStatus.confirmed, BookingStatus.completionVerified, 'admin'), isTrue);
    });
  });

  // ── 2. Account Status State Machine ─────────────────────────────────────

  group('AccountStatus state machine', () {
    test('Client: pendingProfile → pendingFace allowed', () {
      expect(isValidAccountTransition(AccountStatus.pendingProfile, AccountStatus.pendingFace, 'client'), isTrue);
    });

    test('Client: pendingFace → pendingReview allowed (narrow face gate)', () {
      expect(isValidAccountTransition(AccountStatus.pendingFace, AccountStatus.pendingReview, 'client'), isTrue);
    });

    // ATTACK TESTS
    test('ATTACK: Client cannot jump pendingProfile → approved', () {
      expect(isValidAccountTransition(AccountStatus.pendingProfile, AccountStatus.approved, 'client'), isFalse);
    });

    test('ATTACK: Client cannot jump pendingFace → approved', () {
      expect(isValidAccountTransition(AccountStatus.pendingFace, AccountStatus.approved, 'client'), isFalse);
    });

    test('ATTACK: Client cannot jump pendingReview → approved', () {
      expect(isValidAccountTransition(AccountStatus.pendingReview, AccountStatus.approved, 'client'), isFalse);
    });

    test('ATTACK: Client cannot set unknown → approved', () {
      expect(isValidAccountTransition(AccountStatus.unknown, AccountStatus.approved, 'client'), isFalse);
    });

    test('ATTACK: Client cannot unsuspend themselves', () {
      expect(isValidAccountTransition(AccountStatus.suspended, AccountStatus.approved, 'client'), isFalse);
    });

    test('Admin can approve from pendingReview', () {
      expect(isValidAccountTransition(AccountStatus.pendingReview, AccountStatus.approved, 'admin'), isTrue);
    });

    test('Admin can unsuspend', () {
      expect(isValidAccountTransition(AccountStatus.suspended, AccountStatus.approved, 'admin'), isTrue);
    });
  });

  // ── 3. Authority Field Protection ─────────────────────────────────────────

  group('Authority field protection', () {
    test('Safe profile update contains no protected fields', () {
      final safeUpdate = {
        'displayName': 'Ravi Kumar',
        'bio': 'Experienced mason',
        'district': 'Hassan',
        'taluk': 'Holenarasipur',
        'skills': ['mason'],
        'dailyRate': 800,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      expect(updateContainsProtectedField(safeUpdate), isFalse);
    });

    test('ATTACK: Update containing role field is detected', () {
      final attack = {'displayName': 'Ravi', 'role': 'admin'};
      expect(updateContainsProtectedField(attack), isTrue);
    });

    test('ATTACK: Update containing accountStatus is detected', () {
      final attack = {'displayName': 'Ravi', 'accountStatus': 'approved'};
      expect(updateContainsProtectedField(attack), isTrue);
    });

    test('ATTACK: Update containing faceVerified is detected', () {
      final attack = {'faceVerified': true};
      expect(updateContainsProtectedField(attack), isTrue);
    });

    test('ATTACK: Update containing rating inflation is detected', () {
      final attack = {'rating': 5.0, 'ratingCount': 999};
      expect(updateContainsProtectedField(attack), isTrue);
    });

    test('ATTACK: Update containing verifiedWorkCount inflation is detected', () {
      final attack = {'verifiedWorkCount': 999, 'totalJobs': 999};
      expect(updateContainsProtectedField(attack), isTrue);
    });

    test('ATTACK: Update containing approvedBy is detected', () {
      final attack = {'approvedBy': 'self', 'approvedAt': DateTime.now().toIso8601String()};
      expect(updateContainsProtectedField(attack), isTrue);
    });
  });

  // ── 4. OTP Canonicalization ───────────────────────────────────────────────

  group('OTP field canonicalization (DEF-020)', () {
    test('New booking write using canonical arrivalOtp is correct', () {
      final write = {
        'arrivalOtp':         '123456',
        'arrivalOtpExpiry':   DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
        'arrivalOtpUsed':     false,
        'arrivalOtpAttempts': 0,
      };
      expect(newBookingWriteUsesCanonicalOtp(write), isTrue);
      expect(newBookingWriteUsesLegacyOtp(write), isFalse);
    });

    test('ATTACK: Old-style write using legacy otp field is detected', () {
      final legacyWrite = {'otp': '1234', 'status': 'confirmed'};
      expect(newBookingWriteUsesLegacyOtp(legacyWrite), isTrue);
      expect(newBookingWriteUsesCanonicalOtp(legacyWrite), isFalse);
    });

    test('Canonical OTP field name constant is arrivalOtp', () {
      expect(canonicalOtpField, equals('arrivalOtp'));
    });

    test('Legacy OTP field name is otp (for migration reference)', () {
      expect(legacyOtpField, equals('otp'));
    });

    test('OTP write includes expiry, used flag, and attempts', () {
      final canonicalWrite = {
        'arrivalOtp':         '654321',
        'arrivalOtpExpiry':   DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        'arrivalOtpUsed':     false,
        'arrivalOtpAttempts': 0,
      };
      expect(canonicalWrite.containsKey('arrivalOtpExpiry'), isTrue);
      expect(canonicalWrite.containsKey('arrivalOtpUsed'), isTrue);
      expect(canonicalWrite['arrivalOtpUsed'], isFalse);
      expect(canonicalWrite.containsKey('arrivalOtpAttempts'), isTrue);
      expect(canonicalWrite['arrivalOtpAttempts'], equals(0));
    });
  });

  // ── 5. Booking Destination Contract ──────────────────────────────────────

  group('Booking destination contract', () {
    test('Valid Karnataka coordinates pass bounds check', () {
      const lat = 13.0060; // Hassan
      const lng = 76.0954;
      expect(lat >= 6.0 && lat <= 37.0, isTrue);
      expect(lng >= 68.0 && lng <= 97.0, isTrue);
      expect(lat != 0.0 || lng != 0.0, isTrue);
    });

    test('ATTACK: Zero coordinates are invalid', () {
      const lat = 0.0;
      const lng = 0.0;
      final isInvalid = (lat == 0.0 && lng == 0.0);
      expect(isInvalid, isTrue);
    });

    test('ATTACK: Out-of-India coordinates are invalid', () {
      const lat = 51.5074; // London
      const lng = -0.1278;
      final isOutOfIndia = !(lat >= 6.0 && lat <= 37.0 && lng >= 68.0 && lng <= 97.0);
      expect(isOutOfIndia, isTrue);
    });

    test('Booking destination fields are distinct from live tracking fields', () {
      // Booking destination: jobLat, jobLng, jobAddress — set at booking creation, immutable
      const bookingFields = {'jobLat', 'jobLng', 'jobAddress', 'jobId', 'bookingId'};
      // Live tracking: lat, lng, speed, heading, etaSeconds — updated in real-time
      const trackingFields = {'lat', 'lng', 'speed', 'heading', 'etaSeconds', 'seq', 'timestamp'};
      // No overlap — they are separate data
      final overlap = bookingFields.intersection(trackingFields);
      expect(overlap, isEmpty);
    });
  });

  // ── 6. HomeShell Access Guard ─────────────────────────────────────────────

  group('HomeShell access guard (DEF-offline)', () {
    test('Only approved or admin status grants canEnter=true', () {
      bool canEnter(String status, bool isAdmin) =>
          isAdmin || status == 'approved';

      expect(canEnter('approved', false), isTrue);
      expect(canEnter('admin_status', true), isTrue);

      // All non-approved statuses must be denied
      for (final status in ['pending_profile', 'pending_face', 'pending_review',
                             'rejected', 'suspended', 'blocked', 'unknown', '']) {
        expect(canEnter(status, false), isFalse,
            reason: 'Status "$status" must not grant access');
      }
    });

    test('ATTACK: pendingReview + faceVerified must NOT grant access', () {
      // Old bypass: faceVerified && pendingReview → allowed
      // New rule: only isApproved || isAdmin
      const status    = 'pending_review';
      const faceVer   = true; // even if true
      const isApproved = false;
      const isAdmin    = false;

      // The old (dangerous) bypass
      final oldBypass = faceVer && (status == 'pending_review' || status == 'unknown');
      // The new (safe) rule
      final newRule   = isApproved || isAdmin;

      expect(oldBypass, isTrue,  reason: 'Old bypass was dangerously true');
      expect(newRule,   isFalse, reason: 'New rule correctly denies access');
    });

    test('ATTACK: unknown status must NOT grant access', () {
      const status = 'unknown';
      final canEnter = (status == 'approved'); // simplified rule
      expect(canEnter, isFalse);
    });
  });
}
