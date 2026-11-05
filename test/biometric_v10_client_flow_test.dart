// FILE: test/biometric_v10_client_flow_test.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kelasagaara/biometrics/biometric_v10_models_and_client.dart';
import 'package:kelasagaara/widgets/biometric_v10_dialogs_and_badges.dart';

void main() {
  group('KELASAGARA V10 FLUTTER CLIENT & DUPLICATE MODAL SUITE', () {
    testWidgets(
      'FLUTTER-V10-01: DuplicateAccountDetectedDialog displays all 6 masked original account fields clearly',
      (WidgetTester tester) async {
        bool navigatedToLogin = false;

        final mockResponse = BiometricV10Response.fromHttpResponse(409, {
          'success': false,
          'status': 'DUPLICATE_ACCOUNT_DETECTED',
          'uid': 'KS_USR_FAKE_9999',
          'faceVerified': false,
          'existingAccountLocked': false,
          'message': 'Duplicate Account Creation Detected',
          'duplicateAccountDetails': {
            'maskedUid': 'KS-••••-4910',
            'maskedName': 'Su••• Go•••',
            'maskedPhone': '+91 ••••••2233',
            'primarySkill': 'Plumber',
            'dailyRateDisplay': '₹900/day',
            'facialSimilarityPercent': '94.2% Biometric Match',
            'rawCosineSimilarity': 0.942,
          },
        });

        expect(mockResponse.isDuplicateAccountDetected, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    DuplicateAccountDetectedDialog.show(
                      context: context,
                      details: mockResponse.duplicateAccountDetails!,
                      onSignInToOriginalAccount: () {
                        navigatedToLogin = true;
                      },
                    );
                  },
                  child: const Text('Trigger Duplicate Check'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Trigger Duplicate Check'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('duplicate_account_detected_dialog')), findsOneWidget);
        expect(find.byKey(const Key('dup_status')), findsOneWidget);
        expect(find.byKey(const Key('dup_privacy_notice')), findsOneWidget);
        expect(find.text('KS-••••-4910'), findsNothing);
        expect(find.text('+91 ••••••2233'), findsNothing);

        await tester.tap(find.byKey(const Key('dup_signin_existing_btn')));
        await tester.pumpAndSettle();

        expect(navigatedToLogin, isTrue);
      },
    );

    testWidgets(
      'FLUTTER-V10-02: LockedBiometricTokenCard shows KS_FTOK lock token and routes to 1:1 eKYC',
      (WidgetTester tester) async {
        bool ekycTriggered = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LockedBiometricTokenCard(
                faceId: 'KS_FACE_8821',
                biometricLockToken: 'KS_FTOK_9A8B7C6D5E4F3A2B',
                onVerify1To1Ekyc: () {
                  ekycTriggered = true;
                },
                onStepUpReRegister: () {},
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('locked_biometric_token_card')), findsOneWidget);
        expect(find.textContaining('KS_FACE_8821'), findsOneWidget);
        expect(find.textContaining('KS_FTOK_9A8B7C6D5E4F3A2B'), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_verify_1to1_ekyc')));
        await tester.pump();

        expect(ekycTriggered, isTrue);
      },
    );

    test(
      'FLUTTER-V10-03: BiometricV10ApiClient handles Enroll Lock, 1:1 eKYC, and Step-Up Re-Registration',
      () async {
        final mockHttp = MockClient((http.Request req) async {
          if (req.url.path.endsWith('/enroll')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['mode'] == 'INITIAL_ENROLLMENT') {
              return http.Response(
                jsonEncode({
                  'success': true,
                  'status': 'ENROLLED_AND_LOCKED',
                  'uid': body['uid'],
                  'faceId': 'KS_FACE_0001',
                  'biometricLockToken': 'KS_FTOK_LOCKED_V1',
                  'faceVerified': true,
                  'accountStatus': 'approved',
                  'message': 'Locked',
                }),
                200,
              );
            }
          }
          if (req.url.path.endsWith('/verify-ekyc')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 'EKYC_1TO1_VERIFIED',
                'uid': 'KS_USR_01',
                'faceId': 'KS_FACE_0001',
                'biometricLockToken': 'KS_FTOK_LOCKED_V1',
                'faceVerified': true,
                'similarityScore': 0.891,
                'message': '1:1 eKYC Verified',
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': false}), 400);
        });

        final apiClient = BiometricV10ApiClient(
          baseUrl: 'http://localhost:5001',
          httpClient: mockHttp,
        );

        final enrollRes = await apiClient.enrollOrReRegister(
          uid: 'KS_USR_01',
          name: 'Ananda V',
          phone: '+919740098765',
          primarySkill: 'Electrician',
          dailyRate: 850,
          mode: BiometricV10Mode.initialEnrollment,
          sfaceEmbedding128D: List<double>.filled(128, 0.088),
        );

        expect(enrollRes.isEnrolledAndLocked, isTrue);
        expect(enrollRes.biometricLockToken, equals('KS_FTOK_LOCKED_V1'));

        final ekycRes = await apiClient.verifyOneToOneEkyc(
          uid: 'KS_USR_01',
          sfaceEmbedding128D: List<double>.filled(128, 0.088),
        );

        expect(ekycRes.isEkycVerified, isTrue);
        expect(ekycRes.similarityScore, closeTo(0.891, 1e-3));
      },
    );
  });
}
