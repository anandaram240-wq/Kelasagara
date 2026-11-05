# KELASAGARA BIOMATCH V7: COST ANALYSIS & INR OPERATIONAL MODELING

**Document Version:** 1.0.0  
**Phase:** Phase 15 — Cost Analysis & INR Operational Modeling  
**Target Environment:** Firebase Spark Plan (Current Zero-Cost Baseline) to GCP Blaze Production Scaling  
**Primary Currency:** Indian Rupee (INR ₹)  
**USD / INR Conversion Anchor:** 1.00 USD = ₹84.00 INR (GCP Billing Standard Baseline)  
**Cloud Region:** Google Cloud `asia-south1` (Mumbai, India)  
**Owning Role:** Lead Systems Architect & Financial Operations (FinOps) Team  

---

## 1. EXECUTIVE SUMMARY & FINANCIAL INVARIANTS

The economic sustainability of Kelasagara rests on maintaining near-zero fixed infrastructure overhead while serving low-margin unorganized gig economy transactions (earning average daily worker wages of ₹600 – ₹1,200). 

### Key Financial Invariants:
1. **Current Operating Baseline:** **₹0.00 / month (100% Free Spark Plan)**. Under RRL-0 research prototype operation, all biometric vector scans, Firestore document writes, and local Node.js Tier 0 shadow tests incur zero financial liability.
2. **Spark Transition Boundary:** The Firebase Spark tier supports up to **$N = 10,000$ registered gallery subjects** provided daily enrollments are bounded ($\le 50$ enrollments/day) and bounded kNN indexing ($K \le 500$) is enforced.
3. **Blaze Scaling Ceiling ($N = 100,000$):** At state-wide Karnataka scale (100,000 active workers and hirers), total monthly cloud infrastructure costs remain remarkably low: **₹8,470 INR / month** (less than ₹0.09 INR per registered user per month).
4. **Unit Economics Break-Even:** At a modest platform convenience fee of ₹5.00 INR per completed job booking, only **1,694 completed jobs/month** across Karnataka are required to achieve 100% cloud infrastructure breakeven at 100,000 users.

---

## 2. GOOGLE CLOUD & FIREBASE PRICING MATRIX (`asia-south1` MUMBAI)

All rates reflect official Google Cloud Platform pricing for the Mumbai (`asia-south1`) region as of October 2026.

| Infrastructure Component | Free Monthly Allowance (Spark / Free Tier) | Paid Unit Rate (USD) | Paid Unit Rate (INR ₹) | Billing Basis |
|---|---|---|---|---|
| **Cloud Firestore Reads** | 50,000 reads / day (1.5M / mo) | \$0.060 per 100,000 reads | ₹5.04 per 100,000 reads | Per document read |
| **Cloud Firestore Writes** | 20,000 writes / day (600k / mo) | \$0.180 per 100,000 writes | ₹15.12 per 100,000 writes | Per document write |
| **Cloud Firestore Deletes** | 20,000 deletes / day (600k / mo) | \$0.020 per 100,000 deletes | ₹1.68 per 100,000 deletes | Per document delete |
| **Cloud Firestore Storage** | 1.00 GiB total | \$0.180 per GiB-month | ₹15.12 per GiB-month | Billed hourly per GiB |
| **Firestore Vector Search Scans** | Included in read allowances | $\lceil E / 100 \rceil + k$ reads | 1 read per 100 vector entries | Vector index scan divisor |
| **GCP Cloud Run (Compute)** | 2M req, 360k vCPU-s, 180k GiB-s | \$0.00002400 / vCPU-sec | ₹0.002016 / vCPU-sec | 100ms granularity |
| **GCP Cloud Run (Memory)** | 180,000 GiB-seconds / mo | \$0.00000250 / GiB-sec | ₹0.000210 / GiB-sec | 100ms granularity |
| **Network Egress (Internet)** | 10 GiB / month worldwide | \$0.120 per GiB | ₹10.08 per GiB | Outbound network bytes |
| **Play Integrity API** | 10,000 calls / day | \$0.00 (Standard Tier) | ₹0.00 | Free under 10k calls/day |
| **Indian DLT Transactional SMS** | 10 SMS/day (Spark phone auth) | \$0.0018 per SMS (Indian SMS gateway) | ₹0.150 per SMS | Transactional OTP route |

