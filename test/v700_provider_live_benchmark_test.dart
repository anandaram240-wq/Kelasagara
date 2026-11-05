import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/services/routing/osrm_route_provider.dart';

void main() {
  test('Flutter OsrmRouteProvider 20 Live Requests Benchmark', () async {
    const osrmUrl = String.fromEnvironment('OSRM_URL');
    if (osrmUrl.isEmpty) {
      // OSRM is a secondary/legacy router; Valhalla is the authoritative production router.
      print('OSRM_URL not configured — skipping live OSRM integration test.');
      return;
    }

    final provider = OsrmRouteProvider();
    final origin = LatLng(13.0068, 76.1030); // MCE Hassan
    final destination = LatLng(13.0072, 76.0950); // Hassan Bus Stand

    final latencies = <double>[];
    int successes = 0;
    int failures = 0;

    print('\n--- Starting Flutter Live Benchmark (20 Requests) ---');
    for (int i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      try {
        final result = await provider.calculateRoute(
          origin: origin,
          destination: destination,
        );
        sw.stop();
        if (result != null && result.polyline.isNotEmpty) {
          latencies.add(sw.elapsedMilliseconds.toDouble());
          successes++;
        } else {
          failures++;
        }
      } catch (e) {
        sw.stop();
        failures++;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    latencies.sort();
    final p50 = latencies[latencies.length ~/ 2];
    final p95 = latencies[(latencies.length * 0.95).floor()];
    final p99 = latencies.last;

    print('FLUTTER ROUTING BENCHMARK RESULTS:');
    print('Success rate: $successes/20 (${successes * 5}%)');
    print('Failure count: $failures');
    print('P50 latency: ${p50.toStringAsFixed(1)}ms');
    print('P95 latency: ${p95.toStringAsFixed(1)}ms');
    print('P99 latency: ${p99.toStringAsFixed(1)}ms');
    print('Min latency: ${latencies.first.toStringAsFixed(1)}ms');
    print('Max latency: ${latencies.last.toStringAsFixed(1)}ms');

    expect(successes, greaterThanOrEqualTo(18), reason: 'At least 90% success rate expected');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
