# KELASAGARA V14.0
## Presentation Attack Detection (PAD) & Capture Liveness Evidence Audit

**Audit Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Engineer & Application Security Specialist  
**Standard Framework:** ISO/IEC 30107-3:2023 (PAD Testing & Reporting)  
**Formal Evaluation Status:** **NOT VALIDATED AGAINST PHYSICAL PRESENTATION ATTACKS** (Software & Synthetic Harness Verified Only)  

---

## 1. End-to-End PAD Execution Trace

A forensic line-by-line trace was executed from mobile camera acquisition through the backend server decision:

```
[ UNTRUSTED MOBILE CLIENT (Flutter / Dart / Android) ]
  ├── 1. Camera2 Video Stream (30 FPS)
  ├── 2. ML Kit FaceDetector extracts 133 landmarks / contours
  ├── 3. Kinematic EAR tracking: evaluates eye opening (open ≥ 0.58, closed ≤ 0.28)
  ├── 4. Blink State Machine: requires 5 open frames then 2 closed frames
  ├── 5. 2D Laplacian Variance (σ²L) computed on client crop
  ├── 6. Single Best Frame selected and encoded as JPEG base64 (imageBase64)
  ├── 7. Client computes WADH = SHA-256(UID || Nonce || Digest || σ²L || BlinkVerdict || IPD)
  └── 8. HTTP POST /api/biometrics/enroll or /verify-1to1 { imageBase64, challengeNonce, requestHash }
                    │
                    ▼ TLS 1.3
[ TRUSTED BACKEND SERVER (Node.js / Express / Cloud Run) ]
  ├── 1. Authenticate Firebase ID Token
  ├── 2. checkForbiddenVectorFields: rejects any client-supplied vectors (Ticket T-01)
  ├── 3. Invalidate single-use challenge nonce (120s TTL)
  ├── 4. Verify requestHash matches client-reported parameters
  ├── 5. Decode single static image (decodeBase64Image)
  ├── 6. Extract SFace 128-d vector via ONNX Runtime
  └── 7. Execute 1:1 or 1:N cosine comparison against biometric_vault
```

---

## 2. Critical Architectural Findings

### 2.1 Single Static Frame Transmission
The mobile application transmits only a **single static image crop** (`imageBase64`) to the backend. The backend does **not** receive a multi-frame video sequence, raw camera frames, or an independent optical stream.

### 2.2 Client-Side Liveness Enforcement Boundary
The kinematic blink validation and 2D Laplacian texture variance are evaluated **exclusively on the client device**:
- If an attacker modifies the Flutter APK (or uses a dynamic instrumentation tool like Frida) or directly invokes the REST API, they can supply an arbitrary static photograph along with client metadata stating `blinkDetected = true` and `laplacianVariance = 250`.
- The WADH cryptographic request hash binds fields (`blinkDetected`, `laplacianVariance`, `ipdPixels`) that are *all self-reported by the client*. Because the server does not independently extract landmarks across a video stream or verify a hardware cryptographic attestation, a client-side blink check cannot be considered an independently enforced server-side defense.

### 2.3 Status of Hardware Device Attestation
In `face_enrollment_screen.dart`, `integrityToken` is passed as `'play_integrity_verified'`. While `DeviceAttestationService` in `backend/src/services/device_attestation.ts` has routines to parse Google Play Integrity tokens, live server-side token decryption against Google's Play Integrity API requires a configured Google Cloud service account with Play Integrity API enabled. In the current workspace, hardware-bound device attestation is operating with development mocks.

---

## 3. Forensic Audit of Claimed APCER / BPCER Figures

Previous reports cited Level 1 APCER figures (e.g. 0.00% or 3.64%) and BPCER figures (1.20% or 1.34%). 

### 3.1 Provenance of Test Data
Inspection of `backend/src/tests/attack_dry_run.test.ts` and `backend/src/evaluation/attack_evaluation_harness.ts` revealed:
```typescript
// backend/src/evaluation/attack_evaluation_harness.ts lines 50-59
const staticFrames = [
  { timestampMs: 1000, noseTip: { x: 50.0, y: 50.0 } },
  { timestampMs: 1500, noseTip: { x: 50.0, y: 50.0 } },
  { timestampMs: 2000, noseTip: { x: 50.0, y: 50.0 } },
];
const res = PresentationAttackDefenseService.verifyChallenge({
  challengeId: chal.challengeId,
  uid: `user_print_${i}`,
  frames: staticFrames,
});
```

### 3.2 Categorization of Test Reality
1. **Synthetic Software Invariants:** The attack dry run passes simulated JSON coordinate dictionaries into a TypeScript function. It verifies that *if* temporal variance is $< 0.5$px, the software flags `STATIC_2D_PHOTO`.
2. **Zero Physical Presentations:** No real-world physical attack presentations were conducted in physical space:
   - Zero physical color paper printouts placed before a mobile lens.
   - Zero smartphone/tablet screen video replays recorded under ambient lighting.
   - Zero 3D curved paper masks or latex/silicone appliances presented.
   - Zero live human subjects tested for bona fide presentation classification error rates under Karnataka outdoor sunlight.

---

## 4. Formal ISO/IEC 30107-3 Classification

| Attack Category | PAI Species | Test Method in Code | Measured Status | Conformance Finding |
| :--- | :--- | :--- | :---: | :--- |
| **Print Attack (Level 1)** | 2D Matte / Glossy Photo | Synthetic JSON Coordinate Jitter | 0.00% (Synthetic) | **NOT VALIDATED PHYSICALLY** |
| **Display Replay (Level 1)** | Video on AMOLED / IPS Display | Synthetic Coordinate Simulation | 0.00% (Synthetic) | **NOT VALIDATED PHYSICALLY** |
| **Cutout Eye Mask (Level 1)** | Photo with Eye Cutouts | Mock Gesture Variance | 0.00% (Synthetic) | **NOT VALIDATED PHYSICALLY** |
| **Silicone / Latex (Level 2)** | 3D Sculpted Mask | Not Tested | N/A | **OUT OF SCOPE / UNTESTED** |
| **Bona Fide Presentations** | Genuine Human Subjects | Synthetic Mock Frames | 1.20% (Synthetic) | **NOT VALIDATED IN FIELD** |

### Conclusion:
The existing liveness checks represent **client-side heuristic filters**, which are valuable for preventing accidental captures of still photos by benign users, but **must not be represented as an independently certified or physically validated ISO/IEC 30107-3 Level 1 anti-spoofing system**.
