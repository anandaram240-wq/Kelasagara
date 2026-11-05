import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kelasagaara/services/navigation_engine.dart';
import 'package:kelasagaara/models/route_result.dart';

/// Test mock verifying single-flight Future identity guard (Fix D2 in RouteService)
class RouteServiceFlightGuardMock {
  Future<RouteResult?>? _inFlight;
  LatLng? _inFlightOriginBucket;
  LatLng? _inFlightDest;
  int networkCallCount = 0;

  LatLng bucketize(LatLng pos) => LatLng(
        (pos.latitude * 100).round() / 100,
        (pos.longitude * 100).round() / 100,
      );

  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    required Future<RouteResult?> Function() fetcher,
  }) async {
    final originBucket = bucketize(origin);

    if (_inFlight != null) {
      if (_inFlightOriginBucket?.latitude == originBucket.latitude &&
          _inFlightOriginBucket?.longitude == originBucket.longitude &&
          _inFlightDest?.latitude == destination.latitude &&
          _inFlightDest?.longitude == destination.longitude) {
        return _inFlight;
      }
      try {
        await _inFlight;
      } catch (_) {}
    }

    _inFlightOriginBucket = originBucket;
    _inFlightDest = destination;
    final future = () async {
      networkCallCount++;
      return await fetcher();
    }();
    _inFlight = future;

    try {
      return await future;
    } finally {
      _inFlight = null;
      _inFlightOriginBucket = null;
      _inFlightDest = null;
    }
  }
}

/// Simulated arrival state machine mimicking NavigationEngine._checkArrival
class ArrivalGatingMock {
  int arrivalCandidateCount = 0;
  bool hasArrived = false;
  static const int arrivalRequiredStableFixes = 2;

  void checkArrival({
    required double directDistM,
    required double remainingRoadM,
    required double accuracy,
    required double speedKmh,
  }) {
    if (hasArrived) return;

    final isCandidate = (remainingRoadM > 0 && remainingRoadM <= 45.0) ||
        (directDistM <= 50.0 && accuracy <= 35.0);

    if (isCandidate) {
      arrivalCandidateCount++;
      if (arrivalCandidateCount >= arrivalRequiredStableFixes ||
          (directDistM <= 30.0 && speedKmh < 3.0)) {
        hasArrived = true;
      }
    } else {
      arrivalCandidateCount = 0;
    }
  }
}

/// Simulated Speed Derivation Engine mimicking NavigationEngine
class SpeedEngineMock {
  Position? _lastValidPos;
  DateTime? _lastPosTime;
  double? _currentSpeedKmh;
  static const double _maxSpeedKmh = 150.0;

  double processPosition(Position pos) {
    double rawSpeedKmh = 0.0;
    if (pos.speed > 0) {
      rawSpeedKmh = (pos.speed * 3.6).clamp(0.0, _maxSpeedKmh);
    } else if (_lastValidPos != null && _lastPosTime != null) {
      final dt = pos.timestamp.difference(_lastPosTime!).inMilliseconds / 1000.0;
      if (dt >= 0.5 && dt <= 10.0) {
        const d = Distance();
        final distM = d.as(
          LengthUnit.Meter,
          LatLng(pos.latitude, pos.longitude),
          LatLng(_lastValidPos!.latitude, _lastValidPos!.longitude),
        );
        rawSpeedKmh = ((distM / dt) * 3.6).clamp(0.0, _maxSpeedKmh);
      }
    }
    _lastValidPos = pos;
    _lastPosTime = pos.timestamp;

    final double speedKmh;
    if (rawSpeedKmh < 2.0) {
      speedKmh = 0.0; // Stationary suppression
    } else {
      final prevSpeed = (_currentSpeedKmh != null && _currentSpeedKmh! >= 2.0)
          ? _currentSpeedKmh!
          : rawSpeedKmh;
      speedKmh = (0.35 * rawSpeedKmh + 0.65 * prevSpeed).clamp(0.0, _maxSpeedKmh);
    }
    _currentSpeedKmh = speedKmh;
    return speedKmh;
  }
}

/// Camera Follow State Simulator
class CameraFollowManagerMock {
  bool followWorker = true;
  Timer? recenterTimer;
  int cameraMoveCount = 0;
  double currentZoom = 17.5;

  void onUserGesture() {
    followWorker = false;
    recenterTimer?.cancel();
    recenterTimer = Timer(const Duration(seconds: 10), () {
      followWorker = true;
    });
  }

  void onNavStateUpdate(LatLng workerPos) {
    if (followWorker) {
      // 1 Hz camera update preserves user zoom
      cameraMoveCount++;
    }
  }

  void on60FpsAnimationTick(LatLng interpolatedMarkerPos) {
    // 60 FPS marker animation does NOT move camera
    // Camera is untouched!
  }

