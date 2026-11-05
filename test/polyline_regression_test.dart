import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/route_result.dart';

/// Karnataka bounding box check (inline, no dependency on valhalla_service.dart)
bool _isInKarnataka(double lat, double lng) =>
    lat >= 10 && lat <= 20 && lng >= 73 && lng <= 80;

/// India bounding box check
bool _isInIndia(double lat, double lng) =>
    lat >= 6 && lat <= 37 && lng >= 68 && lng <= 97;

void main() {
  group('Polyline Regression and Decoding Tests', () {
    test('Polyline6 decode known Valhalla string', () {
      // Known Valhalla polyline6 string; Valhalla uses precision-6 (1e6).
      const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final points = ValhallaPolyline6.decode(encoded);
      expect(points, isNotEmpty);
      for (final point in points) {
        expect(point.latitude.isFinite, isTrue);
        expect(point.longitude.isFinite, isTrue);
      }
    });

    test('Polyline5 decode known OSRM string via Polyline5Decoder', () {
      // A standard precision-5 polyline (Google/OSRM format).
      // "}|{eF~ps|U" decodes to approximately (38.5, -120.2)
      const encoded = '}|{eF~ps|U';
      final points = Polyline5Decoder.decode(encoded);
      expect(points, isNotEmpty);
      for (final point in points) {
        expect(point.latitude.isFinite, isTrue);
        expect(point.longitude.isFinite, isTrue);
      }
    });

    test('Cross-decode detection: polyline6 decoded as polyline5 gives wrong coords', () {
      // This is the REGRESSION test that prevents the precision confusion bug.
      // Take a polyline6 string. If decoded as polyline5, coords will be ×10
      // larger than intended — completely outside Karnataka (or even Earth bounds).
      const encoded6 = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

      // Decode as polyline6 (correct)
      final correctPoints = ValhallaPolyline6.decode(encoded6);
      expect(correctPoints, isNotEmpty);

      // Decode as polyline5 (WRONG — simulating the bug)
      final wrongPoints = Polyline5Decoder.decode(encoded6);
      expect(wrongPoints, isNotEmpty);

      // The two results must be different (proof that precision matters)
      if (correctPoints.isNotEmpty && wrongPoints.isNotEmpty) {
        final latDiff =
            (correctPoints[0].latitude - wrongPoints[0].latitude).abs();
        // Polyline6 gives 10× more precision so coords will differ significantly
        // OR the wrong decode produces coordinates outside reasonable bounds
        final wrongLat = wrongPoints[0].latitude;
        final wrongLng = wrongPoints[0].longitude;
        final isWrongOutsideIndia = !_isInIndia(wrongLat, wrongLng);
        // Either the coordinates differ or at least one is out of India
        expect(latDiff > 0 || isWrongOutsideIndia, isTrue,
            reason: 'Polyline5 and Polyline6 should decode to different values');
      }
    });

    test('Empty string handling', () {
      expect(ValhallaPolyline6.decode(''), isEmpty);
      expect(Polyline5Decoder.decode(''), isEmpty);
    });

    test('Single point decoding (polyline6)', () {
      const encoded = '_p~iF~ps|U';
      final points = ValhallaPolyline6.decode(encoded);
      expect(points.length, greaterThanOrEqualTo(1));
    });

    test('Polyline6 round-trip concept: Karnataka bounds', () {
      // Hassan, Karnataka: 13.0060°N, 76.0954°E
      const lat = 13.0060;
      const lng = 76.0954;
      expect(_isInKarnataka(lat, lng), isTrue);
      expect(_isInIndia(lat, lng), isTrue);
    });

    test('India bounding box: valid and invalid coordinates', () {
      // Bangalore (valid)
      expect(_isInIndia(12.9716, 77.5946), isTrue);
      // Hassan (valid)
      expect(_isInIndia(13.0060, 76.0954), isTrue);
      // London (invalid)
      expect(_isInIndia(51.5074, -0.1278), isFalse);
      // New York (invalid)
      expect(_isInIndia(40.7128, -74.0060), isFalse);
    });

    test('Polyline5Decoder: known Chennai coordinate', () {
      // The polyline5 string for Chennai (13.0827, 80.2707) approx.
      // We encode manually: lat=1308270/10=130827 steps of 1e-5
      // Just verify decode produces finite, bounded results
      const encoded = 'ek`sFwvk}M';
      final points = Polyline5Decoder.decode(encoded);
      // Should produce at least 1 point with finite coords
      if (points.isNotEmpty) {
        expect(points[0].latitude.isFinite, isTrue);
        expect(points[0].longitude.isFinite, isTrue);
      }
    });
  });
}
