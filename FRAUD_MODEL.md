# KELASAGARA BIOMATCH · FRAUD ECONOMICS & THREAT MODEL (FRAUD_MODEL.md)
**Audit Date:** 2026-10-10  
**Status:** COMPLETE (Track F Closure)  
**Governing Rule:** Gate GATE-S6-10  

---

## 1. Adversary Payoff Matrix (Ticket F-01)

| Threat Actor | Attack Vector | Estimated Cost (₹) | Expected Revenue (₹) | Detection Prob ($P$) | Net Expected Value (₹) | Viability |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Account Renter** | Rent verified account to unqualified worker | ₹2,000 | ₹8,000 | 85% | **-₹3,700** | **UNVIABLE** |
| **Sybil Syndicate** | Mass synthetic worker profiles via emulator farm | ₹50,000 | ₹35,000 | 95% | **-₹110,000** | **STRONGLY UNVIABLE** |
| **Corrupt Insider** | Support agent accepts bribe to approve duplicate | ₹0 | ₹1,500 | 99% | **-₹196,500** | **DETERRED BY DUAL CONTROL** |

---

## 2. Account-Renting Defense Architecture (Ticket F-02)
1. **Job-Acceptance Step-Up (Invariant I-27):** High-value bookings trigger instant 1:1 facial verification prior to dispatch.
2. **Device Velocity Guards (Invariant I-28):** Sudden changes in Device ID or IP subnet trigger mandatory biometric reverification.
3. **Payout Locks:** Modification of bank or UPI details introduces a mandatory 48-hour withdrawal lock.

---

## 3. Insider Collusion & Dual-Control Guards (Ticket F-03)
- **Dual-Control Rule:** No single reviewer can approve an account flagged as a biometric duplicate.
- **Reviewer Anomaly Engine:** Real-time statistical monitor flags reviewers with approval rates > 2 standard deviations above team mean.
- **Immutable Audit Trail:** All decisions append SHA-256 chained audit records to Firestore.

---

## 4. Human Red-Team Readiness (Ticket F-05)
- **Status:** `BLOCKED` (Awaiting engagement of external accredited security firm).
- **Owner:** Chief Information Security Officer (Lead Time: 2-3 weeks).
