// lib/features/tracking/services/worker_telemetry_service.dart
// Production-grade doze-proof background telemetry isolate service for workers.
// 2D Kalman filtering, adaptive cadence, offline ring buffer, and server-side disconnect hooks.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../../services/biometric_service.dart';
import '../domain/road_snapper.dart';
import '../data/models/live_telemetry_model.dart';

@pragma('vm:entry-point')
void startTelemetryCallback() {
  FlutterForegroundTask.setTaskHandler(WorkerTelemetryTaskHandler());
}

class WorkerTelemetryTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;
  Timer? _heartbeatTimer;

  String? _bookingId;
  String? _workerId;
  String _status = 'on_the_way';

  Position? _lastAcceptedPosition;
  DateTime? _lastWriteTime;
  double _lastHeading = 0.0;
  int _sequenceNumber = 0;
  bool _isFirebaseConnected = true;

  final KalmanLatLngFilter _kalmanFilter =
      KalmanLatLngFilter(processNoiseMetersPerSec: 3.2);
  final Queue<Map<String, dynamic>> _offlineRingBuffer =
      Queue<Map<String, dynamic>>();

  static const int _maxRingBufferSize = 25;
  static const double _maxAccuracyMeters = 35.0;
  static const double _maxRealisticSpeedMps = 45.0; // 162 km/h ceiling
  static const int _movingThrottleMs = 1350;
  static const int _stationaryHeartbeatSeconds = 5;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {}

    _bookingId = await FlutterForegroundTask.getData<String>(key: 'bookingId');
    _workerId = await FlutterForegroundTask.getData<String>(key: 'workerId');
    _status = await FlutterForegroundTask.getData<String>(key: 'status') ??
        'on_the_way';

    if (_bookingId == null || _workerId == null) return;

    _setupPresenceAndDisconnectHook();
    _startGpsStream();
    _startStationaryHeartbeat();
  }

  void _setupPresenceAndDisconnectHook() {
    final bookingId = _bookingId;
    if (bookingId == null) return;

    final connectedRef = FirebaseDatabase.instance.ref('.info/connected');
    final trackingRef =
        FirebaseDatabase.instance.ref('liveTracking/$bookingId');

    _connectionSub = connectedRef.onValue.listen((event) async {
      final connected = event.snapshot.value == true;
      _isFirebaseConnected = connected;

      if (connected) {
        await trackingRef.onDisconnect().update({
          'isOnline': false,
          'updatedAt': ServerValue.timestamp,
        });
        await _flushOfflineBuffer(trackingRef);
      }
    });
  }

  void _startGpsStream() {
    late final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: const Duration(milliseconds: 1000),
        forceLocationManager: false,
      );
    } else {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 2,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_handleIncomingPosition, onError: (_) {});
  }

  Future<void> _handleIncomingPosition(Position pos) async {
    final bookingId = _bookingId;
    final workerId = _workerId;
    if (bookingId == null || workerId == null) return;

    // Gate 1: Reject mathematically invalid coordinates and low-accuracy fixes (> 35m)
    if (!pos.latitude.isFinite ||
        pos.latitude.isNaN ||
        pos.latitude < -90.0 ||
        pos.latitude > 90.0 ||
        !pos.longitude.isFinite ||
        pos.longitude.isNaN ||
        pos.longitude < -180.0 ||
        pos.longitude > 180.0) {
      return;
    }
    if (pos.accuracy > _maxAccuracyMeters) return;

    final now = DateTime.now();

    // Gate 2: Throttle rapid burst emissions (< 1.35s)
    if (_lastWriteTime != null &&
        now.difference(_lastWriteTime!).inMilliseconds < _movingThrottleMs) {
      return;
    }

    // Gate 3: Impossible Speed / GPS Teleportation Gate (> 45 m/s)
    if (_lastAcceptedPosition != null) {
      final elapsedSeconds = pos.timestamp
              .difference(_lastAcceptedPosition!.timestamp)
              .inMilliseconds
              .abs() /
          1000.0;
      if (elapsedSeconds > 0.2) {
        final distMeters = Geolocator.distanceBetween(
          _lastAcceptedPosition!.latitude,
          _lastAcceptedPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final impliedSpeedMps = distMeters / elapsedSeconds;
        if (impliedSpeedMps > _maxRealisticSpeedMps && distMeters > 60.0) {
          return;
        }
      }
    }

    final rawSpeed = pos.speed.isFinite && pos.speed > 0 ? pos.speed : 0.0;

    // Gate 4: 2D Kinematic Kalman Smoothing
    final smoothedLatLng = _kalmanFilter.process(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      timestampMs: now.millisecondsSinceEpoch,
      speedMps: rawSpeed,
    );

    // Compute stable heading (prefer GPS heading when moving, else geometric bearing)
    double resolvedHeading = _lastHeading;
    if (pos.heading.isFinite && pos.heading >= 0 && rawSpeed >= 1.2) {
      resolvedHeading = pos.heading % 360.0;
    } else if (_lastAcceptedPosition != null) {
      final movedDist = Geolocator.distanceBetween(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
        smoothedLatLng.latitude,
        smoothedLatLng.longitude,
      );
      if (movedDist >= 2.5) {
        resolvedHeading = RoadSnapper.calculateBearing(
          LatLng(
            _lastAcceptedPosition!.latitude,
            _lastAcceptedPosition!.longitude,
          ),
          smoothedLatLng,
        );
      }
    }

    _lastAcceptedPosition = pos;
    _lastHeading = resolvedHeading;
    _lastWriteTime = now;
    _sequenceNumber++;

    final telemetry = LiveTelemetryModel(
      lat: smoothedLatLng.latitude,
      lng: smoothedLatLng.longitude,
      heading: resolvedHeading,
      speedMps: rawSpeed,
      accuracy: pos.accuracy,
      updatedAtMs: now.millisecondsSinceEpoch,
      workerId: workerId,
      status: _status,
      isSeed: false,
      isOnline: true,
      seq: _sequenceNumber,
    );

    await _publishTelemetry(bookingId, telemetry.toMap());
  }

  void _startStationaryHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _stationaryHeartbeatSeconds),
      (_) async {
        final bookingId = _bookingId;
        final workerId = _workerId;
        final lastPos = _lastAcceptedPosition;
        if (bookingId == null || workerId == null || lastPos == null) return;

        final now = DateTime.now();
        if (_lastWriteTime != null &&
            now.difference(_lastWriteTime!).inSeconds <
                _stationaryHeartbeatSeconds - 1) {
          return;
        }

        _lastWriteTime = now;
        try {
          await FirebaseDatabase.instance
              .ref('liveTracking/$bookingId')
              .update({
            'updatedAt': now.millisecondsSinceEpoch,
            'speedMps': 0.0,
            'isOnline': true,
            'isSeed': false,
          });
        } catch (_) {}
      },
    );
  }

  Future<void> _publishTelemetry(
    String bookingId,
    Map<String, dynamic> payload,
  ) async {
    final ref = FirebaseDatabase.instance.ref('liveTracking/$bookingId');
    if (!_isFirebaseConnected) {
      _enqueueOffline(payload);
      return;
    }

    try {
      await ref.update(payload).timeout(const Duration(seconds: 3));
      FlutterForegroundTask.sendDataToMain(payload);
    } catch (_) {
      _enqueueOffline(payload);
    }
  }

  void _enqueueOffline(Map<String, dynamic> payload) {
    if (_offlineRingBuffer.length >= _maxRingBufferSize) {
      _offlineRingBuffer.removeFirst();
    }
    _offlineRingBuffer.addLast(payload);
  }

  Future<void> _flushOfflineBuffer(DatabaseReference ref) async {
    if (_offlineRingBuffer.isEmpty) return;
    final latestPayload = _offlineRingBuffer.last;
    _offlineRingBuffer.clear();
    try {
      await ref.update(latestPayload);
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data['action'] == 'safety_stop_clear' || data['action'] == 'clear_queue') {
        _offlineRingBuffer.clear();
      }
      final newStatus = data['status']?.toString();
      if (newStatus != null && newStatus.isNotEmpty) {
        _status = newStatus;
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _offlineRingBuffer.clear();
    await _positionSub?.cancel();
    await _connectionSub?.cancel();
    _heartbeatTimer?.cancel();

    final bookingId = _bookingId;
    if (bookingId != null) {
      try {
        await FirebaseDatabase.instance
            .ref('liveTracking/$bookingId')
            .update({
          'isOnline': false,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
  }
}

class WorkerTelemetryService {
  WorkerTelemetryService._();
  static final WorkerTelemetryService instance = WorkerTelemetryService._();

  bool _isInitialized = false;

  Future<void> initService() async {
    if (_isInitialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kelasagara_live_telemetry_v2',
        channelName: 'Kelasagaara Live Worker Navigation',
        channelDescription:
            'Shares real-time worker ETA and road location with your Hirer.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _isInitialized = true;
  }

  Future<void> startTracking({
    required String bookingId,
    required String workerId,
    String status = 'on_the_way',
    String? hirerId,
    String? jobId,
    LatLng? destination,
  }) async {
    await initService();

    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.saveData(key: 'bookingId', value: bookingId);
    await FlutterForegroundTask.saveData(key: 'workerId', value: workerId);
    if (destination != null) {
      await FlutterForegroundTask.saveData(
        key: 'destLat',
        value: destination.latitude.toString(),
      );
      await FlutterForegroundTask.saveData(
        key: 'destLng',
        value: destination.longitude.toString(),
      );
    }
    if (hirerId != null) {
      await FlutterForegroundTask.saveData(key: 'hirerId', value: hirerId);
    }
    if (jobId != null) {
      await FlutterForegroundTask.saveData(key: 'jobId', value: jobId);
    }
    await FlutterForegroundTask.saveData(key: 'status', value: status);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 4102,
        notificationTitle: 'ಕೆಲಸಗಾರ ಲೈವ್ ಟ್ರ್ಯಾಕಿಂಗ್ • Live Journey Active',
        notificationText:
            'Sharing live road ETA with Hirer. Tap to return to journey.',
        callback: startTelemetryCallback,
      );
    }
  }

  /// Backward-compatible alias for startTracking.
  Future<void> startBackgroundTracking({
    required String bookingId,
    required String workerId,
    String? hirerId,
    String? jobId,
    String status = 'on_the_way',
    LatLng? destination,
  }) =>
      startTracking(
        bookingId: bookingId,
        workerId: workerId,
        hirerId: hirerId,
        jobId: jobId,
        status: status,
        destination: destination,
      );

  Future<void> updateJourneyStatus(String status) async {
    await FlutterForegroundTask.saveData(key: 'status', value: status);
    FlutterForegroundTask.sendDataToTask({'status': status});
  }

  Future<void> stopTracking() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Backward-compatible alias for stopTracking.
  Future<void> stopBackgroundTracking() => stopTracking();

  /// Worker safety-stop trigger:
  /// Halts local background tracking immediately for personal safety,
  /// then notifies backend without triggering auto-cancellation or financial penalties.
  Future<bool> triggerSafetyStop({
    required String bookingId,
    required String workerId,
    String? reason,
  }) async {
    // 1. Immediately signal foreground task to purge all queued offline fixes
    FlutterForegroundTask.sendDataToTask({'action': 'safety_stop_clear'});

    // 2. Immediately cease local location updates
    await stopTracking();

    // 2. Transmit safety stop event to backend
    try {
      final base = BiometricService.resolveDefaultEndpoint()
          .replaceAll(RegExp(r'/biometrics/?$'), '');
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final uri = Uri.parse('$base/journey/safety-stop');
      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': bookingId,
          'reason': reason ?? 'Worker halted tracking for personal safety',
        }),
      ).timeout(const Duration(seconds: 10));

      return resp.statusCode == 200;
    } catch (_) {
      // Local collection is reliably stopped regardless of backend connectivity
      return false;
    }
  }
}
