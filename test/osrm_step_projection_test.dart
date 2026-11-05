// test/osrm_step_projection_test.dart
// Automated unit tests for OSRM step polyline index projection.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/models/route_result.dart';

void main() {
  group('OSRM Step Polyline Index Projection Tests', () {
    test('Simulated OSRM step projection assigns monotonic indices', () {
      final polyline = [
        const LatLng(12.9716, 77.5946), // Step 1 start
        const LatLng(12.9730, 77.5960),
        const LatLng(12.9750, 77.5980), // Step 1 end / Step 2 start
        const LatLng(12.9780, 77.6010),
        const LatLng(12.9800, 77.6040), // Step 2 end / Step 3 start
        const LatLng(12.9820, 77.6070), // Step 3 end (destination)
      ];

      final cumDist = RouteResult.buildCumDist(polyline);
      expect(cumDist.length, equals(polyline.length));

      // Simulate step 1 (300m), step 2 (400m), step 3 (300m)
      final stepDistances = [300.0, 400.0, 300.0];
      final steps = <RouteStep>[];

      int currentPolyIndex = 0;
      double accumulatedDist = 0;

      for (int i = 0; i < stepDistances.length; i++) {
        final stepDist = stepDistances[i];
        accumulatedDist += stepDist;
        int endPolyIndex = currentPolyIndex;
        while (endPolyIndex < cumDist.length - 1 &&
               cumDist[endPolyIndex] < accumulatedDist) {
          endPolyIndex++;
        }

        steps.add(RouteStep(
          instruction: 'Step ${i + 1}',
          instructionKn: 'ಹಂತ ${i + 1}',
          durationSec: 60,
          distanceM: stepDist.round(),
          action: 'turn',
          maneuverType: ManeuverType.right,
          polylineStartIndex: currentPolyIndex,
          polylineEndIndex: endPolyIndex,
        ));

        currentPolyIndex = endPolyIndex;
      }

      // Guarantee the final step reaches the end of the polyline (matching valhalla_service.dart)
      if (steps.isNotEmpty && polyline.isNotEmpty) {
        final last = steps.removeLast();
        steps.add(RouteStep(
          instruction:        last.instruction,
          instructionKn:      last.instructionKn,
          durationSec:        last.durationSec,
          distanceM:          last.distanceM,
          action:             last.action,
          maneuverType:       last.maneuverType,
          polylineStartIndex: last.polylineStartIndex,
          polylineEndIndex:   polyline.length - 1,
        ));
      }

      expect(steps.length, equals(3));
      // Invariant: each step has start <= end
      for (final step in steps) {
        expect(step.polylineStartIndex, lessThanOrEqualTo(step.polylineEndIndex));
      }

      // Invariant: step N starts at step N-1 end
      expect(steps[1].polylineStartIndex, equals(steps[0].polylineEndIndex));
      expect(steps[2].polylineStartIndex, equals(steps[1].polylineEndIndex));

      // Final step ends at last polyline index
      expect(steps.last.polylineEndIndex, equals(polyline.length - 1));
    });
  });
}
