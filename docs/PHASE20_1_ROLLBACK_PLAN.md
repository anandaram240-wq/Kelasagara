# KELASAGARA V20.1: ZERO-PLAINTEXT BIOMETRIC VAULT
## PHASE 20.1 TECHNICAL REPORT 7: EMERGENCY ROLLBACK & RECOVERY PLAN

**Author:** Principal Reliability Engineer & Release Auditor  
**Project:** Kelasagara Major Project  
**Phase:** 20.1 — Zero-Plaintext Biometric Vault  
**Protected Release Baseline:** V19.2.3 (`f210f95`, tag `v19.2.3-release`)  
**Status:** Certified & Ready for Deployment  

---

### 1. ROLLBACK POLICY & OBJECTIVE

This rollback plan specifies the deterministic procedure for reverting Phase 20.1 backend changes in the event of an unforeseen production incident (e.g., severe Cloud KMS regional outage, authentication degradation, or unexpected infrastructure failure).

The plan guarantees:
1. **Zero Data Loss:** No user biometric template or registration record is permanently lost.
2. **Preservation of the Baseline Release APK:** The production Android APK `Kelasagara-v19.2.3-release.apk` (SHA-256 `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`) remains 100% operational and requires **zero modification or rebuild**.
3. **Dual-Read Decoupling:** Reverting code does not break unmigrated records, and restoring backup data cleanly returns the vault to its pre-migration state.

---

### 2. ROLLBACK TRIGGERS & DECISION THRESHOLDS

A formal rollback of Phase 20.1 is triggered if any of the following conditions persist for > 10 minutes after deployment:

| Indicator | Threshold | Severity | Immediate Action |
| :--- | :--- | :--- | :--- |
| **KMS Availability** | Cloud KMS RPC error rate > 5% | P0 Critical | Trigger Stage 1 (Fail-closed alert) / Stage 2 Rollback |
| **1:1 Authentication Failure** | Genuine user login failure rate > 1.0% | P0 Critical | Initiate Backend Coordinator Rollback |
| **1:N Duplicate Leak** | Known duplicate enrolled without HTTP 409 | P0 Critical | Halt new enrollments immediately |
| **Firestore Transaction Contention** | Transaction retry count > 5 per minute | P1 High | Inspect latency and concurrency settings |

---

### 3. STEP-BY-STEP ROLLBACK PROCEDURE

#### Stage 1: Immediate Traffic Drain / Deployment Rollback
If the backend exhibits unexpected issues, switch traffic to the previous stable release candidate:

```bash
# 1. Navigate to repository root
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 2. Check out the protected release tag
git checkout v19.2.3-release

# 3. Build backend from baseline release
cd backend
npm run build

# 4. Restart backend daemon
pkill -f "dist/server.js" || true
nohup node dist/server.js > /dev/null 2>&1 &
```

#### Stage 2: Database Restoration (If Migration Has Run)
If the database migration script was executed prior to the rollback trigger, restore legacy plaintext arrays from the pre-migration backup collection:

```bash
# Execute vault restoration from backup collection
cd backend
npx ts-node -e "
import * as admin from 'firebase-admin';
admin.initializeApp();
const db = admin.firestore();

async function restoreVault() {
  const backupDocs = await db.collection('biometric_vault_backup_pre_v2').get();
  console.log('Restoring ' + backupDocs.size + ' records from backup...');
  for (const doc of backupDocs.docs) {
    const data = doc.data();
    await db.collection('biometric_vault').doc(doc.id).set(data);
  }
  console.log('Restoration completed successfully.');
}
restoreVault();
"
```

#### Stage 3: Verification of Baseline Functionality
1. Run backend verification suite:
   ```bash
   cd backend && npm test
   ```
2. Verify baseline release APK checksum:
   ```bash
   shasum -a 256 "/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk"
   # Must yield: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce
   ```
3. Test 1:1 and 1:N face verification endpoints using synthetic probes to verify normal operation.

---

### 4. POST-ROLLBACK AUDIT & INCIDENT ROOT CAUSE

Following any rollback execution:
1. Preserve all backend logs and Google Cloud KMS audit records for the incident window.
2. Verify that all user account statuses (`pending_face`, `approved`, `UNENROLLED`, `ACTIVE`) remain consistent in `/users`.
3. Conduct a post-mortem review before attempting any subsequent deployment.
