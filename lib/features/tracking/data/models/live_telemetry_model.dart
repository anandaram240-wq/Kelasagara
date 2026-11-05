// lib/features/tracking/data/models/live_telemetry_model.dart
// Production-grade RTDB telemetry payload for low-latency worker tracking.

import 'package:latlong2/latlong.dart';

enum WorkerMotionState {
  stationary,
  walking,
  driving,
  arrived,
  seed,
}

class LiveTelemetryModel {
  final double lat;
  final double lng;
  final bool hasCoordinates;
  final double heading;
  final double speedMps;
  final double accuracy;
  final int updatedAtMs;
  final String workerId;
  final String status;
  final bool isSeed;
  final bool isOnline;
  final int seq;
  final int? batteryLevel;

  const LiveTelemetryModel({
    required this.lat,
    required this.lng,
    this.hasCoordinates = true,
    required this.heading,
    required this.speedMps,
    required this.accuracy,
    required this.updatedAtMs,
    required this.workerId,
    this.status = 'on_the_way',
    this.isSeed = false,
    this.isOnline = true,
    this.seq = 0,
    this.batteryLevel,
  });

  LatLng get latLng => LatLng(lat, lng);

  double get latitude => lat;
  double get longitude => lng;
  double get speedKmh => speedMps * 3.6;
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  bool get isValid => isValidCoordinate;

  /// Mathematical validity of the coordinates.
  /// (0, 0) is a valid geographic coordinate and must NOT be rejected.
  /// Missing coordinates, NaN, infinity, and out-of-range values are rejected.
  bool get isValidCoordinate =>
      hasCoordinates &&
      lat.isFinite &&
      lng.isFinite &&
      !lat.isNaN &&
      !lng.isNaN &&
      lat >= -90.0 &&
      lat <= 90.0 &&
      lng >= -180.0 &&
      lng <= 180.0;

  /// Regional plausibility check for South Asia / Karnataka gig operations.
  /// Note: A coordinate outside this region is still valid, but flagged as plausibility outlier.
  bool get isRegionallyPlausible =>
      isValidCoordinate &&
      lat >= 6.0 &&
      lat <= 38.0 &&
      lng >= 68.0 &&
      lng <= 98.0;

  Duration age([DateTime? now]) {
    final reference = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final delta = reference - updatedAtMs;
    return Duration(milliseconds: delta < 0 ? 0 : delta);
  }

  WorkerMotionState get motionState {
    if (isSeed) return WorkerMotionState.seed;
    if (status == 'arrived') return WorkerMotionState.arrived;
    if (speedMps < 0.6) return WorkerMotionState.stationary;
    if (speedMps < 2.2) return WorkerMotionState.walking;
    return WorkerMotionState.driving;
  }

  factory LiveTelemetryModel.fromMap(Map<dynamic, dynamic> map) {
    double? parseOptionalDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    int toInt(dynamic val, [int fallback = 0]) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    final rawLat = map['lat'] ?? map['latitude'];
    final rawLng = map['lng'] ?? map['longitude'];

    final parsedLat = parseOptionalDouble(rawLat);
    final parsedLng = parseOptionalDouble(rawLng);

    final bool hasCoords = parsedLat != null &&
        parsedLng != null &&
        parsedLat.isFinite &&
        parsedLng.isFinite &&
        !parsedLat.isNaN &&
        !parsedLng.isNaN;

    final double latVal = parsedLat ?? 0.0;
    final double lngVal = parsedLng ?? 0.0;

    double toDouble(dynamic val, [double fallback = 0.0]) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    final rawSpeed = map['speedMps'] != null
        ? toDouble(map['speedMps'])
        : (map['speed'] != null ? toDouble(map['speed']) / 3.6 : 0.0);

    final rawTs = map['updatedAt'] ?? map['lastUpdatedAt'] ?? map['timestamp'];
    final int parsedUpdatedMs = rawTs != null
        ? toInt(rawTs, DateTime.now().millisecondsSinceEpoch)
        : DateTime.now().millisecondsSinceEpoch;

    return LiveTelemetryModel(
      lat: latVal,
      lng: lngVal,
      hasCoordinates: hasCoords,
      heading: toDouble(map['heading']) % 360.0,
      speedMps: rawSpeed < 0 ? 0.0 : rawSpeed,
      accuracy: toDouble(map['accuracy'], 15.0),
      updatedAtMs: parsedUpdatedMs,
      workerId: (map['workerId'] ?? '').toString(),
      status: (map['status'] ?? map['arrivalStatus'] ?? 'on_the_way').toString(),
      isSeed: map['isSeed'] == true,
      isOnline: map['isOnline'] != false,
      seq: toInt(map['seq'], 0),
      batteryLevel: map['batteryLevel'] != null ? toInt(map['batteryLevel']) : null,
    );
  }

  factory LiveTelemetryModel.fromRtdb(Map<dynamic, dynamic> m) =>
      LiveTelemetryModel.fromMap(m);

  Map<String, dynamic> toMap() {
    return {
      'lat': double.parse(lat.toStringAsFixed(6)),
      'lng': double.parse(lng.toStringAsFixed(6)),
      'latitude': double.parse(lat.toStringAsFixed(6)),
      'longitude': double.parse(lng.toStringAsFixed(6)),
      'hasCoordinates': hasCoordinates,
      'heading': double.parse((heading % 360.0).toStringAsFixed(1)),
      'speedMps': double.parse(speedMps.toStringAsFixed(2)),
      'speed': double.parse(speedKmh.toStringAsFixed(1)),
      'accuracy': double.parse(accuracy.toStringAsFixed(1)),
      'updatedAt': updatedAtMs,
      'lastUpdatedAt': updatedAtMs,
      'timestamp': updatedAtMs,
      'workerId': workerId,
      'status': status,
      'isSeed': isSeed,
      'isOnline': isOnline,
      'seq': seq,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
    };
  }

  Map<String, dynamic> toRtdbMap() => toMap();

  LiveTelemetryModel copyWith({
    double? lat,
    double? lng,
    bool? hasCoordinates,
    double? heading,
    double? speedMps,
    double? accuracy,
    int? updatedAtMs,
    String? workerId,
    String? status,
    bool? isSeed,
    bool? isOnline,
    int? seq,
    int? batteryLevel,
  }) {
    return LiveTelemetryModel(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      hasCoordinates: hasCoordinates ?? this.hasCoordinates,
      heading: heading ?? this.heading,
      speedMps: speedMps ?? this.speedMps,
      accuracy: accuracy ?? this.accuracy,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      workerId: workerId ?? this.workerId,
      status: status ?? this.status,
      isSeed: isSeed ?? this.isSeed,
      isOnline: isOnline ?? this.isOnline,
      seq: seq ?? this.seq,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }
}
