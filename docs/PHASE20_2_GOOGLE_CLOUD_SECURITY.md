# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 7: GOOGLE CLOUD IAM & CREDENTIAL SECURITY SPECIFICATION

**Author:** Firebase Security Architect & Principal Cloud Infrastructure Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**GCP Project:** `kelasagara-f127a` (Project Number: `993968093461`)  
**Status:** Certified Cloud Security Architecture  

---

### 1. CREDENTIAL ISOLATION & LEAST PRIVILEGE

Under Kelasagara's security architecture, Google Cloud service account credentials are strictly isolated to the server runtime:

```
+----------------------------------------------------------------------------------------------------+
|                                    CREDENTIAL ISOLATION BOUNDARY                                   |
+----------------------------------------------------------------------------------------------------+
|  CLIENT DEVICE (ANDROID / FLUTTER):                                                                |
|  - Contains ZERO Google Cloud service account JSON keys.                                           |
|  - Contains ZERO Google Play Developer API private keys.                                           |
|  - Communicates with Google Play Services daemon exclusively through on-device IPC.                |
|  - Receives only opaque integrity token string.                                                    |
|                                                                                                    |
|  BACKEND SERVER (NODE.JS / EXPRESS):                                                               |
|  - Dedicated Service Account: kelasagara-biometrics@kelasagara-f127a.iam.gserviceaccount.com       |
|  - IAM Role Scopes:                                                                                |
|    * roles/playintegrity.viewer (or Play Integrity API Service Agent)                              |
|    * roles/cloudkms.cryptoKeyEncrypterDecrypter (strictly on biometric-vault-kek-v1)               |
|    * roles/datastore.user (strictly on firestore /biometric_vault)                                 |
|  - Denied all project administrative, owner, and key deletion roles.                               |
+----------------------------------------------------------------------------------------------------+
```

---

### 2. DATA HYGIENE & LOG SANITIZATION

Google Play Integrity tokens and verdicts contain operational telemetry that must be handled with strict data hygiene:

1. **Token Redaction:**
   - Raw integrity tokens (`X-Play-Integrity-Token`) are redacted from HTTP access logs, Winston/Morgan formatters, and Google Cloud Run logging.
   - Headers are sanitized using standard redaction masks: `[REDACTED_PLAY_INTEGRITY_TOKEN]`.
2. **Minimal Verdict Telemetry:**
   - The backend stores only non-reversible categorical summaries:
     ```json
     {
       "transactionId": "txn_1793460000_a1b2",
       "timestamp": "2026-10-31T16:20:00.000Z",
       "appVerdict": "PLAY_RECOGNIZED",
       "deviceVerdict": ["MEETS_DEVICE_INTEGRITY"],
       "policyOutcome": "INTEGRITY_ACCEPTED"
     }
     ```
   - Zero raw facial images, zero biometric vectors, and zero full token JWE payloads are stored in the telemetry collection.