---

## 3. TIERED OPERATIONAL COST MODELS ($N = 1,000$ TO $N = 100,000$)

We evaluate monthly operational costs across 4 distinct deployment scales:
- **Tier 1:** $N = 1,000$ (Hassan District Pilot — High Density Gig Hub)
- **Tier 2:** $N = 10,000$ (Southern Karnataka Regional Expansion: Hassan, Mysuru, Mandya)
- **Tier 3:** $N = 50,000$ (Multi-Division Expansion: Bengaluru Rural, Mangaluru, Belagavi)
- **Tier 4:** $N = 100,000$ (Full Karnataka State Scale)

### 3.1 Assumptions & Workload Parameters

| Parameter | Tier 1 ($N=1\text{k}$) | Tier 2 ($N=10\text{k}$) | Tier 3 ($N=50\text{k}$) | Tier 4 ($N=100\text{k}$) |
|---|:---:|:---:|:---:|:---:|
| **New Enrollments / Day** | 15 | 80 | 250 | 500 |
| **1:1 Login Verifications / Day** | 200 | 2,500 | 12,000 | 25,000 |
| **Core Job Searches & Bookings / Day** | 400 | 4,000 | 20,000 | 45,000 |
| **Realtime Tracking Heartbeats / Day** | 1,200 | 15,000 | 75,000 | 180,000 |
| **Vector Index Entries Scanned ($E$)** | 1,000 | 5,000 (bounded) | 10,000 (bounded) | 20,000 (bounded) |
| **Vector Search Reads / Enrollment** | $\lceil 1000/100 \rceil + 5 = 15$ | $\lceil 5000/100 \rceil + 5 = 55$ | $\lceil 10000/100 \rceil + 5 = 105$ | $\lceil 20000/100 \rceil + 5 = 205$ |
| **Daily Biometric Reads** | 425 | 6,900 | 38,250 | 127,500 |
| **Daily Marketplace Reads** | 12,000 | 32,000 | 85,000 | 195,000 |
| **Total Daily Reads** | 12,425 | 38,900 | 123,250 | 322,500 |
| **Monthly Document Reads** | 372,750 | 1,167,000 | 3,697,500 | 9,675,000 |
| **Monthly Document Writes** | 48,000 | 380,000 | 1,450,000 | 3,600,000 |
| **Stored Biometric Vault Size** | 0.51 MB | 5.12 MB | 25.60 MB | 51.20 MB |
| **Total Firestore Collection Data** | 120 MB | 450 MB | 1.8 GiB | 3.6 GiB |

---

### 3.2 Detailed Financial Breakdown by Tier

#### Tier 1: Hassan Pilot ($N = 1,000$ Enrolled Subjects)
- **Firestore Reads:** 372,750 / month (well below 1.5M free tier) $\rightarrow$ **₹0.00**
- **Firestore Writes:** 48,000 / month (well below 600k free tier) $\rightarrow$ **₹0.00**
- **Firestore Storage:** 120 MB (well below 1 GiB free tier) $\rightarrow$ **₹0.00**
- **Cloud Run Compute:** Tier 0 shadow / local dev $\rightarrow$ **₹0.00**
- **Play Integrity API:** 215 calls / day $\rightarrow$ **₹0.00**
- **SMS OTP:** Within test phone / free tier $\rightarrow$ **₹0.00**
- **Total Monthly Cost:** **₹0.00 INR / month (\$0.00 USD)**

