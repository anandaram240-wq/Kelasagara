/**
 * backend/src/biometric-evaluation/server_nonce_lifecycle_service.ts
 *
 * Kelasagara V20.10: Server-Authoritative Challenge & Nonce Lifecycle Engine.
 *
 * Implements strict three-state challenge lifecycle:
 * ISSUED -> PROCESSING -> CONSUMED
 *
 * Guarantees:
 * 1. Single-use nonces with cryptographic entropy (256-bit).
 * 2. Atomic state transitions to prevent race conditions and duplicate consumption.
 * 3. Immediate rejection of concurrent submissions on the same nonce.
 * 4. Automatic TTL expiration (default: 3 minutes).
 * 5. Strict binding to authenticated UID, deviceKeyId, and captureSessionId.
 */

import * as crypto from 'node:crypto';

export type ChallengeState = 'ISSUED' | 'PROCESSING' | 'CONSUMED' | 'FAILED';

export interface ServerCaptureChallenge {
  readonly challengeId: string;
  readonly nonce: string;
  readonly captureSessionId: string;
  readonly uid: string;
  readonly deviceKeyId: string;
  readonly issuedAt: number;
  readonly expiresAt: number;
  state: ChallengeState;
  processingStartedAt?: number;
  consumedAt?: number;
}

export class ServerNonceLifecycleService {
  private static instance: ServerNonceLifecycleService;
  private readonly challenges = new Map<string, ServerCaptureChallenge>();
  public static readonly DEFAULT_TTL_MS = 3 * 60 * 1000; // 3 minutes

  public static getInstance(): ServerNonceLifecycleService {
    if (!ServerNonceLifecycleService.instance) {
      ServerNonceLifecycleService.instance = new ServerNonceLifecycleService();
    }
    return ServerNonceLifecycleService.instance;
  }

  /**
   * Issues a fresh, server-authoritative challenge in ISSUED state.
   */
  public issueChallenge(params: {
    captureSessionId: string;
    uid: string;
    deviceKeyId: string;
    ttlMs?: number;
  }): ServerCaptureChallenge {
    const { captureSessionId, uid, deviceKeyId, ttlMs = ServerNonceLifecycleService.DEFAULT_TTL_MS } = params;

    if (!captureSessionId || !uid || !deviceKeyId) {
      throw new Error('captureSessionId, uid, and deviceKeyId are required to issue challenge');
    }

    const challengeId = `chal_${crypto.randomUUID()}`;
    const nonce = `KS_NONCE_${crypto.randomBytes(32).toString('hex')}`;
    const now = Date.now();

    const record: ServerCaptureChallenge = {
      challengeId,
      nonce,
      captureSessionId,
      uid,
      deviceKeyId,
      issuedAt: now,
      expiresAt: now + ttlMs,
      state: 'ISSUED',
    };

    this.challenges.set(nonce, record);
    return record;
  }

  /**
   * Atomically acquires and transitions challenge from ISSUED -> PROCESSING.
   * Throws typed errors on expired, replayed, or concurrent requests.
   */
  public beginProcessing(params: {
    nonce: string;
    expectedSessionId: string;
    expectedUid: string;
    expectedDeviceKeyId: string;
  }): ServerCaptureChallenge {
    const { nonce, expectedSessionId, expectedUid, expectedDeviceKeyId } = params;

    const record = this.challenges.get(nonce);
    if (!record) {
      throw new Error('CHALLENGE_NOT_FOUND: Unknown or unissued server nonce');
    }

    if (Date.now() > record.expiresAt) {
      record.state = 'FAILED';
      throw new Error('CHALLENGE_EXPIRED: Server nonce has exceeded TTL');
    }

    if (record.state === 'PROCESSING') {
      throw new Error('CONCURRENT_SUBMISSION_DETECTED: Challenge is already actively processing in another worker');
    }

    if (record.state === 'CONSUMED') {
      throw new Error('NONCE_ALREADY_CONSUMED: Replay detected; challenge was already consumed');
    }

    if (record.state !== 'ISSUED') {
      throw new Error(`INVALID_CHALLENGE_STATE: Challenge is in ${record.state} state`);
    }

    // Verify cryptographic binding context
    if (record.captureSessionId !== expectedSessionId) {
      throw new Error(`SESSION_MISMATCH: Challenge belongs to session ${record.captureSessionId}, received ${expectedSessionId}`);
    }

    if (record.uid !== expectedUid) {
      throw new Error(`UID_MISMATCH: Challenge belongs to UID ${record.uid}, received ${expectedUid}`);
    }

    if (record.deviceKeyId !== expectedDeviceKeyId) {
      throw new Error(`DEVICE_KEY_MISMATCH: Challenge belongs to device ${record.deviceKeyId}, received ${expectedDeviceKeyId}`);
    }

    // Atomic transition to PROCESSING
    record.state = 'PROCESSING';
    record.processingStartedAt = Date.now();
    return record;
  }

  /**
   * Finalizes challenge consumption upon successful verification (PROCESSING -> CONSUMED).
   */
  public commitConsumed(nonce: string): void {
    const record = this.challenges.get(nonce);
    if (!record) {
      throw new Error('CHALLENGE_NOT_FOUND: Cannot commit non-existent nonce');
    }

    if (record.state !== 'PROCESSING') {
      throw new Error(`ILLEGAL_STATE_TRANSITION: Cannot commit challenge in ${record.state} state; must be PROCESSING`);
    }

    record.state = 'CONSUMED';
    record.consumedAt = Date.now();
  }

  /**
   * Transitions challenge to FAILED if verification aborted or errored.
   */
  public markFailed(nonce: string, reason?: string): void {
    const record = this.challenges.get(nonce);
    if (record && record.state === 'PROCESSING') {
      record.state = 'FAILED';
    }
  }

  /**
   * Retrieves active challenge record for audit inspection.
   */
  public getChallenge(nonce: string): ServerCaptureChallenge | undefined {
    return this.challenges.get(nonce);
  }

  /**
   * Test/Maintenance: Clears in-memory storage.
   */
  public clearAll(): void {
    this.challenges.clear();
  }
}
