# KELASAGARA BIOMATCH: SHADOW-MODE ROLLOUT & OPERATIONAL TELEMETRY PLAN (TICKET H-02)
**Document Version:** 1.0.0  
**Date:** 10 October 2026  
**System:** Kelasagara Sovereign Biometric Stack (`kelasagaara_v17`)  
**Deployment Target:** Production Mobile App & Cloud Run / Spark Infrastructure  
**Compliance:** Invariant I-01 (Fail-Closed), I-04, I-05, DPDP Act 2023

---

## 1. Executive Summary & Phased Staging

To eliminate deployment risk and verify model behavior on live, diverse smartphone models across Karnataka without impacting daily wage workers, Kelasagara enforces a strict **Shadow-Mode Rollout Framework**:

```
[Phase 0: Staging CI] -> [Phase 1: 100% Shadow Mode] -> [Phase 2: 10% Canary] -> [Phase 3: 100% Production Active]
  (Zero User Impact)       (Background Verification)     (Gradual User Payout)      (Fully Supervised)
```

During Phase 1 (Shadow Mode), the incoming verification probe is processed by the incumbent production pipeline to render the active user decision. Simultaneously, the candidate model runs in a decoupled background worker thread. Decision agreement, latency, and quality distributions are recorded without altering user authentication status.

---

## 2. Privacy-Safe Telemetry Architecture

Under DPDPA 2023 and Invariant I-04, **telemetry payloads must NEVER contain raw face images, reconstructed landmarks, biometric embeddings, or continuous distance vectors**.

### Allowed Aggregate Metrics Schema:
1. **Binned Similarity Score Histograms:**
   - 20 uniform bins: `[0.00..0.05)`, `[0.05..0.10)`, ..., `[0.95..1.00]`.
   - Emits integer bucket counts only.
2. **Failure-to-Acquire (FTA) Rates:**
   - Aggregated by `device_model` (e.g. `Redmi_9A`, `Samsung_M12`), `os_version`, and `app_version`.
3. **Session Friction Rates:**
   - First-attempt pass rate: Target $\ge 94.0\%$.
   - Multi-attempt retry rate: Target $\le 5.0\%$.
   - Step-Up escalation rate (routing to OTP / document KYC): Target $\le 2.0\%$.
4. **Hardware Performance:**
   - Mobile capture duration, wire transmission latency, server-side inference p50/p95/p99.

---

## 3. Automated Drift Alarms & Anomaly Detection

Real-time telemetry streams into our Prometheus/Grafana and Cloud Logging monitors. Automated alerting triggers if any of the following boundaries are breached over a 1-hour rolling window:

| Alarm Identifier | Severity | Detection Condition | Automated System Action |
| :--- | :--- | :--- | :--- |
| **`ALARM_SCORE_DISTRIBUTION_DRIFT`** | P1 | Median genuine score shifts by $> \pm 0.04$ relative to TUNE baseline. | Notify On-Call Engineer; freeze candidate promotion. |
| **`ALARM_DEVICE_SPECIFIC_FTA_SPIKE`**| P1 | FTA $> 6.0\%$ on any specific device model with $N \ge 50$ attempts. | Enable client-side fill-light prompt for that model. |
| **`ALARM_EXCESSIVE_STEP_UP`** | P2 | Step-Up escalation rate exceeds $> 8.0\%$ across all transactions. | Investigate lighting or server camera codec quality. |
| **`ALARM_LATENCY_DEGRADATION`** | P1 | Server p95 inference latency $> 45.0$ ms. | Scale CPU allocation or route non-critical load to INT8. |

---

## 4. Rollback Criteria & Emergency Abort Procedure

If any of the following critical safety boundaries are violated during shadow or canary rollout, automated rollback is executed immediately:

### Rollback Triggers:
1. **Decision Discordance:** Shadow candidate produces false rejections on $> 1.5\%$ of transactions that the incumbent baseline passed.
2. **Crash / OOM Error:** Unhandled exception rate $> 0.05\%$ in inference worker thread.
3. **Liveness Evasion Anomaly:** A presentation or injection attack detected in post-hoc audit chain that passed candidate matching.
4. **Memory Leak:** Server resident memory exceeds 380 MB on Cloud Run instance.

### Automated Rollback Execution (Time-to-Execute: $< 30$ seconds):
```bash
# 1. Flip dynamic runtime feature flag via Admin Configuration
curl -X POST https://api.kelasagara.in/v1/admin/biometrics/flags \
  -H "Authorization: Bearer $SECURE_ADMIN_KEY" \
  -d '{"enableShadowMode": false, "activeModel": "sface_opencv_zoo_v1_primary"}'

# 2. Verify fallback routing in audit log
node dist/scripts/verify_rollback_status.js
```
The rollback does not require node restart, container redeployment, or database migration.
