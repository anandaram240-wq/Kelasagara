# Biometric API Specification & Data Architecture Contract
## Endpoints, Request/Response Schemas, Error Handling, and Zero-PII Privacy Envelopes

**Platform:** Kelasagara Biometric Engine V5.0  
**Transport:** HTTPS / TLS 1.3 (Production)  
**Standard:** DPDPA 2023 §8(3), ISO/IEC 24745:2022  
**Last Updated:** 2026-10-22  

---

## 1. Architectural Principles & Transport Security

1. **Server-Authoritative Matching:** The client never downloads competitor biometric templates. All 1:N search operations execute inside backend server memory (`InMemoryBiometricIndex`).
2. **Dynamic Challenge Nonce (WADH):** Every state-changing request must include a single-use server nonce bound to the caller's Firebase Auth UID.
3. **Zero-PII Disclosure:** Duplicate detection responses strictly return blinded audit tokens and masked support identifiers.
4. **Endpoint Resolution:** Mobile devices automatically resolve production HTTPS endpoints via `resolveDefaultEndpoint()`, preventing connection failures to `http://10.0.2.2:5001`.

---

## 2. API Endpoints

### 2.1 Request Cryptographic Challenge Nonce
**`POST /api/biometrics/challenge`**
- **Authentication:** Bearer Token (Firebase Auth JWT).
- **Request Body:**
  ```json
  {
    "action": "enroll" | "verify"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "challenge_issued",
    "data": {
      "nonce": "chal_0b060dd3e20e8b2f90a1",
      "expiresAt": 1792683000000,
      "ttlMs": 120000
    },
    "serverTimestamp": "2026-10-22T14:30:00.000Z"
  }
  ```

---

### 2.2 Server-Authoritative 1:N Biometric Enrolment
**`POST /api/biometrics/enroll`**
- **Authentication:** Bearer Token (Firebase Auth JWT).
- **Request Body:**
  ```json
  {
    "nonce": "chal_0b060dd3e20e8b2f90a1",
    "requestHash": "sha256_hash_of_nonce_and_pad_telemetry",
    "imageBase64": "data:image/jpeg;base64,...",
    "laplacianVariance": 342.5,
    "ipdPixels": 114.2,
    "blinkDetected": true
  }
  ```
- **Response: Unique Enrolment Approved (200 OK):**
  ```json
  {
    "success": true,
    "status": "approved",
    "data": {
      "isApproved": true,
      "isDuplicate": false,
      "modelVersion": "sface_opencv_zoo_v1_primary",
      "enrolledAt": "2026-10-22T14:30:02.120Z"
    },
    "serverTimestamp": "2026-10-22T14:30:02.125Z"
  }
  ```
- **Response: Duplicate Intercepted (200 OK - Zero PII Contract):**
  ```json
  {
    "success": true,
    "status": "duplicate_found",
    "data": {
      "isApproved": false,
      "isDuplicate": true,
      "isHardBlock": true,
      "similarityPercent": 88,
      "ticketId": "BIODUP-20261022-9F8A2",
      "maskedUserId": "KLS-xK9***wXy",
      "message": "Biometric duplicate detected. If you already have an account, please log in using your registered mobile number or contact support."
    },
    "serverTimestamp": "2026-10-22T14:30:02.125Z"
  }
  ```
  *(Notice: Zero phone number, zero user full name, zero raw competitor UID exposed per DPDPA §8(3)).*

---

### 2.3 1:1 Biometric Verification (Clock-in / Login)
**`POST /api/biometrics/verify`**
- **Authentication:** Bearer Token (Firebase Auth JWT).
- **Request Body:**
  ```json
  {
    "nonce": "chal_3f89a1c0d4e5",
    "imageBase64": "data:image/jpeg;base64,...",
    "laplacianVariance": 412.0,
    "ipdPixels": 108.5
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "verified",
    "data": {
      "isVerified": true,
      "similarityScore": 0.892,
      "threshold": 0.74,
      "auditRef": "AUTH-20261022-771B"
    },
    "serverTimestamp": "2026-10-22T14:31:00.000Z"
  }
  ```

---

### 2.4 Cross-Account 1:N Fraud Audit
**`POST /api/biometrics/cross-account-check`**
- Verifies that a logged-in user's face does not match any *other* registered user's template in the system.
- Returns `isHardBlock: true` if similarity exceeds $0.90$.

---

### 2.5 Database & Search Readiness Probe
**`GET /api/biometrics/db-readiness`**
- **Authentication:** Bearer Token.
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "db_ready",
    "data": {
      "firestoreLatencyMs": 42,
      "enrolledTemplates": 1250,
      "ramIndexSize": 1250,
      "isRamIndexWarm": true,
      "modelVersion": "sface_opencv_zoo_v1_primary",
      "systemAvailability": {
        "firestoreOk": true,
        "ramIndexOk": true,
        "deduplicationReady": true
      }
    },
    "serverTimestamp": "2026-10-22T14:32:00.000Z"
  }
  ```

---

### 2.6 DPDPA Section 12 Right-to-Erasure
**`DELETE /api/biometrics/vault/:uid`**
- Authenticated user can delete their own biometric template.
- Administrators can delete templates on verified dispute resolution.
- Cross-user unauthorized deletion attempts return `403 FORBIDDEN`.

---

## 3. Firestore Data Schema (`biometric_vault/{userId}`)

```json
{
  "userId": "firebase_auth_uid_string",
  "embedding": [0.012, -0.045, 0.088, "... (128 floats on S^127)"],
  "modelVersion": "kelasagara_biomatch_v2_whitened",
  "geometryModel": "dense_facial_marker_engine_v1",
  "markerCount": 513,
  "enrolledAt": "2026-10-22T14:30:02.120Z",
  "lastVerifiedAt": "2026-10-22T14:31:00.000Z",
  "qualityScore": 0.94,
  "encryptedEnvelope": {
    "version": "v3_kms_gcm",
    "ciphertext": "base64_encoded_encrypted_vector",
    "iv": "base64_encoded_12_byte_iv",
    "authTag": "base64_encoded_16_byte_gcm_tag",
    "wrappedDek": "base64_encoded_kms_wrapped_data_key",
    "keyId": "projects/kelasagara/locations/asia-south1/keyRings/biometrics/cryptoKeys/vault-kek"
  }
}
```
