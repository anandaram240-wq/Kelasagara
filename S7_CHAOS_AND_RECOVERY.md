# KELASAGARA BIOMATCH · STAGE S7 CHAOS DRILLS AND RECOVERY (S7_CHAOS_AND_RECOVERY.md)

**Classification:** Chaos Engineering, Fault Injection & Disaster Recovery  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Fault Injection Scenarios and Observed Resilience

| Chaos Drill Scenario | Injected Failure Mode | Expected Recovery Behavior | Observed Outcome | Exit Status |
| :--- | :--- | :--- | :--- | :---: |
| **Drill 1: Database Timeout** | Firestore client throws `ETIMEDOUT` during enrollment write | Transaction aborts cleanly; fails closed with HTTP 503; zero partial record written | Clean rollback; profile remains in `PENDING_FACE` | `PASS` |
| **Drill 2: SIGTERM during 1:N Update** | Worker process killed during in-memory index upsert | Process exits; subsequent startup rebuilds index from database in 1.25s | Bit-exact index restored; zero corrupted templates | `PASS` |
| **Drill 3: Corrupt Model Buffer** | Random bit flip injected into primary SFace ONNX weight buffer | Backend intercepts runtime fault; smoothly transitions to INT8 fallback model | Fallback inference completes; alert logged | `PASS` |
| **Drill 4: Stale Lease Deadlock** | Prior enrollment session killed without release | Lease TTL (60s) expires; subsequent request claims lock safely | Automated recovery; zero operator intervention | `PASS` |
| **Drill 5: Network Partition** | Cellular drop during multi-sample image burst upload | Incomplete burst rejected; prompt returns to client to retry frame 2 | Zero corrupted embeddings; session remains valid | `PASS` |

---

## 2. Emergency Kill Switch Drill (Part 10.4)

In the event of an operational anomaly or privacy incident, the system must support immediate, total disabling of biometric authentication.

### Kill Switch Architecture
- **Control Signal:** Global Firestore Remote Config flag: `biometrics_enabled = false`.
- **Propagation SLA:** Must disable biometric verification across all running instances in $< 60.0\text{ seconds}$.
- **Measured Disable Latency:** **$18.5\text{ seconds}$** (measured in `evidence/s7/kill_switch_results.json`).
- **Graceful Fallback:** When disabled, all biometric endpoints return HTTP 503 (`BIOMETRICS_OFFLINE`). The mobile client automatically hides camera prompts and routes 100% of workers to Document/OTP KYC without service disruption.

---

## 3. Exit Gate S7-G10 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifacts:**
- `evidence/s7/fault_injection_results.json`
- `evidence/s7/kill_switch_results.json`
