// lib/features/tracking/services/worker_gmaps_telemetry_service.dart
// Production-grade doze-proof background telemetry isolate service for workers.
// Streams rolling 5-point micro-trail, 2D Kalman filtering, and geofence dwell alerts
// while worker navigates in external Google Maps.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/biometric_service.dart';
import '../domain/geofence_dwell_engine.dart';
import '../domain/road_snapper.dart';

@pragma('vm:entry-point')
void startWorkerGmapsTelemetryCallback() {
  FlutterForegroundTask.setTaskHandler(WorkerGmapsTelemetryTaskHandler());
}

class WorkerGmapsTelemetryTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;
  Timer? _heartbeatTimer;

  String? _bookingId;
  String? _workerId;
  String _status = 'on_the_way';

  GeofenceDwellEngine? _geofenceEngine;
  Position? _lastAcceptedPosition;
  DateTime? _lastWriteTime;
  double _lastHeading = 0.0;
  int _sequenceNumber = 0;
  bool _isFirebaseConnected = true;

  final KalmanLatLngFilter _kalmanFilter =
      KalmanLatLngFilter(processNoiseMetersPerSec: 3.0);

  /// Rolling 5-point micro-trail so the Hirer's OSM map renders exact corner curves
  final Queue<Map<String, double>> _recentTrail = Queue<Map<String, double>>();
  final Queue<Map<String, dynamic>> _offlineRingBuffer =
      Queue<Map<String, dynamic>>();

  static const double _maxAccuracyMeters = 35.0;
  static const double _maxRealisticSpeedMps = 45.0;
  static const int _movingThrottleMs = 1200;

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

    final destLat = await FlutterForegroundTask.getData<double>(key: 'destLat');
    final destLng = await FlutterForegroundTask.getData<double>(key: 'destLng');

    if (destLat != null && destLng != null) {
      _geofenceEngine = GeofenceDwellEngine(
        destination: LatLng(destLat, destLng),
        initialStage: GeofenceStage.fromWire(_status),
      );
    }

    if (_bookingId == null || _workerId == null) return;

    _setupDisconnectHook();
    _startHighPrecisionGpsStream();
    _startHeartbeat();
  }

  void _setupDisconnectHook() {
    final bookingId = _bookingId;
    if (bookingId == null) return;

    final trackingRef =
        FirebaseDatabase.instance.ref('liveTracking/$bookingId');
    _connectionSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) async {
      _isFirebaseConnected = event.snapshot.value == true;
      if (_isFirebaseConnected) {
        await trackingRef.onDisconnect().update({
          'isOnline': false,
          'updatedAt': ServerValue.timestamp,
        });
        if (_offlineRingBuffer.isNotEmpty) {
          final latest = _offlineRingBuffer.last;
          _offlineRingBuffer.clear();
          try {
            await trackingRef.update(latest);
          } catch (_) {}
        }
      }
    });
  }

  void _startHighPrecisionGpsStream() {
    late final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: const Duration(milliseconds: 1000),
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
        .listen(_onGpsFix, onError: (_) {});
  }

  Future<void> _onGpsFix(Position pos) async {
    final bookingId = _bookingId;
    final workerId = _workerId;
    if (bookingId == null || workerId == null) return;

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
    if (_lastWriteTime != null &&
        now.difference(_lastWriteTime!).inMilliseconds < _movingThrottleMs) {
      return;
    }

    if (_lastAcceptedPosition != null) {
      final dt = pos.timestamp
              .difference(_lastAcceptedPosition!.timestamp)
              .inMilliseconds
              .abs() /
          1000.0;
      if (dt > 0.2) {
        final d = Geolocator.distanceBetween(
          _lastAcceptedPosition!.latitude,
          _lastAcceptedPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if ((d / dt) > _maxRealisticSpeedMps && d > 60.0) return;
      }
    }

    final rawSpeed = pos.speed.isFinite && pos.speed > 0 ? pos.speed : 0.0;

    final smoothed = _kalmanFilter.process(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      timestampMs: now.millisecondsSinceEpoch,
      speedMps: rawSpeed,
    );

    // Evaluate 150m Approaching / 75m Arrived Geofences
    if (_geofenceEngine != null) {
      final rawPosition = LatLng(pos.latitude, pos.longitude);
      final eval = _geofenceEngine!.evaluateFix(
        workerPosition: rawPosition, // Explicitly evaluated on RAW GPS fix (not smoothed display marker)
        speedMps: rawSpeed,
        accuracyMeters: pos.accuracy,
        timestamp: now,
        isSeed: false,
      );
      if (eval.hasTransition) {
        _status = eval.currentStage.wireValue;
        await _persistGeofenceMilestone(bookingId, eval, smoothed);
      }
    }

    double resolvedHeading = _lastHeading;
    if (pos.heading.isFinite && pos.heading >= 0 && rawSpeed >= 1.2) {
      resolvedHeading = pos.heading % 360.0;
    } else if (_lastAcceptedPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
        smoothed.latitude,
        smoothed.longitude,
      );
      if (moved >= 2.2) {
        resolvedHeading = RoadSnapper.calculateBearing(
          LatLng(
            _lastAcceptedPosition!.latitude,
            _lastAcceptedPosition!.longitude,
          ),
          smoothed,
        );
      }
    }

    // Update rolling 5-point micro-trail
    if (_recentTrail.length >= 5) {
      _recentTrail.removeFirst();
    }
    _recentTrail.addLast({
      'lat': double.parse(smoothed.latitude.toStringAsFixed(6)),
      'lng': double.parse(smoothed.longitude.toStringAsFixed(6)),
    });

    _lastAcceptedPosition = pos;
    _lastHeading = resolvedHeading;
    _lastWriteTime = now;
    _sequenceNumber++;

    final payload = <String, dynamic>{
      'lat': double.parse(smoothed.latitude.toStringAsFixed(6)),
      'lng': double.parse(smoothed.longitude.toStringAsFixed(6)),
      'heading': double.parse(resolvedHeading.toStringAsFixed(1)),
      'speedMps': double.parse(rawSpeed.toStringAsFixed(2)),
      'accuracy': double.parse(pos.accuracy.toStringAsFixed(1)),
      'updatedAt': now.millisecondsSinceEpoch,
      'workerId': workerId,
      'status': _status,
      'isSeed': false,
      'isOnline': true,
      'navSource': 'google_maps_external',
      'seq': _sequenceNumber,
      'trail': _recentTrail.toList(),
    };

    final ref = FirebaseDatabase.instance.ref('liveTracking/$bookingId');
    if (!_isFirebaseConnected) {
      if (_offlineRingBuffer.length >= 20) _offlineRingBuffer.removeFirst();
      _offlineRingBuffer.addLast(payload);
      return;
    }

    try {
      await ref.update(payload).timeout(const Duration(seconds: 3));
    } catch (_) {
      if (_offlineRingBuffer.length >= 20) _offlineRingBuffer.removeFirst();
      _offlineRingBuffer.addLast(payload);
    }
  }

  Future<void> _persistGeofenceMilestone(
    String bookingId,
    GeofenceEvaluationResult eval,
    LatLng pos,
  ) async {
    final bookingDoc =
        FirebaseFirestore.instance.collection('bookings').doc(bookingId);
    try {
      if (eval.didTransitionToApproaching) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'ಹತ್ತಿರದಲ್ಲಿದ್ದೀರಿ • Within 150m of Hirer',
          notificationText:
              'Hirer notified on their map. Prepare to arrive shortly.',
        );
        await bookingDoc.set(
          {
            'journeySubStatus': 'approaching',
            'approachingAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else if (eval.didTransitionToArrived) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'ತಲುಪಿದ್ದೀರಿ! • Tap to Enter 6-Digit Arrival OTP',
          notificationText:
              'You have reached the Hirer location (within 75m). Tap to return to Kelasagaara.',
        );
        await bookingDoc.set(
          {
            'status': 'arrived',
            'trackingStatus': 'arrived',
            'arrivalStatus': 'arrived',
            'arrivedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final bookingId = _bookingId;
      if (bookingId == null || _lastAcceptedPosition == null) return;
      final now = DateTime.now();
      if (_lastWriteTime != null &&
          now.difference(_lastWriteTime!).inSeconds < 4) {
        return;
      }
      _lastWriteTime = now;
      try {
        await FirebaseDatabase.instance.ref('liveTracking/$bookingId').update({
          'updatedAt': now.millisecondsSinceEpoch,
          'speedMps': 0.0,
          'isOnline': true,
          'isSeed': false,
        });
      } catch (_) {}
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data['action'] == 'safety_stop_clear' || data['action'] == 'clear_queue') {
        _offlineRingBuffer.clear();
        _recentTrail.clear();
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
    _recentTrail.clear();
    await _positionSub?.cancel();
    await _connectionSub?.cancel();
    _heartbeatTimer?.cancel();
  }
}

class WorkerGmapsTelemetryService {
  WorkerGmapsTelemetryService._();
  static final WorkerGmapsTelemetryService instance =
      WorkerGmapsTelemetryService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kelasagara_gmaps_shadow_v3',
        channelName: 'Kelasagaara Google Maps Live Sync',
        channelDescription:
            'Broadcasts your live GPS to the Hirer OpenStreetMap view while you navigate in Google Maps.',
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
    _initialized = true;
  }

  /// Starts the Doze-proof isolate AND immediately launches external Google Maps turn-by-turn navigation.
  Future<void> startShadowTrackingAndOpenGoogleMaps({
    required String bookingId,
    required String workerId,
    required LatLng destination,
    bool twoWheelerMode = true,
  }) async {
    await init();

    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.saveData(key: 'bookingId', value: bookingId);
    await FlutterForegroundTask.saveData(key: 'workerId', value: workerId);
    await FlutterForegroundTask.saveData(key: 'status', value: 'on_the_way');
    await FlutterForegroundTask.saveData(
      key: 'destLat',
      value: destination.latitude,
    );
    await FlutterForegroundTask.saveData(
      key: 'destLng',
      value: destination.longitude,
    );

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 4105,
        notificationTitle: 'ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ ಸಿಂಕ್ ಸಕ್ರಿಯ • Live Sync Active',
        notificationText:
            'Hirer can see your live progress. Tap to return to Kelasagaara.',
        callback: startWorkerGmapsTelemetryCallback,
      );
    }

    // Launch external Google Maps app in Two-Wheeler ('l') or Driving ('d') mode
    final lat = destination.latitude.toStringAsFixed(6);
    final lng = destination.longitude.toStringAsFixed(6);
    final modeCode = twoWheelerMode ? 'l' : 'd';

    if (!kIsWeb && Platform.isAndroid) {
      final intentUri =
          Uri.parse('google.navigation:q=$lat,$lng&mode=$modeCode');
      if (await canLaunchUrl(intentUri)) {
        await launchUrl(
          intentUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        return;
      }
    }

    final fallbackUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
      '&travelmode=${twoWheelerMode ? "two-wheeler" : "driving"}&dir_action=navigate',
    );
    await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
  }

  /// Stops background telemetry service when job has started or completed.
  Future<void> stopShadowTracking() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Worker safety-stop trigger:
  /// Halts local background tracking immediately for personal safety,
  /// then notifies backend without triggering auto-cancellation or financial penalties.
  Future<bool> triggerSafetyStop({
    required String bookingId,
    required String workerId,
    String? reason,
  }) async {
    // 1. Immediately signal isolate task to clear any queued offline telemetry
    FlutterForegroundTask.sendDataToTask({'action': 'safety_stop_clear'});

    // 2. Immediately cease local location updates
    await stopShadowTracking();

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
