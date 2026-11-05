import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/enu_kalman_filter.dart';

@pragma('vm:entry-point')
void startEnterpriseTelemetryIsolate() {
  FlutterForegroundTask.setTaskHandler(EnterpriseWorkerTelemetryHandler());
}

class EnterpriseWorkerTelemetryHandler extends TaskHandler {
  StreamSubscription<Position>? _posSub;
  StreamSubscription<DatabaseEvent>? _connSub;
  final EnuKinematicKalmanFilter _kalman = EnuKinematicKalmanFilter();
  final Queue<Map<String, dynamic>> _microTrail = Queue<Map<String, dynamic>>();
  final Queue<Map<String, dynamic>> _offlineSpool = Queue<Map<String, dynamic>>();

  String? _bookingId;
  String? _workerId;
  int _seq = 1;
  double _lastTransmittedHeading = 0.0;
  DateTime _lastRtdbTransmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isRtdbConnected = true;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp();
    _bookingId = await FlutterForegroundTask.getData<String>(key: 'bookingId');
    _workerId = await FlutterForegroundTask.getData<String>(key: 'workerId');
    if (_bookingId == null || _workerId == null) return;

    final DatabaseReference trackingRef =
        FirebaseDatabase.instance.ref('liveTracking/$_bookingId');

    // 1. Register Server-Side Presence & Crash Hook (`onDisconnect`)
    _connSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) async {
      _isRtdbConnected = (event.snapshot.value as bool?) ?? false;
      if (_isRtdbConnected) {
        await trackingRef.onDisconnect().update({
          'connectionState': 'disconnected',
          'disconnectedAt': ServerValue.timestamp,
        });
        await trackingRef.update({'connectionState': 'online'});
        _flushOfflineSpool(trackingRef);
      }
    });

    // 2. Attach to FusedLocationProvider (Piggybacks on Google Maps 1Hz GNSS lock)
    final LocationSettings settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(milliseconds: 900),
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onHardwareLocationFix, onError: (_) {});
  }

  Future<void> _onHardwareLocationFix(Position pos) async {
    if (_bookingId == null) return;

    // 1. ANTI-FRAUD SHIELD: Detect Fake GPS / Mock Location Spoofing Apps
    if (pos.isMocked) {
      await FirebaseDatabase.instance.ref('liveTracking/$_bookingId').update({
        'isMockLocationFlagged': true,
        'connectionState': 'tampered',
        'updatedAt': ServerValue.timestamp,
      });
      return;
    }

    if (pos.accuracy > 42.0) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final double rawHeading =
        (pos.heading >= 0.0 && pos.heading <= 360.0) ? pos.heading : 0.0;
    final double rawSpeed = pos.speed >= 0.0 ? pos.speed : 0.0;

    // 2. Run 4-State ENU Kinematic Kalman Filter + Mahalanobis Gate
    final FilteredKinematics kState = _kalman.processMeasurement(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      rawSpeedMps: rawSpeed,
      rawHeadingDeg: rawHeading,
      timestampMs: nowMs,
    );

    if (kState.wasOutlierRejected) return;

    // 3. Append to 5-Point Rolling Micro-Trail with exact timestamps
    final Map<String, dynamic> trailVertex = {
      'lat': double.parse(kState.position.latitude.toStringAsFixed(6)),
      'lng': double.parse(kState.position.longitude.toStringAsFixed(6)),
      'hdg': double.parse(kState.headingDeg.toStringAsFixed(1)),
      'spd': double.parse(kState.speedMps.toStringAsFixed(2)),
      'ts': nowMs,
    };

    _microTrail.addLast(trailVertex);
    while (_microTrail.length > 5) {
      _microTrail.removeFirst();
    }

    // 4. DYNAMIC TURN-AWARE CADENCE GOVERNOR
    final double headingDelta =
        _angularDelta(kState.headingDeg, _lastTransmittedHeading);
    final int elapsedMs =
        DateTime.now().difference(_lastRtdbTransmit).inMilliseconds;

    // - High-frequency (1000ms) when cornering (> 10 deg turn) so corners never clip
    // - Medium-frequency (1800ms) when cruising straight
    // - Low-frequency (4500ms) when stopped at traffic signals (< 0.6 m/s)
    final int targetIntervalMs = (kState.speedMps < 0.6)
        ? 4500
        : (headingDelta >= 10.0 ? 1000 : 1800);

    if (elapsedMs < targetIntervalMs) return;

    _lastRtdbTransmit = DateTime.now();
    _lastTransmittedHeading = kState.headingDeg;
    _seq++;

    final Map<String, dynamic> payload = {
      'workerId': _workerId,
      'lat': kState.position.latitude,
      'lng': kState.position.longitude,
      'heading': kState.headingDeg,
      'speedMps': kState.speedMps,
      'accuracy': pos.accuracy,
      'altitude': pos.altitude,
      'seq': _seq,
      'isSeed': false,
      'isMockLocationFlagged': false,
      'connectionState': 'online',
      'navSource': 'google_maps_shadow_v2',
      'trail': _microTrail.toList(),
      'clientTs': nowMs,
      'updatedAt': ServerValue.timestamp,
    };

    final DatabaseReference ref =
        FirebaseDatabase.instance.ref('liveTracking/$_bookingId');

    if (_isRtdbConnected) {
      await ref.update(payload);
    } else {
      // Spool locally during 4G dead zones (e.g., underpasses)
      _offlineSpool.addLast(payload);
      while (_offlineSpool.length > 10) {
        _offlineSpool.removeFirst();
      }
    }
  }

  Future<void> _flushOfflineSpool(DatabaseReference ref) async {
    if (_offlineSpool.isEmpty) return;
    final Map<String, dynamic> latest = _offlineSpool.last;
    _offlineSpool.clear();
    await ref.update(latest);
  }

  double _angularDelta(double a, double b) {
    final double d = (a - b).abs() % 360.0;
    return d > 180.0 ? 360.0 - d : d;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_bookingId != null && _isRtdbConnected) {
      FirebaseDatabase.instance.ref('liveTracking/$_bookingId').update({
        'connectionState': 'online',
        'updatedAt': ServerValue.timestamp,
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _posSub?.cancel();
    await _connSub?.cancel();
    if (_bookingId != null) {
      await FirebaseDatabase.instance.ref('liveTracking/$_bookingId').update({
        'connectionState': 'stopped',
        'updatedAt': ServerValue.timestamp,
      });
    }
  }
}

class EnterpriseWorkerTelemetryService {
  EnterpriseWorkerTelemetryService._();
  static final EnterpriseWorkerTelemetryService instance =
      EnterpriseWorkerTelemetryService._();

  Future<void> launchGoogleMapsWithShadowIsolate({
    required String bookingId,
    required String workerId,
    required double destLat,
    required double destLng,
  }) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kelasagara_enterprise_shadow_v2',
        channelName: 'Kelasagara Live Navigation Telemetry',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await FlutterForegroundTask.saveData(key: 'bookingId', value: bookingId);
    await FlutterForegroundTask.saveData(key: 'workerId', value: workerId);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 901,
        notificationTitle: 'Kelasagara Live Job Tracking',
        notificationText: 'Tracking active while navigating in Google Maps',
        callback: startEnterpriseTelemetryIsolate,
      );
    }

    final Uri gmapsIntent = Platform.isAndroid
        ? Uri.parse('google.navigation:q=$destLat,$destLng&mode=l')
        : Uri.parse(
            'comgooglemaps://?daddr=$destLat,$destLng&directionsmode=driving',
          );

    if (await canLaunchUrl(gmapsIntent)) {
      await launchUrl(gmapsIntent, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=two-wheeler',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> stopShadowTracking() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
