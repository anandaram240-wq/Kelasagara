// test/worker_geoquery_test.dart
// Tests for Phase 3 geographic bounding box and haversine filter logic.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// Since Geolocator platform channels may fail in plain unit tests,
// we use a simple Haversine formula inline for the test logic,
// simulating how Geolocator.distanceBetween works.
double _haversineM(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0; // Earth's radius in km
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a)) * 1000.0;
}

void main() {
  group('Bounding box calculation', () {
    // Hassan city centre approximate coordinates
    const hirerLat = 13.0068;

    test('10km radius: latDelta ≈ 0.090 degrees', () {
      final latDelta = 10.0 / 111.0;
      expect(latDelta, closeTo(0.09009, 0.001));
    });

    test('10km radius: lngDelta near Hassan (13°N) ≈ 0.092 degrees', () {
      final lngDelta = 10.0 / (111.0 * cos(hirerLat * pi / 180));
      expect(lngDelta, closeTo(0.0924, 0.002));
    });

    test('5km radius: latDelta ≈ 0.045 degrees', () {
      final latDelta = 5.0 / 111.0;
      expect(latDelta, closeTo(0.04504, 0.001));
    });

    test('20km radius: latDelta ≈ 0.180 degrees', () {
      final latDelta = 20.0 / 111.0;
      expect(latDelta, closeTo(0.18018, 0.001));
    });
  });

  group('Haversine exact filter', () {
    const hirerLat = 13.0068;
    const hirerLng = 76.0996;
    const radiusKm = 10.0;

    double distKm(double wLat, double wLng) {
      return _haversineM(hirerLat, hirerLng, wLat, wLng) / 1000.0;
    }

    test('worker at exact hirer location is within radius', () {
      expect(distKm(hirerLat, hirerLng), closeTo(0, 0.01));
      expect(distKm(hirerLat, hirerLng) <= radiusKm, isTrue);
    });

    test('worker 1km north is within 10km radius', () {
      // 1 km north ≈ 0.009 degrees lat
      final wLat = hirerLat + 0.009;
      expect(distKm(wLat, hirerLng), closeTo(1.0, 0.1));
      expect(distKm(wLat, hirerLng) <= radiusKm, isTrue);
    });

    test('worker 5km away is within 10km radius', () {
      // 5km north ≈ 0.045 degrees
      final wLat = hirerLat + 0.045;
      expect(distKm(wLat, hirerLng) <= radiusKm, isTrue);
    });

    test('worker 15km away is outside 10km radius', () {
      // 15km north ≈ 0.135 degrees
      final wLat = hirerLat + 0.135;
      expect(distKm(wLat, hirerLng) > radiusKm, isTrue);
    });

    test('bounding box corner worker may be outside exact radius', () {
      // Worker at corner of bounding box
      final latDelta = radiusKm / 111.0;
      final lngDelta = radiusKm / (111.0 * cos(hirerLat * pi / 180));
      final cornerLat = hirerLat + latDelta;
      final cornerLng = hirerLng + lngDelta;
      // Distance to corner of box is sqrt(2) * radius ≈ 14.1 km
      final d = distKm(cornerLat, cornerLng);
      expect(d > radiusKm, isTrue); // Corner exceeds radius — haversine filter needed
    });
  });

  group('Service radius eligibility', () {
    const hirerLat = 13.0068;
    const hirerLng = 76.0996;

    double distM(double wLat, double wLng) {
      return _haversineM(hirerLat, hirerLng, wLat, wLng);
    }

    test('worker 8km away with serviceRadiusKm=20 is eligible', () {
      final wLat = hirerLat + 0.072; // ~8km north
      final d = distM(wLat, hirerLng);
      const serviceRadius = 20;
      expect(d <= serviceRadius * 1000.0, isTrue);
    });

    test('worker 8km away with serviceRadiusKm=5 is not eligible', () {
      final wLat = hirerLat + 0.072; // ~8km north
      final d = distM(wLat, hirerLng);
      const serviceRadius = 5;
      expect(d <= serviceRadius * 1000.0, isFalse);
    });
  });
}
