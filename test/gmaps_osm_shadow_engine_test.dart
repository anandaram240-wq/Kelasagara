// test/gmaps_osm_shadow_engine_test.dart
// Unit verification suite for GmapsOsmShadowEngine and CubicHermiteSplineInterpolator.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/features/tracking/domain/gmaps_osm_shadow_engine.dart';

void main() {
  group('GmapsOsmShadowEngine Split-Brain Resolution Suite', () {
    final valhallaMainRoad = <LatLng>[
      const LatLng(12.9700, 77.5946),
      const LatLng(12.9720, 77.5946),
      const LatLng(12.9750, 77.5946),
    ];
    const destination = LatLng(12.9750, 77.5946);

    test('Locks onto OSM road when worker GPS is within 22m and heading aligns', () {
      final engine = GmapsOsmShadowEngine();
      final res = engine.processWorkerFix(
        kalmanPosition: const LatLng(12.9710, 77.59465), // ~5m off main road
        gpsHeading: 2.0, // Moving North along road
        speedMps: 6.0,
        valhallaPolyline: valhallaMainRoad,
        destination: destination,
      );

      expect(res.mode, equals(TrackingGlideMode.osmRoadLocked));
      expect(res.shouldTriggerShadowReroute, isFalse);
      expect(res.effectivePosition.longitude, closeTo(77.5946, 0.00001));
    });

    test('Switches to GoogleShortcutGlide with Elastic Bridge when worker takes a Google Maps detour', () {
      final engine = GmapsOsmShadowEngine();

      // Worker turns 65m East onto a parallel Bengaluru gully in Google Maps
      const shortcutPos = LatLng(12.9715, 77.5952);
      final res1 = engine.processWorkerFix(
        kalmanPosition: shortcutPos,
        gpsHeading: 45.0,
        speedMps: 5.5,
        valhallaPolyline: valhallaMainRoad,
        destination: destination,
      );

      expect(res1.mode, equals(TrackingGlideMode.googleShortcutGlide));
      // Verify marker is NOT yanked back to 77.5946 main road
      expect(res1.effectivePosition, equals(shortcutPos));
      // Verify active route line starts directly at the worker's live position (zero visual gap!)
      expect(res1.activeRoutePolyline.first, equals(shortcutPos));

      // Second consecutive fix on shortcut triggers Heading-Biased Valhalla Shadow Reroute
      final res2 = engine.processWorkerFix(
        kalmanPosition: const LatLng(12.9718, 77.5953),
        gpsHeading: 10.0,
        speedMps: 6.0,
        valhallaPolyline: valhallaMainRoad,
        destination: destination,
      );
      expect(res2.shouldTriggerShadowReroute, isTrue);
    });

    test('CubicHermiteSplineInterpolator bends smoothly around a 90-degree turn', () {
      const start = LatLng(12.9700, 77.5900); // Heading North (0°)
      const end = LatLng(12.9710, 77.5910);   // Turned East (90°)

      final midPose = CubicHermiteSplineInterpolator.interpolate(
        startPos: start,
        startBearingDeg: 0.0,
        endPos: end,
        endBearingDeg: 90.0,
        t: 0.5,
      );

      // A straight chord midpoint would be (12.9705, 77.5905).
      // Because start tangent points North and end tangent points East,
      // the Hermite curve bows outward North-West of the diagonal chord (lat > 12.9705)
      expect(midPose.position.latitude, greaterThan(12.97055));
      expect(midPose.bearing, closeTo(45.0, 10.0));
    });
  });
}
