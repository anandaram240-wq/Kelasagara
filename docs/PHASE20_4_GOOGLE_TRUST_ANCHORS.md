# PHASE 20.4 GOOGLE TRUST ANCHORS & ROOT ROTATION
## Hardware Key Attestation Root Certificate Rotation Architecture

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Target Release:** Phase 20.4 (Independent Device Attestation & Trust-Chain Validation Engine)  
**Parent Phase 20.3 Commit:** `6f8a0c91e509d26ce7fab26bfe554cc902cc599f`  

---

## 1. MANDATORY ROOT ROTATION SPECIFICATION (1 FEBRUARY 2026)

Google's official Android Key Attestation documentation specifies that beginning **1 February 2026**, Android devices using Remote Key Provisioning (RKP) or newly provisioned hardware Keystores began issuing certificate chains rooted in a new ECDSA root certificate (*Google Key Attestation CA1*), alongside existing legacy RSA and EC roots:

1. **Legacy RSA Root 1 (Historical)**:
   - Subject: `CN=Google Hardware Attestation Root`
   - Key Type: RSA 4096-bit
   - SHA-256 Fingerprint: `e63283ca233f2c5890288825c93cb626786c57cbff81cf80687352fe21262ab8`
   - Role: Legacy hardware provisioned through Android 11.
2. **Legacy EC Root 2 (Historical)**:
   - Subject: `CN=Google Hardware Attestation Root`
   - Key Type: ECDSA P-256
   - SHA-256 Fingerprint: `aba4197e682705a6ef6022e3997e06a7495b452e80936e768e16e09c8942b03f`
   - Role: Hardware provisioned through early RKP pilots.
3. **Google Key Attestation CA1 (Active 1 February 2026)**:
   - Subject: `CN=Google Key Attestation CA1`
   - Key Type: ECDSA P-384
   - SHA-256 Fingerprint: `4a242c75a40a8a3a298cb3d7a8d56b26cf8d43890f55cf5f5cbb64b598b958e0`
   - Role: Active primary root for Remote Key Provisioning (RKP) and modern Android devices.
4. **RKP Secondary & Intermediate Roots**:
   - Primary: `c7e6c986915f02c67ad7f485f7a3f87b8b4221147a46985d8525b5974c05ef1e`
   - Secondary: `a02f3a61d1e4c76b107e382b6b0cbb412e84c9826d70ff38367e9b38f8cf6252`

---

## 2. ROOT CERTIFICATE VALIDATION INVARIANTS

The backend verifier (`device_key_attestation.ts`) strictly enforces the following trust anchor rules:

1. **Static Pinning with Rotation Support**: All valid Google trust anchors are compiled into the server's immutable root directory. Roots submitted by the mobile client or downloaded on the fly without verification are **REJECTED**.
2. **Strict Chain Path Validation**: Every certificate in the path from leaf to root is verified:
   - Intermediate certificate signatures are verified against their issuers.
   - The root certificate must match one of the pinned Google SHA-256 fingerprints.
   - Self-signed roots not matching pinned fingerprints trigger immediate termination with error `INVALID_ROOT_SIGNATURE` or `UNKNOWN_ROOT_ANCHOR`.
3. **Validity Period Enforcement**: Verifies `notBefore` and `notAfter` timestamps against the current server UTC time.
4. **Basic Constraints & Key Usage**: Verifies CA bit (`basicConstraints.cA === true`) on all intermediate certificates.
5. **No Client-Supplied Roots**: The root certificate must be discovered from trusted local anchor storage, preventing untrusted root injection attacks.

---

## 3. CONTROLLED TRUST-ANCHOR UPDATE PROCEDURE

To update root anchors in production:
1. Obtain the new certificate directly from the official Google repository (`https://developer.android.com/privacy-and-security/security-key-attestation`).
2. Verify certificate cryptographic attributes using OpenSSL:
   ```bash
   openssl x509 -in root.pem -text -noout
   openssl x509 -in root.pem -fingerprint -sha256
   ```
3. Add the validated root to `GOOGLE_TRUST_ANCHORS` in `backend/src/services/device_key_attestation.ts`.
4. Run root rotation unit tests in `phase20_4_attestation_validation.test.ts` to ensure backward and forward compatibility.
5. Deploy via signed immutable container release.
