# PHASE 20.4 ATTESTATION VERIFIER MIGRATION
## Architecture Evaluation of `github.com/android/keyattestation` and Server-Side Verification Migration

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Target Release:** Phase 20.4 (Independent Device Attestation & Trust-Chain Validation Engine)  
**Parent Phase 20.3 Commit:** `6f8a0c91e509d26ce7fab26bfe554cc902cc599f`  

---

## 1. EVALUATION OF OFFICIAL ANDROID KEY ATTESTATION VERIFIER

Google maintains the reference Java/Kotlin Key Attestation verifier at:  
`https://github.com/android/keyattestation` and documents key attestation verification protocols at:  
`https://developer.android.com/privacy-and-security/security-key-attestation`.

### Key Attestation Verifier Capabilities
1. **Trust Anchor Validation**: Pins official Google Root certificates and validates the X.509 certificate path up to a trusted hardware root.
2. **Revocation Information List**: Downloads and parses status JSON from `https://android.googleapis.com/attestation/status` to ensure no intermediate or leaf certificates are revoked.
3. **Structured ASN.1 Parsing**: Strictly parses ASN.1 SEQUENCE for `KeyDescription` (OID `1.3.6.1.4.1.11129.2.1.17`) including nested multi-byte context-specific tags.
4. **Security Level Distinction**: Differentiates between `Software` (0), `TrustedEnvironment` (1), and `StrongBox` (2) across both attestation and keymint security levels.
5. **Root of Trust Verification**: Extracts verified boot key hash, device lock status (`deviceLocked`), and `verifiedBootState` (`VERIFIED`, `SELF_SIGNED`, `UNVERIFIED`, `FAILED`).
6. **Application Identity Binding**: Validates package names and signing certificate SHA-256 digests against authoritative application declarations.
7. **Challenge Binding**: Verifies byte-exact parity between the attestation challenge and server-minted nonce.

---

## 2. SERVER-SIDE INTEGRATION ARCHITECTURE

### Design Trade-offs Considered

| Architecture Option | Latency | Complexity | Operational Surface | Security Boundary | Decision |
|---|---|---|---|---|---|
| **Option A: External Java/Kotlin Microservice** | High (HTTP roundtrip, network hop) | High (JVM runtime, separate deployment, IPC TLS) | High (New port, monitoring, failure domain) | Network boundary | **Rejected**: Unnecessary operational overhead for university submission |
| **Option B: Node-Java Native Bridge / Child Process** | Medium-High (process spawn, JNI) | High (JNI dependencies, platform-specific libjvm) | Medium (JVM installation on backend host) | Process boundary | **Rejected**: Fragile host dependencies across macOS/Linux |
| **Option C: In-Process Structured ASN.1 DER Schema Verifier (Node.js)** | Ultra-Low (< 2ms) | Low (Zero external daemon, typed TypeScript) | Minimal (Integrated in Express backend) | In-process server-authoritative | **Adopted**: Direct implementation of Google ASN.1 specification in `device_key_attestation.ts` |

### Key Invariants of Option C Implementation
1. **Server-Authoritative Only**: Verification occurs strictly within the trusted Node.js backend. Mobile Flutter code is treated as an untrusted client and never decides attestation validity.
2. **Complete ASN.1 BER/DER Spec Compliance**: Replaced simplistic custom parsing with recursive Tag-Length-Value (TLV) parsing supporting multi-byte context-specific tags ($\ge 31$), such as Tag 704 (`RootOfTrust`) and Tag 709 (`AttestationApplicationId`).
3. **Chain Search for First Trusted Occurrence**: Does not assume the extension is strictly on the leaf; inspects certificates in order, validating that the issuing chain signs the extension.
4. **Cryptographic Validation**: Uses Node.js native `crypto.X509Certificate` for signature verification across the entire chain from leaf to Google Root.

---

## 3. TYPED INTERNAL CONTRACT

The verifier exposes the following typed internal interface (`device_key_attestation.ts`):

```typescript
export interface AttestationVerificationResult {
  readonly isValid: boolean;
  readonly securityLevel: DeviceSecurityLevel; // 'STRONGBOX_BACKED' | 'TEE_BACKED' | 'SOFTWARE_BACKED' | 'UNVERIFIED' | 'REJECTED'
  readonly keymasterVersion?: number;
  readonly attestationVersion?: number;
  readonly attestationSecurityLevel?: number;
  readonly keymintSecurityLevel?: number;
  readonly challengeMatches: boolean;
  readonly applicationPackageMatches: boolean;
  readonly rootOfTrustVerified: boolean;
  readonly verifiedBootState?: 'VERIFIED' | 'SELF_SIGNED' | 'UNVERIFIED' | 'FAILED';
  readonly deviceLocked?: boolean;
  readonly osVersion?: number;
  readonly osPatchLevel?: number;
  readonly vendorPatchLevel?: number;
  readonly bootPatchLevel?: number;
  readonly certificateChainLength: number;
  readonly trustAnchor: string;
  readonly errors: readonly string[];
}
```

---

## 4. RESTRICTION OF CUSTOM DIAGNOSTICS
The legacy parsing logic has been superseded by structured schema parsing. Diagnostic extraction is maintained solely for forensic logging and failure diagnostics when untrusted or malformed chains are submitted during penetration testing.
