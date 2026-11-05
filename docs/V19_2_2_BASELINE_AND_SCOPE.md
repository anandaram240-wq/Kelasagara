# KELASAGARA V19.2.2: BASELINE, INTEGRITY CHECKPOINT & SCOPE BOUNDARY

**Project:** Kelasagara Major Project  
**Current Release Baseline:** V19.2.1  
**Commit Baseline:** `94add175533a9e7c50e0406a1b2da2d13d76d86e` (`94add17`)  
**Branch:** `ui/polish-v1`  
**Checkpoint Tag:** `v19.2.1-checkpoint`  
**Baseline Release APK SHA-256:** `10b5f4772751f9c0e02c14f832a2c661e209e1e6d8b6029a9221fbacecb9450f`  
**Audit Timestamp:** 2026-10-31T15:02:30+05:30  
**Submission Deadline:** 3 November 2026  

---

## 1. REPOSITORY VERIFICATION

- **Absolute Workspace Directory:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`
- **Git Branch:** `ui/polish-v1`
- **HEAD Commit:** `94add17` (`fix(biometrics-v19.2.1): restore authoritative duplicate face detection, masked details modal, and zero-DNS mobile cellular connectivity`)
- **Recoverable Git Tag:** `v19.2.1-checkpoint` created at HEAD `94add17`.

---

## 2. IMMUTABLE FEATURE BOUNDARY (OUT OF SCOPE)

Under the strict university submission deadline of 3 November 2026, the following modules are declared strictly **OUT OF SCOPE** and frozen against modification:

| Module / Subsystem | Status | Scope Boundary Invariant |
|---|---|---|
| **Worker Dashboard** (`worker_dashboard.dart`, etc.) | FROZEN | Preserved without modification |
| **Hirer Dashboard** (`hirer_home_screen.dart`, etc.) | FROZEN | Preserved without modification |
| **Worker Authentication (OTP, SMS, Phone)** | FROZEN | Preserved; only biometric routing hooks touched |
| **Hirer Authentication** | FROZEN | Preserved without modification |
| **Job Posting & Discovery** (`work_detail_screen.dart`, etc.) | FROZEN | Preserved without modification |
| **Booking & Journey Lifecycle** (`journey_provider.dart`, etc.) | FROZEN | Preserved without modification |
| **Live GPS, Maps & OSM Tracking** (`geofence_dwell_engine.dart`, etc.) | FROZEN | Preserved without modification |
| **Payment Gateways & Financial State** | FROZEN | Preserved without modification |
| **Worker Profile Management** (`profile_screen.dart`, etc.) | FROZEN | Preserved without modification |
| **General App Navigation & Routing** (`routing_facade.dart`, etc.) | FROZEN | Preserved; only biometric entry/exit points |

---

## 3. IN-SCOPE BIOMETRIC FILES & DEPENDENCY MATRIX

The scope of Phase 18 is strictly limited to the authoritative biometric recognition pipeline, dual-space deduplication engine, TLS network security, and duplicate account recovery:

### Backend Architecture Files
1. `backend/src/routes/biometric_v10_routes.ts` — API endpoints for challenge, enrollment, 1:1 verification, and template administration.
2. `backend/src/services/biometric_lifecycle_coordinator_v10.ts` — Authoritative biometric lifecycle coordinator, CAS state machine, transaction handling.
3. `backend/src/services/firestore_compatible_gallery_index.ts` — 1:N biometric gallery search, model space partitioning, cosine matching.
4. `backend/src/biometrics/canonical_sface_engine_v10.ts` — Canonical OpenCV SFace ONNX neural embedding extractor, 112x112 input tensor normalization.

### Flutter Client Files
1. `lib/services/biometric_service.dart` — Thin client biometric proxy, network failure categorization, TLS validation.
2. `lib/screens/auth/face_enrollment_screen.dart` — Real-time camera stream, active blink kinematics, temporal burst payload, duplicate interception handling.
3. `lib/widgets/biometric_v10_dialogs_and_badges.dart` — Duplicate account detection dialog and recovery interface.

---

## 4. AUDIT & VERIFICATION GOALS

1. **Model Consistency & Alignment (Phase 3):** Validate BGR/RGB channels, 112×112 shape, 5-point alignment, and Umeyama transform.
2. **Dual-Space Deduplication Correction (Phase 4):** Eliminate mathematical `max(simSFace, simLandmark)` cross-distribution blending; maintain strictly isolated metric spaces with model-calibrated thresholds.
3. **Gallery Pagination & Failure Handling (Phase 5):** Complete Firestore pagination, partition templates by model version, fail-closed on gallery load failure.
4. **Similarity Calibration & ROC (Phase 6):** Independently calibrate SFace and Landmark thresholds; prevent cross-contamination.
5. **TLS Security Hardening (Phase 8):** Remove unconditional certificate bypass (`badCertificateCallback = true`); restore valid TLS and SNI verification for release builds.
6. **Privacy-Preserving Account Recovery (Phase 9):** Implement clean duplicate account recovery without exposing sensitive personal identifiers to unverified applicants.
7. **Demonstration & Build Certification (Phases 11–13):** Maintain 665/665 backend tests, full Flutter tests, and build signed `Kelasagara-v19.2.2-release.apk`.
