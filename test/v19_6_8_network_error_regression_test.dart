// test/v19_6_8_network_error_regression_test.dart
//
// KELASAGARA BIOMATCH V19.6.8
// Network Error Classification, Endpoint Routing & Bilingual Diagnostics Test Suite
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 24745:2022

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/biometric_service.dart';

void main() {
  group('V19.6.8 Endpoint Resolution & URL Construction', () {
    test('1. resolveDefaultEndpoint strips trailing slashes', () {
      final endpoint = BiometricService.resolveDefaultEndpoint();
      expect(endpoint.endsWith('/'), isFalse, reason: 'Endpoint must never end with a trailing slash');
      expect(endpoint.contains('/api/biometrics'), isTrue);
    });

    test('2. Endpoint paths construct valid canonical paths without double slashes', () {
      const baseUrl = 'https://api.kelasagara.com/api/biometrics';
      const enrollPath = '$baseUrl/enroll';
      const challengePath = '$baseUrl/challenge';
      const healthPath = '$baseUrl/health';

      expect(enrollPath, equals('https://api.kelasagara.com/api/biometrics/enroll'));
      expect(challengePath, equals('https://api.kelasagara.com/api/biometrics/challenge'));
      expect(healthPath, equals('https://api.kelasagara.com/api/biometrics/health'));

      // Ensure no double slashes in path (other than https://)
      expect(enrollPath.replaceFirst('https://', '').contains('//'), isFalse);
      expect(challengePath.replaceFirst('https://', '').contains('//'), isFalse);
    });
  });

  group('V19.6.8 Network Error Classification & Diagnostics', () {
    test('3. Classifies connection timeout with bilingual message', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.connectionTimeout,
        message: 'The connection has timed out after 10000ms',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.connectTimeout));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('timed out'), isTrue);
      expect(classified.messageKn.contains('ಸಮಯ ಮೀರಿದೆ'), isTrue);
      expect(classified.userDisplayMessage.contains('('), isTrue);
      expect(classified.correlationId.startsWith('req_'), isTrue);
    });

    test('4. Classifies receive timeout with bilingual message', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.receiveTimeout,
        message: 'The response took longer than 15000ms',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.receiveTimeout));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('Server response timed out'), isTrue);
      expect(classified.messageKn.contains('ಪ್ರತಿಕ್ರಿಯೆ ಸಮಯ ಮೀರಿದೆ'), isTrue);
    });

    test('5. Classifies Android cleartext HTTP block as cleartextProhibited', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.unknown,
        error: 'java.io.IOException: Cleartext HTTP traffic to 10.255.181.23 not permitted by network security policy',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'http://10.255.181.23:5001/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.cleartextProhibited));
      expect(classified.isRetryable, isFalse);
      expect(classified.messageEn.contains('Insecure HTTP connection blocked by Android security policy'), isTrue);
      expect(classified.messageKn.contains('ಅಸುರಕ್ಷಿತ ಸಂಪರ್ಕ ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ'), isTrue);
    });

    test('6. Classifies DNS failure (Failed host lookup) accurately', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.connectionError,
        error: 'SocketException: Failed host lookup: \'api.kelasagara.com\' (OS Error: nodename nor servname provided, errno = 8)',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.dnsFailure));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('Cannot resolve biometric server address (DNS failure)'), isTrue);
      expect(classified.messageKn.contains('DNS ವೈಫಲ್ಯ'), isTrue);
    });

    test('7. Classifies connection refused accurately', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.connectionError,
        error: 'SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = 10.255.181.23, port = 5001',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'http://10.255.181.23:5001/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.connectionRefused));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('Biometric server refused connection'), isTrue);
      expect(classified.messageKn.contains('ಸಂಪರ್ಕವನ್ನು ನಿರಾಕರಿಸಿದೆ'), isTrue);
    });

    test('8. Classifies network unreachable / offline accurately', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        type: DioExceptionType.connectionError,
        error: 'SocketException: Network is unreachable (OS Error: Network is unreachable, errno = 101)',
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.offlineOrInterrupted));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('No internet route to server'), isTrue);
      expect(classified.messageKn.contains('ಯಾವುದೇ ನೆಟ್‌ವರ್ಕ್ ಇಲ್ಲ'), isTrue);
    });

    test('9. Classifies HTTP 401 Unauthorized accurately', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        response: Response(
          requestOptions: RequestOptions(path: '/enroll'),
          statusCode: 401,
          data: {'status': 'unauthorized', 'error': {'message': 'Missing token'}},
        ),
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.http401Unauthorized));
      expect(classified.httpStatus, equals(401));
      expect(classified.isRetryable, isFalse);
      expect(classified.messageEn.contains('Authentication required'), isTrue);
    });

    test('10. Classifies HTTP 404 Route Not Found accurately', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        response: Response(
          requestOptions: RequestOptions(path: '/enroll'),
          statusCode: 404,
        ),
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.http404NotFound));
      expect(classified.httpStatus, equals(404));
      expect(classified.isRetryable, isFalse);
      expect(classified.messageEn.contains('not found on server'), isTrue);
    });

    test('11. Classifies HTTP 500 / 503 server error as retryable', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll'),
        response: Response(
          requestOptions: RequestOptions(path: '/enroll'),
          statusCode: 503,
        ),
      );

      final classified = BiometricService.classifyDioException(dioErr, 'https://api.kelasagara.com/api/biometrics/enroll');

      expect(classified.category, equals(NetworkFailureCategory.http5xxServerError));
      expect(classified.httpStatus, equals(503));
      expect(classified.isRetryable, isTrue);
      expect(classified.messageEn.contains('internal error'), isTrue);
    });

    test('12. Privacy check: classified error strips query parameters and exposes zero PII', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/enroll?token=secret_jwt_abc123&uid=user_789'),
        type: DioExceptionType.connectionTimeout,
      );

      final classified = BiometricService.classifyDioException(
        dioErr,
        'https://api.kelasagara.com/api/biometrics/enroll?token=secret_jwt_abc123&uid=user_789',
      );

      expect(classified.sanitizedPath, equals('https://api.kelasagara.com/api/biometrics/enroll'));
      expect(classified.sanitizedPath.contains('token='), isFalse);
      expect(classified.sanitizedPath.contains('secret_jwt'), isFalse);
      expect(classified.userDisplayMessage.contains('secret_jwt'), isFalse);
    });
  });
}
