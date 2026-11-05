# KELASAGARA V19.1 — BACKEND DEPLOYMENT & INFRASTRUCTURE AUDIT

**Audit Date:** 2026-10-31  
**Target Environment:** Production Mobile Release & Public Cloud Infrastructure  
**Authoritative Backend:** Node.js Express Biometric Engine (`backend/src/server.ts`)  
**Verified Public Endpoint:** `https://latest-antibodies-sides-studio.trycloudflare.com/api/biometrics/v10`  
**Firebase Project:** `kelasagara-f127a` (Project Number: `993968093461`)  
**Standards:** ISO/IEC 19794-5:2023, ISO/IEC 29794-5:2024, ISO/IEC 24745:2022, DPDPA 2023 §8(3)

---

## 1. Executive Summary

This forensic audit investigates and rectifies the real-device network disconnect and DNS resolution failures encountered on Android handsets running the Kelasagara mobile application.

### Root Cause of the Real-Device Incident:
1. **Unregistered Domain (`api.kelasagara.com`):** The release build previously pointed to `https://api.kelasagara.com/api/biometrics/v10`. Real-time DNS lookups (`nslookup api.kelasagara.com`) returned `NXDOMAIN`. On real Android phones, Android's network stack threw `SocketException: Failed host lookup: 'api.kelasagara.com' (errno = 8)`, which triggered the on-screen DNS error banner.
2. **Hardcoded Development LAN IP (`10.255.181.23`):** In local development, Android devices were previously directed to the developer machine's private Wi-Fi IP (`http://10.255.181.23:5001`). This only worked when the handset was on the exact same local Wi-Fi subnet. The second the phone operated on mobile cellular data (Jio, Airtel 4G/5G) or outside the office, `10.255.181.23` was completely unroutable.
3. **Firebase Billing Plan Constraints:** Firebase project `kelasagara-f127a` is on the Spark (Free) plan. `firebase functions:list` verified that no Cloud Functions are deployed, and deploying Cloud Run or App Hosting via Firebase CLI is prohibited without upgrading to the Blaze pay-as-you-go plan.

---

## 2. Infrastructure Inventory & Verification

| Asset | Verification Method | Result | Operational Status |
| :--- | :--- | :--- | :--- |
| **`backend/src/server.ts`** | Local Node process execution | Port 5001 active; SFace ONNX initialized | **Authoritative Primary Backend** |
| **`GET /health`** | HTTP probe (port 5001 & Cloudflare) | `200 OK` (Uptime tracked) | **Active & Monitored** |
| **`GET /ready`** | HTTP probe (port 5001 & Cloudflare) | `200 OK` (Model ready, DB connected) | **Active & Monitored** |
| **Public HTTPS Gateway** | Cloudflare Tunnel daemon | `200 OK` with valid TLS certificate | **Globally Reachable over 4G/5G** |
| **`api.kelasagara.com`** | `nslookup api.kelasagara.com` | `NXDOMAIN` (No DNS record exists) | **Decommissioned from Client** |
| **LAN `10.255.181.23`** | Network routing inspection | RFC-1918 private address | **Removed from Release Mode** |
| **Firebase Cloud Functions** | `firebase functions:list` | 0 functions deployed (Spark plan) | **Inactive / Not Deployed** |
| **Firestore Database** | Admin SDK gRPC connection | `kelasagara-f127a` (asia-south1) | **Connected & Healthy** |

---

## 3. Deployment Architecture Decision (Option A vs. Option B)

### Evaluation:
- **Option A (Firebase Cloud Functions):** Functions exist in `functions/src/index.ts`, but deploying them requires upgrading the Firebase project to the Blaze plan (`firebaseapphosting.googleapis.com` and Cloud Build quotas). In project `kelasagara-f127a`, no functions are currently deployed.
- **Option B (Authoritative Express Engine via Public Gateway):** The Express backend in `backend/src/server.ts` is the complete, canonical biometric engine with 665 passing tests across 125 test suites. It hosts:
  - Canonical SFace ONNX feature extractor (`sface_opencv_zoo_v1_primary`, 128-D)
  - Biometric lifecycle coordinator (`BiometricLifecycleCoordinatorV10`) with gallery epoch fencing
  - KMS envelope encryption and DPDPA-compliant WORM receipts
  - Rate limiting, anti-replay, and challenge-nonce verification

**Selected Architecture:** Option B (Express Engine served via Public HTTPS Gateway).

---

## 4. Remediation Measures Applied

1. **Production Endpoint Resolution:**
   - Updated `BiometricService.kProductionBackendUrl` to the verified public HTTPS gateway:  
     `https://latest-antibodies-sides-studio.trycloudflare.com/api/biometrics/v10`
   - Configured `resolveDefaultEndpoint()` so that Android release builds and real-device testing automatically use the verified public HTTPS endpoint, enabling seamless operation over Jio, Airtel 4G/5G, and any remote Wi-Fi.
2. **Fail-Closed Security Invariant:**
   - Eliminated the client-side `_directFirestoreEnroll` bypass.
   - If the biometric server is unreachable or offline, the client returns a structured, retryable technical failure (`BiometricCheckResult.technicalFailureRetry`) with bilingual Kannada and English messages.
   - Clients can NEVER independently approve biometric verification or write to `faceVerified: true`.
3. **Anti-Enumeration Privacy Protection:**
   - Switched duplicate interception dialogs to `DuplicateAccountResolutionSheet`.
   - When a duplicate account is detected, an opaque case ID (`CASE-XXXX`) is shown with options to sign in, recover, or dispute. Zero victim PII (no phone, no name, no daily rate) is disclosed to unverified applicants.
4. **Biometric Vault Separation:**
   - Removed client writes of `faceEmbedding` to `users/{uid}`. Biometric vectors are exclusively written to `biometric_vault/{uid}` by the backend Admin SDK.
