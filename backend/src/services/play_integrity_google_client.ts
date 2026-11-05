// File: backend/src/services/play_integrity_google_client.ts
import { GoogleAuth } from 'google-auth-library';
import { EXPECTED_PACKAGE_NAME } from './play_integrity_request_binding';

export interface PlayIntegrityDecodedVerdict {
  readonly requestDetails: {
    readonly requestPackageName: string;
    readonly requestHash: string;
    readonly timestampMillis: string | number;
  };
  readonly appIntegrity: {
    readonly appRecognitionVerdict: 'PLAY_RECOGNIZED' | 'UNRECOGNIZED_VERSION' | 'UNEVALUATED';
    readonly packageName?: string;
    readonly certificateSha256Digest?: string[];
    readonly versionCode?: string | number;
  };
  readonly deviceIntegrity: {
    readonly deviceRecognitionVerdict?: Array<
      | 'MEETS_STRONG_INTEGRITY'
      | 'MEETS_DEVICE_INTEGRITY'
      | 'MEETS_BASIC_INTEGRITY'
      | 'MEETS_VIRTUAL_INTEGRITY'
      | 'UNKNOWN'
    >;
  };
  readonly accountDetails?: {
    readonly appLicensingVerdict?: 'LICENSED' | 'UNLICENSED' | 'UNEVALUATED';
  };
  readonly environmentDetails?: {
    readonly playProtectVerdict?: 'NO_ISSUES' | 'RISKY' | 'DANGEROUS' | 'UNEVALUATED';
  };
}

export interface PlayIntegrityGoogleClient {
  decodeIntegrityToken(integrityToken: string): Promise<PlayIntegrityDecodedVerdict>;
}

export class PlayIntegrityClientError extends Error {
  public readonly code: string;
  public readonly retryable: boolean;

  constructor(code: string, message: string, retryable = false) {
    super(`[${code}] ${message}`);
    this.name = 'PlayIntegrityClientError';
    this.code = code;
    this.retryable = retryable;
  }
}

/**
 * Production client communicating with the official Google Play Integrity REST API.
 */
export class ProductionPlayIntegrityGoogleClient implements PlayIntegrityGoogleClient {
  private readonly auth: GoogleAuth;
  private readonly packageName: string;

  constructor(packageName: string = EXPECTED_PACKAGE_NAME) {
    this.packageName = packageName;
    this.auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/playintegrity'],
    });
  }

  public async decodeIntegrityToken(integrityToken: string): Promise<PlayIntegrityDecodedVerdict> {
    if (!integrityToken || integrityToken.trim().length === 0) {
      throw new PlayIntegrityClientError('EMPTY_TOKEN', 'Integrity token must not be empty', false);
    }

    try {
      const client = await this.auth.getClient();
      const url = `https://playintegrity.googleapis.com/v1/${encodeURIComponent(this.packageName)}:decodeIntegrityToken`;

      const response = await client.request<{ tokenPayloadExternal: PlayIntegrityDecodedVerdict }>({
        url,
        method: 'POST',
        data: {
          integrityToken,
        },
        timeout: 10_000,
      });

      if (!response.data || !response.data.tokenPayloadExternal) {
        throw new PlayIntegrityClientError(
          'MALFORMED_DECODE_RESPONSE',
          'Google Play API returned empty token payload',
          true
        );
      }

      return response.data.tokenPayloadExternal;
    } catch (err: any) {
      if (err instanceof PlayIntegrityClientError) throw err;

      const msg = (err?.message || '').toLowerCase();
      const isRetryable =
        msg.includes('timeout') ||
        msg.includes('unavailable') ||
        msg.includes('econnreset') ||
        msg.includes('rate limit');

      if (err?.code === 400 || msg.includes('invalid integrity token')) {
        throw new PlayIntegrityClientError('INVALID_INTEGRITY_TOKEN', 'Token rejected by Google: ' + err.message, false);
      }

      throw new PlayIntegrityClientError(
        'GOOGLE_API_COMMUNICATION_ERROR',
        `Play Integrity API error: ${err?.message || 'Unknown network error'}`,
        isRetryable
      );
    }
  }
}

/**
 * In-memory test client allowing deterministic mocking of verdicts in unit & adversarial suites.
 */
export class MockPlayIntegrityGoogleClient implements PlayIntegrityGoogleClient {
  private readonly mockVerdicts = new Map<string, PlayIntegrityDecodedVerdict>();
  private defaultVerdictGenerator?: (token: string) => PlayIntegrityDecodedVerdict;
  private simulateFailure?: Error;

  public setMockVerdict(token: string, verdict: PlayIntegrityDecodedVerdict) {
    this.mockVerdicts.set(token, verdict);
  }

  public setDefaultVerdictGenerator(generator: (token: string) => PlayIntegrityDecodedVerdict) {
    this.defaultVerdictGenerator = generator;
  }

  public setSimulatedFailure(error: Error | undefined) {
    this.simulateFailure = error;
  }

  public async decodeIntegrityToken(integrityToken: string): Promise<PlayIntegrityDecodedVerdict> {
    if (this.simulateFailure) {
      throw this.simulateFailure;
    }

    if (!integrityToken || integrityToken.trim().length === 0) {
      throw new PlayIntegrityClientError('EMPTY_TOKEN', 'Integrity token must not be empty', false);
    }

    if (this.mockVerdicts.has(integrityToken)) {
      return this.mockVerdicts.get(integrityToken)!;
    }

    if (this.defaultVerdictGenerator) {
      return this.defaultVerdictGenerator(integrityToken);
    }

    // Default synthetic verdict for validly formed mock tokens
    if (integrityToken.startsWith('mock_valid_token_')) {
      const parts = integrityToken.split(':');
      const requestHash = parts[1] || 'mock_request_hash';
      return {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash,
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          packageName: EXPECTED_PACKAGE_NAME,
          certificateSha256Digest: ['a0425250004454e7fc63dba402351e439f975b0ff38f23cb2ca131edb037f7e5'],
          versionCode: '1',
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY', 'MEETS_BASIC_INTEGRITY'],
        },
        accountDetails: {
          appLicensingVerdict: 'LICENSED',
        },
        environmentDetails: {
          playProtectVerdict: 'NO_ISSUES',
        },
      };
    }

    throw new PlayIntegrityClientError(
      'INVALID_INTEGRITY_TOKEN',
      'Token not found in mock store and does not match synthetic pattern',
      false
    );
  }
}
