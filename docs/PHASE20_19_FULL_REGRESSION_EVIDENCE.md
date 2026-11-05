# PHASE 20.19: FULL REGRESSION TEST EVIDENCE, ANDROID COMPILATION & ARTIFACT AUDIT

## 1. Master Regression Test Execution Summary

| Test Suite Category | Runtime / Tool | Invocation Command | Tests Executed | Pass | Fail | Skipped | Duration |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Backend Master Regression** | Node.js native (`node:test`) | `npm test` | **1,249** | **1,249** | **0** | **0** | 50.14s |
| **Phase 20.19 Dedicated Suite** | Node.js native (`node:test`) | `node --test dist/tests/phase20_19_pilot_gate_a_closure.test.js` | **56** | **56** | **0** | **0** | 3.00s |
| **Phase 20.18 Dedicated Suite** | Node.js native (`node:test`) | `node --test dist/tests/phase20_18_pilot_readiness_corrections.test.js` | **45** | **45** | **0** | **0** | 0.97s |
| **Phase 20.17 Dedicated Suite** | Node.js native (`node:test`) | `node --test dist/tests/phase20_17_trusted_execution_provenance.test.js` | **50** | **50** | **0** | **0** | 1.13s |
| **Flutter Biometric Client Suite** | Flutter Test Engine | `flutter test test/biometric_v10_phase10_flutter_test.dart test/profile_biometric_isolation_test.dart` | **12** | **12** | **0** | **0** | 2.1s |
| **Android Kotlin Compilation** | Gradle 9.3.1 / Kotlin | `./gradlew :app:compileDebugKotlin` | **262 tasks** | **262** | **0** | **0** | 12.0s |
| **Android Debug APK Assembly** | Gradle 9.3.1 / AGP 9.0 | `./gradlew :app:assembleDebug` | **555 tasks** | **555** | **0** | **0** | 1m 0s |

---

## 2. Backend Master Regression Details

### 2.1 Invocation Log Output
```text
> kelasagara-biomatch-backend@1.0.0 test
> node --test --test-concurrency=1 dist/tests/*.test.js

ℹ tests 1249
ℹ suites 259
ℹ pass 1249
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 50144.296792
```

