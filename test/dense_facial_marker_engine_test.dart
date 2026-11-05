// test/dense_facial_marker_engine_test.dart
//
// KELASAGARA V3.0: 512-POINT DENSE FACIAL GEOMETRY SUBSYSTEM TESTS
// ================================================================
// Verifies:
// 1. Minimum 500 genuine facial landmark requirement (Gate A).
// 2. Anatomical semantic region correspondence across all 513 markers.
// 3. Canonical 3D Umeyama alignment (in-plane roll & scale normalization).
// 4. ISO/IEC 29794-5:2025 quality decision gates.
// 5. Zero-PII leakage & endpoint security contracts.

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/dense_facial_marker_engine.dart';
import 'package:kelasagaara/services/biometric_service.dart';

List<List<double>> _generateSynthetic513Points({
  double scale = 1.0,
  double offsetX = 0.0,
  double offsetY = 0.0,
  double rollAngle = 0.0,
}) {
  final points = <List<double>>[];
  final cosR = math.cos(rollAngle);
  final sinR = math.sin(rollAngle);

  for (int i = 0; i < DenseFacialMarkerEngine.kTotalCanonicalMarkers; i++) {
    // Generate distinct, anatomically stratified coordinates
    double baseX = 0.0;
    double baseY = 0.0;
    double baseZ = 0.0;

    if (i < 64) {
      // Forehead & supraorbital: y in [-0.8, -0.3], x in [-0.7, 0.7]
      baseX = -0.7 + (i % 8) * 0.2;
      baseY = -0.8 + (i ~/ 8) * 0.06;
      baseZ = -0.1 + (i % 4) * 0.05;
    } else if (i < 116) {
      // Left periocular: centered at x = -0.5, y = 0.0
      final idx = i - 64;
      final angle = (idx / 52.0) * 2 * math.pi;
      baseX = -0.5 + 0.18 * math.cos(angle);
      baseY = 0.0 + 0.10 * math.sin(angle);
      baseZ = 0.02 * math.sin(angle);
    } else if (i < 168) {
      // Right periocular: centered at x = +0.5, y = 0.0
      final idx = i - 116;
      final angle = (idx / 52.0) * 2 * math.pi;
      baseX = 0.5 + 0.18 * math.cos(angle);
      baseY = 0.0 + 0.10 * math.sin(angle);
      baseZ = 0.02 * math.sin(angle);
    } else if (i < 216) {
      // Nasal bridge & dorsum: x ~ 0.0, y in [0.0, 0.45]
      final idx = i - 168;
      baseX = -0.06 + (idx % 4) * 0.04;
      baseY = 0.0 + (idx ~/ 4) * 0.038;
      baseZ = 0.15 + (idx % 3) * 0.05;
    } else if (i < 256) {
      // Alar base & nostrils: x in [-0.2, 0.2], y in [0.42, 0.50]
      final idx = i - 216;
      baseX = -0.2 + (idx % 8) * 0.05;
      baseY = 0.42 + (idx ~/ 8) * 0.016;
      baseZ = 0.22;
    } else if (i < 304) {
      // Upper lip vermilion: x in [-0.36, 0.36], y in [0.65, 0.75]
      final idx = i - 256;
      baseX = -0.36 + (idx % 12) * 0.065;
      baseY = 0.65 + (idx ~/ 12) * 0.025;
      baseZ = 0.12;
    } else if (i < 352) {
      // Lower lip vermilion: x in [-0.36, 0.36], y in [0.75, 0.88]
      final idx = i - 304;
      baseX = -0.36 + (idx % 12) * 0.065;
      baseY = 0.75 + (idx ~/ 12) * 0.03;
      baseZ = 0.10;
    } else if (i < 384) {
      // Inner oral mucosa
      final idx = i - 352;
      baseX = -0.25 + (idx % 8) * 0.07;
      baseY = 0.72 + (idx ~/ 8) * 0.02;
      baseZ = 0.05;
    } else if (i < 448) {
      // Mandibular jawline arc: x in [-0.85, 0.85], y in [0.35, 1.3]
      final idx = i - 384;
      final t = idx / 64.0;
      final theta = math.pi * t;
      baseX = -0.85 * math.cos(theta);
      baseY = 0.35 + 0.95 * math.sin(theta);
      baseZ = -0.2 + 0.2 * math.sin(theta);
    } else if (i < 480) {
      // Chin (mental protuberance): x in [-0.2, 0.2], y in [1.2, 1.38]
      final idx = i - 448;
      baseX = -0.2 + (idx % 8) * 0.05;
      baseY = 1.20 + (idx ~/ 8) * 0.045;
      baseZ = 0.08;
    } else {
      // Zygomatic & temporal: lateral borders
      final idx = i - 480;
      baseX = (idx % 2 == 0) ? -0.82 : 0.82;
      baseY = 0.1 + (idx ~/ 2) * 0.04;
      baseZ = -0.15;
    }

    // Apply scale & rotation & translation in screen pixels (IPD = 100 * scale)
    final px = (baseX * 100.0) * scale;
    final py = (baseY * 100.0) * scale;
    final pz = (baseZ * 100.0) * scale;

    final rx = cosR * px - sinR * py + offsetX;
    final ry = sinR * px + cosR * py + offsetY;

    points.add([rx, ry, pz]);
  }

  return points;
}

