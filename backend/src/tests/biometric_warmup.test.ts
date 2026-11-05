// backend/src/tests/biometric_warmup.test.ts
import assert from "assert";
import { describe, it } from "node:test";
import admin from "firebase-admin";
import { InMemoryBiometricIndex } from "../services/in_memory_biometric_index";
import { warmUpBiometricIndex } from "../services/biometric_enrollment";
import { l2Normalize } from "../services/biometric_matching";

describe("FIRESTORE WARM-UP & IN-MEMORY BIOMETRIC INDEX TESTS", () => {
  it("should query Firestore biometric_vault, populate InMemoryBiometricIndex, and verify idempotency", async () => {
    InMemoryBiometricIndex.clear();

    const v1 = l2Normalize(new Array(128).fill(0).map((_, i) => Math.sin(i)));
    const v2 = l2Normalize(new Array(128).fill(0).map((_, i) => Math.cos(i)));
    const v3 = l2Normalize(new Array(128).fill(0).map((_, i) => (i % 2 === 0 ? 0.1 : -0.1)));

    const mockDocs = [
      {
        id: "warmup_user_1",
        data: () => ({
          uid: "warmup_user_1",
          embedding: v1,
          modelId: "sface_opencv_zoo_v1_primary",
          preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
          phoneNumber: "+919876543210",
          enrolledAt: { toMillis: () => 1700000000000 },
        }),
      },
      {
        id: "warmup_user_2",
        data: () => ({
          uid: "warmup_user_2",
          embedding: { toArray: () => v2 },
          modelId: "sface_opencv_zoo_v1_primary",
          preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
          phoneNumber: "+919876543211",
          enrolledAtMs: 1700000005000,
        }),
      },
      {
        id: "warmup_user_3",
        data: () => ({
          uid: "warmup_user_3",
          embedding: { _values: v3 },
          modelId: "sface_opencv_zoo_v1_primary",
          preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
          phoneNumber: "+919876543212",
          enrolledAt: { seconds: 1700000010 },
        }),
      },
      {
        id: "warmup_user_invalid",
        data: () => ({
          uid: "warmup_user_invalid",
          embedding: [],
          phoneNumber: "+919876543213",
        }),
      },
    ];

    const mockDb = {
      collection: (colName: string) => {
        assert.strictEqual(colName, "biometric_vault");
        return {
          get: async () => ({
            docs: mockDocs,
          }),
        };
      },
    };

    const proto = Object.getPrototypeOf(admin);
    const origDesc = Object.getOwnPropertyDescriptor(proto, "firestore");

    Object.defineProperty(proto, "firestore", {
      value: () => mockDb,
      configurable: true,
      writable: true,
    });

    try {
      // 1. Initial warm-up
      await warmUpBiometricIndex();
      assert.strictEqual(InMemoryBiometricIndex.size(), 3, "Should load 3 valid templates");

      const topCandidates = InMemoryBiometricIndex.findTopK(v1, "some_other_uid", 1);
      assert.strictEqual(topCandidates.length, 1);
      assert.strictEqual(topCandidates[0].uid, "warmup_user_1");
      assert.ok(topCandidates[0].similarity > 0.999);

      // 2. Second warm-up (idempotency check)
      await warmUpBiometricIndex();
      assert.strictEqual(InMemoryBiometricIndex.size(), 3, "Idempotent warm-up must not duplicate templates");
    } finally {
      if (origDesc) {
        Object.defineProperty(proto, "firestore", origDesc);
      }
      InMemoryBiometricIndex.clear();
    }
  });
});
