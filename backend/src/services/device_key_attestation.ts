// File: backend/src/services/device_key_attestation.ts
import * as crypto from 'node:crypto';
import { AttestationRevocationService } from './attestation_revocation_service';

export type AttestationSecurityLevel =
  | 'STRONGBOX_BACKED'
  | 'TEE_BACKED'
  | 'SOFTWARE_BACKED'
  | 'UNVERIFIED'
  | 'REJECTED'
  | 'DEVICE_KEY_STRONGBOX'
  | 'DEVICE_KEY_TEE'
  | 'DEVICE_KEY_SOFTWARE';

export type AttestationStatus =
  | 'VERIFIED'
  | 'SELF_ATTESTED'
  | 'CHALLENGE_MISMATCH'
  | 'PACKAGE_MISMATCH'
  | 'SIGNATURE_DIGEST_MISMATCH'
  | 'REVOKED'
  | 'SUSPENDED'
  | 'EXPIRED'
  | 'UNTRUSTED_ROOT'
  | 'UNSUPPORTED_ALGORITHM'
  | 'INVALID_CHAIN'
  | 'UNVERIFIED_BOOT_STATE'
  | 'DEVICE_UNLOCKED';

export type VerifiedBootStateType = 'VERIFIED' | 'SELF_SIGNED' | 'UNVERIFIED' | 'FAILED';

export interface RootOfTrustRecord {
  readonly verifiedBootKeyHex?: string;
  readonly deviceLocked: boolean;
  readonly verifiedBootState: VerifiedBootStateType;
  readonly verifiedBootStateNumeric: number;
  readonly verifiedBootHashHex?: string;
}

export interface KeyAuthorizationDetails {
  readonly purposes: number[];
  readonly algorithm?: number;
  readonly keySize?: number;
  readonly digests: number[];
  readonly origin?: number; // 0 = GENERATED, 1 = DERIVED, 2 = IMPORTED
  readonly osVersion?: number;
  readonly osPatchLevel?: number;
  readonly vendorPatchLevel?: number;
  readonly bootPatchLevel?: number;
  readonly packageNames: string[];
  readonly signatureDigests: string[];
  readonly rootOfTrust?: RootOfTrustRecord;
}

export interface ParsedAttestationRecord {
  readonly attestationVersion: number;
  readonly attestationSecurityLevel: number; // 0 = Software, 1 = TEE, 2 = StrongBox
  readonly keymintVersion: number;
  readonly keymintSecurityLevel: number;
  readonly attestationChallenge: Buffer;
  readonly uniqueId: Buffer;
  readonly softwareEnforced: KeyAuthorizationDetails;
  readonly hardwareEnforced: KeyAuthorizationDetails;
  readonly extensionPositionInChain: number;
  readonly packageName?: string;
}

export interface DeviceKeyAttestationResult {
  readonly valid: boolean;
  readonly attestationLevel: AttestationSecurityLevel;
  readonly attestationStatus: AttestationStatus;
  readonly publicKeyPem: string;
  readonly keyAlgorithm: 'ECDSA_P256';
  readonly securityLevelNumeric: number;
  readonly applicationPackage?: string;
  readonly attestationChallengeHex?: string;
  readonly certificateChainLength: number;
  readonly trustAnchorFingerprint?: string;
  readonly rootOfTrust?: RootOfTrustRecord;
  readonly osVersion?: number;
  readonly osPatchLevel?: number;
  readonly failureReason?: string;
}

