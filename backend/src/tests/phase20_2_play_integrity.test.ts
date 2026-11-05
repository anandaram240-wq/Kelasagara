// File: backend/src/tests/phase20_2_play_integrity.test.ts
import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'node:crypto';
import {
  computePlayIntegrityRequestHash,
  verifyPlayIntegrityRequestHash,
  computePayloadDigest,
  PlayIntegrityBindingParams,
  EXPECTED_PACKAGE_NAME,
} from '../services/play_integrity_request_binding';
import {
  PlayIntegrityPolicyEngine,
  APPROVED_RELEASE_CERTIFICATES,
} from '../services/play_integrity_policy';
import {
  MockPlayIntegrityGoogleClient,
  PlayIntegrityClientError,
  PlayIntegrityDecodedVerdict,
} from '../services/play_integrity_google_client';
import { PlayIntegrityVerifier } from '../services/play_integrity_verifier';
import { createRequirePlayIntegrityMiddleware } from '../middleware/require_play_integrity';

describe('Phase 20.2: Trusted Android Application Integrity Engine Tests', () => {
  const legitUid = 'usr_alice_12345';
  const legitChallengeId = 'chl_session_001';
  const legitNonce = 'nonce_server_16b_rand';
  const legitIdempotency = 'idem_key_778899';
  const legitRoute = '/auth/biometrics/v10/enroll';
  const legitPayload = computePayloadDigest(new Float32Array(128).fill(0.0883883)); // normalized 128-D vector

  const validParams: PlayIntegrityBindingParams = {
    authenticatedUid: legitUid,
    challengeId: legitChallengeId,
    challengePurpose: 'INITIAL_ENROLLMENT',
    serverNonce: legitNonce,
    idempotencyKey: legitIdempotency,
    httpMethod: 'POST',
    route: legitRoute,
    payloadDigestSha256: legitPayload,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // Track 1: Canonical Request-Binding & Anti-Replay Cryptography
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 1: Canonical Request-Binding & Anti-Replay Cryptography', () => {
    it('computes deterministic, URL-safe base64 requestHash compliant with RFC 4648', () => {
      const hash1 = computePlayIntegrityRequestHash(validParams);
      const hash2 = computePlayIntegrityRequestHash(validParams);

      assert.strictEqual(hash1, hash2, 'Request hash calculation must be 100% deterministic');
      assert.strictEqual(typeof hash1, 'string');
      assert.strictEqual(hash1.length, 43, 'SHA-256 base64url unpadded length must be 43 chars');
      assert.match(hash1, /^[a-zA-Z0-9_-]+$/, 'Must contain only URL-safe characters (no +, /, or =)');
    });

    it('modifying authenticatedUid changes requestHash and fails verification', () => {
      const legitHash = computePlayIntegrityRequestHash(validParams);
      const tamperedParams: PlayIntegrityBindingParams = {
        ...validParams,
        authenticatedUid: 'usr_attacker_bob',
      };
      const tamperedHash = computePlayIntegrityRequestHash(tamperedParams);

      assert.notStrictEqual(legitHash, tamperedHash);
      const verify = verifyPlayIntegrityRequestHash(legitHash, tamperedParams);
      assert.strictEqual(verify.valid, false);
      assert.strictEqual(verify.reason, 'REQUEST_HASH_MISMATCH');
    });

    it('modifying challengeId or serverNonce changes requestHash', () => {
      const legitHash = computePlayIntegrityRequestHash(validParams);
      const badNonce = computePlayIntegrityRequestHash({
        ...validParams,
        serverNonce: 'nonce_tampered_321',
      });
      assert.notStrictEqual(legitHash, badNonce);

      const badChallenge = computePlayIntegrityRequestHash({
        ...validParams,
        challengeId: 'chl_other_session',
      });
      assert.notStrictEqual(legitHash, badChallenge);
    });

    it('modifying route or HTTP method changes requestHash (prevents route substitution)', () => {
      const legitHash = computePlayIntegrityRequestHash(validParams);
      const substitutedRoute = computePlayIntegrityRequestHash({
        ...validParams,
        route: '/auth/biometrics/v10/verify-1to1', // Transplanting token to auth route
      });
      assert.notStrictEqual(legitHash, substitutedRoute);
    });

    it('modifying biometric vector payload changes requestHash (prevents face swapping)', () => {
      const legitHash = computePlayIntegrityRequestHash(validParams);
      const imposterVector = new Float32Array(128).fill(0.05);
      const substitutedPayload = computePlayIntegrityRequestHash({
        ...validParams,
        payloadDigestSha256: computePayloadDigest(imposterVector),
      });
      assert.notStrictEqual(legitHash, substitutedPayload);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Track 2: Google Play Response Validation & Security Gates
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 2: Google Play Response Validation & Security Gates', () => {
    it('accepts valid Play Integrity token on recognized app and certified device', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = `mock_valid_token_alice:${expectedHash}`;

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, true);
      assert.strictEqual(result.outcome, 'INTEGRITY_ACCEPTED');
      assert.strictEqual(result.httpStatus, 200);
      assert.strictEqual(result.evaluation?.appIntegrityPassed, true);
      assert.strictEqual(result.evaluation?.deviceIntegrityPassed, true);
    });

    it('rejects token with wrong package name (rejects repackaged clone app)', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const token = 'token_wrong_pkg';
      const expectedHash = computePlayIntegrityRequestHash(validParams);

      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: 'com.attacker.repackaged.app', // Forged package name
          requestHash: expectedHash,
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          packageName: 'com.attacker.repackaged.app',
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.httpStatus, 403);
      assert.strictEqual(result.errorCode, 'PACKAGE_NAME_MISMATCH');
    });

    it('rejects token with mismatched requestHash (request tampering)', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const token = 'token_mismatched_hash';

      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: 'completely_different_hash_from_another_action',
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.httpStatus, 403);
      assert.strictEqual(result.errorCode, 'REQUEST_HASH_MISMATCH');
    });

    it('rejects expired integrity token (> 300 seconds old) and demands retry', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = 'token_expired_10m';

      const staleTime = Date.now() - 600 * 1000; // 10 minutes ago
      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: expectedHash,
          timestampMillis: staleTime.toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          certificateSha256Digest: [APPROVED_RELEASE_CERTIFICATES[0]],
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_RETRY');
      assert.strictEqual(result.httpStatus, 401);
      assert.strictEqual(result.errorCode, 'INTEGRITY_TOKEN_EXPIRED');
    });

    it('rejects token with timestamp in the future (exceeding permitted clock skew)', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = 'token_future_timestamp';

      const futureTime = Date.now() + 300 * 1000; // 5 minutes in future
      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: expectedHash,
          timestampMillis: futureTime.toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          certificateSha256Digest: [APPROVED_RELEASE_CERTIFICATES[0]],
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_REJECTED');
      assert.strictEqual(result.httpStatus, 403);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Track 3: Device Environment & Attack Scenarios
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 3: Device Environment & Attack Scenarios', () => {
    it('rejects unapproved developer signing certificate in production mode', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = 'token_bad_cert';

      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: expectedHash,
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          certificateSha256Digest: ['deadbeef00112233445566778899aabbccddeeff'], // Unauthorized key
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
      });

      const prodPolicy = new PlayIntegrityPolicyEngine({ environment: 'PRODUCTION' });
      const verifier = new PlayIntegrityVerifier(mockClient, prodPolicy);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_REJECTED');
    });

    it('restricts rooted device / emulator with empty deviceRecognitionVerdict', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = 'token_rooted_emulator';

      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: expectedHash,
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          certificateSha256Digest: [APPROVED_RELEASE_CERTIFICATES[0]],
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: [], // Failed all device integrity checks!
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_RESTRICTED');
      assert.strictEqual(result.httpStatus, 403);
    });

    it('rejects device when Google Play Protect flags a dangerous environment', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = 'token_dangerous_protect';

      mockClient.setMockVerdict(token, {
        requestDetails: {
          requestPackageName: EXPECTED_PACKAGE_NAME,
          requestHash: expectedHash,
          timestampMillis: Date.now().toString(),
        },
        appIntegrity: {
          appRecognitionVerdict: 'PLAY_RECOGNIZED',
          certificateSha256Digest: [APPROVED_RELEASE_CERTIFICATES[0]],
        },
        deviceIntegrity: {
          deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'],
        },
        environmentDetails: {
          playProtectVerdict: 'DANGEROUS',
        },
      });

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_REJECTED');
    });

    it('fails closed with HTTP 503 when Google Play Integrity API is unavailable', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      mockClient.setSimulatedFailure(
        new PlayIntegrityClientError('GOOGLE_API_COMMUNICATION_ERROR', 'Connection timed out', true)
      );

      const verifier = new PlayIntegrityVerifier(mockClient);
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: 'token_timeout_test',
        bindingParams: validParams,
        callerUid: legitUid,
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.outcome, 'INTEGRITY_UNAVAILABLE');
      assert.strictEqual(result.httpStatus, 503);
      assert.strictEqual(result.errorCode, 'PLAY_INTEGRITY_SERVICE_UNAVAILABLE');
    });

    it('detects and rejects cross-user integrity token theft', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = `mock_valid_token_alice:${expectedHash}`;

      const verifier = new PlayIntegrityVerifier(mockClient);

      // Imposter Bob tries to submit Alice's integrity token
      const result = await verifier.verifyRequestIntegrity({
        integrityToken: token,
        bindingParams: validParams, // specifies Alice
        callerUid: 'usr_imposter_bob', // Authenticated caller is Bob!
      });

      assert.strictEqual(result.allowed, false);
      assert.strictEqual(result.httpStatus, 403);
      assert.strictEqual(result.errorCode, 'CROSS_USER_INTEGRITY_THEFT_DETECTED');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Track 4: Express Middleware Integration
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 4: Express Middleware Integration', () => {
    it('middleware allows valid request and attaches verified verdict to req', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = `mock_valid_token_alice:${expectedHash}`;
      const verifier = new PlayIntegrityVerifier(mockClient);

      const middleware = createRequirePlayIntegrityMiddleware(verifier);

      const req: any = {
        user: { uid: legitUid },
        headers: { 'x-play-integrity-token': token },
        body: {
          challengeId: legitChallengeId,
          challengeNonce: legitNonce,
          idempotencyKey: legitIdempotency,
          purpose: 'INITIAL_ENROLLMENT',
          validatedSFaceEmbedding128: Array.from(new Float32Array(128).fill(0.0883883)),
        },
        method: 'POST',
        baseUrl: '/auth/biometrics/v10',
        path: '/enroll',
      };

      let nextCalled = false;
      const res: any = {
        status: (code: number) => {
          assert.fail(`res.status(${code}) should not be called on valid request`);
        },
      };

      await middleware(req, res, () => {
        nextCalled = true;
      });

      assert.strictEqual(nextCalled, true);
      assert.ok(req.playIntegrity);
      assert.strictEqual(req.playIntegrity.allowed, true);
    });

    it('middleware blocks request with tampered embedding before reaching biometric logic', async () => {
      const mockClient = new MockPlayIntegrityGoogleClient();
      const expectedHash = computePlayIntegrityRequestHash(validParams);
      const token = `mock_valid_token_alice:${expectedHash}`;
      const verifier = new PlayIntegrityVerifier(mockClient);

      const middleware = createRequirePlayIntegrityMiddleware(verifier);

      // Attacker swaps vector in body without changing the token
      const req: any = {
        user: { uid: legitUid },
        headers: { 'x-play-integrity-token': token },
        body: {
          challengeId: legitChallengeId,
          challengeNonce: legitNonce,
          idempotencyKey: legitIdempotency,
          purpose: 'INITIAL_ENROLLMENT',
          validatedSFaceEmbedding128: Array.from(new Float32Array(128).fill(0.9999)), // Tampered vector!
        },
        method: 'POST',
        baseUrl: '/auth/biometrics/v10',
        path: '/enroll',
      };

      let statusCode = 0;
      let responseBody: any = null;
      const res: any = {
        status: (code: number) => {
          statusCode = code;
          return {
            json: (data: any) => {
              responseBody = data;
            },
          };
        },
      };

      await middleware(req, res, () => {
        assert.fail('next() should not be called on tampered payload');
      });

      assert.strictEqual(statusCode, 403);
      assert.strictEqual(responseBody.code, 'REQUEST_HASH_MISMATCH');
    });
  });
});
