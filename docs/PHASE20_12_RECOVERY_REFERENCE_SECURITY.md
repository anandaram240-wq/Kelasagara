# KELASAGARA V20.12: RECOVERY REFERENCE SECURITY & ENTROPY SPECIFICATION

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Cryptographic Security & Threat Model Specification  

---

## 1. EXECUTIVE SUMMARY & THREAT ANALYSIS

In earlier pilot phases, duplicate resolution case references were generated using:
```typescript
crypto.randomBytes(4).toString('hex').toUpperCase(); // Yielding e.g. CASE-A1B2C3D4
```
This provided only 32 bits ($4.29 \times 10^9$ possibilities) of entropy. While sufficient to avoid collisions across small test collections, a 32-bit namespace is susceptible to birthday collisions at $2^{16} \approx 65,536$ records and enables automated online query enumeration attacks.

Phase 20.12 executes an entropy and lifecycle hardening mandate:
1. **Entropy Upgrade:** Upgraded to 128 bits of cryptographically secure pseudo-randomness using `crypto.randomBytes(16)`.
2. **Canonical Format:** `CASE-` followed by 32 uppercase hexadecimal characters (total length: exactly 37 ASCII characters).
3. **Collision Resistance:** $2^{128} \approx 3.4028 \times 10^{38}$ distinct states. Birthday collision threshold is $2^{64} \approx 1.84 \times 10^{19}$ cases.
4. **Hashed Blind Indexing:** Internal references and queries support constant-time lookup via `caseReferenceHash = SHA-256(caseReference)`.
5. **Decoupled Authorization:** The case reference is strictly an opaque tracking ticket; possession of the reference confers zero authorization or recovery privileges.

---

## 2. MATHEMATICAL ENTROPY & COLLISION MODEL

### 2.1 State Space Comparison

| Parameter | Legacy Pilot (V20.11) | Hardened V20.12 Canonical | Security Gain |
| :--- | :--- | :--- | :--- |
| **CSPRNG Byte Source** | `randomBytes(4)` | `randomBytes(16)` | $+12$ bytes ($+96$ bits) |
| **Total Entropy** | 32 bits | 128 bits | $2^{96} \times$ namespace expansion |
| **Total Formatted Length** | 13 characters (`CASE-` + 8 hex) | 37 characters (`CASE-` + 32 hex) | Standardized 37-byte fixed buffer |
| **Total Possible States** | $4,294,967,296$ | $340,282,366,920,938,463,463,374,607,431,768,211,456$ | Infinite for operational lifetime |
| **50% Collision Bound** | $\approx 77,163$ cases | $\approx 2.17 \times 10^{19}$ cases | Unreachable under physical constraints |

### 2.2 Brute-Force Enumeration Cost
With a rate limit of 10 requests/minute per client IP:
$$\text{Requests per day per IP} = 10 \times 60 \times 24 = 14,400$$
To achieve a $1\%$ chance of guessing a valid active reference from a pool of 1,000 active cases:
$$p \approx \frac{K \times N}{2^{128}} = \frac{14,400 \times 1,000}{3.4 \times 10^{38}} \approx 4.23 \times 10^{-32}$$
Online enumeration across distributed botnets is cryptographically infeasible.

---

## 3. CASE REFERENCE WIRE & API CONTRACT

### 3.1 Regular Expression Guard
```typescript
/^CASE-[0-9A-F]{32}$/
```
- Prefix: Exact ASCII uppercase `CASE-` (5 bytes).
- Body: Exactly 32 hexadecimal characters `[0-9A-F]`.
- Length: Exactly 37 characters.

### 3.2 Hashed Representation in Firestore
To prevent internal index inspection or leaking references in audit dumps:
```json
{
  "caseId": "CASE-7B93E0184A74CD72295FE230B480C1E5",
  "caseReferenceHash": "d258b6833b378c8bc1e9154a17bb4113e3cb8bc3e85e130ad646c243ee7d4d42",
  "status": "CREATED",
  "expiresAtMs": 1798780800000
}
```

---

## 4. DECOUPLED AUTHORIZATION GUARANTEES

1. **Zero Access Credential:** A case reference cannot be used as a bearer token, password, or biometric bypass.
2. **Mandatory Step-Up Auth:** Account recovery requires multi-factor phone OTP + government ID / Aadhaar offline verification.
3. **No Account Leakage:** A public lookup for an unknown reference returns generic `CASE_NOT_FOUND_OR_EXPIRED` in constant time without disclosing user existence.
