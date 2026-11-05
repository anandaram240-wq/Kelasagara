# KELASAGARA V20.3: LIFECYCLE INTEGRATION
## Biometric Engine Integration & Route-Level Guarding

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-07  
**Classification:** Core Security Engineering Specification

---

## 1. INTEGRATION ARCHITECTURE

In Phase 20.3, the device-bound trust engine is fully integrated into Kelasagara's biometric routes (`backend/src/routes/biometric_v10_routes.ts`) via Express middleware chaining:

```typescript
router.post(
  '/enroll',
  authenticateFirebaseToken,     // 1. Validates Firebase ID Token & extracts caller UID
  requirePlayIntegrity,          // 2. Decodes Google Play Integrity token & verifies app/device verdict
  requireDeviceSignature,        // 3. Verifies device key registration, ownership & ECDSA signature
  async (req, res) => {
    // 4. Executes Server-Side SFace ONNX Inference & V20.1 KMS Envelope Encrypted Persistence
  }
);
```

The exact same 3-factor protection chain is enforced on:
- `POST /api/biometrics/v10/enroll` (Initial Worker Facial Biometric Registration)
- `POST /api/biometrics/v10/verify-1to1` (1:1 eKYC Worker Authentication)
- `POST /api/biometrics/v10/replace` (Authorized Face Template Rotation & Replacement)

---

## 2. PRESERVATION OF EXISTING BIOMETRIC CONTROLS

The integration strictly preserves all existing biometric algorithms and thresholds:
1. **Face Recognition Model:** OpenCV Zoo SFace ONNX (`models/face_recognition_sface_2021dec.onnx`), producing unit-normalized 128-dimensional hyperspherical vectors ($S^{127}$).
2. **Face Detection:** YuNet face detector with 5-point landmark alignment.
3. **Quality & PAD Filters:** Stage 1 fast-fail presentation attack defense (screen replay moiré, photo glare, blur, underexposure, extreme pose).
4. **Biometric Decision Thresholds:**
   - 1:1 Authentication Genuine Floor: Cosine similarity $\ge 0.363$.
   - 1:N De-duplication Warning Threshold: Cosine similarity $\ge 0.74$.
   - 1:N De-duplication Hard Duplicate Floor: Cosine similarity $\ge 0.78$ / $0.90$.
5. **V20.1 Zero-Plaintext Vault:** Biometric templates encrypted with AES-256-GCM using Google Cloud KMS KEK and 8-field binary canonical AAD.

---

## 3. DUPLICATE RECOVERY PROTOCOL PRESERVATION

When 1:N de-duplication identifies a hard duplicate collision (e.g. `CASE-XXXX`), the worker is directed to the duplicate recovery workflow (`/replace` or `/redeem-receipt`).

### Security Hardening in V20.3:
In prior releases, an attacker who intercepted an unresolved duplicate case ticket might attempt to submit an unauthorized replacement from an untrusted device. In V20.3:
1. The replacement request requires valid Google Play Integrity attestation.
2. The replacement request requires cryptographic device signature from a registered hardware key.
3. The replacement request requires an authenticated Firebase session matching the verified worker.
4. Device substitution attacks during duplicate recovery are mathematically blocked.
