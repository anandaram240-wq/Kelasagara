// test/registration_onboarding_flow_test.dart
// Tests for progressive onboarding, role selection, and user ID validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/user_id_service.dart';

void main() {
  group('UserIdService Validation & Reserved IDs', () {
    test('validates format correctly', () {
      expect(UserIdService.validate('ravi_painter').isValid, isTrue);
      expect(UserIdService.validate('anand.kumar').isValid, isTrue);
      expect(UserIdService.validate('shankar123').isValid, isTrue);

      // Too short (< 3 chars)
      expect(UserIdService.validate('ab').isValid, isFalse);
      // Too long (> 20 chars)
      expect(UserIdService.validate('this_username_is_way_too_long_for_system').isValid, isFalse);
      // Invalid characters
      expect(UserIdService.validate('ravi@painter').isValid, isFalse);
      expect(UserIdService.validate('ravi painter').isValid, isFalse);
      expect(UserIdService.validate('ravi#123').isValid, isFalse);
    });

    test('detects reserved system identifiers', () {
      final reservedList = [
        'admin',
        'support',
        'help',
        'kelasagara',
        'official',
        'root',
      ];

      for (final r in reservedList) {
        expect(UserIdService.reservedUserIds.contains(r.toLowerCase()), isTrue,
            reason: '$r should be in reservedUserIds');
      }
    });

    test('normalizes user ID reliably', () {
      expect(UserIdService.normalize('Ravi_Kumar'), 'ravi_kumar');
      expect(UserIdService.normalize('Anand_Electrician'), 'anand_electrician');
      expect(UserIdService.normalize('   shankar.99   '), 'shankar.99');
    });
  });

  group('Registration Experience and Level Mapping', () {
    test('experience years properly maps to experience level', () {
      String getLevel(int years) {
        if (years <= 2) return '1-2 yrs';
        if (years <= 5) return '3-5 yrs';
        if (years <= 10) return '5-10 yrs';
        return '10+ yrs';
      }

      expect(getLevel(1), '1-2 yrs');
      expect(getLevel(2), '1-2 yrs');
      expect(getLevel(3), '3-5 yrs');
      expect(getLevel(5), '3-5 yrs');
      expect(getLevel(7), '5-10 yrs');
      expect(getLevel(10), '5-10 yrs');
      expect(getLevel(12), '10+ yrs');
      expect(getLevel(25), '10+ yrs');
    });
  });
}