#### Tier 2: Regional Hub ($N = 10,000$ Enrolled Subjects)
- **Firestore Reads:** 1,167,000 / month (100% within 1.5M free Spark tier) $\rightarrow$ **₹0.00**
- **Firestore Writes:** 380,000 / month (100% within 600k free Spark tier) $\rightarrow$ **₹0.00**
- **Firestore Storage:** 450 MB (100% within 1 GiB free tier) $\rightarrow$ **₹0.00**
- **Compute (Cloud Run):** 75,000 invocations $\times$ 120ms = 9,000 vCPU-sec (within 360k free vCPU-sec) $\rightarrow$ **₹0.00**
- **Transactional SMS OTP:** 80 enrollments $\times$ 30 days = 2,400 SMS @ ₹0.15 $\rightarrow$ **₹360.00**
- **Total Monthly Cost:** **₹360.00 INR / month (\$4.28 USD)**  
*(If SMS is supplemented via WhatsApp / Firebase Auth free quotas, infrastructure cost is ₹0.00).*

#### Tier 3: Multi-Division Scale ($N = 50,000$ Enrolled Subjects)
- **Firestore Reads:** 3,697,500 reads / mo. (Billable above 1.5M free: 2,197,500 reads @ ₹5.04 / 100k) $\rightarrow$ **₹110.75**
- **Firestore Writes:** 1,450,000 writes / mo. (Billable above 600k free: 850,000 writes @ ₹15.12 / 100k) $\rightarrow$ **₹128.52**
- **Firestore Storage:** 1.8 GiB total (0.8 GiB billable @ ₹15.12 / GiB-mo) $\rightarrow$ **₹12.10**
- **Compute (Cloud Run):** 360,000 invocations $\times$ 120ms = 43,200 vCPU-sec (within 360k free vCPU-sec) $\rightarrow$ **₹0.00**
- **Network Egress:** 18 GiB total (8 GiB billable @ ₹10.08 / GiB) $\rightarrow$ **₹80.64**
- **Transactional SMS OTP:** 250 enrollments/day $\times$ 30 days = 7,500 SMS @ ₹0.15 $\rightarrow$ **₹1,125.00**
- **Total Monthly Cost:** **₹1,457.01 INR / month (\$17.35 USD)**

#### Tier 4: Karnataka State Scale ($N = 100,000$ Enrolled Subjects)
- **Firestore Reads:** 9,675,000 reads / mo. (Billable: 8,175,000 reads @ ₹5.04 / 100k) $\rightarrow$ **₹412.02**
- **Firestore Writes:** 3,600,000 writes / mo. (Billable: 3,000,000 writes @ ₹15.12 / 100k) $\rightarrow$ **₹453.60**
- **Firestore Storage:** 3.6 GiB total (2.6 GiB billable @ ₹15.12 / GiB-mo) $\rightarrow$ **₹39.31**
- **Compute (Cloud Run):** 750,000 invocations $\times$ 120ms = 90,000 vCPU-sec (within 360k free tier) $\rightarrow$ **₹0.00**
- **Cloud Run Memory:** 45,000 GiB-sec (within 180k free tier) $\rightarrow$ **₹0.00**
- **Network Egress:** 45 GiB total (35 GiB billable @ ₹10.08 / GiB) $\rightarrow$ **₹352.80**
- **Play Integrity API:** 25,500 calls/day (requires Tier 1 quota approval; zero cost for verified apps) $\rightarrow$ **₹0.00**
- **Transactional SMS OTP:** 500 enrollments/day $\times$ 30 days = 15,000 SMS @ ₹0.15 $\rightarrow$ **₹2,250.00**
- **Human Manual Review Operations:** 5% review queue $\times$ 15,000 enrollments = 750 reviews @ ₹6.50/review $\rightarrow$ **₹4,875.00**
- **Total Monthly Operational Cost:** **₹8,382.73 INR / month (\$99.79 USD)**

---

## 4. CONSOLIDATED COST COMPARISON TABLE

