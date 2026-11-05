# KELASAGARA V20.12: ADVERSARIAL TEST REPORT (34 SCENARIOS)

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Test Suite:** `backend/src/tests/phase20_12_biometric_trust_provenance.test.ts`  
**Test Execution Date:** 2026-11-01  
**Status:** 100% PASS (34 of 34 Executable Tests)  

---

## 1. TEST RESULTS SUMMARY

```
▶ KELASAGARA V20.12: Biometric Trust Provenance, Recovery Reference Hardening & Inventory Verification Suite
  ▶ Workstream H.1: Recovery Reference Security & 128-bit Entropy (Tests 1–10)
    ✔ 1. 128-bit CSPRNG output: produces CASE- followed by exactly 32 hex chars (37 chars, 128 bits)
    ✔ 2. Invalid reference length: validates exactly 37 characters and rejects short or long strings
    ✔ 3. Invalid hexadecimal characters: rejects non-hex characters in reference body
    ✔ 4. Collision handling: coordinator detects existing case reference and rejects collision
    ✔ 5. No predictable sequential identifiers: 2,000 samples exhibit zero duplicates and high Hamming distance
    ✔ 6. Reference cannot authorize account recovery alone without independent verification
    ✔ 7. Unauthorized lookup rejected: public lookup returns zero PII (no UID, name, phone or embeddings)
    ✔ 8. Expired reference rejected: expired cases fail resolution and lookup
    ✔ 9. Rate limiting: > 10 lookups per minute from same client triggers rate limiting
    ✔ 10. Generic response against enumeration: unknown or invalid references return generic failure
  ✔ Workstream H.1: Recovery Reference Security & 128-bit Entropy (Tests 1–10) (8.79ms)
  ▶ Workstream H.2: Provenance & Metadata Tamper Protection (Tests 11–18)
    ✔ 11. Client cannot assign canonical embedding metadata: classifyBiometricTemplate guards canonical space
    ✔ 12. Client cannot overwrite model hashes: mismatched model hash classifies as UNKNOWN
    ✔ 13. Unknown embedding-space identifier rejected: unrecognized space maps to UNKNOWN
    ✔ 14. Incorrect detector model hash rejected: altered YuNet hash classifies as UNKNOWN
    ✔ 15. Missing pipeline manifest rejected: altered manifestHash classifies as UNKNOWN
    ✔ 16. Cross-space gallery comparisons prevented: searchTopKCompatible excludes non-canonical templates
    ✔ 17. Superseded templates excluded: records with status SUPERSEDED are filtered out
    ✔ 18. Corrupted metadata rejected: records with invalid embedding dimensions fail closed
  ✔ Workstream H.2: Provenance & Metadata Tamper Protection (Tests 11–18) (20.98ms)
  ▶ Workstream H.3: Runtime Object Safety & Provenance Boundary (Tests 19–23)
    ✔ 19. Arbitrary Buffer rejected: small or incorrect length buffer fails runtime validation
    ✔ 20. Valid-length noise rejected: 37,632 random bytes rejected with UNAUTHORIZED_CANONICAL_FACE_OBJECT
    ✔ 21. Manually fabricated canonical object rejected: TypeScript casts cannot bypass runtime gate
    ✔ 22. Invalid alignment provenance rejected: tampered buffer fails HMAC verification
    ✔ 23. Valid trusted pipeline object accepted: authoritative aligned buffer succeeds and returns 128-D unit vector
  ✔ Workstream H.3: Runtime Object Safety & Provenance Boundary (Tests 19–23) (75.62ms)
  ▶ Workstream H.4: Authorized Replacement Transaction (Tests 24–29)
    ✔ 24. Only authorized account owner can replace: mismatched UID is rejected with 403 UNAUTHORIZED
    ✔ 25. Old template and new template update atomically: transaction sets old to SUPERSEDED and new to ACTIVE
    ✔ 26. Transaction retries do not create duplicate templates: retry succeeds idempotently
    ✔ 27. Gallery epoch is updated consistently: gallery epoch document is incremented
    ✔ 28. Concurrent replacement fails safely: stale template version check halts conflicting transaction
    ✔ 29. External side effects remain outside retried callbacks: ONNX inference is executed before transaction
  ✔ Workstream H.4: Authorized Replacement Transaction (Tests 24–29) (8.60ms)
  ▶ Workstream H.5: Manual Review Workflow (Tests 30–34)
    ✔ 30. Case is durably created: openReviewCase initializes case with 128-bit reference and audit chain
    ✔ 31. Unauthorized reviewers cannot access the case / adjudicate: non-auditor role rejected
    ✔ 32. Case state transitions are authorized: cannot skip required states to RESOLVED
    ✔ 33. Case expiry is enforced: expired case halts transition and maintains tamper chain
    ✔ 34. The user cannot use the reference alone to take control of an account: audit trail is unbroken
  ✔ Workstream H.5: Manual Review Workflow (Tests 30–34) (0.57ms)
✔ KELASAGARA V20.12 Suite: 34 tests, 6 suites, 0 failures, 115.0ms duration
```

