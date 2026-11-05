import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/features/tracking/domain/road_snapper.dart';

void main() {
  group('RoadSnapper Production v2 Suite', () {
    test('calculateBearing returns accurate cardinal azimuths', () {
      const origin = LatLng(12.9716, 77.5946);
      const north = LatLng(12.9816, 77.5946);
      const east = LatLng(12.9716, 77.6046);

      expect(RoadSnapper.calculateBearing(origin, north), closeTo(0.0, 1.0));
      expect(RoadSnapper.calculateBearing(origin, east), closeTo(90.0, 1.0));
    });

    test('lerpBearing interpolates across 0/360 boundary via shortest arc', () {
      final mid = RoadSnapper.lerpBearing(350.0, 10.0, 0.5);
      expect(mid % 360.0, closeTo(0.0, 0.01));

      final reverseMid = RoadSnapper.lerpBearing(10.0, 350.0, 0.5);
      expect(reverseMid % 360.0, closeTo(0.0, 0.01));
    });

    test('Heading-aware snapToPolyline prefers segment aligned with worker heading', () {
      // Cross-intersection: Segment 0 goes North, Segment 1 turns East
      final polyline = <LatLng>[
        const LatLng(12.9700, 77.5946),
        const LatLng(12.9720, 77.5946), // Corner intersection
        const LatLng(12.9720, 77.5970),
      ];

      // Worker is right near the corner moving East (heading ~90 deg, speed 6 m/s)
      const rawPoint = LatLng(12.97195, 77.59465);
      final snap = RoadSnapper.snapToPolyline(
        rawPoint: rawPoint,
        polyline: polyline,
        gpsHeading: 90.0,
        speedMps: 6.0,
      );

      expect(snap.isSnapped, isTrue);
      expect(snap.segmentIndex, equals(1)); // Snapped to Eastbound segment
      expect(snap.roadBearing, closeTo(90.0, 2.0));
    });

    test('interpolateAlongPath crawls around 90-degree corner instead of cutting diagonally', () {
      final lShapePath = <LatLng>[
        const LatLng(12.9700, 77.5900),
        const LatLng(12.9710, 77.5900), // 90-degree corner vertex
        const LatLng(12.9710, 77.5910),
      ];

      // At t = 0.5, the marker should pass right through the corner vertex (12.9710, 77.5900)
      final midpointPose = RoadSnapper.interpolateAlongPath(
        path: lShapePath,
        t: 0.5,
        fallbackStartBearing: 0.0,
        fallbackEndBearing: 90.0,
      );

      expect(midpointPose.position.latitude, closeTo(12.9710, 0.0001));
      expect(midpointPose.position.longitude, closeTo(77.5900, 0.0001));
    });

    test('KalmanLatLngFilter dampens sudden high-inaccuracy GPS spikes', () {
      final filter = KalmanLatLngFilter();
      final p1 = filter.process(
        lat: 12.9716,
        lng: 77.5946,
        accuracyMeters: 5.0,
        timestampMs: 1000,
      );
      // Sudden noisy multipath jump 50m away with poor 30m accuracy
      final p2 = filter.process(
        lat: 12.9760,
        lng: 77.5946,
        accuracyMeters: 30.0,
        timestampMs: 2000,
      );

      // Filtered latitude should stay much closer to p1 than the noisy spike
      expect((p2.latitude - p1.latitude).abs(), lessThan(0.0015));
    });

    test('Elastic soft-snap releases snap into Free-Follow mode when worker takes a traffic shortcut', () {
      final mainRoadPolyline = <LatLng>[
        const LatLng(12.9700, 77.5900),
        const LatLng(12.9750, 77.5900),
      ];

      // Worker turns onto a shortcut gully 28 meters away with heading diverging (45 deg away)
      const shortcutGps = LatLng(12.9725, 77.59026); // ~28m East of polyline
      final snap = RoadSnapper.snapToPolyline(
        rawPoint: shortcutGps,
        polyline: mainRoadPolyline,
        gpsHeading: 45.0, // Turning north-east into gully shortcut
        speedMps: 7.0,
        isExactGoogleRoute: false, // fallback route triggers tight 22m snap threshold
      );

      // Snap lock must release so the marker follows the actual shortcut rather than snapping to the main road
      expect(snap.isSnapped, isFalse);
      expect(snap.snappedPoint.latitude, equals(shortcutGps.latitude));
      expect(snap.snappedPoint.longitude, equals(shortcutGps.longitude));
      expect(snap.isOffRoute, isFalse); // < 55m is within shortcut tolerance, avoiding false reroute storms
    });
  });
}