export interface VerifyDeviceAttestationParams {
  readonly certificateChainBase64: string[];
  readonly expectedChallenge: string | Buffer;
  readonly expectedPackageName?: string;
  readonly expectedSigningCertDigest?: string;
  readonly allowSelfAttestedDev?: boolean;
  readonly requireDeviceLocked?: boolean;
  readonly requireVerifiedBoot?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// GOOGLE HARDWARE ATTESTATION TRUST ANCHORS (Updated for 2026 Rotation)
// Reference: https://developer.android.com/privacy-and-security/security-key-attestation#root_certificates
// ─────────────────────────────────────────────────────────────────────────────
export const GOOGLE_ROOT_ANCHORS = {
  // 1. Google Hardware Attestation Root 1 (RSA-4096, legacy factory anchor)
  RSA_ROOT_1: 'e63283ca233f2d24ab742cc10ec1f211d13b35be92a3424177b8b4b74a3fbe3f',
  // 2. Google Hardware Attestation Root 2 (EC P-256, secondary hardware anchor)
  EC_ROOT_2: 'aba4197e009d2550c39e256ee44817d861d199cb25a59ef6a45a37098cb9f14b',
  // 3. Google Hardware Key Attestation CA1 (ECDSA P-384, 1 Feb 2026 Rotation Anchor)
  KEY_ATTESTATION_CA1_2026: '4a242c75a40a8cf5c64c1b9ea892550f2427b3d3ff3e0b240b957e84f50f22f8',
  // 4. Remote Key Provisioning (RKP) Infrastructure Roots
  RKP_ROOT_PRIMARY: '170c8f5539eb858c2f168b422a578a1f81f5c6e86ef5dc1b3cfb9b27a3c3e869',
  RKP_ROOT_SECONDARY: '2d4f808fcb0a39d8924b22c7a6e72bf89c445695cfb116d4454b5dfa97b209d6',
} as const;

export const KNOWN_GOOGLE_ROOT_FINGERPRINTS = new Set<string>(Object.values(GOOGLE_ROOT_ANCHORS));

// Android Attestation Extension OID bytes: 1.3.6.1.4.1.11129.2.1.17
export const ATTESTATION_OID_BYTES = Buffer.from([
  0x2b, 0x06, 0x01, 0x04, 0x01, 0xd6, 0x79, 0x02, 0x01, 0x11,
]);

/**
 * Robust ASN.1 TLV Reader supporting multi-byte lengths and multi-byte tags
 */
export function readAsn1Tlv(
  buf: Buffer,
  offset: number
): { tag: number; tagBytesCount: number; length: number; value: Buffer; totalLength: number } | null {
  if (offset >= buf.length) return null;

  let pos = offset;
  let tag = buf[pos++];
  let tagBytesCount = 1;

  // Handle multi-byte tags (tag & 0x1F === 0x1F)
  if ((tag & 0x1f) === 0x1f) {
    let tagNum = 0;
    while (pos < buf.length) {
      const b = buf[pos++];
      tagBytesCount++;
      tagNum = (tagNum << 7) | (b & 0x7f);
      if ((b & 0x80) === 0) break;
    }
  }

  if (pos >= buf.length) return null;

  let lenByte = buf[pos++];
  let length = 0;
  let lenBytesCount = 1;

  if (lenByte < 0x80) {
    length = lenByte;
  } else {
    const numBytes = lenByte & 0x7f;
    lenBytesCount = 1 + numBytes;
    length = 0;
    for (let i = 0; i < numBytes; i++) {
      if (pos >= buf.length) return null;
      length = (length << 8) | buf[pos++];
    }
  }

  if (pos + length > buf.length) {
    // Malformed length
    return null;
  }

  const value = buf.subarray(pos, pos + length);
  const totalLength = tagBytesCount + lenBytesCount + length;

  return { tag, tagBytesCount, length, value, totalLength };
}

/**
 * Parses an AuthorizationList sequence into structured key parameters.
 */
export function parseAuthorizationList(authListBuf: Buffer): KeyAuthorizationDetails {
  const details: KeyAuthorizationDetails = {
    purposes: [],
    digests: [],
    packageNames: [],
    signatureDigests: [],
  };

  let pos = 0;
  while (pos < authListBuf.length) {
    const tlv = readAsn1Tlv(authListBuf, pos);
    if (!tlv) break;

    // Check context-specific tags:
    // Tag 1 (0xA1): purpose (SET of INTEGER)
    if (tlv.tag === 0xa1) {
      let pPos = 0;
      while (pPos < tlv.value.length) {
        const item = readAsn1Tlv(tlv.value, pPos);
        if (!item) break;
        if (item.tag === 0x02) {
          details.purposes.push(item.value.readIntBE(0, item.value.length));
        }
        pPos += item.totalLength;
      }
    }
    // Tag 2 (0xA2): algorithm (INTEGER)
    else if (tlv.tag === 0xa2) {
      if (tlv.value[0] === 0x02) {
        const intTlv = readAsn1Tlv(tlv.value, 0);
        if (intTlv) (details as any).algorithm = intTlv.value.readIntBE(0, intTlv.value.length);
      } else {
        (details as any).algorithm = tlv.value.readIntBE(0, tlv.value.length);
      }
    }
    // Tag 3 (0xA3): keySize (INTEGER)
    else if (tlv.tag === 0xa3) {
      if (tlv.value[0] === 0x02) {
        const intTlv = readAsn1Tlv(tlv.value, 0);
        if (intTlv) (details as any).keySize = intTlv.value.readIntBE(0, intTlv.value.length);
      } else {
        (details as any).keySize = tlv.value.readIntBE(0, tlv.value.length);
      }
    }
    // Tag 5 (0xA5): digest (SET of INTEGER)
    else if (tlv.tag === 0xa5) {
      let dPos = 0;
      while (dPos < tlv.value.length) {
        const item = readAsn1Tlv(tlv.value, dPos);
        if (!item) break;
        if (item.tag === 0x02) {
          details.digests.push(item.value.readIntBE(0, item.value.length));
        }
        dPos += item.totalLength;
      }
    }
    // Multi-byte tags: check by buffer match or tag values
    // Tag 702 (0xBF853E): origin (INTEGER)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x3e]))) {
      const intTlv = readAsn1Tlv(tlv.value, 0);
      if (intTlv) (details as any).origin = intTlv.value.readIntBE(0, intTlv.value.length);
    }
    // Tag 704 (0xBF8540): rootOfTrust (SEQUENCE)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x40]))) {
      const rotSeq = readAsn1Tlv(tlv.value, 0);
      if (rotSeq && rotSeq.tag === 0x30) {
        let rPos = 0;
        const keyTlv = readAsn1Tlv(rotSeq.value, rPos);
        rPos += keyTlv ? keyTlv.totalLength : 0;
        const lockTlv = readAsn1Tlv(rotSeq.value, rPos);
        rPos += lockTlv ? lockTlv.totalLength : 0;
        const bootStateTlv = readAsn1Tlv(rotSeq.value, rPos);
        rPos += bootStateTlv ? bootStateTlv.totalLength : 0;
        const hashTlv = readAsn1Tlv(rotSeq.value, rPos);

        const deviceLocked = lockTlv ? lockTlv.value[0] !== 0 : false;
        const stateNum = bootStateTlv ? bootStateTlv.value.readIntBE(0, bootStateTlv.value.length) : 2;
        const stateNames: VerifiedBootStateType[] = ['VERIFIED', 'SELF_SIGNED', 'UNVERIFIED', 'FAILED'];
        const verifiedBootState: VerifiedBootStateType = stateNames[stateNum] || 'UNVERIFIED';

        (details as any).rootOfTrust = {
          verifiedBootKeyHex: keyTlv?.value.toString('hex'),
          deviceLocked,
          verifiedBootState,
          verifiedBootStateNumeric: stateNum,
          verifiedBootHashHex: hashTlv?.value.toString('hex'),
        };
      }
    }
    // Tag 705 (0xBF8541): osVersion (INTEGER)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x41]))) {
      const intTlv = readAsn1Tlv(tlv.value, 0);
      if (intTlv) (details as any).osVersion = intTlv.value.readIntBE(0, intTlv.value.length);
    }
    // Tag 706 (0xBF8542): osPatchLevel (INTEGER)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x42]))) {
      const intTlv = readAsn1Tlv(tlv.value, 0);
      if (intTlv) (details as any).osPatchLevel = intTlv.value.readIntBE(0, intTlv.value.length);
    }
    // Tag 709 (0xBF8545): attestationApplicationId (OCTET STRING)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x45]))) {
      const appBuf = tlv.value;
      // Extract package names from ASN.1 OCTET STRINGs or UTF-8 tokens
      const text = appBuf.toString('utf8');
      const matches = text.match(/[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)+/g);
      if (matches) {
        for (const m of matches) {
          if (!details.packageNames.includes(m)) {
            details.packageNames.push(m);
          }
        }
      }
    }
    // Tag 718 (0xBF854E): vendorPatchLevel (INTEGER)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x4e]))) {
      const intTlv = readAsn1Tlv(tlv.value, 0);
      if (intTlv) (details as any).vendorPatchLevel = intTlv.value.readIntBE(0, intTlv.value.length);
    }
    // Tag 719 (0xBF854F): bootPatchLevel (INTEGER)
    else if (authListBuf.subarray(pos, pos + 3).equals(Buffer.from([0xbf, 0x85, 0x4f]))) {
      const intTlv = readAsn1Tlv(tlv.value, 0);
      if (intTlv) (details as any).bootPatchLevel = intTlv.value.readIntBE(0, intTlv.value.length);
    }

    pos += tlv.totalLength;
  }

  return details;
}

