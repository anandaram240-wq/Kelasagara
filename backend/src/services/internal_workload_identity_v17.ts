/**
 * KELASAGARA V20.17: INTERNAL WORKLOAD IDENTITY & SERVICE-TO-SERVICE AUTHENTICATION
 *
 * Implements cryptographic service-to-service authentication adhering to NIST SP 800-207
 * Zero Trust Architecture and Google Cloud Service Account OIDC standards.
 *
 * Core Controls:
 * 1. Strict Workload Identity vs End-User Separation: Distinguishes between end-user JWTs
 *    (Firebase Auth uids) and genuine cloud backend service identities (Service Account OIDC).
 *    Ordinary user tokens cannot masquerade as privileged backend services.
 * 2. Token Claims Validation: Strictly verifies issuer (https://accounts.google.com),
 *    audience (target microservice URL), cryptographic signature, and expiration.
 * 3. Principal Assertions: Rejects caller-supplied unauthenticated headers ('x-principal',
 *    'x-forwarded-user') unless backed by a cryptographically verified OIDC token.
 * 4. Token Replay Prevention: Maintains an in-memory replay prevention cache for token JTIs.
 * 5. Arbitrary UID Substitution Defense: Prohibits callers from substituting arbitrary user UIDs
 *    outside their authorized session boundary.
 */

import * as crypto from 'crypto';

export interface InternalWorkloadTokenClaims {
  iss: string; // Must be 'https://accounts.google.com'
  aud: string; // Target microservice URL
  email: string; // Service account email
  email_verified: boolean;
  exp: number; // Expiration epoch seconds
  iat: number;
  sub: string;
  jti?: string;
  authorizedWorkloadPurpose?: string;
  boundUserUid?: string;
}

export interface InternalServiceCallContext {
  targetServiceUrl: string;
  rawAuthorizationHeader?: string;
  callerSuppliedPrincipalHeader?: string;
  requestedTargetUid: string;
  expectedServiceAccountEmail: string;
  expectedWorkloadPurpose?: string;
}

export interface WorkloadVerificationResult {
  authorized: boolean;
  verifiedServiceAccountEmail?: string;
  errorCode?: string;
  errorMessage?: string;
}

export class InternalWorkloadIdentityService {
  private jtiReplayCache = new Map<string, number>(); // jti -> expiry timestamp
  private testPublicKeys = new Map<string, string>(); // keyId -> pem

  constructor() {
    // Periodic cleanup of expired JTIs
    setInterval(() => {
      const now = Date.now();
      for (const [jti, exp] of this.jtiReplayCache.entries()) {
        if (now > exp) {
          this.jtiReplayCache.delete(jti);
        }
      }
    }, 60000).unref();
  }

  /**
   * Registers a public key for signature verification in test environments.
   */
  public registerVerificationKey(keyId: string, publicKeyPem: string): void {
    this.testPublicKeys.set(keyId, publicKeyPem);
  }

  /**
   * Signs a synthetic test OIDC token using an EC private key.
   */
  public generateTestOidcToken(
    claims: InternalWorkloadTokenClaims,
    privateKeyPem: string,
    keyId: string = 'key-1'
  ): string {
    const header = { alg: 'ES256', typ: 'JWT', kid: keyId };
    const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
    const encodedPayload = Buffer.from(JSON.stringify(claims)).toString('base64url');
    const signInput = `${encodedHeader}.${encodedPayload}`;

    const sign = crypto.createSign('SHA256');
    sign.update(signInput);
    sign.end();
    const signature = sign.sign(privateKeyPem, 'base64url');

    return `${signInput}.${signature}`;
  }