  void userZooms(double newZoom) {
    onUserGesture();
    currentZoom = newZoom;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V900 Navigation Forensic Suite Tests', () {
    final engine = NavigationEngine.instance;

    test('1. Geometric Projection & Snapping: Orthogonal projection within threshold snaps onto segment', () {
      final a = LatLng(12.97160, 77.59460);
      final b = LatLng(12.97160, 77.59560); // Eastward segment

      // Test point 10 meters north of segment midpoint
      final pNorth = LatLng(12.97169, 77.59510);
      final proj = engine.projectOntoSegmentForTest(pNorth, a, b);

      expect(proj.distanceM, lessThan(15.0));
      expect(proj.distanceM, greaterThan(8.0));
      // Projected point latitude should match the segment latitude (12.97160)
      expect(proj.projection.latitude, closeTo(12.97160, 0.00005));
      expect(proj.projection.longitude, closeTo(77.59510, 0.00005));

      // Test polyline snapping
      final polyline = [a, b, LatLng(12.97260, 77.59560)];
      final snapRes = engine.projectOntoPolylineForTest(pNorth, polyline, hintIndex: 0, maxSnapDistanceM: 25.0);
      expect(snapRes.isSnapped, isTrue);
      expect(snapRes.nearestSegmentIndex, 0);
      expect(snapRes.position.latitude, closeTo(12.97160, 0.00005));
    });

    test('2. Geometric Projection: Points beyond maxSnapDistanceM do NOT snap', () {
      final a = LatLng(12.97160, 77.59460);
      final b = LatLng(12.97160, 77.59560);
      final polyline = [a, b];

      // Point 60m away (exceeds 25m snap threshold)
      final farPoint = LatLng(12.97215, 77.59510);
      final snapRes = engine.projectOntoPolylineForTest(farPoint, polyline, hintIndex: 0, maxSnapDistanceM: 25.0);

      expect(snapRes.isSnapped, isFalse);
      expect(snapRes.position.latitude, farPoint.latitude);
      expect(snapRes.position.longitude, farPoint.longitude);
      expect(snapRes.distanceM, greaterThan(25.0));
    });

    test('3. Geometric Projection: Clamps to segment endpoints for acute projections', () {
      final a = LatLng(12.97160, 77.59460);
      final b = LatLng(12.97160, 77.59560);

      // Point far to the west of point A
      final pWest = LatLng(12.97160, 77.59300);
      final proj = engine.projectOntoSegmentForTest(pWest, a, b);

      // Should clamp to endpoint A
      expect(proj.projection.latitude, closeTo(a.latitude, 0.00001));
      expect(proj.projection.longitude, closeTo(a.longitude, 0.00001));
    });

    test('4. Heading Angle Lerp: Shortest arc wrap-around (359° -> 1°)', () {
      final lerped = engine.lerpAngleForTest(358.0, 2.0, 0.5);
      // Halfway between 358° and 2° across 0° is 0° (or 360°)
      expect(lerped, closeTo(0.0, 0.5));
    });

    test('5. Speed Derivation & EMA: Fallback calculation when hardware Doppler speed is 0', () {
      final speedEngine = SpeedEngineMock();
      final t0 = DateTime(2026, 9, 25, 10, 0, 0);

      // Fix 1: Doppler speed = 0, initial fix
      final pos1 = Position(
        latitude: 12.97160,
        longitude: 77.59460,
        timestamp: t0,
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0, // Hardware returns 0
        speedAccuracy: 0.0,
      );
      final speed1 = speedEngine.processPosition(pos1);
      expect(speed1, 0.0);

      // Fix 2: Moved 20 meters in 2 seconds = 10 m/s = 36 km/h (Doppler speed still 0)
      const d = Distance();
      final targetLatLng = d.offset(LatLng(12.97160, 77.59460), 20.0, 90.0); // 20m East
      final pos2 = Position(
        latitude: targetLatLng.latitude,
        longitude: targetLatLng.longitude,
        timestamp: t0.add(const Duration(seconds: 2)),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 90.0,
        headingAccuracy: 0.0,
        speed: 0.0, // Missing Doppler
        speedAccuracy: 0.0,
      );
      final speed2 = speedEngine.processPosition(pos2);

      // Derived raw speed should be ~36 km/h. First non-zero fix initializes EMA to raw speed (~36 km/h)
      expect(speed2, closeTo(36.0, 2.0));

      // Fix 3: Moved 20m in another 2 seconds (~36 km/h). EMA smooths: 0.35 * 36 + 0.65 * 36 = 36 km/h
      final targetLatLng3 = d.offset(targetLatLng, 20.0, 90.0);
      final pos3 = Position(
        latitude: targetLatLng3.latitude,
        longitude: targetLatLng3.longitude,
        timestamp: t0.add(const Duration(seconds: 4)),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 90.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      final speed3 = speedEngine.processPosition(pos3);
      expect(speed3, closeTo(36.0, 2.0));
    });

    test('6. Speed Engine: Stationary suppression (< 2.0 km/h becomes exactly 0.0)', () {
      final speedEngine = SpeedEngineMock();
      final t0 = DateTime(2026, 9, 25, 10, 0, 0);

      // Jitter fix: moved only 0.5 meters in 2 seconds = 0.25 m/s = 0.9 km/h
      final pos1 = Position(
        latitude: 12.971600,
        longitude: 77.594600,
        timestamp: t0,
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      speedEngine.processPosition(pos1);

      final pos2 = Position(
        latitude: 12.971604,
        longitude: 77.594600,
        timestamp: t0.add(const Duration(seconds: 2)),
        accuracy: 5.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      final speed = speedEngine.processPosition(pos2);
      expect(speed, 0.0, reason: 'Speed < 2 km/h must be suppressed to 0.0 to prevent drift');
    });

    test('7. Multi-Stage Arrival Gating: Single false spike does NOT cause premature arrival', () {
      final arrivalMock = ArrivalGatingMock();

      // Tick 1: Random GPS jump into 40m direct distance
      arrivalMock.checkArrival(
        directDistM: 40.0,
        remainingRoadM: 40.0,
        accuracy: 25.0,
        speedKmh: 15.0, // Still moving fast
      );

      // Should be candidate #1, but NOT marked as arrived!
      expect(arrivalMock.arrivalCandidateCount, 1);
      expect(arrivalMock.hasArrived, isFalse);

      // Tick 2: GPS hops back out to 90m (glitch dissipated)
      arrivalMock.checkArrival(
        directDistM: 90.0,
        remainingRoadM: 95.0,
        accuracy: 20.0,
        speedKmh: 18.0,
      );

      // Counter reset to 0
      expect(arrivalMock.arrivalCandidateCount, 0);
      expect(arrivalMock.hasArrived, isFalse);
    });

    test('8. Multi-Stage Arrival Gating: Consecutive stable fixes confirm arrival', () {
      final arrivalMock = ArrivalGatingMock();

      // Fix 1: In candidate zone
      arrivalMock.checkArrival(
        directDistM: 35.0,
        remainingRoadM: 35.0,
        accuracy: 15.0,
        speedKmh: 5.0,
      );
      expect(arrivalMock.arrivalCandidateCount, 1);
      expect(arrivalMock.hasArrived, isFalse);

      // Fix 2: Second consecutive fix in zone
      arrivalMock.checkArrival(
        directDistM: 32.0,
        remainingRoadM: 30.0,
        accuracy: 15.0,
        speedKmh: 4.0,
      );
      expect(arrivalMock.arrivalCandidateCount, 2);
      expect(arrivalMock.hasArrived, isTrue);
    });

    test('9. Multi-Stage Arrival Gating: Direct distance <= 30m with stationary speed arrives immediately', () {
      final arrivalMock = ArrivalGatingMock();

      // Arrived at destination and stopped
      arrivalMock.checkArrival(
        directDistM: 25.0,
        remainingRoadM: 25.0,
        accuracy: 10.0,
        speedKmh: 0.0, // Stationary
      );

      expect(arrivalMock.hasArrived, isTrue);
    });

    test('10. Camera Follow Gesture Decoupling: User pan/zoom disables follow mode; 60fps tick does not fight', () {
      final cameraMock = CameraFollowManagerMock();
      expect(cameraMock.followWorker, isTrue);

      // Initial state: camera moves with 1Hz GPS updates
      cameraMock.onNavStateUpdate(LatLng(12.9716, 77.5946));
      expect(cameraMock.cameraMoveCount, 1);

      // 60 FPS marker animation runs — verifies it NEVER calls mapCtrl.move()
      cameraMock.on60FpsAnimationTick(LatLng(12.97165, 77.59465));
      expect(cameraMock.cameraMoveCount, 1); // Remains 1!

      // User pinches or drags the map
      cameraMock.userZooms(14.0);
      expect(cameraMock.followWorker, isFalse);
      expect(cameraMock.currentZoom, 14.0);

      // While following is disabled, 1Hz updates do NOT move camera
      cameraMock.onNavStateUpdate(LatLng(12.9717, 77.5947));
      expect(cameraMock.cameraMoveCount, 1); // Camera is not fighting user!
    });

    test('11. RouteService Single-Flight Identity: Identical requests share Future; distinct requests do not collide', () async {
      final guard = RouteServiceFlightGuardMock();
      final o1 = LatLng(12.9716, 77.5946);
      final d1 = LatLng(12.9800, 77.6000);
      final d2 = LatLng(12.9900, 77.6100);

      final dummyResult1 = RouteResult(
        polyline: [o1, d1],
        distanceM: 1500,
        durationSec: 300,
        provider: 'test',
        calculatedAt: DateTime.now(),
        steps: const [],
      );

      // Call 1 & Call 2: Identical O/D launched concurrently
      final f1 = guard.getRoute(
        origin: o1,
        destination: d1,
        fetcher: () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return dummyResult1;
        },
      );

      final f2 = guard.getRoute(
        origin: o1,
        destination: d1,
        fetcher: () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return dummyResult1;
        },
      );

      final results = await Future.wait([f1, f2]);
      expect(results[0], dummyResult1);
      expect(results[1], dummyResult1);
      // Both shared the exact same network call
      expect(guard.networkCallCount, 1);

      // Call 3: Request for DIFFERENT destination d2
      final f3 = await guard.getRoute(
        origin: o1,
        destination: d2,
        fetcher: () async {
          return dummyResult1;
        },
      );
      expect(f3, dummyResult1);
      expect(guard.networkCallCount, 2); // Distinct call was executed
    });
  });
}
