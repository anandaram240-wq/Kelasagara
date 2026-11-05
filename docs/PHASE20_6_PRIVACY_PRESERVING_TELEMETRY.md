# PHASE 20.6 PRIVACY-PRESERVING TELEMETRY
## Telemetry Architecture: Decoupling Operational Security from Research Ground-Truth

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** DPDPA 2023 & ISO/IEC 19795-1:2021  
**Lead Architect:** Privacy and Security Architect & Senior TypeScript Engineer  
**Date:** 2026-10-31  

---

## 1. ARCHITECTURAL DECOUPLING: TELEMETRY VS GROUND TRUTH

A catastrophic error in production biometric systems is logging raw facial imagery or persistent vectors under the guise of "telemetry." 

Kelasagara enforces strict architectural separation between **Operational Security Telemetry** and **Research Ground-Truth Data**:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                   OPERATIONAL TELEMETRY vs RESEARCH GROUND-TRUTH                       │
├───────────────────────────────────┬────────────────────────────────────────────────────┤
│ Operational Security Telemetry    │ Research Ground-Truth Data                         │
├───────────────────────────────────┼────────────────────────────────────────────────────┤
│ • Production marketplace logins   │ • Consented voluntary research cohort              │
│ • Unknown true identity label     │ • 100% Verified ground-truth labels                │
│ • Aggregated similarity score bin │ • Exact raw comparison distance                    │
│ • Hardware attestation integrity  │ • Physical camera & lux sensor metadata            │
│ • ZERO RAW IMAGES COLLECTED       │ • Offline encrypted images (IRB approved only)     │
│ • ZERO EMBEDDINGS STORED          │ • Ephemeral evaluation memory only                 │
│ • Cannot be used to claim FMR     │ • Authorizes empirical FMR/FNMR statistical claim  │
└───────────────────────────────────┴────────────────────────────────────────────────────┘
```

---

## 2. PRIVACY-PRESERVING TELEMETRY PAYLOAD SCHEMA

When an authenticated worker undergoes biometric authentication in production, the telemetry payload transmitted to the monitoring queue contains **zero personal data and zero biometric vectors**:

```json
{
  "$schema": "https://kelasagara.org/schemas/telemetry/v20.6/biometric-metric.json",
  "telemetryEventId": "EVT-89f41a02-c118",
  "timestampUtc": "2026-10-31T23:50:00Z",
  "deviceAttestation": {
    "keymasterLevel": "KM_VERSION_TRUSTED_ENVIRONMENT",
    "verifiedBootState": "VERIFIED",
    "playIntegrityVerdict": "MEETS_DEVICE_INTEGRITY"
  },
  "operationalMetrics": {
    "latencyBreakdown": {
      "preprocessingMs": 31,
      "inferenceMs": 11,
      "kmsDecryptMs": 48,
      "signatureVerifyMs": 2
    },
    "similarityBin": "BIN_0.90_TO_1.00",
    "decisionOutcome": "AUTHENTICATION_ACCEPTED",
    "livenessSummary": {
      "earCompressionObserved": true,
      "lumaStepWithinTolerance": true,
      "textureEnergyPassed": true
    }
  },
  "privacySanitization": {
    "rawImageLogged": false,
    "embeddingVectorLogged": false,
    "userUidMasked": true,
    "geoCoordinatesLogged": false
  }
}
```

### Invariants Enforced:
1. **Similarity Binning:** The raw floating-point similarity score (e.g. `0.942817`) is coarsely binned into deciles (`BIN_0.90_TO_1.00`) to prevent template inversion attacks from telemetry logs.
2. **Zero Image Capture:** The camera frame buffer is zeroed out in RAM (`frameBuffer.fill(0)`) immediately following inference. No disk write is ever executed for routine logins.
3. **Zero Automated Account Suspension:** Low similarity scores or anomalous telemetry triggers step-up authentication (e.g. registered phone OTP or compliance officer review), **never** automated account deletion or punitive worker bans.
