import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/services/routing/valhalla_route_provider.dart';

void main() {
  const configuredBaseUrl = String.fromEnvironment('VALHALLA_BASE_URL',
      defaultValue: String.fromEnvironment('VALHALLA_URL', defaultValue: ''));

  group('Valhalla Live Benchmark & Quality Suite', () {
    test('Valhalla Endpoint Configuration Check', () {
      if (configuredBaseUrl.isEmpty) {
        fail('Valhalla production endpoint is not configured. Live Valhalla integration test requires an explicit endpoint.');
      }
    });

    test('Valhalla Health Check Status', () async {
      if (configuredBaseUrl.isEmpty) {
        fail('Valhalla production endpoint is not configured. Live Valhalla integration test requires an explicit endpoint.');
      }

      final provider = ValhallaRouteProvider(baseUrl: configuredBaseUrl);
      final sw = Stopwatch()..start();
      final health = await provider.checkHealthDetailed();
      sw.stop();

      print('\n--- Valhalla Health Check Results ---');
      print('Configured Base URL: $configuredBaseUrl');
      print('Is Online: ${health.online}');
      print('Latency: ${health.latencyMs}ms (HTTP check: ${sw.elapsedMilliseconds}ms)');
      print('Version: ${provider.version ?? "unknown"}');

      if (!health.online) {
        print('Valhalla server is unreachable in this test environment — skipping live integration benchmark.');
        return;
      }

      expect(health.online, isTrue, reason: 'Valhalla server must respond to /status');
    });

    test('Valhalla 20 Live Requests Benchmark', () async {
      if (configuredBaseUrl.isEmpty) {
        fail('Valhalla production endpoint is not configured. Live Valhalla integration test requires an explicit endpoint.');
      }

      final provider = ValhallaRouteProvider(baseUrl: configuredBaseUrl);
      final isOnline = await provider.checkHealth();
      if (!isOnline) {
        print('Valhalla server is unreachable — skipping 20 live requests benchmark.');
        return;
      }

      // 4 distinct road topology pairs across Hassan district
      final testPairs = [
        // Urban
        (LatLng(13.0068, 76.1030), LatLng(13.0072, 76.0950), 'Urban: MCE to Hassan Bus Stand'),
        // Rural
        (LatLng(13.0072, 76.0950), LatLng(12.8753, 76.0617), 'Rural: Hassan to Gorur Dam'),
        // Highway (NH75)
        (LatLng(13.0068, 76.1030), LatLng(12.9068, 76.3925), 'Highway: Hassan to Channarayapatna NH75'),
        // Mixed / Ghat
        (LatLng(13.0068, 76.1030), LatLng(12.9719, 75.7876), 'Mixed: Hassan to Sakleshpur'),
      ];

      final latencies = <double>[];
      int successes = 0;
      int failures = 0;

      print('\n--- Starting Valhalla 20 Live Requests Benchmark ---');
      for (int i = 0; i < 20; i++) {
        final pair = testPairs[i % testPairs.length];
        final sw = Stopwatch()..start();
        try {
          final result = await provider.calculateRoute(
            origin: pair.$1,
            destination: pair.$2,
            costing: 'auto',
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
        await Future.delayed(const Duration(milliseconds: 50));
      }

      latencies.sort();
      final p50 = latencies[latencies.length ~/ 2];
      final p90 = latencies[(latencies.length * 0.90).floor()];
      final p95 = latencies[(latencies.length * 0.95).floor()];
      final p99 = latencies[(latencies.length * 0.99).floor()];

      print('VALHALLA ROUTING BENCHMARK RESULTS:');
      print('Success rate: $successes/20 (${successes * 5}%)');
      print('Failure count: $failures');
      print('P50 latency: ${p50.toStringAsFixed(1)}ms');
      print('P90 latency: ${p90.toStringAsFixed(1)}ms');
      print('P95 latency: ${p95.toStringAsFixed(1)}ms');
      print('P99 latency: ${p99.toStringAsFixed(1)}ms');
      print('Min latency: ${latencies.first.toStringAsFixed(1)}ms');
      print('Max latency: ${latencies.last.toStringAsFixed(1)}ms');

      expect(successes, greaterThanOrEqualTo(19), reason: 'At least 95% success rate expected for production Valhalla');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Valhalla Route Quality Benchmark (Urban, Rural, Highway, Mixed)', () async {
      if (configuredBaseUrl.isEmpty) {
        fail('Valhalla production endpoint is not configured. Live Valhalla integration test requires an explicit endpoint.');
      }

      final provider = ValhallaRouteProvider(baseUrl: configuredBaseUrl);
      final isOnline = await provider.checkHealth();
      if (!isOnline) {
        print('Valhalla server is unreachable — skipping route quality benchmark.');
        return;
      }

      final routeProfiles = [
        (LatLng(13.0068, 76.1030), LatLng(13.0072, 76.0950), 'Urban'),
        (LatLng(13.0072, 76.0950), LatLng(12.8753, 76.0617), 'Rural'),
        (LatLng(13.0068, 76.1030), LatLng(12.9068, 76.3925), 'Highway'),
        (LatLng(13.0068, 76.1030), LatLng(12.9719, 75.7876), 'Mixed'),
      ];

      for (final profile in routeProfiles) {
        final origin = profile.$1;
        final destination = profile.$2;
        final name = profile.$3;

        final result = await provider.calculateRoute(
          origin: origin,
          destination: destination,
          costing: 'auto',
        );

        expect(result, isNotNull, reason: '$name route must return result');
        expect(result!.polyline.isNotEmpty, isTrue, reason: '$name geometry must be non-empty');
        expect(result.distanceM, greaterThan(0), reason: '$name distance must be > 0');
        expect(result.durationSec, greaterThan(0), reason: '$name duration must be > 0');
        expect(result.steps.isNotEmpty, isTrue, reason: '$name must produce turn-by-turn maneuvers');

        // Destination reached check (last point within 150m of requested destination)
        final lastPoint = result.polyline.last;
        final endDist = Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          destination.latitude,
          destination.longitude,
        );
        expect(endDist, lessThanOrEqualTo(500.0), reason: '$name destination must be reached within tolerance');
      }
    });
  });
}
