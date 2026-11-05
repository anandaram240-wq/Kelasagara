// test/worker_discovery_location_test.dart
// Tests for Phase 3 discovery location fields in UserProfile.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';

void main() {
  group('UserProfile discovery fields', () {
    test('fromMap parses discoveryLat and discoveryLng', () {
      final map = {
        'uid': 'uid1',
        'role': 'worker',
        'accountStatus': 'approved',
        'discoveryLat': 13.0068,
        'discoveryLng': 76.0996,
        'discoveryAccuracy': 12.5,
        'discoverySessionId': 'sess_001',
        'serviceRadiusKm': 20,
      };
      final profile = UserProfile.fromMap('uid1', map);
      expect(profile.discoveryLat, closeTo(13.0068, 0.0001));
      expect(profile.discoveryLng, closeTo(76.0996, 0.0001));
      expect(profile.discoveryAccuracy, closeTo(12.5, 0.01));
      expect(profile.discoverySessionId, 'sess_001');
      expect(profile.serviceRadiusKm, 20);
    });

    test('fromMap handles null discovery fields gracefully', () {
      final map = {
        'uid': 'uid2',
        'role': 'worker',
        'accountStatus': 'approved',
        // No discovery fields
      };
      final profile = UserProfile.fromMap('uid2', map);
      expect(profile.discoveryLat, isNull);
      expect(profile.discoveryLng, isNull);
      expect(profile.discoveryUpdatedAt, isNull);
      expect(profile.discoverySessionId, '');
      expect(profile.discoveryAccuracy, 0.0);
      expect(profile.serviceRadiusKm, 15); // Default
    });

    test('fromMap uses int serviceRadiusKm', () {
      final map = {'uid': 'u', 'serviceRadiusKm': 30};
      final profile = UserProfile.fromMap('u', map);
      expect(profile.serviceRadiusKm, 30);
    });

    test('toMap includes discoveryLat when not null', () {
      final profile = UserProfile(uid: 'u', discoveryLat: 13.1, discoveryLng: 76.1);
      final map = profile.toMap();
      expect(map['discoveryLat'], 13.1);
      expect(map['discoveryLng'], 76.1);
      expect(map['serviceRadiusKm'], 15);
    });

    test('toMap omits discoveryLat when null', () {
      final profile = UserProfile(uid: 'u');
      final map = profile.toMap();
      expect(map.containsKey('discoveryLat'), isFalse);
      expect(map.containsKey('discoveryLng'), isFalse);
    });

    test('copyWith updates discovery fields', () {
      final p = UserProfile(uid: 'u', discoveryLat: 13.0, discoveryLng: 76.0);
      final p2 = p.copyWith(serviceRadiusKm: 25);
      expect(p2.serviceRadiusKm, 25);
      // Original unchanged
      expect(p.serviceRadiusKm, 15);
    });
  });
}
