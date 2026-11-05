# KELASAGARA V20.10: NONCE REPLAY DEFENCE & LIFECYCLE
## Three-State Challenge Machine (ISSUED -> PROCESSING -> CONSUMED)

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Backend Systems & Distributed Concurrency Architect  
**Date:** November 1, 2026

---

### 1. Challenge Lifecycle State Machine

To prevent replay attacks, concurrent request races, and stale session resubmissions, `ServerNonceLifecycleService` enforces a strict 3-state transition model:

```
    ┌──────────┐
    │  ISSUED  │ ── (Server issues 256-bit cryptographically secure nonce with 3m TTL)
    └────┬─────┘
         │
         │ beginProcessing() [Atomic check-and-set]
         ▼
  ┌──────────────┐
  │  PROCESSING  │ ── (Actively executing cryptographic verification & SFace inference)
  └──────┬───────┘
         │
         ├───────────────────────────────┐
         │ commitConsumed()              │ markFailed()
         ▼                               ▼
  ┌──────────────┐                ┌──────────────┐
  │   CONSUMED   │ (Terminal)     │    FAILED    │ (Terminal)
  └──────────────┘                └──────────────┘
```

---

### 2. Concurrency Safety Rules

1. **Atomic Check-and-Set:** When a request arrives, `beginProcessing()` checks if the challenge is `ISSUED`. It atomically marks the record as `PROCESSING`.
2. **Concurrent Request Defense:** If a second identical request arrives while the first is in `PROCESSING`, the engine immediately throws:
   `CONCURRENT_SUBMISSION_DETECTED`
3. **Replay Defense:** Once verification succeeds, `commitConsumed()` moves the record to `CONSUMED`. Any subsequent attempt to reuse the nonce immediately throws:
   `NONCE_ALREADY_CONSUMED`
4. **Time-To-Live (TTL):** Nonces expire 3 minutes after issuance. Expired nonces throw:
   `CHALLENGE_EXPIRED`
