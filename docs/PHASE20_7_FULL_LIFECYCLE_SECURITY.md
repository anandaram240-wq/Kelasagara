# PHASE 20.7: FULL-LIFECYCLE MULTI-TIER BIOMETRIC SECURITY ARCHITECTURE
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Security Level:** Defense-in-Depth Multi-Layered Trust Model  
**Author:** Principal Application Security Architect & Cryptography Engineer  
**Date:** November 2026  
**Status:** VALIDATED & COMPREHENSIVELY AUDITED

---

## 1. Executive Summary & Security Philosophy

Biometric identity security cannot rely on facial pattern matching alone. A compromised client, an intercepted network payload, or an unencrypted database renders even the most advanced computer vision models useless.

Kelasagara implements a **Zero-Trust, Multi-Tier Biometric Security Lifecycle** where every stage of a biometric transaction—from photon capture on the handset to encrypted ciphertext persistence in Firestore—is cryptographically authenticated, hardware-bound, and verifiable.

```
+--------------------------------------------------------------------------------------------------+
| LAYER 1: HARDWARE KEYSTORE & HARDWARE ATTESTATION (Android Keystore ECDSA P-256)                 |
|  - Key generated in Secure Element (StrongBox / TEE)                                             |
|  - Attestation certificate chain validated against Google Root CA (X.509 extension 1.3.6.1.4.1)|
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 2: APPLICATION & DEVICE INTEGRITY (Google Play Integrity API)                              |
|  - Verdict: MEETS_DEVICE_INTEGRITY, LICENSED, sha256(APK) matched                               |
|  - Replay prevention: Cryptographic nonce bound to user session                                  |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 3: DEVICE-BOUND REQUEST SIGNATURE & PAYLOAD INTEGRITY                                      |
|  - Signature: ECDSA-P256-SHA256(Nonce || Timestamp || Method || Path || SHA256(Body))           |
|  - Timestamp tolerance: <= 300,000ms; Single-use nonce consumed via CAS in Redis/Memory          |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 4: MULTI-MODAL PRESENTATION ATTACK DETECTION (PAD)                                         |
|  - Baseline: Umeyama stability, eyelid aperture blink ratio (<=0.60), luminance variance (<=15%) |
|  - Hardened: Electronic display grid (Moiré) + Active chromatic corneal curvature delta (>0.02)  |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 5: SERVER-AUTHORITATIVE SFACE 128-D RECOGNITION                                            |
|  - ONNX Runtime execution in isolated process sandbox                                            |
|  - Umeyama affine alignment to 112x112 canonical reference                                       |
|  - Unit-norm projection (L2 norm = 1.0); 1:1 Cosine Similarity vs 1:N Gallery Search             |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 6: ZERO-PLAINTEXT BIOMETRIC VAULT ENCRYPTION                                               |
|  - Google Cloud KMS Envelope Encryption (AES-256-GCM)                                            |
|  - Canonical Binary Length-Prefixed AAD Binding (Tenant ID, User UID, Algorithm Version)         |
|  - Zero plaintext vectors persisted to Firestore or logs                                         |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LAYER 7: ATOMIC DEDUPLICATION & COMPLIANCE DISPUTE WORKFLOW                                      |
|  - Epoch CAS transactional deduplication (prevents duplicate account creation)                   |
|  - Borderline similarities (0.78 - 0.90) route to Compliance Officer Queue (CASE-XXXX)           |
+--------------------------------------------------------------------------------------------------+
```

---

## 2. Threat Vector Matrix & Defensive Mitigations

| Threat Vector | Attack Mechanism | Protective Security Layer | Verified Interception Test |
| :--- | :--- | :--- | :--- |
| **API Emulation / Script Bot** | Attacker calls `/verify` directly via cURL/Python | Layer 1 & Layer 3 | `phase20_3_device_bound_trust.test.ts` (Rejected: Missing Keystore Signature) |
| **Integrity Token Replay** | Attacker captures and replays valid Play Integrity token | Layer 2 | `phase20_2_play_integrity.test.ts` (Rejected: Nonce Expired / Replayed) |
| **Payload Tampering (MITM)** | Attacker alters `targetPersonId` or vector payload in transit | Layer 3 | `phase20_3_device_bound_trust.test.ts` (Signature Verification Mismatch) |
| **Modified / Repackaged APK** | Attacker injects hooking code into APK | Layer 2 | `phase20_2_play_integrity.test.ts` (Play Integrity APK Cert Mismatch) |
| **Rooted / Compromised OS** | Attacker hooks camera via Frida/Xposed | Layer 1 & Layer 2 | Hardware Attestation `verifiedBootState` check != `VERIFIED` |
| **Tablet Screen Video Replay** | Attacker replays video of victim blinking on iPad | Layer 4 (Hardened) | `phase20_7_pad_hardening.test.ts` (Rejected: Moiré Subpixel Grid / Specular) |
| **Database Compromise (Data Leak)** | Malicious insider dumps Firestore database | Layer 6 | `phase20_1_biometric_vault_encryption.test.ts` (AES-256-GCM Ciphertext Only) |
| **AAD Context Substitution** | Attacker swaps encrypted vector between two users | Layer 6 | `phase20_1_biometric_vault_encryption.test.ts` (GCM Tag Verification Failure) |
| **Concurrent Race Re-Enrollment** | Attacker submits two identical enrollments simultaneously | Layer 7 | `biometric_v10_phase10_persistence.test.ts` (Epoch CAS Abort & Retry) |

---

## 3. Cryptographic Invariants & Verification Guarantees

1. **Hardware-Enforced Keymaster Invariant (`INV-KEY-01`):**
   The private ECDSA key is non-exportable and marked with `PURPOSE_SIGN`. The private scalar never enters Android user space memory.
2. **Canonical AAD Framing Invariant (`INV-KMS-02`):**
   Additional Authenticated Data (AAD) utilizes length-prefixed binary framing:
   $$\text{AAD} = \text{len}(T) \parallel T \parallel \text{len}(U) \parallel U \parallel \text{len}(V) \parallel V$$
   This mathematically prevents delimiter collision attacks where `tenantA|userB` could collide with `tenantAuser|B`.
3. **Nonce Uniqueness & Freshness Invariant (`INV-REQ-03`):**
   Client request nonces are generated from secure random entropy ($256\,\text{bits}$) and stored with a 5-minute TTL. Replays with duplicate nonces fail immediately with `401 REPLAY_ATTACK_DETECTED`.
4. **Ephemerality of Raw Biometrics Invariant (`INV-BIO-04`):**
   Raw images decoded by Sharp or received via HTTP multipart are unlinked and memory-cleared within the same request execution stack. Zero raw JPEG/PNG images exist on disk or cloud storage.

---

## 4. Operational Compliance & Disaster Recovery

- **Dispute Resolution Queue (`CASE-XXXX`):**
  When a candidate similarity score falls into Band 2 ($0.78 \le s < 0.90$), the system writes an encrypted audit record to `biometric_investigation_cases` with a unique human-review case identifier (e.g. `CASE-2026-8821`).
- **Role-Based Access Control:**
  Only users possessing the Firebase Custom Claim `biometric_compliance_officer = true` can access the resolution endpoints. All review decisions require dual-authorization and cryptographic signing.

---

## 5. Summary Conclusion

The Kelasagara full-lifecycle security architecture provides uncompromised, defense-in-depth protection across all operational tiers. The candidate hardened PAD enhancements introduced in Phase 20.7 successfully close the physical sensor attack surface while maintaining absolute fidelity to the cryptographic foundations established in Phases 20.1 through 20.4.
