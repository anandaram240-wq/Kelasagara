// File: backend/src/services/play_integrity_verifier.ts
import {
  PlayIntegrityGoogleClient,
  PlayIntegrityDecodedVerdict,
  ProductionPlayIntegrityGoogleClient,
  MockPlayIntegrityGoogleClient,
  PlayIntegrityClientError,
} from './play_integrity_google_client';
import {
  PlayIntegrityBindingParams,
  verifyPlayIntegrityRequestHash,
  EXPECTED_PACKAGE_NAME,
} from './play_integrity_request_binding';
import {
  PlayIntegrityPolicyEngine,
  IntegrityPolicyEvaluation,
  IntegrityDecisionOutcome,
} from './play_integrity_policy';

export interface PlayIntegrityVerificationRequest {
  readonly integrityToken: string;
  readonly bindingParams: PlayIntegrityBindingParams;
  readonly callerUid: string;
}

export interface PlayIntegrityVerificationResult {
  readonly allowed: boolean;
  readonly outcome: IntegrityDecisionOutcome;
  readonly httpStatus: number;
  readonly errorCode?: string;
  readonly message: string;
  readonly evaluation?: IntegrityPolicyEvaluation;
  readonly rawVerdict?: PlayIntegrityDecodedVerdict;
}

export class PlayIntegrityVerifier {
  private static instance: PlayIntegrityVerifier | null = null;
  private readonly googleClient: PlayIntegrityGoogleClient;
  private readonly policyEngine: PlayIntegrityPolicyEngine;

  constructor(
    googleClient?: PlayIntegrityGoogleClient,
    policyEngine?: PlayIntegrityPolicyEngine
  ) {
    if (googleClient) {
      this.googleClient = googleClient;
    } else {
      // Auto-provider selection:
      if (process.env.GOOGLE_APPLICATION_CREDENTIALS && process.env.APP_ENV === 'PRODUCTION') {
        this.googleClient = new ProductionPlayIntegrityGoogleClient();
      } else {
        this.googleClient = new MockPlayIntegrityGoogleClient();
      }
    }

    this.policyEngine = policyEngine ?? new PlayIntegrityPolicyEngine();
  }

  public static getInstance(): PlayIntegrityVerifier {
    if (!PlayIntegrityVerifier.instance) {
      PlayIntegrityVerifier.instance = new PlayIntegrityVerifier();
    }
    return PlayIntegrityVerifier.instance;
  }

  public static setInstanceForTesting(verifier: PlayIntegrityVerifier | null) {
    PlayIntegrityVerifier.instance = verifier;
  }

  public async verifyRequestIntegrity(
    req: PlayIntegrityVerificationRequest
  ): Promise<PlayIntegrityVerificationResult> {
    const { integrityToken, bindingParams, callerUid } = req;

    // 1. Token presence check
    if (!integrityToken || integrityToken.trim().length === 0) {
      return {
        allowed: false,
        outcome: 'INTEGRITY_REJECTED',
        httpStatus: 400,
        errorCode: 'MISSING_PLAY_INTEGRITY_TOKEN',
        message: 'Play Integrity token must be provided in X-Play-Integrity-Token header or payload',
      };
    }

    // 2. Cross-caller binding check (Token parameters must match authenticated Firebase user)
    if (bindingParams.authenticatedUid !== callerUid) {
      return {
        allowed: false,
        outcome: 'INTEGRITY_REJECTED',
        httpStatus: 403,
        errorCode: 'CROSS_USER_INTEGRITY_THEFT_DETECTED',
        message: 'Integrity binding UID does not match authenticated session caller',
      };
    }

    // 3. Decode token via Google API client
    let decodedVerdict: PlayIntegrityDecodedVerdict;
    try {
      decodedVerdict = await this.googleClient.decodeIntegrityToken(integrityToken);
    } catch (err: any) {
      if (err instanceof PlayIntegrityClientError) {
        if (err.code === 'INVALID_INTEGRITY_TOKEN') {
          return {
            allowed: false,
            outcome: 'INTEGRITY_REJECTED',
            httpStatus: 403,
            errorCode: 'INVALID_PLAY_INTEGRITY_TOKEN',
            message: 'Integrity token was rejected as forged, malformed, or untrusted by Google',
          };
        }

        // Network or Google API downtime -> Fail closed with 503
        return {
          allowed: false,
          outcome: 'INTEGRITY_UNAVAILABLE',
          httpStatus: 503,
          errorCode: 'PLAY_INTEGRITY_SERVICE_UNAVAILABLE',
          message: 'Google Play Integrity verification service is temporarily unavailable',
        };
      }

      return {
        allowed: false,
        outcome: 'INTEGRITY_UNAVAILABLE',
        httpStatus: 503,
        errorCode: 'INTERNAL_INTEGRITY_ERROR',
        message: 'Unexpected error during token verification',
      };
    }

    // 4. Package Name Verification
    const targetPackage = decodedVerdict.requestDetails.requestPackageName;
    if (targetPackage !== EXPECTED_PACKAGE_NAME) {
      return {
        allowed: false,
        outcome: 'INTEGRITY_REJECTED',
        httpStatus: 403,
        errorCode: 'PACKAGE_NAME_MISMATCH',
        message: `Token was minted for '${targetPackage}', expected '${EXPECTED_PACKAGE_NAME}'`,
        rawVerdict: decodedVerdict,
      };
    }

    // 5. Canonical RequestHash Binding Verification
    const hashCheck = verifyPlayIntegrityRequestHash(
      decodedVerdict.requestDetails.requestHash,
      bindingParams
    );

    if (!hashCheck.valid) {
      return {
        allowed: false,
        outcome: 'INTEGRITY_REJECTED',
        httpStatus: 403,
        errorCode: 'REQUEST_HASH_MISMATCH',
        message: `Token requestHash does not match canonical transaction digest (${hashCheck.reason})`,
        rawVerdict: decodedVerdict,
      };
    }

    // 6. Security Decision Engine Evaluation
    const evaluation = this.policyEngine.evaluateVerdict(decodedVerdict);

    if (evaluation.outcome === 'INTEGRITY_ACCEPTED') {
      return {
        allowed: true,
        outcome: 'INTEGRITY_ACCEPTED',
        httpStatus: 200,
        message: 'Play Integrity verification passed',
        evaluation,
        rawVerdict: decodedVerdict,
      };
    }

    if (evaluation.outcome === 'INTEGRITY_RETRY') {
      return {
        allowed: false,
        outcome: 'INTEGRITY_RETRY',
        httpStatus: 401,
        errorCode: 'INTEGRITY_TOKEN_EXPIRED',
        message: 'Integrity token has expired, client must refresh and retry',
        evaluation,
        rawVerdict: decodedVerdict,
      };
    }

    if (evaluation.outcome === 'INTEGRITY_STEP_UP') {
      return {
        allowed: false,
        outcome: 'INTEGRITY_STEP_UP',
        httpStatus: 403,
        errorCode: 'DEVICE_INTEGRITY_STEP_UP_REQUIRED',
        message: 'Device hardware integrity unconfirmed; additional verification required',
        evaluation,
        rawVerdict: decodedVerdict,
      };
    }

    return {
      allowed: false,
      outcome: evaluation.outcome,
      httpStatus: 403,
      errorCode: 'INTEGRITY_VERDICT_REJECTED',
      message: `Integrity check rejected: ${evaluation.reason}`,
      evaluation,
      rawVerdict: decodedVerdict,
    };
  }
}
