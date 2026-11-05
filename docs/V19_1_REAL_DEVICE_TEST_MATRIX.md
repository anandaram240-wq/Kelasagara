# KELASAGARA V19.1 — REAL-DEVICE VALIDATION MATRIX

**Execution Environment:** Production Android Handsets (Jio 4G/5G, Airtel 5G, Remote Wi-Fi, Office LAN)  
**Date:** October 31, 2026  
**Artifact Tested:** `Kelasagara-v19.1.0-release.apk`

---

## Test Execution Matrix

| Test ID | Network Condition | Scenario | Expected Outcome | Actual Result | Status |
|---|---|---|---|---|---|
| **NET-01** | Jio 4G (Cellular) | Fresh Worker initial face registration | Reaches public Cloudflare endpoint over HTTPS; extracts 128-D SFace embedding; passes 1:N deduplication; writes vault doc; returns HTTP 200 | HTTP 200 OK — Approved | **PASS** |
| **NET-02** | Airtel 5G (Cellular) | Duplicate face registration (existing user face scanned) | Intercepts 1:N match ($\ge 0.74$); returns HTTP 409 `FACE_ALREADY_LINKED` with masked details; Flutter UI renders `DuplicateAccountDetectedDialog` | HTTP 409 Conflict — Dialog displays masked phone, name, ID, rate, skill, similarity % | **PASS** |
| **NET-03** | Remote Wi-Fi (Home broadband) | Re-enroll Face ID on active user profile | Authenticated user passes `isReEnrollment: true`; updates SFace embedding in vault; preserves user account status | HTTP 200 OK — Updated successfully | **PASS** |
| **NET-04** | Office LAN Wi-Fi (`10.255.181.23`) | Seamless local failover | Resolves via public HTTPS or transparently fails over to LAN IP `10.255.181.23:5001` | HTTP 200 OK — Instant LAN low-latency response (< 250ms) | **PASS** |
| **NET-05** | Flight Mode / Offline | Network request initiated without connectivity | Fails closed; returns typed `offlineOrInterrupted` bilingual error; never self-approves | `ಬಯೋಮೆಟ್ರಿಕ್ ಸರ್ವರ್ ಸಂಪರ್ಕ ವಿಫಲವಾಗಿದೆ` banner displayed; fails closed | **PASS** |
| **NET-06** | Ephemeral Tunnel Drop | Primary tunnel unavailable | Client immediately retries next candidate endpoint in `kFallbackCandidateUrls` without crashing | Automatic candidate rollover | **PASS** |

---

## Security Verification Checklist

- [x] **Zero Victim PII Leakage in Plaintext**: All phones, names, and IDs masked per DPDP Act §8(3) before client delivery.
- [x] **Zero Raw Vectors in Client Payloads**: Handset transmits JPEG frame burst only; SFace feature extraction executed exclusively on the trusted backend.
- [x] **Zero Direct Firestore Enrollment**: `_directFirestoreEnroll()` permanently removed.
- [x] **Fail-Closed Gate**: On network failure, client returns retryable error; account status remains unapproved.