| Cost Category | Tier 1 ($N=1\text{k}$) | Tier 2 ($N=10\text{k}$) | Tier 3 ($N=50\text{k}$) | Tier 4 ($N=100\text{k}$) |
|---|:---:|:---:|:---:|:---:|
| **Firestore Database (Reads/Writes/Storage)** | ₹0.00 | ₹0.00 | ₹251.37 | ₹904.93 |
| **Compute Engine (Cloud Run `asia-south1`)** | ₹0.00 | ₹0.00 | ₹0.00 | ₹0.00 |
| **Network Egress (Internet)** | ₹0.00 | ₹0.00 | ₹80.64 | ₹352.80 |
| **Telecom (Indian DLT SMS OTP)** | ₹0.00 | ₹360.00 | ₹1,125.00 | ₹2,250.00 |
| **Operational Review Workforce (5% Queue)** | ₹0.00 | ₹0.00 | ₹0.00 (Admin staff) | ₹4,875.00 |
| **Total Monthly Operating Cost (TCO)** | **₹0.00** | **₹360.00** | **₹1,457.01** | **₹8,382.73** |
| **Cost per Active Registered User / Month** | **₹0.00** | **₹0.036** | **₹0.029** | **₹0.084** |
| **Cost per Completed Gig Job Transaction** | **₹0.00** | **₹0.003** | **₹0.002** | **₹0.006** |

---

## 5. SPARK-TO-BLAZE MIGRATION THRESHOLDS & INFLECTION POINTS

The project team must strictly monitor quota thresholds to prevent service interruption.

```
       [FREE SPARK PLAN (₹0/mo)]
                   │
                   │ Daily Reads Reach 45,000 (90% Spark Cap)
                   │ OR Registered Gallery Exceeds N = 10,000
                   ▼
       [BLAZE PLAN ACTIVATION CHECKLIST]
                   │
                   ├── 1. Set Google Cloud Budget Alert at ₹2,500 INR / month
                   ├── 2. Enable Hard Quota Cap on Cloud Run (max 10 instances)
                   ├── 3. Enforce In-Process LRU Vector Cache (K <= 500)
                   └── 4. Link Indian Rupee Billing Account (Auto-Debit with RBI e-mandate)
```

### 5.1 Early Warning Indicators:
1. **Firestore Daily Read Consumption $> 40,000$:** Triggers immediate vector scan window reduction ($K$ clamped from 500 to 250).
2. **Play Integrity Calls $> 8,000$ / day:** Requests Google Play Developer console quota expansion from standard 10,000 to custom tier.
3. **SMS OTP Consumption $> 80$ / day:** Triggers fallback to In-App WhatsApp Deep-Link OTP or voice-call OTP to conserve telecom spend.

---

## 6. FINANCIAL SAFEGUARDS & CIRCUIT BREAKERS

To guarantee zero runaway cloud bills under Denial-of-Wallet (DoW) attacks:
1. **GCP Billing Budget & Automated Actions:**
   - Budget ceiling: **₹3,000 INR / month** during initial commercial rollout.
   - 50% Alert (₹1,500): Email notification to engineering team.
   - 90% Alert (₹2,700): Triggers automated Cloud Function to switch Tier 0 backend into degraded review-only mode.
   - 100% Alert (₹3,000): Enforces read-only mode for non-essential catalog features.
2. **Rate Limiting Protection:**
   - Standalone API route level: 60 requests / minute per IP address.
   - Per-user biometric enrollment rate limit: maximum 3 enrollment attempts per UID per 24-hour sliding window.
3. **Bounded Scan Invariant (I-27):**
   - Under no circumstances does the system execute an unbounded `collection("biometric_vault").get()`.
   - All vector scans are bounded by Firestore inequality partitions or explicit `limit(500)`.

---

## 7. GATE G15 CONCLUSION

The economic analysis proves that Kelasagara BioMatch V7 is extraordinarily cost-efficient. The architecture operates completely free of charge during research and early pilot stages ($N \le 1,000$), scales to regional pilot ($N = 10,000$) for just ₹360/month, and supports a massive state-wide workforce of 100,000 gig workers for less than ₹8,500/month in total cloud and operational expenditure.
