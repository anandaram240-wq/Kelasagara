# PHASE 20.19: PLAIN TEXT DEK MEMORY LIFECYCLE & BEST-EFFORT BUFFER CLEARING

## 1. Threat Model & Memory Hygiene

### 1.1 In-Memory Sensitive Material Exposure
When decrypting biometric templates using AES-256-GCM envelope encryption:
1. The wrapped Data Encryption Key (DEK) is unwrapped via Cloud KMS into a 32-byte plaintext Buffer.
2. The plaintext DEK is used to initialize the `crypto.createDecipheriv` stream.
3. If an unhandled exception occurs (e.g. authentication tag failure, malformed ciphertext, premature stream close), poorly designed exception paths may leave the plaintext DEK buffer in memory indefinitely.
4. Subsequent memory heap dumps, error reports, core dumps, or garbage collection stalls could expose plaintext DEKs.

---

## 2. Phase 20.19 Implementation: Best-Effort Clearing in `finally` Blocks

In `backend/src/services/pilot_cryptographic_isolation_v19.ts` and `backend/src/services/vault_decryption_service_v18.ts`:

### 2.1 Pattern Specification
```typescript
let plaintextDek: Buffer | null = null;
try {
  // 1. Unwrap DEK into owned Buffer
  plaintextDek = Buffer.alloc(rawDek.length);
  rawDek.copy(plaintextDek);

  // 2. Decrypt with Decipheriv
  const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
  decipher.setAAD(aad);
  decipher.setAuthTag(authTag);

  decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return { templateId: record.templateId, embedding };
} finally {
  // 3. Best-Effort Buffer Clearing
  if (plaintextDek) {
    plaintextDek.fill(0);
  }
}
```

### 2.2 Strict Invariants
- **Success Path Clearing:** After decryption and embedding extraction, `plaintextDek.fill(0)` executes immediately in the `finally` block before returning.
- **Exception Path Clearing:** If `decipher.final()` fails due to an invalid authentication tag or corrupted ciphertext, control routes through `finally`, ensuring `plaintextDek.fill(0)` executes prior to bubbling the exception.
- **Prohibition Against Retention:** Plaintext DEKs are never assigned to class properties, never logged to stdout/stderr, never cached in memory tables, and never passed across asynchronous boundaries.

---

## 3. Honest Runtime Realities & The Six Memory Limitations

> [!WARNING]
> ### Correction of Terminology: Best-Effort Clearing vs Complete Zeroization
> All previous claims of "guaranteed memory zeroization" or "complete zeroization" are formally withdrawn.
> **Kelasagara does not claim complete memory zeroization.**
> In high-level managed runtimes such as Node.js (V8) running on modern operating systems and flash media, complete hardware-level zeroization is impossible. The architecture strictly implements **best-effort in-memory clearing of mutable, application-owned Buffers via `plaintextDek.fill(0)` and `crypto.randomFillSync()` in `finally` blocks**.
>
> The following six fundamental technical limitations are formally acknowledged:
> 1. **Immutable JavaScript Strings:** JavaScript primitives (strings) in V8 are strictly immutable. If a key or token is represented as or converted to a string, V8 allocates it in immutable heap memory that cannot be modified or zeroed in-place.
> 2. **V8 Managed Memory:** The V8 engine allocates memory within dynamic heap spaces (New Space, Old Pointer Space, Large Object Space). Objects and buffers are subject to pointer relocation and internal memory fragmentation outside application control.
> 3. **Garbage Collection and Memory Copying:** V8's generational garbage collector (Orinoco / Scavenger) copies live objects between "From" and "To" semispace during young-generation collections. These copying routines can leave transient, unzeroed replicas of memory buffers in abandoned heap regions until subsequent memory sweeps occur.
> 4. **Native Cryptographic Library Allocations:** The Node.js native `crypto` module invokes OpenSSL / BoringSSL through C++ FFI bindings. Internal cipher contexts (`EVP_CIPHER_CTX`), expanded key schedules, and intermediate authentication state are allocated on the native C-heap outside V8's direct Buffer control.
> 5. **Operating System Memory and Swap:** Under physical memory pressure, the OS kernel virtual memory manager may page dirty memory frames (including process heap buffers) to disk swap space (`pagefile.sys`, swap partitions). Disk-swapped pages remain outside process-space control and cannot be zeroed by `Buffer.fill(0)`.
> 6. **Solid-State Drive (SSD) Wear-Levelling:** When memory pages swapped to disk or temporary disk files are unlinked, modern flash controllers use wear-leveling translation layers (FTL) to remap logical sectors across physical NAND flash cells. Software overwrite passes write to newly remapped physical blocks, leaving data remnants in original physical cells until TRIM and controller garbage collection cycles execute.
>
> **Definitive Standard:** Kelasagara accurately classifies all in-memory clearing routines as **best-effort clearing of owned plaintext buffers in `finally` blocks**, representing the highest achievable security posture in a managed Node.js environment without physical hardware zeroization guarantees.

---

## 4. Test Evidence

Track D of `phase20_19_pilot_gate_a_closure.test.ts` validates:
- **Test 24:** `plaintextDek` buffer is cleared with `fill(0)` upon successful decryption (PASS).
- **Test 25:** `plaintextDek` buffer is cleared with `fill(0)` in `finally` block even when decipher tag authentication fails (PASS).
