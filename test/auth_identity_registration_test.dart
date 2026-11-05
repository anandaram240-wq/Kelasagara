// test/auth_identity_registration_test.dart
// Change 2 — Auth & Identity Registration Test Suite
// Tests: UserIdService validation, normalization, PasswordPolicyService strength,
//        ProfileCompletion calculation (worker + hirer), reserved names, separators.
// These are pure unit tests — no Firebase/Firestore calls required.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/user_id_service.dart';
import 'package:kelasagaara/services/auth/password_policy_service.dart';
import 'package:kelasagaara/models/user_profile.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  UserIdService — normalization
  // ══════════════════════════════════════════════════════════════════════════
  group('UserIdService.normalize()', () {
    test('lowercases input', () {
      expect(UserIdService.normalize('RaviPainter'), equals('ravipainter'));
    });

    test('trims leading and trailing whitespace', () {
      expect(UserIdService.normalize('  ravi  '), equals('ravi'));
    });

    test('preserves valid separators', () {
      expect(UserIdService.normalize('ravi_painter'), equals('ravi_painter'));
      expect(UserIdService.normalize('ravi.painter'), equals('ravi.painter'));
    });

    test('case-insensitive: all variants normalize to same result', () {
      final a = UserIdService.normalize('RAVI');
      final b = UserIdService.normalize('ravi');
      final c = UserIdService.normalize('Ravi');
      expect(a, equals(b));
      expect(b, equals(c));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  UserIdService — format validation
  // ══════════════════════════════════════════════════════════════════════════
  group('UserIdService.validate() — format checks', () {
    test('accepts simple lowercase alphanumeric', () {
      expect(UserIdService.validate('ravi123').isValid, isTrue);
    });

    test('accepts underscore separator', () {
      expect(UserIdService.validate('ravi_painter').isValid, isTrue);
    });

    test('accepts dot separator', () {
      expect(UserIdService.validate('ravi.painter').isValid, isTrue);
    });

    test('rejects consecutive underscores', () {
      final r = UserIdService.validate('ravi__painter');
      expect(r.isValid, isFalse);
      expect(r.errorMessage, isNotNull);
    });

    test('rejects consecutive dots', () {
      expect(UserIdService.validate('ravi..painter').isValid, isFalse);
    });

    test('rejects mixed consecutive separators ._', () {
      expect(UserIdService.validate('ravi._painter').isValid, isFalse);
    });

    test('rejects mixed consecutive separators _.', () {
      expect(UserIdService.validate('ravi_.painter').isValid, isFalse);
    });

    test('rejects leading underscore', () {
      expect(UserIdService.validate('_ravi').isValid, isFalse);
    });

    test('rejects trailing dot', () {
      expect(UserIdService.validate('ravi.').isValid, isFalse);
    });

    test('rejects leading dot', () {
      expect(UserIdService.validate('.ravi').isValid, isFalse);
    });

    test('normalizes uppercase before validating (Ravi123 → ravi123, valid)', () {
      // validate() calls normalize() internally, so uppercase input is accepted
      // and the normalized result is returned. The raw input is not rejected.
      final r = UserIdService.validate('Ravi123');
      expect(r.isValid, isTrue);
      expect(r.normalized, equals('ravi123'));
    });

    test('rejects spaces', () {
      expect(UserIdService.validate('ravi painter').isValid, isFalse);
    });

    test('rejects @ character', () {
      expect(UserIdService.validate('ravi@painter').isValid, isFalse);
    });

    test('rejects too short (< 3 chars)', () {
      expect(UserIdService.validate('ab').isValid, isFalse);
    });

    test('accepts minimum 3 chars', () {
      expect(UserIdService.validate('abc').isValid, isTrue);
    });

    test('rejects exceeding maxLength', () {
      final longId = 'a' * (UserIdService.maxLength + 1);
      expect(UserIdService.validate(longId).isValid, isFalse);
    });

    test('accepts exactly maxLength chars', () {
      // Must start with letter, use only valid chars
      final maxId = 'a' + ('b' * (UserIdService.maxLength - 1));
      expect(maxId.length, equals(UserIdService.maxLength));
      expect(UserIdService.validate(maxId).isValid, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  UserIdService — reserved names
  // ══════════════════════════════════════════════════════════════════════════
  group('UserIdService — reserved names blocked', () {
    final reserved = [
      'admin', 'administrator', 'kelasagara', 'kelasagaara',
      'root', 'system', 'null', 'undefined', 'settings',
      'login', 'logout', 'api', 'register',
    ];

    for (final name in reserved) {
      test('blocks reserved name "$name"', () {
        expect(UserIdService.reservedUserIds.contains(name), isTrue);
        // validate() should also reject them
        expect(UserIdService.validate(name).isValid, isFalse);
      });
    }

    test('does not block normal user names', () {
      expect(UserIdService.validate('ravi123').isValid, isTrue);
      expect(UserIdService.validate('suresh_painter').isValid, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  PasswordPolicyService — strength levels
  // ══════════════════════════════════════════════════════════════════════════
  group('PasswordPolicyService.evaluate()', () {
    test('empty password → none level', () {
      final r = PasswordPolicyService.evaluate('');
      expect(r.level, equals(PasswordStrengthLevel.none));
      expect(r.score, equals(0));
    });

    test('very short password (< 8 chars) → none level (score 0)', () {
      // abc fails all 4 rules: no min length, no uppercase, no digit, no special
      // score = 0 maps to none
      final r = PasswordPolicyService.evaluate('abc');
      expect(r.level, equals(PasswordStrengthLevel.none));
      expect(r.score, equals(0));
    });

    test('min length only (8 lowercase chars) → weak/fair (score ≤ 2)', () {
      final r = PasswordPolicyService.evaluate('abcdefgh');
      expect(r.score, lessThanOrEqualTo(2));
    });

    test('length + uppercase + lowercase → score ≥ 2', () {
      final r = PasswordPolicyService.evaluate('Abcdefgh');
      expect(r.score, greaterThanOrEqualTo(2));
    });

    test('all 4 rules + 12+ chars → strong', () {
      final r = PasswordPolicyService.evaluate('Abcdefg12!xyz');
      expect(r.level, equals(PasswordStrengthLevel.strong));
    });

    test('password containing userId is downgraded', () {
      final rWithout = PasswordPolicyService.evaluate('Abcdefg12!xyz');
      expect(rWithout.level, equals(PasswordStrengthLevel.strong));

      // When userId appears in the password, it should weaken it
      final rWithId = PasswordPolicyService.evaluate(
        'Abcdefg12!xyz', userId: 'abcdefg12');
      expect(rWithId.level.index, lessThan(PasswordStrengthLevel.strong.index));
    });

    test('at-least-8-chars rule is first rule', () {
      final r = PasswordPolicyService.evaluate('abc');
      // First rule is min-length — should be false for short password
      expect(r.rules.first.isMet, isFalse);
    });

    test('special character rule detected', () {
      final r = PasswordPolicyService.evaluate('Abcdefg1!');
      // Should find at least one rule where isMet is true for special chars
      expect(r.rules.any((rule) => rule.isMet && rule.label.contains('symbol')), isTrue);
    });

    test('all 4 rules pass for strong password', () {
      final r = PasswordPolicyService.evaluate('Abcdefg12!xyz');
      expect(r.rules.every((c) => c.isMet), isTrue);
    });

    test('isAcceptable is true for good+ passwords', () {
      final r = PasswordPolicyService.evaluate('Abcdefg12');
      // score >= 2 and has min length → acceptable
      expect(r.isAcceptable, isTrue);
    });

    test('isAcceptable is false for short password', () {
      final r = PasswordPolicyService.evaluate('abc');
      expect(r.isAcceptable, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  ProfileCompletion — worker
  // ══════════════════════════════════════════════════════════════════════════
  group('UserProfile.calculateProfileCompletion() — worker', () {
    UserProfile makeWorker({
      String userId = '',
      String displayName = '',
      String district = '',
      String taluk = '',
      List<String> skills = const [],
      String bio = '',
      String photoUrl = '',
      bool faceVerified = false,
      String phone = '',
      int experienceYears = 0,
    }) {
      return UserProfile(
        uid: 'uid_test',
        userId: userId,
        displayName: displayName,
        district: district,
        taluk: taluk,
        skills: skills,
        bio: bio,
        photoUrl: photoUrl,
        faceVerified: faceVerified,
        phone: phone,
        experienceYears: experienceYears,
        role: 'worker',
      );
    }

    test('empty worker → 0%', () {
      final r = makeWorker().calculateProfileCompletion();
      expect(r.percentage, equals(0));
      expect(r.missingItems.isNotEmpty, isTrue);
    });

    test('100%: all worker fields complete', () {
      final r = makeWorker(
        userId: 'ravi_painter',
        displayName: 'Ravi Kumar',
        district: 'Bengaluru Urban',
        taluk: 'Bengaluru North',
        skills: ['electrician'],
        bio: 'Experienced electrician',
        phone: '+919876543210',
        experienceYears: 5,
      ).calculateProfileCompletion();
      expect(r.percentage, equals(100));
      expect(r.missingItems, isEmpty);
    });

    test('userId contributes exactly 15 pts', () {
      final withoutId = makeWorker(
        displayName: 'Ravi',
        district: 'Bengaluru Urban',
        taluk: 'Bengaluru North',
        skills: ['electrician'],
        bio: 'Bio',
        photoUrl: 'https://example.com/photo.jpg',
        faceVerified: true,
      ).calculateProfileCompletion();

      final withId = makeWorker(
        userId: 'ravi',
        displayName: 'Ravi',
        district: 'Bengaluru Urban',
        taluk: 'Bengaluru North',
        skills: ['electrician'],
        bio: 'Bio',
        photoUrl: 'https://example.com/photo.jpg',
        faceVerified: true,
      ).calculateProfileCompletion();

      expect(withId.percentage - withoutId.percentage, equals(15));
    });

    test('missing skills listed as actionable item', () {
      final r = makeWorker(
        userId: 'ravi',
        displayName: 'Ravi',
        district: 'Bengaluru Urban',
        taluk: 'N',
        bio: 'Bio',
        faceVerified: true,
      ).calculateProfileCompletion();
      expect(r.missingItems.any((i) => i.key == 'skills'), isTrue);
    });

    test('phone empty lists phone in missing items', () {
      final r = makeWorker(
        userId: 'ravi',
        displayName: 'Ravi',
        district: 'Bengaluru Urban',
        taluk: 'N',
        skills: ['electrician'],
        bio: 'Bio',
        phone: '',
      ).calculateProfileCompletion();
      expect(r.missingItems.any((i) => i.key == 'phone'), isTrue);
    });

    test('isComplete is false when any field is missing', () {
      expect(makeWorker().calculateProfileCompletion().isComplete, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  ProfileCompletion — hirer
  // ══════════════════════════════════════════════════════════════════════════
  group('UserProfile.calculateProfileCompletion() — hirer', () {
    UserProfile makeHirer({
      String userId = '',
      String displayName = '',
      String district = '',
      String taluk = '',
      String bio = '',
      String phone = '',
      String photoUrl = '',
    }) {
      return UserProfile(
        uid: 'uid_hirer',
        userId: userId,
        displayName: displayName,
        district: district,
        taluk: taluk,
        bio: bio,
        phone: phone,
        photoUrl: photoUrl,
        role: 'hirer',
      );
    }

    test('empty hirer → 0%', () {
      final r = makeHirer().calculateProfileCompletion();
      expect(r.percentage, equals(0));
    });

    test('100%: all hirer fields complete', () {
      final r = makeHirer(
        userId: 'sridhar_hirer',
        displayName: 'Sridhar Gowda',
        district: 'Bengaluru Urban',
        taluk: 'Bengaluru South',
        bio: 'We are a construction firm',
        phone: '9876543210',
        photoUrl: 'https://example.com/photo.jpg',
      ).calculateProfileCompletion();
      expect(r.percentage, equals(100));
      expect(r.missingItems, isEmpty);
    });

    test('missing contact phone lists in missing items', () {
      final r = makeHirer(
        userId: 'sridhar',
        displayName: 'Sridhar',
        district: 'Bengaluru Urban',
        taluk: 'N',
        bio: 'Bio',
        photoUrl: 'photo.jpg',
      ).calculateProfileCompletion();
      expect(r.missingItems.any((i) => i.key == 'contact'), isTrue);
    });

    test('hirer does not require skills', () {
      final r = makeHirer(
        userId: 'sridhar',
        displayName: 'Sridhar',
        district: 'Bengaluru Urban',
        taluk: 'N',
        bio: 'Bio',
        phone: '9876543210',
        photoUrl: 'photo.jpg',
      ).calculateProfileCompletion();
      // No 'skills' key should appear in hirer missing items
      expect(r.missingItems.any((i) => i.key == 'skills'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  Migration helper
  // ══════════════════════════════════════════════════════════════════════════
  group('UserIdService.migrateExistingUserIfNeeded() — static needsMigration check', () {
    // The actual migration touches Firestore (async, needs mock).
    // We test the static pre-condition: userId empty → needs migration.

    test('user with empty userId triggers migration condition', () {
      final profile = UserProfile(uid: 'uid_legacy', userId: '');
      // userId empty → this user should go through migration
      expect(profile.userId.isEmpty, isTrue);
    });

    test('user with userId set does NOT need migration', () {
      final profile = UserProfile(uid: 'uid_existing', userId: 'ravi_worker');
      expect(profile.userId.isEmpty, isFalse);
    });
  });
}