  /**
   * Verifies an incoming internal service call.
   */
  public verifyInternalServiceCall(context: InternalServiceCallContext): WorkloadVerificationResult {
    // 1. Reject unverified caller-supplied principal headers without token
    if (context.callerSuppliedPrincipalHeader && !context.rawAuthorizationHeader) {
      return {
        authorized: false,
        errorCode: 'ERR_FORGED_PRINCIPAL_HEADER',
        errorMessage: `FORGED_HEADER_REJECTED: Caller supplied '${context.callerSuppliedPrincipalHeader}' in unverified header without cryptographically signed OIDC Bearer token.`,
      };
    }

    // 2. Validate presence of Bearer token
    if (!context.rawAuthorizationHeader || !context.rawAuthorizationHeader.startsWith('Bearer ')) {
      return {
        authorized: false,
        errorCode: 'ERR_MISSING_INTERNAL_TOKEN',
        errorMessage: 'AUTHENTICATION_REQUIRED: Missing Bearer token in internal service invocation.',
      };
    }

    const token = context.rawAuthorizationHeader.slice(7).trim();
    const parts = token.split('.');
    if (parts.length !== 3) {
      return {
        authorized: false,
        errorCode: 'ERR_MALFORMED_INTERNAL_TOKEN',
        errorMessage: 'MALFORMED_TOKEN: OIDC token must comprise header, payload, and signature.',
      };
    }

    // 3. Decode header and payload
    let header: any;
    let payload: InternalWorkloadTokenClaims;
    try {
      header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
      payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    } catch {
      return {
        authorized: false,
        errorCode: 'ERR_INVALID_TOKEN_ENCODING',
        errorMessage: 'JSON_DECODE_FAILED: Could not parse token JSON claims.',
      };
    }

    // 4. Reject End-User Tokens attempting to impersonate backend workloads
    if ((payload as any).user_id || (payload as any).firebase || (payload as any).role === 'worker') {
      return {
        authorized: false,
        errorCode: 'ERR_END_USER_TOKEN_IMPERSONATION',
        errorMessage:
          'PRIVILEGE_VIOLATION: Ordinary end-user account token cannot masquerade as an internal Google Cloud backend service identity.',
      };
    }

    // 5. Verify Issuer
    if (payload.iss !== 'https://accounts.google.com') {
      return {
        authorized: false,
        errorCode: 'ERR_INVALID_TOKEN_ISSUER',
        errorMessage: `INVALID_ISSUER: Token issuer '${payload.iss}' is not authorized. Must be 'https://accounts.google.com'.`,
      };
    }

    // 6. Verify Audience
    if (payload.aud !== context.targetServiceUrl) {
      return {
        authorized: false,
        errorCode: 'ERR_AUDIENCE_MISMATCH',
        errorMessage: `AUDIENCE_MISMATCH: Token audience '${payload.aud}' does not match target service URL '${context.targetServiceUrl}'.`,
      };
    }

    // 7. Verify Expiration
    const nowSec = Math.floor(Date.now() / 1000);
    if (payload.exp <= nowSec) {
      return {
        authorized: false,
        errorCode: 'ERR_INTERNAL_TOKEN_EXPIRED',
        errorMessage: `TOKEN_EXPIRED: Internal workload token expired at epoch ${payload.exp} (current: ${nowSec}).`,
      };
    }

    // 8. Verify Cryptographic Signature
    const keyId = header.kid || 'key-1';
    const pubKeyPem = this.testPublicKeys.get(keyId);
    if (!pubKeyPem) {
      return {
        authorized: false,
        errorCode: 'ERR_UNKNOWN_VERIFICATION_KEY',
        errorMessage: `UNKNOWN_KEY: No registered verification key for kid '${keyId}'.`,
      };
    }

    const signInput = `${parts[0]}.${parts[1]}`;
    const verify = crypto.createVerify('SHA256');
    verify.update(signInput);
    verify.end();

    const isSigValid = verify.verify(pubKeyPem, parts[2], 'base64url');
    if (!isSigValid) {
      return {
        authorized: false,
        errorCode: 'ERR_INVALID_TOKEN_SIGNATURE',
        errorMessage: 'SIGNATURE_INVALID: Internal service identity token signature verification failed.',
      };
    }

    // 9. Replay Prevention via JTI Cache
    if (payload.jti) {
      if (this.jtiReplayCache.has(payload.jti)) {
        return {
          authorized: false,
          errorCode: 'ERR_TOKEN_REPLAYED',
          errorMessage: `REPLAY_ATTACK_DETECTED: Token JTI '${payload.jti}' has already been consumed.`,
        };
      }
      this.jtiReplayCache.set(payload.jti, payload.exp * 1000);
    }

    // 10. Verify Service Account Identity Matches Expected
    if (payload.email !== context.expectedServiceAccountEmail) {
      return {
        authorized: false,
        errorCode: 'ERR_WRONG_SERVICE_IDENTITY',
        errorMessage: `IDENTITY_MISMATCH: Calling service account '${payload.email}' does not match expected '${context.expectedServiceAccountEmail}'.`,
      };
    }

    // 11. Reject Arbitrary UID Substitution
    if (payload.boundUserUid && payload.boundUserUid !== context.requestedTargetUid) {
      return {
        authorized: false,
        errorCode: 'ERR_UNAUTHORIZED_UID_SUBSTITUTION',
        errorMessage: `UID_SUBSTITUTION_BLOCKED: Token is bound to user '${payload.boundUserUid}', but caller requested '${context.requestedTargetUid}'.`,
      };
    }

    return {
      authorized: true,
      verifiedServiceAccountEmail: payload.email,
    };
  }
}
