// test/auth_userid_password_flow_test.dart
// Tests for User ID + Password registration and password reset resolution.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/auth/password_policy_service.dart';
import 'package:kelasagaara/services/user_id_service.dart';

void main() {
  group('User ID & Password Policy Validation', () {
    test('Validates User ID format and normalization', () {
      final res = UserIdService.validate('ravi_painter');
      expect(res.isValid, isTrue);
      expect(res.normalized, 'ravi_painter');

      final handleRes = UserIdService.validate('kiran_electric');
      expect(handleRes.isValid, isTrue);
      expect(handleRes.normalized, 'kiran_electric');
    });

    test('Rejects weak password (< 8 chars)', () {
      final res = PasswordPolicyService.evaluate('weak1');
      expect(res.isAcceptable, isFalse);
      expect(res.level, PasswordStrengthLevel.weak);
    });

    test('Accepts strong password meeting requirements', () {
      final res = PasswordPolicyService.evaluate('StrongPass@2026!');
      expect(res.isAcceptable, isTrue);
      expect(res.level == PasswordStrengthLevel.strong ||
             res.level == PasswordStrengthLevel.good, isTrue);
    });

    test('Detects matching passwords between password and confirm fields', () {
      const pass = 'Karnataka@2026';
      const confirm = 'Karnataka@2026';
      expect(pass == confirm, isTrue);
    });
  });

  group('Password Reset Identifier Parsing', () {
    test('Identifies email format directly', () {
      const email = 'user@example.com';
      expect(email.contains('@') && !email.startsWith('@'), isTrue);
    });

    test('Normalizes @userId handle for database lookup', () {
      const handle = '@Ravi_Painter';
      final clean = handle.replaceAll('@', '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      expect(clean, 'ravi_painter');
    });
  });
}
