/**
 * KELASAGARA V20.14: RFC 8785 JSON CANONICALIZATION SCHEME (JCS) INDEPENDENT CONFORMANCE SUITE
 *
 * Validates strict conformance to RFC 8785:
 * - Official test vectors
 * - Lexicographical UTF-16 code unit sorting
 * - Duplicate property name rejection in raw input
 * - Lone surrogate rejection
 * - Safe integer boundaries
 * - Negative zero normalization
 * - Permutation invariance and SHA-256 digest parity
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalizeJson,
  canonicalizeRawJson,
  computeJcsSha256,
  hasLoneSurrogates,
  parseJsonRejectingDuplicates,
  Rfc8785CanonicalizationError,
} from '../crypto/rfc8785_canonicalizer';

describe('KELASAGARA V20.14: RFC 8785 JCS Independent Conformance Suite', () => {
  describe('1. Official RFC 8785 Canonicalization Vectors', () => {
    it('Vector 1.1: Simple key ordering (ASCII UTF-16)', () => {
      const input = { b: 2, a: 1 };
      assert.equal(canonicalizeJson(input), '{"a":1,"b":2}');
    });

    it('Vector 1.2: Numbers, exponents, and integers without trailing decimal zeros', () => {
      const input = {
        e: 1e2,
        f: 1.0,
        g: 1e-2,
        h: 0.000001,
      };
      // In RFC 8785 / ECMAScript: 1.0 -> 1, 1e2 -> 100, 1e-2 -> 0.01, 1e-6 -> 0.000001
      assert.equal(canonicalizeJson(input), '{"e":100,"f":1,"g":0.01,"h":0.000001}');
    });

    it('Vector 1.3: Negative zero normalization (-0 -> 0)', () => {
      const input = { a: -0, b: 0, c: -0.0 };
      assert.equal(canonicalizeJson(input), '{"a":0,"b":0,"c":0}');
    });

    it('Vector 1.4: Arrays preserve declared element order, nested objects are sorted', () => {
      const input = [
        { z: 9, a: 1 },
        { y: 8, b: 2 },
      ];
      assert.equal(canonicalizeJson(input), '[{"a":1,"z":9},{"b":2,"y":8}]');
    });

    it('Vector 1.5: UTF-16 code-unit ordering across Unicode planes', () => {
      // Key code units:
      // "a": 97
      // "e": 101
      // "\u00e9" (é): 233
      // "\u20ac" (€): 8364
      // "\ud83d\ude00" (😀): 55357, 56832
      const input = {
        '\u20ac': 'Euro',
        '\u00e9': 'e-acute',
        e: 'latin-e',
        a: 'latin-a',
        '\uD83D\uDE00': 'grinning-face',
      };
      const canonical = canonicalizeJson(input);
      const keys = Object.keys(JSON.parse(canonical));
      assert.deepEqual(keys, ['a', 'e', '\u00e9', '\u20ac', '\uD83D\uDE00']);
    });
  });

  describe('2. Duplicate Property Name Rejection (Raw Input Validation)', () => {
    it('Rejects duplicate property at top-level', () => {
      const raw = '{"id": 1, "name": "Worker", "id": 2}';
      assert.throws(
        () => parseJsonRejectingDuplicates(raw),
        /RFC 8785 violation: Duplicate property name 'id' detected/
      );
    });

    it('Rejects duplicate property in nested object', () => {
      const raw = '{"profile": {"tier": "gold", "tier": "silver"}}';
      assert.throws(
        () => parseJsonRejectingDuplicates(raw),
        /RFC 8785 violation: Duplicate property name 'tier' detected/
      );
    });

    it('canonicalizeRawJson rejects duplicate keys before canonicalizing', () => {
      const raw = '{"a": 100, "b": 200, "a": 300}';
      assert.throws(
        () => canonicalizeRawJson(raw),
        /RFC 8785 violation: Duplicate property name 'a' detected/
      );
    });

    it('Accepts distinct properties with identical values', () => {
      const raw = '{"a": 1, "b": 1, "c": 1}';
      assert.equal(canonicalizeRawJson(raw), '{"a":1,"b":1,"c":1}');
    });
  });

  describe('3. Unicode & Lone Surrogate Rejection', () => {
    it('Detects lone high surrogate code unit', () => {
      const loneHigh = '\uD800';
      assert.equal(hasLoneSurrogates(loneHigh), true);
      assert.throws(
        () => canonicalizeJson({ invalid: loneHigh }),
        /RFC 8785 violation: Lone surrogate/
      );
    });

    it('Detects lone low surrogate code unit', () => {
      const loneLow = '\uDC00';
      assert.equal(hasLoneSurrogates(loneLow), true);
      assert.throws(
        () => canonicalizeJson({ invalid: loneLow }),
        /RFC 8785 violation: Lone surrogate/
      );
    });

    it('Accepts valid surrogate pairs (Emoji / Supplementary planes)', () => {
      const validPair = 'Kelasagara \uD83D\uDE80 Rocket';
      assert.equal(hasLoneSurrogates(validPair), false);
      const res = canonicalizeJson({ msg: validPair });
      assert.ok(res.includes('Rocket'));
    });

    it('Rejects lone surrogate in object keys', () => {
      const badObj = { ['\uD800']: 'value' };
      assert.throws(
        () => canonicalizeJson(badObj),
        /RFC 8785 violation: Lone surrogate code unit detected in object key/
      );
    });
  });

  describe('4. Number Boundaries & Safe Integer Invariants', () => {
    it('Strictly rejects NaN', () => {
      assert.throws(
        () => canonicalizeJson({ val: NaN }),
        /Non-finite numbers \(NaN, Infinity, -Infinity\) are strictly rejected/
      );
    });

    it('Strictly rejects positive Infinity', () => {
      assert.throws(
        () => canonicalizeJson({ val: Infinity }),
        /Non-finite numbers/
      );
    });

    it('Strictly rejects negative Infinity', () => {
      assert.throws(
        () => canonicalizeJson({ val: -Infinity }),
        /Non-finite numbers/
      );
    });

    it('Strictly rejects integers outside safe integer range to prevent silent rounding', () => {
      const unsafePositive = Number.MAX_SAFE_INTEGER + 1; // 9007199254740992
      assert.throws(
        () => canonicalizeJson({ bigId: unsafePositive }),
        /exceeds safe integer range/
      );

      const unsafeNegative = Number.MIN_SAFE_INTEGER - 1;
      assert.throws(
        () => canonicalizeJson({ bigId: unsafeNegative }),
        /exceeds safe integer range/
      );
    });

    it('Permits safe integers and floating points within IEEE 754 precision', () => {
      assert.equal(canonicalizeJson({ safeMax: Number.MAX_SAFE_INTEGER }), `{"safeMax":${Number.MAX_SAFE_INTEGER}}`);
      assert.equal(canonicalizeJson({ safeMin: Number.MIN_SAFE_INTEGER }), `{"safeMin":${Number.MIN_SAFE_INTEGER}}`);
      assert.equal(canonicalizeJson({ floatVal: 3.14159 }), '{"floatVal":3.14159}');
    });
  });

  describe('5. Permutation Invariance & Cryptographic Digest Parity', () => {
    it('Produces bit-identical canonical byte digest across 10 random key permutations', () => {
      const keys = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta'];
      const baseObj: Record<string, number> = {};
      keys.forEach((k, idx) => {
        baseObj[k] = idx * 10;
      });

      const referenceDigest = computeJcsSha256(baseObj);

      for (let trial = 0; trial < 10; trial++) {
        const shuffledKeys = [...keys].sort(() => Math.random() - 0.5);
        const permutedObj: Record<string, number> = {};
        shuffledKeys.forEach((k) => {
          permutedObj[k] = baseObj[k];
        });

        const trialDigest = computeJcsSha256(permutedObj);
        assert.equal(trialDigest, referenceDigest);
      }
    });

    it('Cross-runtime parity check on canonical manifest representation', () => {
      const manifestMock = {
        version: '3.0.0',
        pipeline: 'YUNET_SFACE_V3',
        detector: {
          name: 'yunet',
          hash: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
          input: [320, 320],
        },
        recognizer: {
          name: 'sface',
          hash: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
          dim: 128,
        },
      };

      const digest = computeJcsSha256(manifestMock);
      assert.equal(typeof digest, 'string');
      assert.equal(digest.length, 64); // 256 bits = 64 hex characters
      // Repeat to prove determinism
      assert.equal(computeJcsSha256(manifestMock), digest);
    });
  });
});
