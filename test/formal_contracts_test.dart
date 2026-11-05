// test/formal_contracts_test.dart
// Automated unit tests for Formal System Contracts.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/journey_state.dart';
import 'package:kelasagaara/models/route_result.dart';

void main() {
  group('Contract 1: Booking Destination Contract Tests', () {
    test('Valid Karnataka coordinates return true', () {
      const contract = BookingDestinationContract(
        bookingId: 'bk_karnataka_101',
        jobLat: 14.7900,  // Harakanahalu / Harapanahalli
        jobLng: 75.9899,
        jobAddress: 'Harakanahalu Dodda Tanda',
        workerId: 'worker_42',
        hirerId: 'hirer_99',
      );
      expect(contract.isValid(), isTrue);
    });

    test('Out-of-country coordinates return false (Rejected at boundary)', () {
      const contract = BookingDestinationContract(
        bookingId: 'bk_invalid_001',
        jobLat: 51.5074, // London UK
        jobLng: -0.1278,
        jobAddress: 'Trafalgar Square',
        workerId: 'worker_42',
        hirerId: 'hirer_99',
      );
      expect(contract.isValid(), isFalse);
    });

    test('Empty booking ID returns false', () {
      const contract = BookingDestinationContract(
        bookingId: '   ',
        jobLat: 12.9716,
        jobLng: 77.5946,
        jobAddress: 'Bengaluru',
        workerId: 'worker_42',
        hirerId: 'hirer_99',
      );
      expect(contract.isValid(), isFalse);
    });
  });

  group('Contract 2: GPS Quality Classification Tests', () {
    test('High accuracy (<15m) and fresh fix (<3s) classified as LIVE', () {
      final quality = GpsQuality.classify(
        accuracyM: 8.0,
        timestamp: DateTime.now().subtract(const Duration(seconds: 1)),
        isMocked: false,
      );
      expect(quality, equals(GpsQuality.live));
    });

    test('Poor accuracy (>40m) classified as INVALID', () {
      final quality = GpsQuality.classify(
        accuracyM: 65.0,
        timestamp: DateTime.now(),
        isMocked: false,
      );
      expect(quality, equals(GpsQuality.invalid));
    });

    test('Mocked GPS classified as INVALID', () {
      final quality = GpsQuality.classify(
        accuracyM: 5.0,
        timestamp: DateTime.now(),
        isMocked: true,
      );
      expect(quality, equals(GpsQuality.invalid));
    });

    test('Old GPS fix (>15s) classified as STALE', () {
      final quality = GpsQuality.classify(
        accuracyM: 10.0,
        timestamp: DateTime.now().subtract(const Duration(seconds: 20)),
        isMocked: false,
      );
      expect(quality, equals(GpsQuality.stale));
    });
  });

  group('Contract 3: Route Cumulative Distances Tests', () {
    test('buildCumDist produces monotonic non-decreasing distances', () {
      final points = [
        const LatLng(12.9716, 77.5946), // Point A
        const LatLng(12.9750, 77.5980), // Point B
        const LatLng(12.9800, 77.6020), // Point C
      ];

      final cumDist = RouteResult.buildCumDist(points);
      expect(cumDist.length, equals(3));
      expect(cumDist[0], equals(0.0));
      expect(cumDist[1], greaterThan(0.0));
      expect(cumDist[2], greaterThan(cumDist[1]));
    });

    test('buildCumDist handles empty list gracefully', () {
      final cumDist = RouteResult.buildCumDist([]);
      expect(cumDist, isEmpty);
    });
  });
}