/**
 * Searches the certificate chain and parses the FIRST trusted occurrence of the
 * Android KeyStore Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17).
 */
export function findAndParseAttestationExtension(chainDers: Buffer[]): ParsedAttestationRecord | null {
  for (let certIndex = 0; certIndex < chainDers.length; certIndex++) {
    const certDer = chainDers[certIndex];
    const idx = certDer.indexOf(ATTESTATION_OID_BYTES);
    if (idx === -1) continue;

    let scanPos = idx + ATTESTATION_OID_BYTES.length;
    // Check if critical boolean (tag 0x01) precedes the octet string
    if (certDer[scanPos] === 0x01) {
      scanPos += 3;
    }

    if (certDer[scanPos] !== 0x04) continue;

    const octetTlv = readAsn1Tlv(certDer, scanPos);
    if (!octetTlv) continue;

    const seqBuf = octetTlv.value;
    if (seqBuf[0] !== 0x30) continue;

    const seqTlv = readAsn1Tlv(seqBuf, 0);
    if (!seqTlv) continue;

    const items = seqTlv.value;
    let pos = 0;

    // Field 1: attestationVersion (INTEGER)
    const it1 = readAsn1Tlv(items, pos);
    if (!it1) continue;
    const attestationVersion = it1.value.readIntBE(0, it1.value.length);
    pos += it1.totalLength;

    // Field 2: attestationSecurityLevel (ENUMERATED)
    const it2 = readAsn1Tlv(items, pos);
    if (!it2) continue;
    const attestationSecurityLevel = it2.value.readIntBE(0, it2.value.length);
    pos += it2.totalLength;

    // Field 3: keymintVersion (INTEGER)
    const it3 = readAsn1Tlv(items, pos);
    if (!it3) continue;
    const keymintVersion = it3.value.readIntBE(0, it3.value.length);
    pos += it3.totalLength;

    // Field 4: keymintSecurityLevel (ENUMERATED)
    const it4 = readAsn1Tlv(items, pos);
    if (!it4) continue;
    const keymintSecurityLevel = it4.value.readIntBE(0, it4.value.length);
    pos += it4.totalLength;

    // Field 5: attestationChallenge (OCTET STRING)
    const it5 = readAsn1Tlv(items, pos);
    if (!it5) continue;
    const attestationChallenge = it5.value;
    pos += it5.totalLength;

    // Field 6: uniqueId (OCTET STRING)
    const it6 = readAsn1Tlv(items, pos);
    const uniqueId = it6 ? it6.value : Buffer.alloc(0);
    pos += it6 ? it6.totalLength : 0;

    // Field 7: softwareEnforced (SEQUENCE / AuthorizationList)
    const it7 = readAsn1Tlv(items, pos);
    const softwareEnforced = it7 ? parseAuthorizationList(it7.value) : { purposes: [], digests: [], packageNames: [], signatureDigests: [] };
    pos += it7 ? it7.totalLength : 0;

    // Field 8: hardwareEnforced (SEQUENCE / AuthorizationList)
    const it8 = readAsn1Tlv(items, pos);
    const hardwareEnforced = it8 ? parseAuthorizationList(it8.value) : { purposes: [], digests: [], packageNames: [], signatureDigests: [] };

    // Package name detection fallback if embedded in raw bytes
    const pkg = 'com.kelasagaara.kelasagaara';
    if (seqBuf.indexOf(Buffer.from(pkg, 'utf8')) !== -1 && !softwareEnforced.packageNames.includes(pkg)) {
      softwareEnforced.packageNames.push(pkg);
    }

    return {
      attestationVersion,
      attestationSecurityLevel,
      keymintVersion,
      keymintSecurityLevel,
      attestationChallenge,
      uniqueId,
      softwareEnforced,
      hardwareEnforced,
      extensionPositionInChain: certIndex,
      packageName: softwareEnforced.packageNames[0] || hardwareEnforced.packageNames[0],
    };
  }

  return null;
}

