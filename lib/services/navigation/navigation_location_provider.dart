// lib/services/navigation/navigation_location_provider.dart
// ============================================================================
// KELASAGARA — Single Authoritative Real GPS Engine (Phase 6 Redesign)
//
// Responsibilities:
//   - Staged bounded GPS bootstrap:
//       1. Hardware location service check
//       2. Permission verification / request
//       3. Precise / reduced location inspection
//       4. Recent cached fix evaluation (freshness <= 60s)
//       5. Concurrent active acquisition + stream race (first usable wins)
//       6. Continuous 1Hz hardware GPS stream for live guidance
//   - Diagnostic logging: GPS_START, GPS_PERMISSION, GPS_SERVICE,
//     GPS_CACHED_RESULT, GPS_CURRENT_REQUEST, GPS_FIRST_FIX,
//     GPS_FIX_ACCEPTED, GPS_FIX_REJECTED, GPS_FAILURE
//   - Zero fake GPS, zero hardcoded centroids, zero silent fallbacks.
//   - Teardown: cancels listeners, prevents zombie subscriptions.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../models/live_location.dart';
import '../../models/navigation_health.dart';
import '../routing/gps_quality_engine.dart';

enum GpsState {
  unknown,
  searching,
  valid,
  weak,
  lost,
}

class GpsBootstrapResult {
  final bool isSuccess;
  final LiveLocation? location;
  final GpsStatus status;
  final String? errorMessage;
  final String source; // 'cached', 'current_position', 'stream'
  final int latencyMs;

  const GpsBootstrapResult({
    required this.isSuccess,
    this.location,
    required this.status,
    this.errorMessage,
    this.source = 'none',
    this.latencyMs = 0,
  });

  factory GpsBootstrapResult.success(
    LiveLocation location, {
    required String source,
    required int latencyMs,
  }) =>
      GpsBootstrapResult(
        isSuccess: true,
        location: location,
        status: GpsStatus.ready,
        source: source,
        latencyMs: latencyMs,
      );

  factory GpsBootstrapResult.failure(
    GpsStatus status,
    String message, {
    int latencyMs = 0,
  }) =>
      GpsBootstrapResult(
        isSuccess: false,
        status: status,
        errorMessage: message,
        latencyMs: latencyMs,
      );
}

class NavigationLocationProvider {
  NavigationLocationProvider._();
  static final NavigationLocationProvider instance =
      NavigationLocationProvider._();

  StreamSubscription<Position>? _gpsSub;
  final StreamController<LiveLocation> _rawLocationController =
      StreamController<LiveLocation>.broadcast();
  final StreamController<LatLng> _matchedLocationController =
      StreamController<LatLng>.broadcast();
  final StreamController<GpsState> _gpsStateController =
      StreamController<GpsState>.broadcast();

  LiveLocation? _lastRawLocation;
  LatLng? _lastMatchedLocation;
  GpsState _currentState = GpsState.unknown;
  DateTime? _lastFixTime;
  Timer? _lossWatchdogTimer;

  Stream<LiveLocation> get rawLocationStream => _rawLocationController.stream;
  Stream<LatLng> get matchedLocationStream => _matchedLocationController.stream;
  Stream<GpsState> get gpsStateStream => _gpsStateController.stream;

  LiveLocation? get lastRawLocation => _lastRawLocation;
  LatLng? get lastMatchedLocation => _lastMatchedLocation;
  GpsState get currentState => _currentState;
  bool get isStreaming => _gpsSub != null;

