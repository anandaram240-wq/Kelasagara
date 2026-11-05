import 'package:cloud_functions/cloud_functions.dart';
import 'biometric_service.dart';

class CloudFunctionsCallableChallengeAdapter
    implements FirebaseCallableChallengeInvoker {
  final FirebaseFunctions _functions;
  final Duration timeout;

  CloudFunctionsCallableChallengeAdapter({
    FirebaseFunctions? functions,
    this.timeout = const Duration(seconds: 4),
  }) : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  Future<Map<String, dynamic>> invokeRequestBiometricChallenge({
    required String purpose,
    required String clientRequestId,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable(
      'requestBiometricChallenge',
      options: HttpsCallableOptions(timeout: timeout),
    );

    final HttpsCallableResult<dynamic> result = await callable.call<dynamic>(
      <String, dynamic>{
        'purpose': purpose,
        'clientRequestId': clientRequestId,
      },
    );

    if (result.data is! Map) {
      throw const FormatException('CALLABLE_RESPONSE_NOT_A_MAP');
    }

    return Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
  }
}
