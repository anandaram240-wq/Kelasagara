// test/user_id_uniqueness_test.dart
// Unit Tests for User ID Normalization, Validation, and Reservation Rules

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/user_id_service.dart';

void main() {
  group('UserIdService Validation & Normalization Tests', () {
    test('Valid usernames pass validation', () {
      final validCases = ['ananda123', 'ravi_painter', 'kumar_hassan', 'kiccha240', 'john_doe_99'];
      for (final username in validCases) {
        final res = UserIdService.validate(username);
        expect(res.isValid, isTrue, reason: 'Failed on $username');
        expect(res.normalized, equals(username.toLowerCase()));
      }
    });

    test('Case normalization is deterministic: Ananda123 -> ananda123', () {
      final res = UserIdService.validate('Ananda123');
      expect(res.isValid, isTrue);
      expect(res.normalized, equals('ananda123'));
    });

    test('Empty or whitespace username is rejected', () {
      final res = UserIdService.validate('   ');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot be empty'));
    });

    test('Usernames shorter than 3 characters are rejected', () {
      final res = UserIdService.validate('ab');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('at least 3 characters'));
    });

    test('Usernames longer than 20 characters are rejected', () {
      final res = UserIdService.validate('this_username_is_way_too_long_for_system');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('must not exceed 20 characters'));
    });

    test('Usernames starting with a number are rejected', () {
      final res = UserIdService.validate('123ananda');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('must start with a letter'));
    });

    test('Usernames with special characters or spaces are rejected', () {
      final invalidCases = ['ananda@123', 'ravi painter', 'kumar-hassan', 'user#1'];
      for (final u in invalidCases) {
        final res = UserIdService.validate(u);
        expect(res.isValid, isFalse, reason: 'Allowed invalid characters on $u');
      }
    });

    test('Reserved administrative usernames are strictly rejected', () {
      final reserved = ['admin', 'root', 'kelasagara', 'support', 'official', 'system'];
      for (final u in reserved) {
        final res = UserIdService.validate(u);
        expect(res.isValid, isFalse, reason: 'Allowed reserved username $u');
        expect(res.errorMessage, contains('reserved'));
      }
    });
  });
}
