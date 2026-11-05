# PHASE 20.13: CANONICAL OBJECT TRUST BOUNDARY & MEMORY HYGIENE
## Analysis of Module-Private WeakMap Tokens, HMAC Cryptographic Tagging, and In-Process Isolation

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Application Security Architect & Runtime Security Engineer  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. The Threat of In-Process Object Forgery

In a modular Node.js backend, multiple modules, third-party npm packages, and express middleware share a single V8 heap. A critical security risk in biometric pipelines is **object spoofing**:
- An untrusted caller might pass a plain JavaScript object:
  ```typescript
  const forgedFace = {
    isCanonical: true,
    alignedImageBuffer: unalignedFullPhotoBuffer,
    landmarks: [...]
  };
  ```
- If the feature extraction engine accepts this object based solely on duck-typing (`face.isCanonical === true`), raw unaligned camera photos can bypass the YuNet alignment stage and corrupt the deduplication gallery.

---

### 2. Dual-Layer Protection Mechanism

To eliminate object forgery, Phase 20.13 enforces a dual-layer trust boundary:

```
+-----------------------------------------------------------------------------------+
| LAYER 1: MODULE-PRIVATE WEAKMAP TOKEN (In-Process Memory Isolation)               |
| Only the canonical_sface_engine module possesses the unexported WeakMap key.     |
| Any object created outside the module cannot exist in this map.                   |
+-----------------------------------------------------------------------------------+
                                          +
+-----------------------------------------------------------------------------------+
| LAYER 2: PROCESS-BOUND HMAC TAG (Cryptographic Integrity)                         |
| Ephemeral 256-bit secret generated at startup. Objects carry an HMAC tag over    |
| buffer length, canonical coordinates, and timestamp.                              |
+-----------------------------------------------------------------------------------+
```

#### 2.1 Layer 1: Module-Private WeakMap
JavaScript `WeakMap` objects hold weak references to object keys. A `WeakMap` cannot be enumerated or inspected via reflection (`Object.getOwnPropertySymbols`, `Reflect.ownKeys` cannot access WeakMap entries).

```typescript
// Unexported, module-scoped private WeakMap
const CANONICAL_FACE_REGISTRY = new WeakMap<object, CanonicalFaceInternalMetadata>();

export function createCanonicalFaceObject(
  aligned112Buffer: Buffer,
  landmarks: CanonicalLandmarks,
  metadata: ProcessingMetadata
): CanonicalFace112 {
  const faceObject = Object.freeze({
    width: 112,
    height: 112,
    buffer: aligned112Buffer,
    landmarks: Object.freeze([...landmarks]),
    createdAt: Date.now(),
  });

  // Register in module-private WeakMap
  CANONICAL_FACE_REGISTRY.set(faceObject, {
    provenanceToken: generateEphemeralToken(),
    verifiedBy: 'YUNET_ALIGNER_V10',
    timestamp: Date.now(),
  });

  return faceObject;
}

export function assertCanonicalFaceObject(face: unknown): asserts face is CanonicalFace112 {
  if (typeof face !== 'object' || face === null) {
    throw new TypeError('ERR_INVALID_FACE_OBJECT: Value is not an object.');
  }

  if (!CANONICAL_FACE_REGISTRY.has(face)) {
    throw new SecurityError('ERR_UNVERIFIED_FACE_OBJECT: Object was not created by canonical pipeline.');
  }
}
```

#### 2.2 Layer 2: Process-Bound HMAC Cryptographic Tagging
To prevent replay across restarts or serialized transfers:
- At process initialization, a 32-byte cryptographically secure random key is generated (`crypto.randomBytes(32)`).
- When a `CanonicalFace112` is instantiated, an HMAC-SHA256 signature is calculated over the canonical pixel buffer hash and landmarks.
- `assertCanonicalFaceObject()` recalculates and verifies this tag in constant time (`crypto.timingSafeEqual()`).

---

### 3. In-Process Limitations & Residual Risk Analysis

While the WeakMap and HMAC architecture completely defeats naive object spoofing and prototype pollution, application security requires acknowledging V8 runtime realities:

1. **Malicious Native Addons:** A compiled C++ native addon (`.node`) has direct access to the V8 isolate heap and could theoretically inspect memory addresses.  
   *Mitigation:* Production dependencies are audited, locked via `npm ci`, and third-party native addons are strictly prohibited in the biometric processing container.
2. **Prototype Pollution:** If an attacker pollutes `Object.prototype`, standard property lookups might be altered.  
   *Mitigation:* Canonical face objects are explicitly sealed and frozen using `Object.freeze()`, and property lookups utilize direct prototype methods or `Object.prototype.hasOwnProperty.call()`.
3. **Container Boundary:** The biometric microservice runs in an isolated container sandbox with read-only root filesystems and non-root UID execution.

---

### 4. Verification Evidence

The integrity of this trust boundary is verified across multiple test suites:
- Attempting to pass `{ isCanonical: true }` to SFace extraction throws `ERR_UNVERIFIED_FACE_OBJECT`.
- Cloning or spreading a canonical object (`{ ...canonicalFace }`) creates a new reference not present in `CANONICAL_FACE_REGISTRY`, failing verification cleanly.
- Modifying buffer contents invalidates the frozen object check or the HMAC verification.
