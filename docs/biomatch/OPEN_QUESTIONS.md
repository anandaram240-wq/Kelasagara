# KELASAGARA BIOMATCH V7: OPEN QUESTIONS & SAFE DEFAULTS

These questions are raised as part of Gate G1 per Section 2.3 of the BioMatch V7 Execution Spec.  
**Execution policy:** Safe defaults are actively applied so implementation is never blocked.

---

### Q1. Why exactly can't the project upgrade to Blaze?
- **Options / Diagnostics:** Payment instrument declined, recurring-payment/e-mandate 2FA limitation, Indian RBI recurring card mandate, Google Cloud account verification, or strict organization policy.
- **Safe Default Applied:** Project remains on the free Spark plan; zero paid cloud services or billing APIs will be invoked.

### Q2. Commercial intent and target launch date?
- **Safe Default Applied:** Commercial intent assumed; target launch date is open/unspecified.  
  *Critical Licensing Invariant:* A permissive open-source code license (e.g. Apache 2.0 or MIT) does **NOT** constitute a cleared model weight license or a cleared training-data license. Code, neural weights, and upstream training dataset provenance must each be independently verified and cleared before any commercial deployment. Non-commercial research weight packs (such as InsightFace Buffalo/Antelope or MS1M-V2 derivatives) remain strictly forbidden.

### Q3. Expected biometric gallery size $N$ and daily enrollment volume?
- **Safe Default Applied:**
  - 6 Months: $N = 1,000$ users
  - 12 Months: $N = 10,000$ users
  - 24 Months: $N = 50,000$ users
  - Daily Enrollments: 50 / day.
  Firestore 50,000 daily read quota accommodates this volume if bounded searches ($K \le 500$) are maintained.

### Q4. Cross-role policy (Can the same human be both a Worker and a Hirer)?
- **Safe Default Applied:** One Worker profile and one Hirer profile per verified human being permitted via explicit account linking; registering a second profile under the same role with a different phone is classified as a duplicate.

### Q5. Do you hold, or may you collect, consented face training data?
- **Safe Default Applied:** None available currently. Therefore, custom neural network training is **BLOCKED**; system must use cleared pre-trained models or pre-calibrated architectures.

### Q6. Is legal counsel available for DPDP and licensing reviews?
- **Safe Default Applied:** No legal counsel available. All `[COUNSEL]` items (e.g., SFace training data provenance) remain open risk items with disclaimers.

### Q7. Target client devices, minimum OS floor, and language support?
- **Safe Default Applied:** Android 8.0 (API 26) minimum, 3 GB RAM floor, multilingual support for Kannada, English, and Hindi.

### Q8. Human reviewer capacity for manual fraud review?
- **Safe Default Applied:** 20 cases/day capacity, reviewed by application administrator via the existing Admin Dashboard.

### Q9. Is biometric account recovery in scope for v1?
- **Safe Default Applied:** Architecture is designed with recovery state machine, but feature-flagged **OFF** for initial release.

### Q10. Minimum user age policy?
- **Safe Default Applied:** 18+ strictly enforced. Biometric enrollment is blocked for individuals under 18 years of age.