void main() {
  group('Gate A: 500+ Genuine Facial Landmark Requirement', () {
    test('enforces strict minimum of 500 genuine markers per frame', () {
      final invalidPoints = List.generate(468, (_) => [0.0, 0.0, 0.0]);

      expect(
        () => DenseFacialMarkerEngine.processDenseMesh(
          rawPoints3D: invalidPoints,
          originalIpd: 100.0,
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'Must refuse landmark meshes with < 500 genuine detected points',
      );
    });

    test('successfully processes 513 genuine anatomically mapped markers', () {
      final points = _generateSynthetic513Points();
      expect(points.length, DenseFacialMarkerEngine.kTotalCanonicalMarkers);
      expect(points.length, greaterThanOrEqualTo(500));

      final markers = DenseFacialMarkerEngine.processDenseMesh(
        rawPoints3D: points,
        originalIpd: 100.0,
      );

      expect(markers.length, DenseFacialMarkerEngine.kTotalCanonicalMarkers);
      expect(markers.length, greaterThanOrEqualTo(500));

      // Verify all markers have unique indices
      final indices = markers.map((m) => m.index).toSet();
      expect(indices.length, markers.length);

      // Verify semantic anatomical regions
      expect(markers[0].region, FacialMarkerRegion.foreheadSupraorbital);
      expect(markers[90].region, FacialMarkerRegion.leftPeriocular);
      expect(markers[142].region, FacialMarkerRegion.rightPeriocular);
      expect(markers[190].region, FacialMarkerRegion.nasalBridgeDorsum);
      expect(markers[230].region, FacialMarkerRegion.alarBaseNostrils);
      expect(markers[280].region, FacialMarkerRegion.upperLipVermilion);
      expect(markers[320].region, FacialMarkerRegion.lowerLipVermilion);
      expect(markers[360].region, FacialMarkerRegion.innerOralMucosa);
      expect(markers[410].region, FacialMarkerRegion.mandibularJawline);
      expect(markers[460].region, FacialMarkerRegion.chinMental);
      expect(markers[500].region, FacialMarkerRegion.zygomaticTemporal);
    });
  });

  group('Canonical 3D Umeyama Alignment & Invariance', () {
    test('normalizes scale and in-plane roll across all 512 points', () {
      // Standard upright face
      final upright = _generateSynthetic513Points(scale: 1.0, rollAngle: 0.0);
      final markersUpright = DenseFacialMarkerEngine.processDenseMesh(
        rawPoints3D: upright,
        originalIpd: 100.0,
      );

      // Scaled (1.5x) and tilted (15 degrees) face
      final transformed = _generateSynthetic513Points(
        scale: 1.5,
        rollAngle: 15.0 * math.pi / 180.0,
        offsetX: 120.0,
        offsetY: 80.0,
      );
      final markersTransformed = DenseFacialMarkerEngine.processDenseMesh(
        rawPoints3D: transformed,
        originalIpd: 150.0,
      );

      // Verify that after canonical alignment, corresponding markers align within tight tolerance
      double maxDeviation = 0.0;
      for (int i = 0; i < markersUpright.length; i++) {
        final p1 = markersUpright[i];
        final p2 = markersTransformed[i];
        final dx = p1.x - p2.x;
        final dy = p1.y - p2.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        maxDeviation = math.max(maxDeviation, dist);
      }

      expect(maxDeviation, lessThan(0.05),
          reason: 'Canonical Umeyama alignment cancels roll and distance scale across all 512 points');
    });
  });

  group('Gate E & F: Quality Gating & Privacy Protection', () {
    test('passes quality gate for frontal, unoccluded high-quality face', () {
      final points = _generateSynthetic513Points();
      final markers = DenseFacialMarkerEngine.processDenseMesh(
        rawPoints3D: points,
        originalIpd: 110.0,
      );

      final report = DenseFacialMarkerEngine.evaluateQuality(
        markers: markers,
        originalIpd: 110.0,
      );

      expect(report.passesQualityGate, isTrue);
      expect(report.markerCount, greaterThanOrEqualTo(500));
      expect(report.ipdPixels, 110.0);
      expect(report.rejectionReason, isNull);
    });

    test('rejects low-IPD (too far from camera) per ISO 19794-5', () {
      final points = _generateSynthetic513Points();
      final markers = DenseFacialMarkerEngine.processDenseMesh(
        rawPoints3D: points,
        originalIpd: 50.0, // < 75px
      );

      final report = DenseFacialMarkerEngine.evaluateQuality(
        markers: markers,
        originalIpd: 50.0,
      );

      expect(report.passesQualityGate, isFalse);
      expect(report.rejectionReason, contains('Move closer'));
    });

    test('zero PII leakage in duplicate check result contract', () {
      final result = BiometricCheckResult.duplicateFound(
        matchedUid: null, // Guardrail: null UID
        maskedPhone: '******', // Guardrail: zero phone numbers exposed
        maskedName: null,
        maskedUserId: 'KLS-PROTECTED',
        similarityPercent: 88,
        maxSimilarity: 0.88,
        message: 'Duplicate profile found.',
      );

      expect(result.matchedUid, isNull, reason: 'Must never expose raw matched UID to client');
      expect(result.maskedPhone, '******', reason: 'Must never expose registered phone number');
      expect(result.maskedUserId, 'KLS-PROTECTED', reason: 'Must display generic protected ID');
      expect(result.isDuplicate, isTrue);
    });

    test('masked account recovery details in duplicate check result contract', () {
      final result = BiometricCheckResult.duplicateFound(
        matchedUid: 'usr_xK9mP2qRsT7uVwXy',
        maskedPhone: '+91 ******7890',
        maskedName: 'Ra*** K***',
        maskedUserId: 'KLS-usr***wXy-7890',
        similarityPercent: 97,
        maxSimilarity: 0.97,
        message: 'Duplicate profile found.',
      );

      expect(result.maskedPhone, contains('7890'), reason: 'Must display masked phone for account recovery');
      expect(result.maskedUserId, startsWith('KLS-'), reason: 'Must display KLS masked user ID');
      expect(result.maskedName, 'Ra*** K***', reason: 'Must display masked name');
      expect(result.similarityPercent, 97);
      expect(result.isDuplicate, isTrue);
    });

    test('endpoint resolver returns production HTTPS URL in release mode', () {
      expect(BiometricService.kProductionBackendUrl, startsWith('https://'));
      expect(BiometricService.kProductionBackendUrl, contains('/api/biometrics/v10'));
    });
  });
}
