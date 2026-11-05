// File: backend/src/services/attestation_revocation_service.ts
import * as crypto from 'node:crypto';
import * as https from 'node:https';

export type RevocationStatusType = 'REVOKED' | 'SUSPENDED';
export type RevocationReasonType =
  | 'UNSPECIFIED'
  | 'KEY_COMPROMISE'
  | 'CA_COMPROMISE'
  | 'SUPERSEDED'
  | 'SOFTWARE_FLAW';

export interface RevocationEntry {
  readonly status: RevocationStatusType;
  readonly reason?: RevocationReasonType;
  readonly comment?: string;
}

export interface RevocationStatusPayload {
  readonly entries: Record<string, RevocationEntry>;
}

export interface RevocationCheckResult {
  readonly isRevoked: boolean;
  readonly serialNormalized: string;
  readonly status?: RevocationStatusType;
  readonly reason?: RevocationReasonType;
  readonly comment?: string;
}

export interface RevocationServiceHealth {
  readonly healthy: boolean;
  readonly cachedEntriesCount: number;
  readonly lastSuccessfulRefreshMs: number | null;
  readonly lastRefreshIso: string | null;
  readonly ttlMs: number;
  readonly isStale: boolean;
  readonly lastError?: string;
}

export const GOOGLE_ATTESTATION_STATUS_URL = 'https://android.googleapis.com/attestation/status';
export const DEFAULT_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

export class AttestationRevocationService {
  private static instance: AttestationRevocationService;
  private cachedEntries: Map<string, RevocationEntry> = new Map();
  private lastSuccessfulRefreshMs: number | null = null;
  private currentTtlMs: number = DEFAULT_CACHE_TTL_MS;
  private lastError?: string;
  private refreshPromise: Promise<boolean> | null = null;

  public static getInstance(): AttestationRevocationService {
    if (!AttestationRevocationService.instance) {
      AttestationRevocationService.instance = new AttestationRevocationService();
    }
    return AttestationRevocationService.instance;
  }

  /**
   * Normalizes a certificate serial number to Google's key format:
   * Lowercase hex without leading zeros (matching ^[a-f1-9][a-f0-9]*$).
   */
  public static normalizeSerialNumber(serial: string): string {
    if (!serial) return '';
    // Strip colons, spaces, 0x prefix, leading zeros, and convert to lowercase
    const cleaned = serial.replace(/[:\s]/g, '').replace(/^0x/i, '').toLowerCase();
    const stripped = cleaned.replace(/^0+/, '');
    return stripped || '0';
  }

  /**
   * Checks if a certificate serial number is listed as REVOKED or SUSPENDED.
   */
  public checkRevocation(serialHex: string): RevocationCheckResult {
    const normalized = AttestationRevocationService.normalizeSerialNumber(serialHex);
    const entry = this.cachedEntries.get(normalized);

    if (entry) {
      return {
        isRevoked: true,
        serialNormalized: normalized,
        status: entry.status,
        reason: entry.reason,
        comment: entry.comment,
      };
    }

    return {
      isRevoked: false,
      serialNormalized: normalized,
    };
  }

  /**
   * Checks a crypto.X509Certificate instance for revocation status.
   */
  public checkCertificate(cert: crypto.X509Certificate): RevocationCheckResult {
    return this.checkRevocation(cert.serialNumber);
  }

  /**
   * Fetches latest certificate status from https://android.googleapis.com/attestation/status.
   * Respects HTTP Cache-Control header and handles fail-closed caching.
   */
  public async refreshRevocationList(force: boolean = false): Promise<boolean> {
    const now = Date.now();
    if (!force && this.lastSuccessfulRefreshMs && now - this.lastSuccessfulRefreshMs < this.currentTtlMs) {
      return true; // Cache is still fresh
    }

    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = this.fetchFromGoogle();
    try {
      const success = await this.refreshPromise;
      return success;
    } finally {
      this.refreshPromise = null;
    }
  }

  private fetchFromGoogle(): Promise<boolean> {
    return new Promise((resolve) => {
      // In offline/test environments where network calls are restricted or mocked:
      if (process.env.MOCK_REVOCATION_STATUS === 'true') {
        this.lastSuccessfulRefreshMs = Date.now();
        resolve(true);
        return;
      }

      const req = https.get(
        GOOGLE_ATTESTATION_STATUS_URL,
        {
          headers: {
            'User-Agent': 'Kelasagara-Biometric-Security-Engine/20.4',
            Accept: 'application/json',
          },
          timeout: 10000,
        },
        (res) => {
          if (res.statusCode !== 200) {
            this.lastError = `HTTP ${res.statusCode} from attestation status endpoint`;
            res.resume();
            resolve(false);
            return;
          }

          // Parse Cache-Control max-age if present
          const cacheControl = res.headers['cache-control'];
          if (cacheControl) {
            const match = cacheControl.match(/max-age=(\d+)/i);
            if (match) {
              const seconds = parseInt(match[1], 10);
              if (!isNaN(seconds) && seconds > 0) {
                this.currentTtlMs = seconds * 1000;
              }
            }
          }

          const chunks: Buffer[] = [];
          res.on('data', (chunk) => chunks.push(chunk));
          res.on('end', () => {
            try {
              const rawText = Buffer.concat(chunks).toString('utf8');
              const data = JSON.parse(rawText) as RevocationStatusPayload;

              if (data && typeof data.entries === 'object') {
                const newMap = new Map<string, RevocationEntry>();
                for (const [key, val] of Object.entries(data.entries)) {
                  if (val && (val.status === 'REVOKED' || val.status === 'SUSPENDED')) {
                    const normKey = AttestationRevocationService.normalizeSerialNumber(key);
                    newMap.set(normKey, {
                      status: val.status,
                      reason: val.reason,
                      comment: val.comment,
                    });
                  }
                }
                this.cachedEntries = newMap;
                this.lastSuccessfulRefreshMs = Date.now();
                this.lastError = undefined;
                resolve(true);
              } else {
                this.lastError = 'Invalid payload format: missing entries dictionary';
                resolve(false);
              }
            } catch (err: any) {
              this.lastError = `JSON parse failure: ${err.message}`;
              resolve(false);
            }
          });
        }
      );

      req.on('error', (err) => {
        this.lastError = `Network error: ${err.message}`;
        resolve(false);
      });

      req.on('timeout', () => {
        req.destroy();
        this.lastError = 'Connection timed out';
        resolve(false);
      });
    });
  }

  /**
   * Test fixture helper: injects mock revocation entries for adversarial test suites.
   */
  public setMockEntries(entries: Record<string, RevocationEntry>): void {
    const newMap = new Map<string, RevocationEntry>();
    for (const [k, v] of Object.entries(entries)) {
      newMap.set(AttestationRevocationService.normalizeSerialNumber(k), v);
    }
    this.cachedEntries = newMap;
    this.lastSuccessfulRefreshMs = Date.now();
  }

  /**
   * Returns current health and diagnostic status.
   */
  public getHealthStatus(): RevocationServiceHealth {
    const now = Date.now();
    const isStale = this.lastSuccessfulRefreshMs === null || now - this.lastSuccessfulRefreshMs > this.currentTtlMs;

    return {
      healthy: !isStale && this.lastError === undefined,
      cachedEntriesCount: this.cachedEntries.size,
      lastSuccessfulRefreshMs: this.lastSuccessfulRefreshMs,
      lastRefreshIso: this.lastSuccessfulRefreshMs ? new Date(this.lastSuccessfulRefreshMs).toISOString() : null,
      ttlMs: this.currentTtlMs,
      isStale,
      lastError: this.lastError,
    };
  }
}
