// FILE: test/biometric_v18_unified_client_and_fiqa_test.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kelasagaara/biometrics/biometric_v18_client_and_fiqa.dart';

void main() {
  group('KELASAGARA BIOMETRIC ENGINE V18 — PHASE 20 FLUTTER SDK & ON-DEVICE FIQA SUITE', () {
    test(
      'PHASE20-01: OnDeviceOpticalFiqaCalculatorV18 distinguishes sharp textured face crops from blurry or sun-clipped frames',
      () {
        const int w = 112;
        const int h = 112;

        // 1. Sharp, well-exposed textured luma buffer -> passes FIQA
        final sharpLuma = Uint8List(w * h);
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            // High-frequency checkerboard + gradient within [40..210] (no sunlight clipping)
            final int pattern = ((x + y) % 2 == 0) ? 165 : 75;
            sharpLuma[y * w + x] = pattern;
          }
        }

        final goodFiqa = OnDeviceOpticalFiqaCalculatorV18.computeFromLumaPlane(
          lumaBytes: sharpLuma,
          width: w,
          height: h,
          rollingShutterSkewDegrees: 1.1,
        );

        expect(goodFiqa.passesClientPreCheck, isTrue);
        expect(goodFiqa.laplacianSharpnessScore, greaterThanOrEqualTo(45.0));
        expect(goodFiqa.highlightClippingFraction, lessThanOrEqualTo(0.12));
        expect(goodFiqa.highFreqSkinTextureEnergy, greaterThanOrEqualTo(0.18));

        // 2. Uniform/blurry frame -> fails with ERR_OPTICAL_MOTION_OR_LENS_BLUR
        final blurryLuma = Uint8List(w * h)..fillRange(0, w * h, 128);
        final blurryFiqa = OnDeviceOpticalFiqaCalculatorV18.computeFromLumaPlane(
          lumaBytes: blurryLuma,
          width: w,
          height: h,
        );

        expect(blurryFiqa.passesClientPreCheck, isFalse);
        expect(
          blurryFiqa.clientFailureReason,
          equals('ERR_OPTICAL_MOTION_OR_LENS_BLUR'),
        );

        // 3. Overexposed >80,000 lux sunlight frame (30% pixels >= 250) -> fails clipping check
        final sunClippedLuma = Uint8List.fromList(sharpLuma);
        for (int i = 0; i < (w * h * 0.30).round(); i++) {
          sunClippedLuma[i] = 255;
        }
        final clippedFiqa = OnDeviceOpticalFiqaCalculatorV18.computeFromLumaPlane(
          lumaBytes: sunClippedLuma,
          width: w,
          height: h,
        );

        expect(clippedFiqa.passesClientPreCheck, isFalse);
        expect(
          clippedFiqa.clientFailureReason,
          equals('ERR_HARSH_SUNLIGHT_HIGHLIGHT_CLIPPING'),
        );
      },
    );

    test(
      'PHASE20-02: BiometricV18UnifiedClient handles 200 COMMITTED, 409 Privacy-Safe Audit Ticket, 422 FIQA Reject, and 503 KMS Lockdown',
      () async {
        final mockHttp = MockClient((http.Request req) async {
          if (req.url.path.endsWith('/api/v18/biometrics/enroll')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final uid = body['applicantUid'] as String;

            if (uid == 'WORKER_CLEAN') {
              return http.Response(
                jsonEncode({
                  'success': true,
                  'status': 'COMMITTED',
                  'applicantUid': uid,
                  'committedEpoch': 1,
                  'walSequenceNumber': 14,
                  'wormAnchorPath': 'worm-anchors/v18/seq_1_to_21.json',
                  'batchSizeCoalesced': 21,
                }),
                200,
              );
            }

            if (uid == 'WORKER_DUP') {
              return http.Response(
                jsonEncode({
                  'success': false,
                  'status': 'DUPLICATE_INVESTIGATION_PENDING',
                  'applicantUid': uid,
                  'collisionSource': 'EXISTING_GALLERY',
                  'auditTicketId': 'AUD_TKT_99A8B7C6D5E4',
                  'existingAccountLocked': false,
                  'wormAnchorPath': 'worm-anchors/v18/seq_1_to_21.json',
                }),
                409,
              );
            }

            if (uid == 'WORKER_LOCKDOWN') {
              return http.Response(
                jsonEncode({
                  'success': false,
                  'error': 'ERR_HSM_LOCKDOWN_ACTIVE',
                  'kmsCircuitState': 'HSM_REVOKED_LOCKDOWN',
                }),
                503,
              );
            }
          }

          if (req.url.path.endsWith('/api/v18/biometrics/calibration/gate-h-status')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'adbConnectedSerials': <String>[],
                'verdict': {
                  'gateStatus': 'BLOCKED_NO_PHYSICAL_DEVICE',
                  'productionBiometricCalibrationApproved': false,
                  'consentedParticipantCount': 0,
                  'tiersVerified': <String>[],
                  'failureToAcquireRatePct': 100,
                  'genuineAcceptanceRatePct': 0,
                  'measuredFarAtThreshold': 1,
                  'rejectionReasons': [
                    'adb devices returned 0 physical Android devices.'
                  ],
                },
              }),
              200,
            );
          }

          return http.Response(jsonEncode({'success': false}), 400);
        });

        final client = BiometricV18UnifiedClient(
          baseUrl: 'http://localhost:5001',
          httpClient: mockHttp,
        );

        const sampleFiqa = OpticalFrameFiqaTelemetryV18(
          laplacianSharpnessScore: 88.0,
          highlightClippingFraction: 0.03,
          rollingShutterSkewDegrees: 1.0,
          highFreqSkinTextureEnergy: 0.35,
          ambientLuxEstimate: 30000,
        );

        final unitVec = BiometricV18UnifiedClient.normalize128D(
          List<double>.generate(128, (i) => (i % 2 == 0) ? 0.1 : -0.1),
        );

        // 1. Clean 200 Commit
        final cleanRes = await client.submitUnifiedEnrollment(
          requestId: 'REQ_1',
          applicantUid: 'WORKER_CLEAN',
          embedding128: unitVec,
          opticalFiqa: sampleFiqa,
        );
        expect(cleanRes.isCommitted, isTrue);
        expect(cleanRes.committedEpoch, equals(1));
        expect(cleanRes.batchSizeCoalesced, equals(21));

        // 2. Duplicate 409 Privacy-Safe Audit Ticket
        final dupRes = await client.submitUnifiedEnrollment(
          requestId: 'REQ_2',
          applicantUid: 'WORKER_DUP',
          embedding128: unitVec,
          opticalFiqa: sampleFiqa,
        );
        expect(dupRes.isDuplicateInvestigationPending, isTrue);
        expect(dupRes.auditTicketId, equals('AUD_TKT_99A8B7C6D5E4'));
        expect(dupRes.existingAccountLocked, isFalse);

        // 3. KMS Lockdown 503
        final lockdownRes = await client.submitUnifiedEnrollment(
          requestId: 'REQ_3',
          applicantUid: 'WORKER_LOCKDOWN',
          embedding128: unitVec,
          opticalFiqa: sampleFiqa,
        );
        expect(lockdownRes.isKmsLockdown, isTrue);
        expect(lockdownRes.kmsCircuitState, equals('HSM_REVOKED_LOCKDOWN'));

        // 4. Gate H Status Check
        final gateH = await client.fetchGateHStatus();
        expect(gateH.gateStatus, equals('BLOCKED_NO_PHYSICAL_DEVICE'));
        expect(gateH.productionBiometricCalibrationApproved, isFalse);
      },
    );
  });
}
