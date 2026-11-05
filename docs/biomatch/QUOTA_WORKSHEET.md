# KELASAGARA BIOMATCH V7: QUOTA & CAPACITY WORKSHEET

**Document ID:** `QW-BIOMATCH-V7-001`  
**Phase:** Phase 2 (Requirements, Threat Model, SLOs, Tiers, Quota Math)  
**As-of Date:** 2026-10-10  
**Target Environment:** Firebase Spark Plan (Free Tier)  
**Primary Constraints:**
- No Blaze billing upgrade.
- Cloud Firestore as the sole persistent database.
- Standalone Node.js backend authority (Tier 0 / local host / shadow).

---

## 1. PRIMARY QUOTA REFERENCE BASELINE

All quota allowances and consumption models are verified against primary Google Cloud and Firebase documentation as of 2026-10-10.

| Resource / API | Free Spark Plan Limit | Unit of Measurement | Primary Source Reference | Access Date |
|---|---|---|---|---|
| **Cloud Firestore Document Reads** | **50,000** | Document reads / day | `firebase.google.com/docs/firestore/pricing` | 2026-10-10 |
| **Cloud Firestore Document Writes** | **20,000** | Document writes / day | `firebase.google.com/docs/firestore/pricing` | 2026-10-10 |
| **Cloud Firestore Document Deletes** | **20,000** | Document deletes / day | `firebase.google.com/docs/firestore/pricing` | 2026-10-10 |
| **Cloud Firestore Stored Data** | **1.0 GiB** | Total collection data | `firebase.google.com/docs/firestore/quotas` | 2026-10-10 |
| **Firebase App Check / Play Integrity** | **10,000** | Verdict calls / day (Standard Tier) | `developer.android.com/google/play/integrity/overview` | 2026-10-10 |
| **Firebase Remote Config Fetches** | **100,000** | Fetch requests / day | `firebase.google.com/docs/remote-config/limits` | 2026-10-10 |
| **Firebase Auth (Phone SMS OTP)** | **10** (Spark) / **99** (Trial) | SMS verifications / day | `firebase.google.com/docs/auth/limits` | 2026-10-10 |

---

## 2. FIRESTORE kNN VECTOR SEARCH CONSUMPTION MATH

### 2.1 Billing Formula
Under Google Cloud Firestore Vector Search (exact flat kNN index), document reads per vector query are governed by:

$$\text{Reads}_{\text{query}} = \left\lceil \frac{E}{100} \right\rceil + k$$

Where:
- $E$ = Number of vector index entries scanned within the query's filtered partition scope.
- $k$ = Number of nearest neighbor documents returned (default $k = 5$ for candidate re-ranking).
- $100$ = Document batch divisor for Firestore flat vector scanning (1 read per 100 documents scanned).

*Source:* Google Cloud Firestore Documentation: *Vector Search pricing and read calculation rules* (2026-10-10).

### 2.2 Total Daily Reads Model
$$\text{Reads}_{\text{total/day}} = \text{Reads}_{\text{marketplace\_base}} + \sum_{m=1}^{M} \left[ \text{Enrollments}_{\text{day}} \times \left( \left\lceil \frac{E_m}{100} \right\rceil + k \right) \right] + \text{Verifications}_{\text{day}}$$

Where:
- $\text{Reads}_{\text{marketplace\_base}}$ = Baseline daily reads for existing Kelasagara features (worker discovery, job listings, application status, chat, profile reads). Estimated at **35,000 reads/day** for an active pilot.
- $\text{Biometric Read Headroom}$ = $50,000 - 35,000 = \mathbf{15,000\text{ reads/day}}$.
- $M$ = Number of active model spaces simultaneously maintained (e.g., $M = 1$ for MobileFaceNet; $M = 2$ during migration to SFace).
- $\text{Verifications}_{\text{day}}$ = Direct document gets for 1:1 verification: **1 read per verification** (direct doc read on `users/{uid}` or `biometric_vault/{uid}`; no vector index scan required).

---

## 3. CAPACITY MATRICES ACROSS GALLERY SCALES ($N$)

We evaluate three planned gallery sizes:
1. **$N = 1,000$** (Initial Hassan / Karnataka district pilot).
2. **$N = 10,000$** (Regional scaling across Southern Karnataka).
3. **$N = 50,000$** (State-wide scaling).

### 3.1 Case A: Unbounded Flat Vector Scan ($E = N$)

In an unpartitioned gallery, every 1:N duplicate screening scans the entire vault ($E = N$).