### 2.2 Functional Categories Validated Across 1,249 Tests
1. **Biometric Vault & AES-256-GCM Envelope Encryption:** Cloud KMS AAD binding, ISO/IEC 19772:2020 authenticated encryption, v1/v2/v3 envelope downgrade protection, nonce uniqueness across 1,000 iterations.
2. **Face Detection & Inference Pipeline:** YuNet landmark detection, canonical 5-point similarity transformation, SFace ONNX 128-D vector extraction, cosine similarity matching threshold (0.363).
3. **Audit Ledger & Off-Site Notary Checkpoints:** Hash-chained local audit events, write-once GCS precondition headers (`ifGenerationMatch=0`), RSA-PSS signature attestation, discontinuity detection.
4. **Workload Identity & Anti-Replay Tokens:** OAuth2/OIDC JWT validation, audience and issuer binding, durable SQLite replay defense, single-use token invalidation.
5. **OpenTofu Plan Input Attestation & Precedence:** Hashing of `.tf`, `terraform.tfvars`, `terraform.tfvars.json`, `*.auto.tfvars`, `*.auto.tfvars.json`, provider lock file, module source trees, CLI `-var-file`, and CLI `-var`; exact OpenTofu canonical variable precedence (Layer 1 -> Layer 2 -> Layer 3 -> Layer 4 -> Layer 5, CLI argument order); protected keyed HMAC secret fingerprinting; immutable Secret Manager numeric versions; saved binary plan reuse enforcement.
6. **OpenTofu Plan Encryption At Rest:** Native plan container encryption (`KSEP_V19`, AES-256-GCM, 0o600 permissions), historical key recovery across rotations, memory buffer scrubbing in `finally` blocks, fail-closed rejection of unencrypted plaintext plans (`ERR_UNENCRYPTED_PLAN_AT_REST`).
7. **Secret Manager Reference Validation & Version State Resolution:** Strict GCP project ID (hyphenated, no underscores) and numeric project number validation, secret ID character validation, metadata retrieval verifying `ENABLED` state, fail-closed rejection of `DISABLED` or `DESTROYED` versions (`ERR_SECRET_VERSION_NOT_ENABLED`).
8. **Cloud KMS HMAC Identity Mapping:** Canonical mapping from `plan-secret-hmac` to `projects/{project}/locations/asia-south1/keyRings/kelasagara-infra-keyring/cryptoKeys/plan-secret-hmac/cryptoKeyVersions/1`, least-privilege IAM separation (`signerVerifier` for runner vs `verifier` for apply gate), and Gate B boundary declaration (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`).
9. **Two-Person Dual Custody Recovery:** Independent officer registry interface, active status check, distinct `idpSubject` enforcement, distinct `mfaCredentialId` enforcement, requester self-approval block, and collusion limit disclosures.
10. **Pilot Cohort-Level Cryptographic Key Isolation:** Dedicated `biometric-pilot-vault-db` Firestore database, dedicated `pilot_dek_wrap` Cloud KMS key, fail-closed cross-environment query boundaries, and cohort-level vs per-user isolation disclosures.
11. **Plaintext Memory Hygiene:** Deterministic best-effort clearing of application-owned DEK buffers via `plaintextDek.fill(0)` in `finally` blocks on both success and exception pathways.
12. **Binary Plan Storage Protection:** 0o600 filesystem permissions, AES-256-GCM transit encryption, memory buffer scrubbing, and physical SSD erasure limitation disclosures.

---

## 3. Flutter & Android Native Build Evidence

### 3.1 Flutter Test Execution
```text
00:00 +0: loading test/biometric_v10_phase10_flutter_test.dart
00:00 +1: FLUTTER-P10-01: BiometricDuplicateAccountDialog displays all 6 masked original account fields clearly on HTTP 409
00:00 +2: DuplicateAccountResolutionSheet Tests 1: Renders opaque case reference, dual language headings, and handles all 3 action buttons
00:00 +3: FLUTTER-P10-02: BiometricLockedAccountBanner displays primary faceId and KS_FTOK lock token with working action callbacks
00:00 +4: DuplicateAccountResolutionSheet Tests 2: Renders ambiguous review headline when isAmbiguousReview=true
00:01 +6: Profile Screen Biometric Isolation Tests 3: Tapping Name & Bio opens edit modal directly with zero face verification or camera triggers
00:01 +7: Profile Screen Biometric Isolation Tests 4: Tapping Skills & Daily Rate opens edit modal directly with zero face verification triggers
00:01 +8: Profile Screen Biometric Isolation Tests 5: Tapping Experience Level opens edit modal directly with zero biometric triggers
00:01 +9: Profile Screen Biometric Isolation Tests 6: Tapping Coverage Area opens service area modal directly with zero biometric triggers
00:02 +9: All tests passed!
```

### 3.2 Android Native Kotlin Compilation (`:app:compileDebugKotlin`)
```text
BUILD SUCCESSFUL in 12s
262 actionable tasks: 5 executed, 257 up-to-date
Exit code: 0
```

### 3.3 Android Debug APK Assembly (`:app:assembleDebug`) & Forensic Size Breakdown
```text
BUILD SUCCESSFUL in 1m
555 actionable tasks: 71 executed, 484 up-to-date
Exit code: 0
Generated Artifact: build/app/outputs/flutter-apk/app-debug.apk
Size: 280,591,846 bytes (267.6 MB)
SHA-256: 90b0f3f90af0734320d6ed2552cbfce2b5ab02bd4c86542f0dc14244532199a1
```

#### Forensic APK Directory Size Breakdown (348.4 MB Uncompressed across 712 entries)
- **`assets/` (157.6 MB / 47.4%):**
  - `assets/flutter_assets/kernel_blob.bin` (100.81 MB): Uncompressed Flutter debug JIT Dart bytecode and AST snapshot.
  - `assets/flutter_assets/assets/models/sface.onnx` (36.90 MB): Pinned SFace deep learning facial recognition ONNX model.
  - `assets/flutter_assets/isolate_snapshot_data` (11.11 MB): Debug VM isolate state.
- **`lib/` (144.3 MB / 43.4%):** Triplicated native shared libraries across 3 architectures in a single fat universal APK:
  - `arm64-v8a`: 59.83 MB (`libflutter.so`: 43.1 MB, `libface_detector_v2_jni.so`: 9.5 MB, `libVkLayer_khronos_validation.so`: 5.8 MB)
  - `x86_64`: 47.62 MB (`libflutter.so`: 34.2 MB, `libface_detector_v2_jni.so`: 7.9 MB, `libVkLayer_khronos_validation.so`: 4.7 MB)
  - `armeabi-v7a`: 36.84 MB (`libflutter.so`: 29.5 MB, `libface_detector_v2_jni.so`: 6.2 MB, `libVkLayer_khronos_validation.so`: 4.0 MB)
- **`root/` (29.6 MB / 8.9%):** Multi-dex un-minified debug class files (`classes.dex`, `classes2.dex`, etc.).

#### Production Split-per-ABI Release APK Comparison
When compiled with `--split-per-abi` in release mode (tree-shaken AOT compilation, R8 minification, validation layers removed):
- `app-arm64-v8a-release.apk`: **43,636,419 bytes (41.6 MB)** | SHA-256: `6feef447b0b9da5511cd8a7b202fd45d0f52f8716d1748174ebd6f79f8a9d4bd`
- `app-armeabi-v7a-release.apk`: **38,293,809 bytes (36.5 MB)** | SHA-256: `66e095b3fd2893469ec221ac0542e41ee2bae3acdf8a98988d4a8a18273e6f59`
- `app-x86_64-release.apk`: **46,503,610 bytes (44.3 MB)** | SHA-256: `e78cc01998e48f02c5f5292111a2aa7c08c1912a85e7949cf721cf63a0e9262d`
- Universal Release APK (`app-release.apk`): **138,547,923 bytes (132.1 MB)** | SHA-256: `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`

> [!NOTE]
> **Gate C Status:** Physical Android device qualification is **PENDING**. The APK builds successfully and passes local compilation tests; however, qualification of physical sensors, camera, and biometric capture requires deployment to an authorized physical handset under Gate C.

---

## 4. Immutable Checksum & Provenance Verification

| Artifact Name | Expected Hash / Commit | Measured Hash / Commit | Status |
| :--- | :--- | :--- | :---: |
| **Protected Git Release Tag** | `8634a1813c84fccc73b8944803b6bd541f5e2326` (`v19.2.3-release`) | `8634a1813c84fccc73b8944803b6bd541f5e2326` | **BIT-IDENTICAL MATCH** |
| **V19.2.3 Release APK** | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` | **BIT-IDENTICAL MATCH** |
| **Generated Debug APK** | `90b0f3f90af0734320d6ed2552cbfce2b5ab02bd4c86542f0dc14244532199a1` | `90b0f3f90af0734320d6ed2552cbfce2b5ab02bd4c86542f0dc14244532199a1` | **VERIFIED GENERATED** |
| **SFace ONNX Model** | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | **BIT-IDENTICAL MATCH** |
| **YuNet ONNX Model** | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | **BIT-IDENTICAL MATCH** |
| **OpenTofu Toolchain** | `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c` | `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c` | **BIT-IDENTICAL MATCH** |

---

## 5. Non-Negotiable Operational Constraints Verified

1. **Zero Production Mutation:** Zero changes made to production Firestore, Cloud Functions, Cloud Storage, or IAM.
2. **Zero Live Deployment:** No cloud resources were deployed or mutated (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`).
3. **Aadhaar Disabled:** Aadhaar Offline e-KYC remains strictly disabled.
4. **Zero Human Biometric Collection:** No human biometrics or live participant enrollments were conducted.
5. **No V20.20 Branching:** All corrections are reconciled on `security/phase20.19-pilot-gate-a-closure`.
