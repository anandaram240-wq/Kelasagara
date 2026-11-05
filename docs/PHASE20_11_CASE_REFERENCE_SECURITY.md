# PHASE 20.11: CASE REFERENCE SECURITY & ENTROPY AUDIT
**Role:** Backend Cryptography & Application Security Auditor  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. PURPOSE & THREAT MODEL

When a biometric enrollment encounters a duplicate block (HTTP 409) or ambiguous match requiring review (HTTP 202), the server returns an opaque case reference in the format:
```
CASE-XXXXXXXX
```
This identifier allows the worker to contact human dispute review or initiate account recovery without revealing:
- The identity, phone number, or name of the existing account holder.
- The applicant's raw similarity score.
- Sequential registration patterns.

### Threat Model:
1. **Enumeration Attack:** An adversary attempts to enumerate sequential or predictable case references to scrape review queues or monitor registration volumes.
2. **Collision Attack:** Two disparate applicants receive identical case references, corrupting review audits.
3. **Information Leakage:** The case reference embeds timestamps, user IDs, or reversible personal metadata.

---

## 2. CRYPTOGRAPHIC ENTROPY IMPLEMENTATION

In Phase 20.11, the case reference generator was upgraded to draw directly from the operating system's cryptographically secure pseudorandom number generator (CSPRNG via Node.js `crypto.randomBytes`):

```typescript
const caseId = `CASE-${randomBytes(4).toString('hex').toUpperCase()}`;
```

### 2.1 Entropy & Collision Analysis
- **Byte Length:** 4 bytes = 32 bits of pure CSPRNG entropy.
- **Hex Representation:** 8 uppercase hexadecimal characters from `[0-9A-F]`.
- **Search Space:** $2^{32} = 4,294,967,296$ unique combinations.
- **Birthday Paradox Collision Probability:**
  For $N$ concurrently active review cases:
  $$P(\text{collision}) \approx 1 - e^{-\frac{N^2}{2 \times 2^{32}}}$$
  - For $N = 1,000$ active cases: $P \approx 1.16 \times 10^{-4}$ (0.01%)
  - For $N = 10,000$ active cases: $P \approx 1.16 \times 10^{-2}$ (1.16%)
  - When combined with Firestore unique document keys in collection `biometric_duplicate_cases`, any collision attempts fail closed on transaction write.

---

## 3. ACCESS CONTROL & RATE LIMITING

1. **Storage Isolation:** Case documents are stored in the server-only collection `biometric_duplicate_cases`.
2. **Access Control:** No public client read endpoints exist for case references. Only officers with custom claim `biometric_compliance_officer = true` can inspect case records via authenticated admin routes.
3. **Zero Information Leakage:** The reference contains no timestamps, user IDs, phone hashes, or geographic coordinates.