| Gallery Size ($N$) | Model Spaces ($M$) | Reads per Enrollment Query | Max Enrollments/Day (Zero Other Traffic: 50k Cap) | Max Enrollments/Day (Normal Traffic: 15k Headroom) | Quota Viability Status |
|---|---|---|---|---|---|
| **$N = 1,000$** | 1 space | $\lceil 1000/100 \rceil + 5 = \mathbf{15}$ | $50,000 / 15 = \mathbf{3,333}$ | $15,000 / 15 = \mathbf{1,000}$ | **SUSTAINABLE** |
| **$N = 1,000$** | 2 spaces | $2 \times 15 = \mathbf{30}$ | $50,000 / 30 = \mathbf{1,666}$ | $15,000 / 30 = \mathbf{500}$ | **SUSTAINABLE** |
| **$N = 10,000$** | 1 space | $\lceil 10000/100 \rceil + 5 = \mathbf{105}$ | $50,000 / 105 = \mathbf{476}$ | $15,000 / 105 = \mathbf{142}$ | **CONSTRAINED** |
| **$N = 10,000$** | 2 spaces | $2 \times 105 = \mathbf{210}$ | $50,000 / 210 = \mathbf{238}$ | $15,000 / 210 = \mathbf{71}$ | **CONSTRAINED** |
| **$N = 50,000$** | 1 space | $\lceil 50000/100 \rceil + 5 = \mathbf{505}$ | $50,000 / 505 = \mathbf{99}$ | $15,000 / 505 = \mathbf{29}$ | **EXHAUSTION RISK** |
| **$N = 50,000$** | 2 spaces | $2 \times 505 = \mathbf{1,010}$ | $50,000 / 1010 = \mathbf{49}$ | $15,000 / 1010 = \mathbf{14}$ | **CRITICAL EXHAUSTION** |

> [!WARNING]
> At $N = 50,000$ with unpartitioned flat scan and 2 model spaces, just **15 enrollments** will completely deplete the daily biometric read budget, causing Firestore to throw `RESOURCE_EXHAUSTED` (HTTP 429) across all app services.

---

### 3.2 Case B: Bounded & Partitioned Scan ($K_{\text{max}} = 500$)

To guarantee quota safety under Spark, `FirestoreBiometricRepository` implements bounded candidate scanning ($E \le 500$) combined with pre-filter partitioning (e.g., district-level or pre-clustering):

$$\text{Reads}_{\text{query}} = \left\lceil \frac{500}{100} \right\rceil + 5 = 5 + 5 = \mathbf{10\text{ reads / query}}$$

| Gallery Size ($N$) | Model Spaces ($M$) | Reads per Enrollment Query | Max Enrollments/Day (Zero Other Traffic: 50k Cap) | Max Enrollments/Day (Normal Traffic: 15k Headroom) | Quota Viability Status |
|---|---|---|---|---|---|
| **$N = 1,000$** | 1 space | $\mathbf{10}$ | $50,000 / 10 = \mathbf{5,000}$ | $15,000 / 10 = \mathbf{1,500}$ | **HIGH HEADROOM** |
| **$N = 10,000$** | 1 space | $\mathbf{10}$ | $50,000 / 10 = \mathbf{5,000}$ | $15,000 / 10 = \mathbf{1,500}$ | **HIGH HEADROOM** |
| **$N = 50,000$** | 1 space | $\mathbf{10}$ | $50,000 / 10 = \mathbf{5,000}$ | $15,000 / 10 = \mathbf{1,500}$ | **HIGH HEADROOM** |
| **$N = 50,000$** | 2 spaces | $\mathbf{20}$ | $50,000 / 20 = \mathbf{2,500}$ | $15,000 / 20 = \mathbf{750}$ | **SAFE** |

**Conclusion:** Enforcing the $K \le 500$ candidate boundary is mandatory on Spark. It bounds the read cost to a deterministic maximum of 10 reads per enrollment space regardless of total gallery growth.

---

## 4. STORAGE CONSUMPTION & DOCUMENT FOOTPRINT

### 4.1 Document Size Calculation (Biometric Vault)
Each biometric template stored in `biometric_vault/{uid}` consists of:

| Field Name | Type | Size (Bytes) | Notes |
|---|---|---|---|
| `uid` | String | 36 | Subject UID identifier |
| `modelId` | String | 32 | Model namespace |
| `modelVersion` | String | 8 | E.g. `v1.0.0` |
| `embedding` | Array of 128 float32 | $128 \times 8 = 1,024$ | Firestore stores numbers as 64-bit float |
| `encryptedTemplate` | String (Base64) | 512 | AES-256-GCM ciphertext |
| `cryptoSalt` | String | 32 | Per-subject salt for envelope key derivation |
| `enrolledAt` | Timestamp | 8 | Firestore timestamp |
| `status` | String | 16 | `ACTIVE`, `REVOKED`, etc. |
| Firestore Metadata Overhead | Internal | 64 | Field names, collection path overhead |
| **Total Size per Document** | - | **$\sim 1,732\text{ Bytes}$ ($\approx 1.7\text{ KB}$)** | - |

### 4.2 Storage Capacity on 1 GiB Spark Free Tier
$$\text{Max Stored Templates} = \frac{1.0 \times 1024 \times 1024\text{ KB}}{1.7\text{ KB}} \approx \mathbf{616,000\text{ templates}}$$

Even accounting for non-biometric documents (`users`, `jobs`, `applications`, `bookings`), a gallery of $N = 50,000$ consumes:
$$50,000 \times 1.7\text{ KB} = 85,000\text{ KB} \approx \mathbf{83\text{ MiB}} \quad (\mathbf{8.1\%}\text{ of the 1 GiB Spark limit})$$

**Verdict:** Storage capacity is not a limiting constraint on Spark. The hard operational bottleneck is strictly daily document reads.

---

## 5. APP CHECK & PLAY INTEGRITY API BUDGET

- **Google Play Integrity Standard Tier Allowance:** 10,000 verdict calls / day per app.
- **Consumption per Lifecycle Event:**
  - Initial app cold start: 1 verdict call (cached in-app with 1-hour TTL).
  - Biometric enrollment session: 1 verdict call (fresh token required, un-cached).
  - High-value booking completion: 1 verdict call.
- **Daily Budget Calculation:**
  $$\text{Calls}_{\text{day}} = \text{DAU} \times 1 + \text{Enrollments}_{\text{day}} \times 1 + \text{Completions}_{\text{day}} \times 1$$
  For a pilot with 2,000 Daily Active Users (DAU), 100 enrollments/day, and 300 completions/day:
  $$\text{Calls}_{\text{day}} = 2000 + 100 + 300 = \mathbf{2,400\text{ calls/day}} \quad (\mathbf{24\%}\text{ of 10,000 limit})$$
- **Headroom:** 7,600 calls/day headroom.
- **Circuit Breaker:** If DAU approaches 8,000, request a free Standard-to-Enterprise tier quota increase via Google Play Console form (Processing time: 2-3 business days).

---

## 6. FIREBASE REMOTE CONFIG FETCH INTERVALS

- **Spark Plan Allowance:** 100,000 fetch calls / day across all app instances.
- **Client Configuration:**
  - Development / Debug mode: 0s fetch interval (`fetch(0)`).
  - Production mode: Minimum fetch interval $\ge \mathbf{3,600\text{ seconds}}$ (1 hour) per client.
  - Maximum fetches per active device: $24\text{ fetches/day}$.
- **Safe DAU Capacity:**
  $$\text{Max DAU} = \frac{100,000\text{ fetches/day}}{24\text{ fetches/device/day}} \approx \mathbf{4,166\text{ DAU}}$$
  With standard in-app local caching (12-hour default fetch interval), supported DAU scales to $\mathbf{50,000\text{ DAU}}$.

---

## 7. AUTOMATED CIRCUIT BREAKERS & INVARIANT I-27 SAFEGUARDS

To enforce Invariant I-27 (*Quota/DoS awareness: Quota exhaustion degrades to queue/alternate path and never to approval*):

1. **Pre-Flight Rate Limiter:**
   - Maximum 3 biometric enrollment attempts per UID per 24-hour rolling window.
   - Maximum 10 biometric enrollment attempts per client IP per hour.
2. **Read Quota Alarm:**
   - Standalone backend tracks cumulative daily Firestore vector reads via an in-memory sliding counter.
   - If cumulative daily reads exceed **42,500** (85% of Spark limit), backend automatically triggers **Degraded Mode**:
     - 1:N automated duplicate searches are temporarily suspended.
     - New enrollments are assigned status `PENDING_REVIEW` with flag `REASON_QUOTA_QUEUED`.
     - System informs client: *"Verification queued for asynchronous processing. Please check back shortly."*
     - **Crucial Rule:** The system NEVER bypasses screening or auto-approves accounts under quota saturation.
3. **Bounded Candidate Ceiling:**
   - `FirestoreBiometricRepository` strictly imposes `query.limit(500)`. Any attempt to perform an unpartitioned scan beyond 500 entries throws a configuration exception during initialization.