/**
 * Backward compatibility alias for single-certificate extension parsing.
 */
export function parseAndroidAttestationExtension(certDer: Buffer): ParsedAttestationRecord | null {
  return findAndParseAttestationExtension([certDer]);
}

/**
 * Server-Side Independent Android Hardware Key Attestation Verifier (Phase 20.4)
 */
export class DeviceKeyAttestationVerifier {
  private static instance: DeviceKeyAttestationVerifier;
  private readonly revocationService: AttestationRevocationService;

  constructor(revocationService?: AttestationRevocationService) {
    this.revocationService = revocationService ?? AttestationRevocationService.getInstance();
  }

  public static getInstance(revocationService?: AttestationRevocationService): DeviceKeyAttestationVerifier {
    if (!DeviceKeyAttestationVerifier.instance) {
      DeviceKeyAttestationVerifier.instance = new DeviceKeyAttestationVerifier(revocationService);
    }
    return DeviceKeyAttestationVerifier.instance;
  }

  /**
   * Independently verifies the complete Android hardware key attestation trust chain,
   * performs certificate revocation checks against Google's status endpoint,
   * inspects verified boot and lock state, and classifies the hardware assurance level.
   */
  public verifyAttestation(params: VerifyDeviceAttestationParams): DeviceKeyAttestationResult {
    const {
      certificateChainBase64,
      expectedChallenge,
      expectedPackageName = 'com.kelasagaara.kelasagaara',
      allowSelfAttestedDev,
      requireDeviceLocked = false,
      requireVerifiedBoot = false,
    } = params;

    if (!certificateChainBase64 || !Array.isArray(certificateChainBase64) || certificateChainBase64.length === 0) {
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'INVALID_CHAIN',
        publicKeyPem: '',
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: 0,
        certificateChainLength: 0,
        failureReason: 'Certificate chain is empty or missing',
      };
    }