---

## 2. ADVERSARIAL PENETRATION DRILL MATRIX

| Workstream | Test ID | Scenario Description | Attack Vector / Drill Input | System Defense & Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **Entropy** | T-01 | 128-bit CSPRNG | Generate case reference | Matches `/^CASE-[0-9A-F]{32}$/` ($2^{128}$ entropy) |
| **Entropy** | T-02 | Short/Long Ref | Malformed input `CASE-1234` | Rejected by format guard (`false`) |
| **Entropy** | T-03 | Non-Hex Chars | Injected characters `CASE-...ZZ!` | Rejected by format guard (`false`) |
| **Entropy** | T-04 | ID Collision | Duplicate reference insertion | Collision detected; aborts atomic write |
| **Entropy** | T-05 | Non-Sequential | Sample 2,000 references | Zero collisions; uniform distribution |
| **Entropy** | T-06 | Standalone Auth | Direct skip to `RESOLVED` | Throws `ERR_ILLEGAL_STATE_TRANSITION` |
| **Entropy** | T-07 | PII Leakage | Public status check query | Zero PII returned (UID, name, phone suppressed) |
| **Entropy** | T-08 | Expired Case | Query after TTL expiration | Fails closed with `CASE_EXPIRED` |
| **Entropy** | T-09 | Rate Limit | 11 requests within 60s | Returns HTTP 429 `ERR_RATE_LIMIT_EXCEEDED` |
| **Entropy** | T-10 | ID Enumeration | Random non-existent reference | Generic `CASE_NOT_FOUND_OR_EXPIRED` |
| **Provenance** | T-11 | Client Space ID | Client injects `CANONICAL_V2` | Flagged `clientModified`; quarantined to `UNKNOWN` |
| **Provenance** | T-12 | Spoofed Model | Altered SFace weights hash | Quarantined to `LEGACY_TEMPLATE_UNKNOWN` |
| **Provenance** | T-13 | Unknown Space | Unrecognized space ID | Quarantined to `LEGACY_TEMPLATE_UNKNOWN` |
| **Provenance** | T-14 | Spoofed YuNet | Altered detector weights hash | Quarantined to `LEGACY_TEMPLATE_UNKNOWN` |
| **Provenance** | T-15 | Bad Manifest | Corrupted manifest hash | Quarantined to `LEGACY_TEMPLATE_UNKNOWN` |
| **Provenance** | T-16 | Cross-Space Match | Canonical probe vs mixed gallery | Filters out legacy/unknown; compares V2 only |
| **Provenance** | T-17 | Superseded Leak | Match against superseded doc | Excluded from gallery candidate pool |
| **Provenance** | T-18 | Dim Corruption | Malformed 3-D embedding vector | Fails closed; skipped safely |
| **Runtime** | T-19 | Short Buffer | Injected 100-byte buffer | Rejected with `INVALID_BYTE_LENGTH` |
| **Runtime** | T-20 | Random Noise | 37,632 bytes Gaussian noise | Rejected with `UNAUTHORIZED_CANONICAL_FACE_OBJECT` |
| **Runtime** | T-21 | Forged TS Cast | `buf as CanonicalAlignedFace112` | Rejected (`UNREGISTERED_BUFFER`) |
| **Runtime** | T-22 | Buffer Mutation | Pixel modified after registration | Rejected with `TAMPERED_BUFFER` |
| **Runtime** | T-23 | Authoritative | Output of `alignFaceToCanonical112` | Accepted; valid 128-D unit vector on $S^{127}$ |
| **Replacement** | T-24 | Account Hijack | Attacker UID in replacement | Rejected with HTTP 403 `UNAUTHORIZED` |
| **Replacement** | T-25 | Atomic Swap | Old active, new active | Old -> `SUPERSEDED`, New -> `ACTIVE` in 1 tx |
| **Replacement** | T-26 | Tx Retry | Retry on contention | Idempotent deterministic opId; zero duplicates |
| **Replacement** | T-27 | Epoch Bump | Replacement committed | Gallery epoch incremented consistently |
| **Replacement** | T-28 | Stale Version | Concurrently changed active ID | Fails closed with `ERR_STALE_BIOMETRIC_VERSION` |
| **Replacement** | T-29 | Tx Isolation | Heavy ONNX run in tx | Pre-computed outside tx; zero side-effects in cb |
| **Review** | T-30 | Durable Case | Ambiguous match triggered | Case persisted with 128-bit ID and genesis hash |
| **Review** | T-31 | Unauth Role | Tier-1 support adjudicates | Throws `ERR_UNAUTHORIZED_REVIEWER_ROLE` |
| **Review** | T-32 | State Machine | Skip verification steps | Throws `ERR_ILLEGAL_STATE_TRANSITION` |
| **Review** | T-33 | Expiry Guard | Adjudicate expired case | Fails closed with `ERR_CASE_EXPIRED` |
| **Review** | T-34 | Account Control | Attacker presents `CASE-...` | Requires OTP recovery; zero bypass granted |