  /// Check location permission.
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission.
  Future<LocationPermission> requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm;
  }

  /// Check if hardware location services (GPS) are enabled.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Bounded staged startup implementing Phase 6 & 7 requirements:
  ///   - Checks service, permission, cached fix, and races active request with stream.
  ///   - Diagnostic logging for every milestone.
  Future<GpsBootstrapResult> acquireInitialPosition({
    required String sessionId,
    required String requestId,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[GPS_START] sessionId=$sessionId requestId=$requestId elapsedMs=0');

    // STEP 1: Location Services Check
    final serviceEnabled = await isLocationServiceEnabled();
    debugPrint('[GPS_SERVICE] enabled=$serviceEnabled sessionId=$sessionId elapsedMs=${sw.elapsedMilliseconds}');
    if (!serviceEnabled) {
      debugPrint('[GPS_FAILURE] sessionId=$sessionId reason=service_disabled elapsedMs=${sw.elapsedMilliseconds}');
      return GpsBootstrapResult.failure(
        GpsStatus.serviceDisabled,
        'Device location service (GPS) is turned off. Please enable location in system settings.',
        latencyMs: sw.elapsedMilliseconds,
      );
    }

    // STEP 2 & 3: Permission Check & Request
    LocationPermission perm = await checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await requestPermission();
    }
    debugPrint('[GPS_PERMISSION] status=$perm sessionId=$sessionId elapsedMs=${sw.elapsedMilliseconds}');
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      debugPrint('[GPS_FAILURE] sessionId=$sessionId reason=permission_denied elapsedMs=${sw.elapsedMilliseconds}');
      return GpsBootstrapResult.failure(
        GpsStatus.permissionDenied,
        'Location permission is required for Kelasagara turn-by-turn navigation.',
        latencyMs: sw.elapsedMilliseconds,
      );
    }

    // STEP 4: Precision Check
    try {
      final accuracyStatus = await Geolocator.getLocationAccuracy();
      debugPrint('[GPS_ACCURACY_STATUS] status=$accuracyStatus sessionId=$sessionId');
    } catch (_) {}

    // STEP 5 & 6: Cached Recent Fix Check
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        final ageMs = DateTime.now().difference(cached.timestamp).inMilliseconds.abs();
        final isUsable = GpsQualityEngine.instance.isUsableForRouting(cached);
        debugPrint('[GPS_CACHED_RESULT] usable=$isUsable accuracy=${cached.accuracy}m locationAgeMs=$ageMs elapsedMs=${sw.elapsedMilliseconds}');
        if (isUsable && ageMs <= 60000) {
          final loc = LiveLocation.fromPosition(cached);
          _lastRawLocation = loc;
          _lastFixTime = DateTime.now();
          _updateGpsState(loc.accuracy <= 50.0 ? GpsState.valid : GpsState.weak);
          debugPrint('[GPS_FIRST_FIX] source=cached accuracy=${loc.accuracy}m locationAgeMs=$ageMs elapsedMs=${sw.elapsedMilliseconds}');
          debugPrint('[GPS_FIX_ACCEPTED] source=cached accuracy=${loc.accuracy}m elapsedMs=${sw.elapsedMilliseconds}');
          return GpsBootstrapResult.success(loc, source: 'cached', latencyMs: sw.elapsedMilliseconds);
        }
      } else {
        debugPrint('[GPS_CACHED_RESULT] usable=false reason=no_cached_position elapsedMs=${sw.elapsedMilliseconds}');
      }
    } catch (e) {
      debugPrint('[GPS_CACHED_RESULT] error=$e elapsedMs=${sw.elapsedMilliseconds}');
    }

    // STEP 7 & 8: Active Acquisition & Stream Race
    debugPrint('[GPS_CURRENT_REQUEST] sessionId=$sessionId timeout=${timeout.inSeconds}s elapsedMs=${sw.elapsedMilliseconds}');
    final completer = Completer<GpsBootstrapResult>();

    StreamSubscription<Position>? primeSub;
    primeSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500),
      ),
    ).listen((pos) {
      final ageMs = DateTime.now().difference(pos.timestamp).inMilliseconds.abs();
      if (GpsQualityEngine.instance.isUsableForRouting(pos)) {
        if (!completer.isCompleted) {
          debugPrint('[GPS_FIRST_FIX] source=stream accuracy=${pos.accuracy}m locationAgeMs=$ageMs elapsedMs=${sw.elapsedMilliseconds}');
          debugPrint('[GPS_FIX_ACCEPTED] source=stream accuracy=${pos.accuracy}m elapsedMs=${sw.elapsedMilliseconds}');
          final loc = LiveLocation.fromPosition(pos);
          _lastRawLocation = loc;
          _lastFixTime = DateTime.now();
          _updateGpsState(loc.accuracy <= 50.0 ? GpsState.valid : GpsState.weak);
          completer.complete(GpsBootstrapResult.success(loc, source: 'stream', latencyMs: sw.elapsedMilliseconds));
        }
      } else {
        debugPrint('[GPS_FIX_REJECTED] source=stream accuracy=${pos.accuracy}m reason=quality_check_failed elapsedMs=${sw.elapsedMilliseconds}');
      }
    }, onError: (e) {
      debugPrint('[GPS_STREAM_ERROR] $e');
    });

    Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    ).then((pos) {
      final ageMs = DateTime.now().difference(pos.timestamp).inMilliseconds.abs();
      if (GpsQualityEngine.instance.isUsableForRouting(pos)) {
        if (!completer.isCompleted) {
          debugPrint('[GPS_FIRST_FIX] source=current_position accuracy=${pos.accuracy}m locationAgeMs=$ageMs elapsedMs=${sw.elapsedMilliseconds}');
          debugPrint('[GPS_FIX_ACCEPTED] source=current_position accuracy=${pos.accuracy}m elapsedMs=${sw.elapsedMilliseconds}');
          final loc = LiveLocation.fromPosition(pos);
          _lastRawLocation = loc;
          _lastFixTime = DateTime.now();
          _updateGpsState(loc.accuracy <= 50.0 ? GpsState.valid : GpsState.weak);
          completer.complete(GpsBootstrapResult.success(loc, source: 'current_position', latencyMs: sw.elapsedMilliseconds));
        }
      } else {
        debugPrint('[GPS_FIX_REJECTED] source=current_position accuracy=${pos.accuracy}m reason=quality_check_failed elapsedMs=${sw.elapsedMilliseconds}');
      }
    }).catchError((e) {
      debugPrint('[GPS_CURRENT_ERROR] $e elapsedMs=${sw.elapsedMilliseconds}');
    });

    Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('[GPS_FAILURE] reason=timeout_exceeded elapsedMs=${sw.elapsedMilliseconds}');
        completer.complete(GpsBootstrapResult.failure(
          GpsStatus.unavailable,
          'Unable to acquire a usable device location within ${timeout.inSeconds} seconds.',
          latencyMs: sw.elapsedMilliseconds,
        ));
      }
    });

    final res = await completer.future;
    await primeSub.cancel();
    return res;
  }

  /// Backward-compatible wrapper for getFreshLocation.
  Future<LiveLocation?> getFreshLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final res = await acquireInitialPosition(
      sessionId: 'sess_fresh_${DateTime.now().millisecondsSinceEpoch}',
      requestId: 'req_fresh',
      timeout: timeout,
    );
    return res.location;
  }

  /// Starts the continuous authoritative 1Hz hardware GPS stream.
  Future<bool> startContinuousStream({
    required void Function(LiveLocation rawLoc) onLocation,
    void Function(GpsState state)? onStateChanged,
  }) async {
    await stopContinuousStream();

    final perm = await requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _updateGpsState(GpsState.lost);
      return false;
    }

    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      _updateGpsState(GpsState.lost);
      return false;
    }

    _updateGpsState(GpsState.searching);

    // Warm up with recent location in parallel
    if (_lastRawLocation != null) {
      onLocation(_lastRawLocation!);
    }

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
      intervalDuration: const Duration(seconds: 1),
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _handleRawPosition(pos);
        if (_lastRawLocation != null) {
          onLocation(_lastRawLocation!);
        }
      },
      onError: (err) {
        debugPrint('[NavLocationProvider] Stream error: $err');
        _updateGpsState(GpsState.lost);
      },
    );

    _startWatchdog();
    return true;
  }

  void _handleRawPosition(Position pos) {
    _lastFixTime = DateTime.now();

    if (!GpsQualityEngine.instance.isUsableForRouting(pos)) {
      debugPrint('[NavLocationProvider] Live fix rejected: accuracy=${pos.accuracy}m');
      if (pos.accuracy > 70.0) {
        _updateGpsState(GpsState.weak);
      }
      return;
    }

    final loc = LiveLocation.fromPosition(pos);
    _lastRawLocation = loc;
    _rawLocationController.add(loc);

    if (loc.accuracy <= 50.0) {
      _updateGpsState(GpsState.valid);
    } else {
      _updateGpsState(GpsState.weak);
    }
  }

  /// Sets the route-projected matched location (separate from raw GPS).
  void setMatchedLocation(LatLng matched) {
    _lastMatchedLocation = matched;
    _matchedLocationController.add(matched);
  }

  void _updateGpsState(GpsState state) {
    if (_currentState != state) {
      _currentState = state;
      _gpsStateController.add(state);
    }
  }

  void _startWatchdog() {
    _lossWatchdogTimer?.cancel();
    _lossWatchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_lastFixTime != null) {
        final age = DateTime.now().difference(_lastFixTime!);
        if (age.inSeconds >= 15 && _currentState != GpsState.lost) {
          debugPrint('[NavLocationProvider] Watchdog: GPS lost (last fix ${age.inSeconds}s ago)');
          _updateGpsState(GpsState.lost);
        }
      }
    });
  }

  /// Fully cancels and tears down the continuous GPS stream and watchdog.
  Future<void> stopContinuousStream() async {
    _lossWatchdogTimer?.cancel();
    _lossWatchdogTimer = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _currentState = GpsState.unknown;
  }
}
