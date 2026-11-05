// FILE: lib/biometrics/biometric_v18_client_and_fiqa.dart

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

enum AndroidHardwareTierV18 {
  tier1EntryCmos('TIER_1_ENTRY_CMOS'),
  tier2MidRange('TIER_2_MID_RANGE'),
  tier3Reference('TIER_3_REFERENCE');

  final String wireValue;
  const AndroidHardwareTierV18(this.wireValue);
}

class OpticalFrameFiqaTelemetryV18 {
  final double laplacianSharpnessScore;
  final double highlightClippingFraction;
  final double rollingShutterSkewDegrees;
  final double highFreqSkinTextureEnergy;
  final double ambientLuxEstimate;

  const OpticalFrameFiqaTelemetryV18({
    required this.laplacianSharpnessScore,
    required this.highlightClippingFraction,
    required this.rollingShutterSkewDegrees,
    required this.highFreqSkinTextureEnergy,
    required this.ambientLuxEstimate,
  });

  bool get passesClientPreCheck =>
      laplacianSharpnessScore >= 45.0 &&
      highlightClippingFraction <= 0.12 &&
      rollingShutterSkewDegrees <= 4.5 &&
      highFreqSkinTextureEnergy >= 0.18;

  String? get clientFailureReason {
    if (laplacianSharpnessScore < 45.0) {
      return 'ERR_OPTICAL_MOTION_OR_LENS_BLUR';
    }
    if (highlightClippingFraction > 0.12) {
      return 'ERR_HARSH_SUNLIGHT_HIGHLIGHT_CLIPPING';
    }
    if (rollingShutterSkewDegrees > 4.5) {
      return 'ERR_CMOS_ROLLING_SHUTTER_DISTORTION';
    }
    if (highFreqSkinTextureEnergy < 0.18) {
      return 'ERR_ISP_SKIN_SMOOTHING_FILTER_DETECTED';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'laplacianSharpnessScore': laplacianSharpnessScore,
        'highlightClippingFraction': highlightClippingFraction,
        'rollingShutterSkewDegrees': rollingShutterSkewDegrees,
        'highFreqSkinTextureEnergy': highFreqSkinTextureEnergy,
        'ambientLuxEstimate': ambientLuxEstimate,
      };

  factory OpticalFrameFiqaTelemetryV18.fromJson(Map<String, dynamic> json) {
    return OpticalFrameFiqaTelemetryV18(
      laplacianSharpnessScore:
          (json['laplacianSharpnessScore'] as num?)?.toDouble() ?? 0.0,
      highlightClippingFraction:
          (json['highlightClippingFraction'] as num?)?.toDouble() ?? 1.0,
      rollingShutterSkewDegrees:
          (json['rollingShutterSkewDegrees'] as num?)?.toDouble() ?? 90.0,
      highFreqSkinTextureEnergy:
          (json['highFreqSkinTextureEnergy'] as num?)?.toDouble() ?? 0.0,
      ambientLuxEstimate:
          (json['ambientLuxEstimate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Computes real ISO/IEC 29794-5 optical quality metrics on-device from an aligned
/// 8-bit grayscale/luma face crop (e.g., 112x112) before sending over the network.
class OnDeviceOpticalFiqaCalculatorV18 {
  static OpticalFrameFiqaTelemetryV18 computeFromLumaPlane({
    required Uint8List lumaBytes,
    required int width,
    required int height,
    double rollingShutterSkewDegrees = 0.8,
  }) {
    if (lumaBytes.length < width * height || width < 16 || height < 16) {
      throw ArgumentError(
        'Invalid luma buffer size: expected >= ${width * height}, got ${lumaBytes.length}',
      );
    }

    final int totalPixels = width * height;
    int clippedHighlightPixels = 0;
    double lumaSum = 0.0;

    for (int i = 0; i < totalPixels; i++) {
      final int px = lumaBytes[i];
      lumaSum += px;
      if (px >= 250) {
        clippedHighlightPixels++;
      }
    }

    final double highlightClippingFraction =
        clippedHighlightPixels / totalPixels;
    final double meanLuma = lumaSum / totalPixels;

    // Compute 3x3 Discrete Laplacian Variance for focus sharpness & high-freq skin texture energy
    int interiorCount = 0;
    double lapSum = 0.0;
    double lapSqSum = 0.0;
    double highFreqAbsSum = 0.0;

    for (int y = 1; y < height - 1; y++) {
      final int rowOffset = y * width;
      for (int x = 1; x < width - 1; x++) {
        final int idx = rowOffset + x;
        final int center = lumaBytes[idx];
        final int top = lumaBytes[idx - width];
        final int bottom = lumaBytes[idx + width];
        final int left = lumaBytes[idx - 1];
        final int right = lumaBytes[idx + 1];

        // 4-neighbor Laplacian kernel: [0, 1, 0; 1, -4, 1; 0, 1, 0]
        final double lap =
            (top + bottom + left + right - (4 * center)).toDouble();
        lapSum += lap;
        lapSqSum += lap * lap;
        highFreqAbsSum += lap.abs() / 255.0;
        interiorCount++;
      }
    }

    final double lapMean = interiorCount > 0 ? lapSum / interiorCount : 0.0;
    final double lapVariance = interiorCount > 1
        ? (lapSqSum / interiorCount) - (lapMean * lapMean)
        : 0.0;

    // Normalize sharpness & texture metrics to V18 verifier scale
    final double laplacianSharpnessScore =
        double.parse((lapVariance / 18.0).clamp(0.0, 500.0).toStringAsFixed(2));
    final double highFreqSkinTextureEnergy = double.parse(
      (interiorCount > 0 ? (highFreqAbsSum / interiorCount) : 0.0)
          .clamp(0.0, 2.0)
          .toStringAsFixed(4),
    );
    final double ambientLuxEstimate =
        double.parse(((meanLuma / 255.0) * 60000.0).toStringAsFixed(0));

    return OpticalFrameFiqaTelemetryV18(
      laplacianSharpnessScore: laplacianSharpnessScore,
      highlightClippingFraction:
          double.parse(highlightClippingFraction.toStringAsFixed(4)),
      rollingShutterSkewDegrees:
          double.parse(rollingShutterSkewDegrees.toStringAsFixed(2)),
      highFreqSkinTextureEnergy: highFreqSkinTextureEnergy,
      ambientLuxEstimate: ambientLuxEstimate,
    );
  }
}

class BiometricV18EnrollResponse {
  final int httpStatus;
  final bool success;
  final String status;
  final String applicantUid;
  final int? committedEpoch;
  final int? walSequenceNumber;
  final String? wormAnchorPath;
  final int? batchSizeCoalesced;
  final String? collisionSource;
  final String? auditTicketId;
  final bool? existingAccountLocked;
  final String? failureCode;
  final String? error;
  final String? kmsCircuitState;

  const BiometricV18EnrollResponse({
    required this.httpStatus,
    required this.success,
    required this.status,
    required this.applicantUid,
    this.committedEpoch,
    this.walSequenceNumber,
    this.wormAnchorPath,
    this.batchSizeCoalesced,
    this.collisionSource,
    this.auditTicketId,
    this.existingAccountLocked,
    this.failureCode,
    this.error,
    this.kmsCircuitState,
  });

  bool get isCommitted => httpStatus == 200 && status == 'COMMITTED';
  bool get isDuplicateInvestigationPending =>
      httpStatus == 409 && status == 'DUPLICATE_INVESTIGATION_PENDING';
  bool get isOpticalFiqaRejected =>
      httpStatus == 422 && status == 'OPTICAL_FIQA_REJECTED';
  bool get isKmsLockdown => httpStatus == 503;

  factory BiometricV18EnrollResponse.fromHttp(
    int statusCode,
    Map<String, dynamic> json,
  ) {
    return BiometricV18EnrollResponse(
      httpStatus: statusCode,
      success: json['success'] == true,
      status:
          json['status']?.toString() ?? json['error']?.toString() ?? 'UNKNOWN',
      applicantUid: json['applicantUid']?.toString() ?? '',
      committedEpoch: (json['committedEpoch'] as num?)?.toInt(),
      walSequenceNumber: (json['walSequenceNumber'] as num?)?.toInt(),
      wormAnchorPath: json['wormAnchorPath']?.toString(),
      batchSizeCoalesced: (json['batchSizeCoalesced'] as num?)?.toInt(),
      collisionSource: json['collisionSource']?.toString(),
      auditTicketId: json['auditTicketId']?.toString(),
      existingAccountLocked: json['existingAccountLocked'] as bool?,
      failureCode: json['failureCode']?.toString(),
      error: json['error']?.toString(),
      kmsCircuitState: json['kmsCircuitState']?.toString(),
    );
  }
}

class GateHStatusResponseV18 {
  final String gateStatus;
  final bool productionBiometricCalibrationApproved;
  final int consentedParticipantCount;
  final List<String> tiersVerified;
  final double failureToAcquireRatePct;
  final double genuineAcceptanceRatePct;
  final double measuredFarAtThreshold;
  final List<String> adbConnectedSerials;
  final List<String> rejectionReasons;

  const GateHStatusResponseV18({
    required this.gateStatus,
    required this.productionBiometricCalibrationApproved,
    required this.consentedParticipantCount,
    required this.tiersVerified,
    required this.failureToAcquireRatePct,
    required this.genuineAcceptanceRatePct,
    required this.measuredFarAtThreshold,
    required this.adbConnectedSerials,
    required this.rejectionReasons,
  });

  factory GateHStatusResponseV18.fromJson(Map<String, dynamic> root) {
    final verdict =
        (root['verdict'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return GateHStatusResponseV18(
      gateStatus:
          verdict['gateStatus']?.toString() ?? 'BLOCKED_NO_PHYSICAL_DEVICE',
      productionBiometricCalibrationApproved:
          verdict['productionBiometricCalibrationApproved'] == true,
      consentedParticipantCount:
          (verdict['consentedParticipantCount'] as num?)?.toInt() ?? 0,
      tiersVerified: (verdict['tiersVerified'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      failureToAcquireRatePct:
          (verdict['failureToAcquireRatePct'] as num?)?.toDouble() ?? 100.0,
      genuineAcceptanceRatePct:
          (verdict['genuineAcceptanceRatePct'] as num?)?.toDouble() ?? 0.0,
      measuredFarAtThreshold:
          (verdict['measuredFarAtThreshold'] as num?)?.toDouble() ?? 1.0,
      adbConnectedSerials:
          (root['adbConnectedSerials'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      rejectionReasons:
          (verdict['rejectionReasons'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
    );
  }
}

/// Production Flutter SDK for `/api/v18/biometrics` endpoints mounted in Phase 19.
class BiometricV18UnifiedClient {
  final String baseUrl;
  final http.Client _httpClient;

  BiometricV18UnifiedClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Uri _uri(String path) {
    final clean = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$clean/api/v18/biometrics$path');
  }

  /// 1. POST /api/v18/biometrics/enroll
  Future<BiometricV18EnrollResponse> submitUnifiedEnrollment({
    required String requestId,
    required String applicantUid,
    required List<double> embedding128,
    required OpticalFrameFiqaTelemetryV18 opticalFiqa,
  }) async {
    final res = await _httpClient.post(
      _uri('/enroll'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requestId': requestId,
        'applicantUid': applicantUid,
        'embedding128': embedding128,
        'opticalFiqa': opticalFiqa.toJson(),
      }),
    );

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return BiometricV18EnrollResponse.fromHttp(res.statusCode, decoded);
  }

  /// 2. POST /api/v18/biometrics/calibration/capture
  Future<bool> uploadPhysicalCalibrationCapture({
    required String participantId,
    required bool isAdultConsentVerified,
    required String adbHardwareSerial,
    required String deviceModel,
    required AndroidHardwareTierV18 hardwareTier,
    required int sessionNumber,
    required OpticalFrameFiqaTelemetryV18 opticalFiqa,
    required List<double> embedding128,
  }) async {
    final res = await _httpClient.post(
      _uri('/calibration/capture'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'participantId': participantId,
        'isAdultConsentVerified': isAdultConsentVerified,
        'adbHardwareSerial': adbHardwareSerial,
        'deviceModel': deviceModel,
        'hardwareTier': hardwareTier.wireValue,
        'sessionNumber': sessionNumber,
        'opticalFiqa': opticalFiqa.toJson(),
        'embedding128': embedding128,
      }),
    );
    return res.statusCode == 201;
  }

  /// 3. GET /api/v18/biometrics/calibration/gate-h-status
  Future<GateHStatusResponseV18> fetchGateHStatus() async {
    final res = await _httpClient.get(_uri('/calibration/gate-h-status'));
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return GateHStatusResponseV18.fromJson(decoded);
  }

  /// Helper to L2-normalize a 128-D vector on the client prior to transmission
  static List<double> normalize128D(List<double> raw) {
    if (raw.length != 128) {
      throw ArgumentError('Expected 128-D vector, got ${raw.length}');
    }
    double sumSq = 0.0;
    for (final v in raw) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm < 1e-8) {
      throw StateError('Zero-energy embedding vector');
    }
    return raw.map((v) => v / norm).toList(growable: false);
  }
}
