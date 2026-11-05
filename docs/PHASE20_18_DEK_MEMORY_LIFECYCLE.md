# KELASAGARA V20.18 — DEK MEMORY LIFECYCLE & BEST-EFFORT BUFFER CLEARING
## Accurate Runtime Memory Disclosure and Direct In-Place Buffer Zeroing

**Author:** Principal Application Security Engineer, Systems Programmer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. Honest Disclosure on Node.js / V8 Memory Semantics

In earlier documentation drafts, memory clearing was occasionally described as "guaranteed hardware zeroization". This is technically inaccurate in managed runtime environments:

1. **V8 Heap Compaction and Movement:**
   V8's Garbage Collector can copy or compact heap objects across generation spaces. While Node.js `Buffer.alloc()` allocates memory outside the V8 heap in C++ memory space, intermediate strings or subarrays can result in transient memory copies.
2. **OS Memory Swapping and Virtual Memory:**
   Operating systems can swap dirty physical memory pages to disk (swap/pagefile) where residual bits can persist across power cycles.
3. **Compiler & JIT Optimizations:**
   Aggressive dead-store elimination in JIT compilers can theoretically optimize away overwrites if the buffer is immediately de-referenced.

**Honest Engineering Definition:** Kelasagara documents all RAM clearing routines as **best-effort memory clearing**, not hardware-guaranteed physical zeroization.

---

### 2. Implementation: Direct In-Place Buffer Clearing in `finally` Blocks

To achieve true best-effort memory hygiene:
- The plaintext DEK buffer is allocated with exact length (32 bytes) without redundant copying.
- Plaintext DEK buffers are NEVER logged, serialized, or attached to long-lived singleton objects.
- Plaintext DEK lifetime is strictly bounded to the synchronous `decipher.update()` and `decipher.final()` call.
- The owned buffer is cleared directly in an unconditional `finally` block using `plaintextDek.fill(0)`:

```typescript
let plaintextDek: Buffer | null = null;
try {
  plaintextDek = unwrapKmsKey(wrappedDek);
  const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
  decipher.setAAD(trustedTemplateAad);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
} finally {
  if (plaintextDek) {
    plaintextDek.fill(0); // Best-effort direct buffer wipe
  }
}
```

---

### 3. Error-Path and Exception Resilience

The `finally` block ensures that clearing is executed under all operational conditions:
- **Ciphertext Corruption:** When `decipher.final()` throws an authentication tag error, `plaintextDek.fill(0)` still executes.
- **KMS Unwrap Failure:** If unwrapping fails partway, any partial allocation is scrubbed.
- **Cancelled Request:** If the client disconnects or an unhandled exception occurs, the buffer is zeroed before control returns to the event loop.
