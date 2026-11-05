# PHASE 20.4 DEVICE SECURITY POLICY & HARDWARE EVALUATION
## Verified Boot, StrongBox vs TEE Classification, and Security Patch Policy

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Target Release:** Phase 20.4 (Independent Device Attestation & Trust-Chain Validation Engine)  
**Parent Phase 20.3 Commit:** `6f8a0c91e509d26ce7fab26bfe554cc902cc599f`  

---

## 1. HARDWARE SECURITY CLASSIFICATION

Hardware key attestation reports two distinct security level parameters:
- `attestationSecurityLevel`: The security level of the environment that signs the certificate chain.
- `keymasterSecurityLevel` / `keymintSecurityLevel`: The security level of the environment that stores and uses the private key.

### Security Level Taxonomy
The backend verifier (`device_key_attestation.ts`) classifies every device into one of five mutually exclusive security tiers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DEVICE SECURITY CLASSIFICATION                        │
├────────────────────┬──────────────┬─────────────┬──────────────┬────────────┤
│ Tier               │ Attestation  │ KeyMint     │ Hardware     │ Policy     │
│                    │ Level        │ Level       │ Component    │ Decision   │
├────────────────────┼──────────────┼─────────────┼──────────────┼────────────┤
│ STRONGBOX_BACKED   │ 2 (StrongBox)│ 2(StrongBox)│ Discrete SE  │ FULL PASS  │
│ TEE_BACKED         │ 1 (TEE)      │ 1 (TEE)     │ ARM TrustZone│ FULL PASS  │
│ SOFTWARE_BACKED    │ 0 (Software) │ 0 (Software)│ Android OS   │ REJECTED   │
│ UNVERIFIED         │ Non-matching │ Inconsistent│ Emulators    │ REJECTED   │
│ REJECTED           │ Any          │ Any         │ Tampered/Rev │ BLOCKED    │
└────────────────────┴──────────────┴─────────────┴──────────────┴────────────┘
```

### Invariants on StrongBox vs TEE
1. **Never Represented as Equivalent**: StrongBox uses dedicated tamper-resistant hardware (e.g. Titan M2, Secure Element), while TEE uses ARM TrustZone on the main SoC.
2. **Compatibility Policy**: Legitimate consumer Android devices lacking StrongBox (such as mid-range or earlier generation devices) are **NOT** blocked. `TEE_BACKED` devices are fully approved for all worker and marketplace workflows.
3. **Software-Backed Rejection**: `SOFTWARE_BACKED` keys (security level 0) are strictly forbidden from performing biometric transactions or registering as trusted devices.

---

## 2. VERIFIED BOOT & ROOT-OF-TRUST POLICY

Extracted from Tag 704 (`RootOfTrust`):
- `verifiedBootState`:
  - `0 (VERIFIED)`: Device booted an OEM-signed system image. Approved.
  - `1 (SELF_SIGNED)`: Device booted custom firmware with locked bootloader. Requires compliance warning.
  - `2 (UNVERIFIED)`: Unlocked bootloader or custom ROM without hardware verification. **REJECTED**.
  - `3 (FAILED)`: Boot verification failed. **REJECTED IMMEDIATELY**.
- `deviceLocked`: Boolean. If `false` (unlocked bootloader), the registration is **REJECTED** to prevent memory dump or physical extraction attacks.
- `verifiedBootKey`: SHA-256 digest of the OEM root of trust public key.

---

## 3. CONFIGURABLE SECURITY PATCH LEVEL POLICY

Rather than imposing arbitrary calendar date thresholds that artificially obsolete working devices, patch levels are evaluated against an evidence-based compatibility window:

```typescript
export interface DevicePatchPolicy {
  readonly minOsVersion: number; // e.g. 10 (API 29)
  readonly minOsPatchLevel: number; // YYYYMM format (e.g. 202101)
  readonly minVendorPatchLevel?: number;
  readonly minBootPatchLevel?: number;
}
```

- **Default Policy**: Minimum Android 10 (`osVersion >= 10`), minimum patch level `20210101`.
- **Configurability**: Policy parameters are stored in Firestore configuration docs (`system_config/device_policy`), allowing dynamic tuning without backend rebuilds.
