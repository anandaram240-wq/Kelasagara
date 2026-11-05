# KELASAGARA V19.1 — CLOUD INFRASTRUCTURE & SECURITY SPECIFICATION

**Authoritative Backend:** Node.js Express Biometric Engine (`backend/src/server.ts`)  
**Containerization:** Dockerfile configured with multi-stage build, ONNX runtime dependencies, and Node 20+  
**Security Model:** Zero-Trust Client, Server-Authoritative Inference, Private Vault Isolation  
**Public Ingress:** Automated TLS/SSL Endpoint Termination  
**Database:** Cloud Firestore (`kelasagara-f127a` / `asia-south1`)  
**Cryptographic Envelope:** AES-256-GCM with length-prefixed canonical AAD

---

## 1. Cloud Architecture Overview

Kelasagara's biometric verification subsystem implements a strict **split-plane security model**:

1. **Client Plane (Android Mobile Application):**
   - Runs on unconstrained client hardware (Android 11–15, ARM64).
   - Responsible strictly for raw camera frame acquisition, ISO/IEC 29794-5 optical quality pre-checks, screen-fill illumination, and eyelid blink detection.
   - **Zero Biometric Authority:** Mobile client vectors and local similarity estimates are never accepted as proof of identity.
   - Communicates exclusively over HTTPS with verified TLS certificates.

2. **Ingress Plane (Public HTTPS Gateway):**
   - Public gateway terminating inbound connections with DDoS mitigation and TLS 1.3 encryption.
   - Forwards traffic to the Express core listening on local port 5001.

3. **Core Biometric Engine (Express Node.js):**
   - Pre-loads primary ONNX model (`sface_opencv_zoo_v1_primary`, 128-D) to eliminate cold starts.
   - Enforces Firebase ID token authentication on all non-health routes.
   - Rejects any client-submitted vectors with `CLIENT_VECTOR_REJECTED` (Ticket T-01).
   - Authoritatively extracts SFace vectors directly from raw image bytes.
   - Manages 1:N deduplication, gallery epoch fencing, and atomic CAS commits.

4. **Data Isolation Plane (Firestore Vault):**
   - `users/{uid}`: Contains public profile data, worker skills, and public account status. **Strictly zero biometric vectors.**
   - `biometric_vault/{enrollmentId}`: Encrypted 128-D vectors, salt, KMS key version, model metadata. Protected by Firestore security rules `allow read, write: if false;` — **accessible only by backend Admin SDK**.
   - `biometric_challenges/{challengeId}`: Single-use, 60-second cryptographic nonces.
   - `biometric_duplicate_cases/{caseId}`: Full forensic incident log for administrative and compliance review.

---

## 2. Docker & Container Deployment Specification

For deployment to Google Cloud Run, AWS ECS, or any containerized Kubernetes environment, the backend includes the following production container configuration:

```dockerfile
# Multi-stage Docker build for Kelasagara Biometric Engine
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src/ ./src/
RUN npm run build

FROM node:20-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=5001
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY models/ ./models/

EXPOSE 5001
USER node
CMD ["node", "dist/server.js"]
```

### Resource Requirements on Cloud Run:
- **CPU:** 2 vCPU (for optimized multi-threaded ONNX SIMD execution)
- **Memory:** 1 GiB (sufficient for SFace ONNX working buffer and 500-candidate gallery cache)
- **Concurrency:** 80 requests per instance
- **Min Instances:** 1 (to eliminate ONNX model warm-up cold starts)
- **Max Instances:** 10

---

## 3. Secret Management & Credential Governance

Per Section 3 of MISSION V19.1:
1. **No Embedded Service Account Keys:** The Flutter APK contains zero service account JSON files, zero private keys, and zero database passwords.
2. **Client Authentication:** Flutter clients authenticate exclusively via ephemeral Firebase Auth JWT tokens signed by Google identity services.
3. **Server Credentials:** In Google Cloud Run, the backend inherits IAM roles via the default compute service account (`roles/datastore.user`, `roles/cloudkms.cryptoKeyEncrypterDecrypter`).
4. **Environment Isolation:** Dev bypass flags (`ALLOW_DEV_TOKEN`) are strictly prohibited and hard-disabled in `NODE_ENV=production` by `validateAuthenticationGovernance()`.
