# KELASAGARA BIOMATCH V19.6.8: API RUNTIME CONTRACT & HEALTH SPECIFICATION
**Date:** 2026-10-24  
**Author:** Antigravity Senior Backend & Infrastructure Engineer  
**Baseline Commit:** `ff2814e`  
**Safety Status:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. Effective URL Hierarchy & Route Mount Contract

The client [`BiometricService`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart) and Express [`server.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/server.ts) maintain exact 1:1 route path alignment without prefix duplication:

| Operational Route | Method | Authentication | Client Construction | Server Handler |
|:---|:---:|:---:|:---|:---|
| **Root Health Probe** | `GET` | Public | `$_backendBaseUrl/health` | `backend/src/routes/face_routes.ts:127` |
| **Active Challenge Nonce** | `POST` | `Bearer <JWT>` | `$_backendBaseUrl/challenge` | `backend/src/routes/face_routes.ts:151` |
| **Biometric Vault Enrollment** | `POST` | `Bearer <JWT>` | `$_backendBaseUrl/enroll` | `backend/src/routes/face_routes.ts:221` |
| **1:1 Face Verification** | `POST` | `Bearer <JWT>` | `$_backendBaseUrl/verify-1to1` | `backend/src/routes/face_routes.ts:453` |
| **1:N Cross-Account Dedup** | `POST` | `Bearer <JWT>` | `$_backendBaseUrl/cross-account-check` | `backend/src/routes/face_routes.ts:707` |

---

## 2. URL Prefix Canonicalization & Anti-Duplication Proof

In [`BiometricService`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart):
```dart
static const String kProductionBackendUrl = 'https://api.kelasagara.com/api/biometrics';
```
When endpoints append `/enroll`, `/challenge`, or `/health`, the resulting strings are:
- `https://api.kelasagara.com/api/biometrics/enroll`
- `https://api.kelasagara.com/api/biometrics/challenge`
- `https://api.kelasagara.com/api/biometrics/health`

The test suite [`backend/src/tests/v19_6_8_api_runtime_contract.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_8_api_runtime_contract.test.ts) verified:
1. `enrollUrl.contains('/api/biometrics/api/biometrics') === false`.
2. Clean sanitization of trailing slashes via `replaceAll(RegExp(r'/+$'), '')`.
3. `GET /api/biometrics/health` returns status `200` with:
   ```json
   {
     "success": true,
     "status": "healthy",
     "data": {
       "service": "kelasagara-biomatch-backend",
       "modelVersion": "sface_opencv_zoo_v1_primary",
       "verificationThreshold": 0.363,
       "duplicateThreshold": 0.74,
       "hardBlockThreshold": 0.9,
       "isProductionCalibrated": false
     }
   }
   ```

---

## 3. Network Transport & Reachability Matrix

| Test Origin | Target Endpoint | Transport | Result | Diagnostic |
|:---|:---|:---:|:---:|:---|
| **Workstation Local** | `http://localhost:5001/api/biometrics/health` | Loopback HTTP | `HTTP 200 OK` | ✅ Responds in 2.1 ms |
| **Workstation LAN** | `http://10.255.181.23:5001/api/biometrics/health` | Local Wi-Fi | `HTTP 200 OK` | ✅ Responds in 3.4 ms |
| **Android via USB Cable** | `http://127.0.0.1:5001/api/biometrics/health` | `adb reverse tcp:5001 tcp:5001` | Supported | Localhost reverse tunnel |
| **Android via Cellular 5G** | `http://10.255.181.23:5001` | Cellular IP | Failed | ❌ Non-routable private IP |
| **Public Internet** | `https://api.kelasagara.com/api/biometrics` | Public DNS | Failed | ❌ Unmapped hostname (curl error 6) |

---

## 4. Workstation vs. Device Development Runbook

When developing or verifying on a physical Android handset:

1. **Option A: USB Reverse Tunnel (Most Reliable):**
   ```bash
   adb reverse tcp:5001 tcp:5001
   ```
   In the mobile app, tap the `<···>` button on the face screen and select **Localhost (5001)** (`http://localhost:5001/api/biometrics`).

2. **Option B: Local Wi-Fi LAN:**
   Ensure both Mac and phone are connected to the same Wi-Fi router. Select **Mac LAN (10.255.181.23)**.

3. **Option C: Production Cloud Deployment:**
   Deploy the backend to Cloud Run or Firebase App Hosting with configured public DNS `api.kelasagara.com` and valid TLS certificate. Select **Cloud HTTPS**.