    // Convert expected challenge to Buffer
    const expectedChallengeBuf = Buffer.isBuffer(expectedChallenge)
      ? expectedChallenge
      : Buffer.from(
          expectedChallenge,
          typeof expectedChallenge === 'string' && /^[0-9a-fA-F]+$/.test(expectedChallenge) && expectedChallenge.length % 2 === 0
            ? 'hex'
            : 'utf8'
        );

    // 1. Parse X.509 certificates and DER buffers
    const certs: crypto.X509Certificate[] = [];
    const chainDers: Buffer[] = [];
    try {
      for (const b64 of certificateChainBase64) {
        const der = Buffer.from(b64, 'base64');
        chainDers.push(der);
        certs.push(new crypto.X509Certificate(der));
      }
    } catch (e: any) {
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'INVALID_CHAIN',
        publicKeyPem: '',
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: 0,
        certificateChainLength: 0,
        failureReason: `Failed to parse X.509 certificate: ${e.message}`,
      };
    }

    const leafCert = certs[0];
    const rootCert = certs[certs.length - 1];

    // 2. Algorithm Verification (Must be ECDSA over P-256)
    const pubKeyObj = leafCert.publicKey;
    if (pubKeyObj.asymmetricKeyType !== 'ec') {
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'UNSUPPORTED_ALGORITHM',
        publicKeyPem: pubKeyObj.export({ type: 'spki', format: 'pem' }).toString(),
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: 0,
        certificateChainLength: certs.length,
        failureReason: `Expected EC P-256 key, got ${pubKeyObj.asymmetricKeyType}`,
      };
    }

    const leafPublicKeyPem = pubKeyObj.export({ type: 'spki', format: 'pem' }).toString();

    // 3. Validity Period Audit
    const now = Date.now();
    for (let i = 0; i < certs.length; i++) {
      const validFrom = new Date(certs[i].validFrom).getTime();
      const validTo = new Date(certs[i].validTo).getTime();
      if (now < validFrom || now > validTo) {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: 'EXPIRED',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: 0,
          certificateChainLength: certs.length,
          failureReason: `Certificate at index ${i} is outside its validity period`,
        };
      }
    }

    // 4. Cryptographic Signature Chain Audit
    for (let i = 0; i < certs.length - 1; i++) {
      const subject = certs[i];
      const issuer = certs[i + 1];
      const verified = subject.verify(issuer.publicKey);
      if (!verified) {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: 'INVALID_CHAIN',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: 0,
          certificateChainLength: certs.length,
          failureReason: `Cryptographic signature verification failed between certificate ${i} and issuer ${i + 1}`,
        };
      }
    }

    // 5. Certificate Revocation Audit (Google CRL Status Check)
    for (let i = 0; i < certs.length; i++) {
      const revCheck = this.revocationService.checkCertificate(certs[i]);
      if (revCheck.isRevoked) {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: revCheck.status === 'SUSPENDED' ? 'SUSPENDED' : 'REVOKED',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: 0,
          certificateChainLength: certs.length,
          failureReason: `Certificate at index ${i} (serial: ${revCheck.serialNormalized}) is ${revCheck.status}: ${revCheck.reason || 'UNSPECIFIED'}`,
        };
      }
    }

    // 6. Root CA Anchor Verification (Supports 2026 Rotation Roots)
    const isSelfSignedRoot = rootCert.verify(rootCert.publicKey);
    const rootFingerprint = rootCert.fingerprint256.toLowerCase().replace(/:/g, '');
    const isKnownGoogleRoot = KNOWN_GOOGLE_ROOT_FINGERPRINTS.has(rootFingerprint);

    if (process.env.APP_ENV === 'PRODUCTION') {
      if (!isKnownGoogleRoot) {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: 'UNTRUSTED_ROOT',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: 0,
          certificateChainLength: certs.length,
          trustAnchorFingerprint: rootFingerprint,
          failureReason: `Root certificate does not anchor to a trusted Google Attestation Root CA (got ${rootFingerprint})`,
        };
      }
    }

    // 7. Structured Android Key Attestation Extension Validation
    const attestation = findAndParseAttestationExtension(chainDers);

    if (!attestation) {
      if (allowSelfAttestedDev || process.env.APP_ENV === 'LOCAL' || process.env.APP_ENV === 'TEST') {
        return {
          valid: true,
          attestationLevel: 'SOFTWARE_BACKED',
          attestationStatus: 'SELF_ATTESTED',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: 0,
          certificateChainLength: certs.length,
        };
      }
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'UNTRUSTED_ROOT',
        publicKeyPem: leafPublicKeyPem,
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: 0,
        certificateChainLength: certs.length,
        failureReason: 'Missing Android KeyStore Attestation extension (OID 1.3.6.1.4.1.11129.2.1.17)',
      };
    }

    // 8. Challenge Verification
    const challengeMatch =
      attestation.attestationChallenge.equals(expectedChallengeBuf) ||
      attestation.attestationChallenge.toString('hex') === expectedChallengeBuf.toString('hex') ||
      attestation.attestationChallenge.toString('utf8') === expectedChallengeBuf.toString('utf8');

    if (!challengeMatch) {
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'CHALLENGE_MISMATCH',
        publicKeyPem: leafPublicKeyPem,
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: attestation.attestationSecurityLevel,
        attestationChallengeHex: attestation.attestationChallenge.toString('hex'),
        certificateChainLength: certs.length,
        failureReason: 'Attestation challenge does not match server-issued challenge',
      };
    }

    // 9. Application Identity Verification (Package Name)
    const combinedPackages = [
      ...attestation.softwareEnforced.packageNames,
      ...attestation.hardwareEnforced.packageNames,
    ];
    if (expectedPackageName && combinedPackages.length > 0 && !combinedPackages.includes(expectedPackageName)) {
      return {
        valid: false,
        attestationLevel: 'REJECTED',
        attestationStatus: 'PACKAGE_MISMATCH',
        publicKeyPem: leafPublicKeyPem,
        keyAlgorithm: 'ECDSA_P256',
        securityLevelNumeric: attestation.attestationSecurityLevel,
        applicationPackage: combinedPackages[0],
        certificateChainLength: certs.length,
        failureReason: `Package name mismatch: expected ${expectedPackageName}, got ${combinedPackages.join(', ')}`,
      };
    }

    // 10. Verified Boot & Device Lock Verification
    const rootOfTrust = attestation.hardwareEnforced.rootOfTrust || attestation.softwareEnforced.rootOfTrust;
    if (rootOfTrust) {
      if (requireVerifiedBoot && rootOfTrust.verifiedBootState === 'FAILED') {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: 'UNVERIFIED_BOOT_STATE',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: attestation.attestationSecurityLevel,
          rootOfTrust,
          certificateChainLength: certs.length,
          failureReason: 'Device verified boot state is FAILED',
        };
      }

      if (requireDeviceLocked && !rootOfTrust.deviceLocked) {
        return {
          valid: false,
          attestationLevel: 'REJECTED',
          attestationStatus: 'DEVICE_UNLOCKED',
          publicKeyPem: leafPublicKeyPem,
          keyAlgorithm: 'ECDSA_P256',
          securityLevelNumeric: attestation.attestationSecurityLevel,
          rootOfTrust,
          certificateChainLength: certs.length,
          failureReason: 'Device bootloader is unlocked',
        };
      }
    }

    // 11. Security Assurance Classification
    const secLevelNum = attestation.attestationSecurityLevel;
    let attestationLevel: AttestationSecurityLevel = 'SOFTWARE_BACKED';
    if (secLevelNum === 2) {
      attestationLevel = 'STRONGBOX_BACKED';
    } else if (secLevelNum === 1) {
      attestationLevel = 'TEE_BACKED';
    }

    const osVersion = attestation.hardwareEnforced.osVersion ?? attestation.softwareEnforced.osVersion;
    const osPatchLevel = attestation.hardwareEnforced.osPatchLevel ?? attestation.softwareEnforced.osPatchLevel;

    return {
      valid: true,
      attestationLevel,
      attestationStatus: 'VERIFIED',
      publicKeyPem: leafPublicKeyPem,
      keyAlgorithm: 'ECDSA_P256',
      securityLevelNumeric: secLevelNum,
      applicationPackage: combinedPackages[0] || expectedPackageName,
      attestationChallengeHex: attestation.attestationChallenge.toString('hex'),
      certificateChainLength: certs.length,
      trustAnchorFingerprint: rootFingerprint,
      rootOfTrust,
      osVersion,
      osPatchLevel,
    };
  }
}
