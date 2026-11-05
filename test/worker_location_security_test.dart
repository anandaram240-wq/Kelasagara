// test/worker_location_security_test.dart
// Tests for security properties of discovery location fields.
// These are unit tests for model constraints.
// Firestore rule tests require Firebase emulator (see docs).

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';

void main() {
  group('Discovery field isolation', () {
    test('discoveryLat is separate from district/taluk', () {
      final profile = UserProfile(
        uid: 'u1',
        district: 'Hassan',
        taluk: 'Hassan',
        discoveryLat: 13.0068,
        discoveryLng: 76.0996,
      );
      // Profile location fields are independent of discovery location
      expect(profile.district, 'Hassan');
      expect(profile.taluk, 'Hassan');
      expect(profile.discoveryLat, isNotNull);
      expect(profile.discoveryLng, isNotNull);
      // They must be independent (no coupling)
    });

    test('worker with no discovery location has null discoveryLat', () {
      final profile = UserProfile(uid: 'u1', district: 'Mysuru', taluk: 'KR Nagar');
      expect(profile.discoveryLat, isNull);
      expect(profile.discoveryLng, isNull);
    });

    test('serviceRadiusKm defaults to 15 (not zero)', () {
      final profile = UserProfile(uid: 'u1');
      // Default must be non-zero: zero would exclude all hirers from service area check
      expect(profile.serviceRadiusKm, greaterThan(0));
      expect(profile.serviceRadiusKm, 15);
    });

    test('discoverySessionId is empty string by default', () {
      final profile = UserProfile(uid: 'u1');
      expect(profile.discoverySessionId, '');
    });

    test('RTDB liveTracking fields are NOT in UserProfile', () {
      // LiveTracking is in RTDB, not in users/{uid}
      // This test ensures we haven't accidentally added RTDB fields to UserProfile
      final profile = UserProfile(uid: 'u1');
      final map = profile.toMap();
      expect(map.containsKey('liveTracking'), isFalse);
      expect(map.containsKey('bookingId'), isFalse);
      expect(map.containsKey('activeBookingLat'), isFalse);
    });
  });

  group('No fake GPS fallback', () {
    test('UserProfile with null discovery coords does not invent a location', () {
      final profile = UserProfile(uid: 'u1', district: 'Hassan');
      // Must not return Hassan city coords or any hardcoded lat/lng
      expect(profile.discoveryLat, isNull);
      expect(profile.discoveryLng, isNull);
    });
  });
}
