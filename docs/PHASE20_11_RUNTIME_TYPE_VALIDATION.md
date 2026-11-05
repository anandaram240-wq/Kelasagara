# PHASE 20.11: RUNTIME SAFETY OF CANONICAL FACE TYPES
**Role:** Senior TypeScript Backend Engineer & Application Security Specialist  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. THREAT MODEL & COMPILE-TIME VS RUNTIME BOUNDARIES

In TypeScript, nominal branding (`type CanonicalAlignedFace112 = Buffer & { readonly __brand: unique symbol }`) enforces type safety at compile time. However:
1. In compiled JavaScript, branded nominal types vanish completely.
2. An upstream caller or rogue module could bypass compile-time checks using an `as any` or `as unknown as CanonicalAlignedFace112` cast.
3. If an unaligned camera frame, corrupted image, or degenerate solid buffer is cast and passed into `extractCanonicalEmbeddingFromAligned112`, the ONNX model would execute without error, producing an unaligned embedding.

---

## 2. THE RUNTIME FACTORY & DEFENSIVE VALIDATOR

To permanently close this loophole, Phase 20.11 implemented `CanonicalAlignedFace112Factory`:

```typescript
export class CanonicalAlignedFace112Factory {
  public static readonly EXPECTED_BYTE_LENGTH = 112 * 112 * 3; // 37,632 bytes

  public static validateBuffer(
    buffer: unknown,
    options?: { checkStrictUniformity?: boolean; minVariance?: number }
  ): { valid: boolean; reason?: string } {
    if (!Buffer.isBuffer(buffer)) {
      return { valid: false, reason: 'INPUT_NOT_BUFFER: Provided input is not a Buffer instance.' };
    }
    if (buffer.length !== CanonicalAlignedFace112Factory.EXPECTED_BYTE_LENGTH) {
      return {
        valid: false,
        reason: `INVALID_BYTE_LENGTH: Expected ${CanonicalAlignedFace112Factory.EXPECTED_BYTE_LENGTH} bytes, got ${buffer.length}.`,
      };
    }

    let minVal = 255;
    let maxVal = 0;
    let sum = 0;
    const len = buffer.length;

    for (let i = 0; i < len; i++) {
      const v = buffer[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
      sum += v;
    }

    if (minVal === 0 && maxVal === 0) {
      return { valid: false, reason: 'DEGENERATE_UNIFORM_BUFFER: Buffer is completely zeroed (all pixels = 0).' };
    }

    if (minVal === 255 && maxVal === 255) {
      return { valid: false, reason: 'DEGENERATE_UNIFORM_BUFFER: Buffer is completely saturated (all pixels = 255).' };
    }

    if (options?.checkStrictUniformity && minVal === maxVal) {
      return { valid: false, reason: `DEGENERATE_UNIFORM_BUFFER: Buffer is completely uniform (all pixels = ${minVal}).` };
    }

    if (options?.minVariance !== undefined) {
      const mean = sum / len;
      let varSum = 0;
      for (let i = 0; i < len; i++) {
        const diff = buffer[i] - mean;
        varSum += diff * diff;
      }
      const variance = varSum / len;
      if (variance < options.minVariance) {
        return { valid: false, reason: `INSUFFICIENT_VARIANCE: Pixel variance (${variance.toFixed(4)}) is below threshold (${options.minVariance}).` };
      }
    }

    return { valid: true };
  }

  public static create(buffer: Buffer): CanonicalAlignedFace112 {
    const check = CanonicalAlignedFace112Factory.validateBuffer(buffer);
    if (!check.valid) {
      throw new BiometricPreprocessingError(
        'CANONICAL_EMBEDDING_FAILED',
        `Runtime validation failed for CanonicalAlignedFace112: ${check.reason}`
      );
    }
    return buffer as CanonicalAlignedFace112;
  }
}
```

---

## 3. MANDATORY RUNTIME ENFORCEMENT

Inside `extractCanonicalEmbeddingFromAligned112`:
```typescript
const validation = CanonicalAlignedFace112Factory.validateBuffer(aligned112ImageBuffer);
if (!validation.valid) {
  throw new BiometricPreprocessingError(
    'CANONICAL_EMBEDDING_FAILED',
    `extractCanonicalEmbeddingFromAligned112 strictly requires a pre-aligned 112x112x3 RGB buffer. Runtime validation rejected input: ${validation.reason}.`
  );
}
```

Even if an attacker uses `extractCanonicalEmbeddingFromAligned112(rawSceneBuffer as any)`, the execution fails closed with a typed `BiometricPreprocessingError` before reaching the neural inference engine.
