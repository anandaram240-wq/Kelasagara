# KELASAGARA BIOMETRIC ENGINE V10.0
# Biometric Migration Strategy, Versioning & Safe Rollback Runbook
## Multi-Version Template Compatibility, Dual-Read Lifecycle, and Disaster Recovery Procedures

**Document ID:** `REP-MIGRATION-V10-01`  
**System:** Kelasagara Biometric Platform  
**Target Architecture:** Multi-Version Hyperspherical Vector Schema  
**Status:** Approved Operational Runbook  
**Version:** 10.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Model Versioning Architecture & Precedence

To eliminate data corruption and prevent service disruption during algorithm upgrades, the biometric system strictly enforces model versioning:

```
+----------------------------------------------------------------------------------------------------+
|                                    SUPPORTED BIOMETRIC MODEL VERSIONS                              |
+--------------------------+-------------------+--------------------+--------------------------------+
|  Model Version Tag       | Representation    | Dimension          | Status                         |
+--------------------------+-------------------+--------------------+--------------------------------+
|  v4_whitened_procrustes  | Linear Orthogonal | 128-d (FP32)       | ACTIVE (Primary Production)    |
|  v3_whitened             | Linear Gaussian   | 128-d (FP32)       | SUPPORTED (Backward-compatible)|
|  v2_whitened             | RFF (Transitional)| 128-d (FP32)       | DEPRECATED (Auto-migrated)     |
|  null (Legacy)           | Unnormalized Mesh | Variable           | SUNSET (Re-enrollment forced)  |
+--------------------------+-------------------+--------------------+--------------------------------+
```

---

## 2. Zero-Downtime Migration Strategy: Lazy Re-Embedding

Migrating millions of biometric templates cannot be executed via batch database rewrites because the raw facial images do not exist on disk (strict DPDPA data minimization).

Kelasagara executes a **Lazy On-Authentication Migration Strategy**:
1. **Dual-Read Inspection:** When a user logs in, `BiometricService` inspects the `modelVersion` tag in `biometric_vault/{uid}`.
2. **Direct Authentication:** If `modelVersion == "v4_whitened_procrustes"`, standard 1:1 verification executes.
3. **Automatic Upgrade on Verification:** If `modelVersion` is legacy or deprecated (`v2_whitened` or `null`), the system validates identity using the legacy compatibility comparator. Upon successful verification, the client generates a fresh `v4_whitened_procrustes` embedding from the live bona fide capture and seamlessly overwrites the vault document.
4. **Zero Forced Mass Logouts:** Users upgrade naturally during routine attendance verification with zero disruption.

---

## 3. Safe Rollback Runbook

If an unpredicted operational anomaly occurs in production, operators follow this standardized runbook:

### 3.1 Instant Client-Side Fallback via Remote Config
- **Trigger:** Anomaly detection alert indicates false rejection spike ($>5\%$) on specific phone models.
- **Action:** Update Firebase Remote Config flag:
  ```json
  {
    "biometric_primary_model": "v3_whitened",
    "biometric_dedup_threshold": 0.72
  }
  ```
- **Time to Effect:** $<60	ext{ seconds}$ globally without requiring an app store release.

### 3.2 Backend SFace Matcher Fallback
- **Trigger:** SFace ONNX engine experiences native binary runtime failure on Cloud Run.
- **Action:** The backend configuration automatically activates the pure TypeScript geometric comparator fallback, logging an incident to Google Cloud Error Reporting.

### 3.3 Database State Integrity Recovery
- Cloud Firestore retains **Point-in-Time Recovery (PITR)** up to 7 days.
- In the event of catastrophic accidental template deletion, execute:
  ```bash
  gcloud firestore databases restore \
    --source-database='(default)' \
    --destination-database='recovery-db' \
    --restore-time='2026-10-22T14:00:00Z'
  ```
