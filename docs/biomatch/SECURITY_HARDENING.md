# KELASAGARA BIOMATCH V7: SECURITY HARDENING & SECRETS MANAGEMENT SPECIFICATION

**Document ID:** `SPEC-SECURITY-BIOMATCH-001`  
**Phase:** Phase 12 (Security Hardening & Secrets Management)  
**As-of Date:** 2026-10-10  
**Current Branch:** `biomatch/v7-hardening`  
**Release Readiness Level:** **RRL-0 (Research Prototype)**  

---

## 1. Executive Summary & Purpose

This specification governs platform security hardening, cryptographic key hygiene, network isolation, and secrets lifecycle management for the Kelasagara BioMatch system across the Flutter client (`kelasagaara_v17`) and the standalone Node.js Tier 0 service (`backend/`).

### Core Security Mandates:
1. **Zero Persistent Cloud Secrets in Git:** Service account private keys (`*.json`, `*.pem`, `*.key`) MUST NEVER be committed to version control. Verified via automated `gitleaks` scanning.
2. **Strict Network & Origin Lockdown:** Browser cross-origin requests are limited strictly to whitelisted origins (`config.allowedOrigins`). Unauthorized origins receive HTTP 403 `CORS_FORBIDDEN`.
3. **Defense-in-Depth HTTP Headers:** Enforcement of HSTS (Strict-Transport-Security), Content-Security-Policy (`default-src 'none'`), `X-Content-Type-Options: nosniff`, and `X-Frame-Options: DENY` on all responses.
4. **Denial-of-Service & Resource Exhaustion Defense:** Request payload size capped at 5MB (`config.maxPayloadSize`) with HTTP 413 error handling, paired with an in-memory IP rate limiter (60 requests/minute).
5. **Fail-Closed Authentication:** Any request to sensitive biometric endpoints lacking a valid Firebase Bearer token is immediately rejected with HTTP 401 without parsing biometric probes.

---

## 2. Secrets Management & Key Lifecycle

### 2.1 Service Account Key Handling (ADR-006)
- **Production / Cloud Deployment:**
  - On Google Cloud Run or Firebase App Hosting, services utilize **Workload Identity** (Application Default Credentials). No static JSON private keys are stored on disk or injected via environment variables.
- **Local Developer & CI Workstations:**
  - Developers configure `GOOGLE_APPLICATION_CREDENTIALS` pointing to a local, untracked path outside the repository root (e.g. `~/.config/gcloud/...`).
  - `.gitignore` in both repository root and `backend/` strictly ignores:
    - `*service-account*.json`
    - `serviceAccountKey.json`
    - `*.pem`, `*.key`, `*.p12`, `*.jks`
    - `.env`, `*.env`

### 2.2 Key Rotation Protocol (90-Day Cadence)
1. **Generation:** Administrator generates a secondary service account key in Google Cloud Console / IAM.
2. **Staged Deployment:** The secondary key is deployed to developer workstations or secure secret vaults.
3. **Verification:** Live health and verification probes execute successfully under the new credential.
4. **Revocation:** The retired primary key is deleted in IAM within 24 hours of rotation.
5. **Audit Logging:** Rotation events are immutably logged into the SHA-256 tamper-evident audit ledger (`TamperEvidentAuditService`).

### 2.3 Compromise Incident Response Plan
In the event of an unauthorized credential exposure:
1. **Immediate Revocation:** The exposed service account key or Firebase token is revoked in Google Cloud IAM immediately ($\le 15\text{ minutes}$).
2. **Session Termination:** Active user sessions associated with the compromised credential are invalidated in Firebase Auth.
3. **Forensic Audit:** The tamper-evident audit chain (`biometric_audit_logs`) is inspected to detect unauthorized queries or template tampering during the exposure window.
4. **Post-Mortem & Disclosure:** A forensic report is generated pursuant to DPDPA 2023 notification requirements.

---

## 3. Network Hardening & HTTP Security Architecture

### 3.1 Security Headers Configuration
All responses emitted by the Tier 0 service include:
```http
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'none'; frame-ancestors 'none'
X-XSS-Protection: 0
Referrer-Policy: no-referrer
```

### 3.2 CORS Whitelist Policy
```typescript
const corsOptions: cors.CorsOptions = {
  origin: (origin, callback) => {
    // Mobile applications (Flutter native) and CLI tools send no Origin header
    if (!origin) return callback(null, true);
    if (config.allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error(`CORS origin '${origin}' is not permitted by BioMatch security policy.`));
  },
  methods: ["GET", "POST", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Dev-Uid"],
  credentials: true,
  maxAge: 86400,
};
```

### 3.3 Payload Capping & 413 Handling
- Payload parser: `express.json({ limit: "5mb" })`.
- Requests exceeding 5MB are intercepted before memory allocation and returned as:
```json
{
  "success": false,
  "status": "payload_too_large",
  "error": {
    "code": "PAYLOAD_TOO_LARGE",
    "message": "Request payload exceeds allowed limit of 5mb."
  },
  "serverTimestamp": "2026-10-10T03:50:00.000Z"
}
```

---

## 4. Verification Evidence & Test Automation

- **Automated Security Suite:** `backend/src/tests/security_hardening.test.ts` (5/5 tests passing).
- **Gitleaks Repository Audit:** Full git commit history scanned; zero private keys or production secrets committed.
- **Fail-Closed Gatekeeping:** Unauthenticated probe injection strictly returns HTTP 401.
