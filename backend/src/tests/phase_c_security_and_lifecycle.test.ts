// backend/src/tests/phase_c_security_and_lifecycle.test.ts
import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert";
import crypto from "crypto";
import { DeviceAttestationService } from "../services/device_attestation";
import { AccountLifecycleService } from "../services/account_lifecycle";
import { PresentationAttackDefenseService } from "../services/presentation_attack_defense";
import { InMemoryBiometricIndex } from "../services/in_memory_biometric_index";
import { FirestoreBiometricRepository } from "../services/firestore_biometric_repository";
import { l2Normalize } from "../services/biometric_matching";
import { AuditService } from "../services/audit_service";

describe("PHASE C HARDENING: Device Attestation, Lifecycle, PAD & In-Memory Index", () => {
  // ── 1. DEVICE ATTESTATION & FRAME PROVENANCE ─────────────────────────────
  describe("1. Device Attestation & Frame Provenance (Finding F2 / Invariants I-25, I-26)", () => {
    it("should accept valid device attestation tokens", () => {
      const res = DeviceAttestationService.verifyDeviceIntegrity("mock_play_integrity_device");
      assert.strictEqual(res.isValid, true);
      assert.strictEqual(res.verdict, "MEETS_DEVICE_INTEGRITY");
    });

    it("should detect and reject emulator / hooking signatures", () => {
      const res = DeviceAttestationService.verifyDeviceIntegrity("test_emulator_hook_frida");
      assert.strictEqual(res.isValid, false);
      assert.strictEqual(res.verdict, "EMULATOR_HOOKING_DETECTED");
      assert.match(res.reason || "", /hooking or emulator/i);
    });

    it("should reject missing attestation token when dev bypass is disabled", () => {
      const res = DeviceAttestationService.verifyDeviceIntegrity(undefined, false);
      assert.strictEqual(res.isValid, false);
      assert.strictEqual(res.verdict, "EMULATOR_HOOKING_DETECTED");
    });

    it("should allow dev bypass when explicitly enabled in config", () => {
      const res = DeviceAttestationService.verifyDeviceIntegrity(undefined, true);
      assert.strictEqual(res.isValid, true);
      assert.strictEqual(res.verdict, "UNATTESTED_DEV_ENVIRONMENT");
    });

    it("should verify genuine frame provenance matching SHA-256 and session nonce", () => {
      const frameBuffer = Buffer.alloc(100, 42);
      const sha256 = crypto.createHash("sha256").update(frameBuffer).digest("hex");
      const nonce = "chal_valid_session_nonce_123";

      const provRes = DeviceAttestationService.verifyFrameProvenance(
        frameBuffer,
        {
          challengeNonce: nonce,
          captureTimestampMs: Date.now() - 500, // 500ms ago
          deviceId: "device_hardware_uuid_999",
          cameraLens: "front",
          frameSha256: sha256,
        },
        nonce
      );

      assert.strictEqual(provRes.isValid, true);
    });

    it("should reject frame provenance on hash mismatch (Virtual Camera Injection)", () => {
      const frameBuffer = Buffer.alloc(100, 42);
      const nonce = "chal_valid_session_nonce_123";

      const provRes = DeviceAttestationService.verifyFrameProvenance(
        frameBuffer,
        {
          challengeNonce: nonce,
          captureTimestampMs: Date.now() - 500,
          deviceId: "device_hardware_uuid_999",
          cameraLens: "front",
          frameSha256: "tampered_injected_frame_hash_00000000000000000000000000000000",
        },
        nonce
      );

      assert.strictEqual(provRes.isValid, false);
      assert.match(provRes.failureReason || "", /hash mismatch/i);
    });

    it("should reject frame provenance on expired capture timestamp (Pre-recorded Video Replay)", () => {
      const frameBuffer = Buffer.alloc(100, 42);
      const sha256 = crypto.createHash("sha256").update(frameBuffer).digest("hex");
      const nonce = "chal_valid_session_nonce_123";

      const provRes = DeviceAttestationService.verifyFrameProvenance(
        frameBuffer,
        {
          challengeNonce: nonce,
          captureTimestampMs: Date.now() - 120 * 1000, // 2 minutes ago (> 60s TTL)
          deviceId: "device_hardware_uuid_999",
          cameraLens: "front",
          frameSha256: sha256,
        },
        nonce
      );

      assert.strictEqual(provRes.isValid, false);
      assert.match(provRes.failureReason || "", /timestamp expired/i);
    });
  });

  // ── 2. ACCOUNT LIFECYCLE & RENTAL DEFENSE ────────────────────────────────
  describe("2. Account Lifecycle & Shift Re-Verification (Finding F4 / Invariants I-27, I-28)", () => {
    const mockUid = "worker_lifecycle_test_01";
    let mockEnrolledVector: number[];

    before(() => {
      mockEnrolledVector = l2Normalize(Array.from({ length: 128 }, (_, i) => Math.sin(i + 1)));

      // Mock Firestore repository getEnrolledTemplate
      FirestoreBiometricRepository.getEnrolledTemplate = async (uid: string) => {
        if (uid === mockUid) return mockEnrolledVector;
        return null;
      };

      // Mock Firestore users collection
      const mockUserData: Record<string, any> = {
        shiftExpiresAt: 0,
        boundDeviceId: "device_authorized_pixel_01",
        lastLocation: { latitude: 12.9716, longitude: 77.5946 }, // Bangalore
        lastLocationTimestamp: Date.now() - 1000 * 60 * 60, // 1 hour ago
      };

      const mockDocRef = {
        get: async () => ({
          exists: true,
          data: () => mockUserData,
        }),
        update: async (fields: any) => {
          Object.assign(mockUserData, fields);
        },
      };

      const mockDb = {
        collection: (name: string) => ({
          doc: (docId: string) => mockDocRef,
        }),
      };

      Object.defineProperty(AccountLifecycleService, "db", {
        get: () => mockDb,
        configurable: true,
      });

      // Mock AuditService to prevent unmocked Firestore writes
      (AuditService as any).logEvent = async () => null;
    });

    it("should report requiresReverification when shift is inactive", async () => {
      const status = await AccountLifecycleService.getShiftStatus(mockUid);
      assert.strictEqual(status.isShiftActive, false);
      assert.strictEqual(status.requiresReverification, true);
    });

    it("should reject re-verification when mock GPS is detected", async () => {
      const res = await AccountLifecycleService.reVerifyWorker({
        uid: mockUid,
        probeEmbedding: mockEnrolledVector,
        deviceId: "device_authorized_pixel_01",
        isMockGps: true,
      });

      assert.strictEqual(res.success, false);
      assert.match(res.message, /Mock GPS location provider detected/i);
    });

    it("should successfully re-verify worker and activate 10h shift", async () => {
      const res = await AccountLifecycleService.reVerifyWorker({
        uid: mockUid,
        probeEmbedding: mockEnrolledVector, // Exact match
        deviceId: "device_authorized_pixel_01",
        latitude: 12.9720,
        longitude: 77.5950,
      });

      assert.strictEqual(res.success, true);
      assert.strictEqual(res.isMatch, true);
      assert.strictEqual(res.shiftActive, true);
      assert.strictEqual(res.requiresDeviceChallenge, false);

      const status = await AccountLifecycleService.getShiftStatus(mockUid);
      assert.strictEqual(status.isShiftActive, true);
      assert.strictEqual(status.requiresReverification, false);
    });

    it("should flag untrusted device switch (Account Sharing / Rental risk)", async () => {
      const res = await AccountLifecycleService.reVerifyWorker({
        uid: mockUid,
        probeEmbedding: mockEnrolledVector,
        deviceId: "different_untrusted_device_xyz",
      });

      assert.strictEqual(res.success, true);
      assert.strictEqual(res.requiresDeviceChallenge, true); // Flagged for step-up!
    });
  });

  // ── 3. PRESENTATION ATTACK DETECTION (PAD) ──────────────────────────────
  describe("3. Presentation Attack Detection (Finding F3 / Invariants I-29, I-30)", () => {
    it("should issue randomized multi-action interactive challenge", () => {
      const chal = PresentationAttackDefenseService.issueChallenge("test_user_pad_01");
      assert.ok(chal.challengeId.startsWith("liveness_"));
      assert.ok(chal.actionSequence.length >= 2);
      assert.ok(chal.expiresAt > Date.now());
    });

    it("should reject static 2D photograph with zero landmark motion (Invariant I-30)", () => {
      const chal = PresentationAttackDefenseService.issueChallenge("test_user_pad_static");

      // Frame sequence with identical coordinates (static printed paper)
      const staticFrames = [
        { timestampMs: 1000, noseTip: { x: 50, y: 50 } },
        { timestampMs: 1500, noseTip: { x: 50, y: 50 } },
        { timestampMs: 2000, noseTip: { x: 50, y: 50 } },
      ];

      const res = PresentationAttackDefenseService.verifyChallenge({
        challengeId: chal.challengeId,
        uid: "test_user_pad_static",
        frames: staticFrames,
      });

      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.attackTypeDetected, "STATIC_2D_PHOTO");
      assert.match(res.failureReason || "", /Zero physical motion detected/i);
    });

    it("should verify dynamic interactive gestures across moving frames", () => {
      const chal = PresentationAttackDefenseService.issueChallenge("test_user_pad_live");

      // Dynamic frames with natural motion, eye blink (EAR drop), and head turn
      const dynamicFrames = [
        {
          timestampMs: 1000,
          noseTip: { x: 50, y: 50 },
          leftEyeUpper: { x: 30, y: 40 },
          leftEyeLower: { x: 30, y: 46 }, // open: h=6
          leftMouthCorner: { x: 40, y: 80 },
          rightMouthCorner: { x: 60, y: 80 },
          yawDegrees: 0,
        },
        {
          timestampMs: 1500,
          noseTip: { x: 52, y: 51 },
          leftEyeUpper: { x: 30, y: 43 },
          leftEyeLower: { x: 30, y: 44 }, // closed: h=1 (blink)
          leftMouthCorner: { x: 38, y: 80 },
          rightMouthCorner: { x: 63, y: 80 }, // smile: w=25 (+25%)
          yawDegrees: -15, // turn left
        },
        {
          timestampMs: 2000,
          noseTip: { x: 55, y: 53 },
          leftEyeUpper: { x: 30, y: 40 },
          leftEyeLower: { x: 30, y: 46 }, // open again
          leftMouthCorner: { x: 38, y: 80 },
          rightMouthCorner: { x: 64, y: 80 },
          yawDegrees: 15, // turn right
        },
      ];

      const res = PresentationAttackDefenseService.verifyChallenge({
        challengeId: chal.challengeId,
        uid: "test_user_pad_live",
        frames: dynamicFrames,
      });

      assert.strictEqual(res.passed, true);
      assert.ok(res.score >= 80);
      assert.strictEqual(res.actionBreakdown.length, chal.actionSequence.length);
    });
  });

  // ── 4. IN-MEMORY BIOMETRIC INDEX ─────────────────────────────────────────
  describe("4. In-Memory Biometric Deduplication Index (Finding F8 / Invariant I-31)", () => {
    beforeEach(() => {
      InMemoryBiometricIndex.clear();
    });

    it("should upsert and retrieve nearest neighbor in RAM", () => {
      const v1 = l2Normalize([1, 0, 0, ...new Array(125).fill(0)]);
      const v2 = l2Normalize([0.9, 0.1, 0, ...new Array(125).fill(0)]);
      const v3 = l2Normalize([0, 1, 0, ...new Array(125).fill(0)]);

      InMemoryBiometricIndex.upsert({
        uid: "user_a",
        embedding: v1,
        modelId: "sface_opencv_zoo_v1_primary",
        preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
        phoneNumber: "+919888811111",
        enrolledAtMs: Date.now(),
      });

      InMemoryBiometricIndex.upsert({
        uid: "user_b",
        embedding: v3,
        modelId: "sface_opencv_zoo_v1_primary",
        preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
        phoneNumber: "+919888822222",
        enrolledAtMs: Date.now(),
      });

      assert.strictEqual(InMemoryBiometricIndex.size(), 2);

      // Probe near user_a
      const topK = InMemoryBiometricIndex.findTopK(v2, "probe_uid", 2);
      assert.strictEqual(topK.length, 2);
      assert.strictEqual(topK[0].uid, "user_a");
      assert.ok(topK[0].similarity > 0.95);
      assert.strictEqual(topK[1].uid, "user_b");
    });

    it("should filter out templates from different models or preprocessing (Invariant I-06)", () => {
      const v1 = l2Normalize([1, 0, 0, ...new Array(125).fill(0)]);

      InMemoryBiometricIndex.upsert({
        uid: "user_diff_model",
        embedding: v1,
        modelId: "legacy_model_v0",
        preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
        phoneNumber: "+919888833333",
        enrolledAtMs: Date.now(),
      });

      const topK = InMemoryBiometricIndex.findTopK(v1, "probe_uid", 1);
      assert.strictEqual(topK.length, 0, "Cross-model candidates must be filtered out in RAM");
    });

    it("should cleanly remove deleted templates on DPDPA erasure", () => {
      const v1 = l2Normalize([1, 0, 0, ...new Array(125).fill(0)]);

      InMemoryBiometricIndex.upsert({
        uid: "user_to_delete",
        embedding: v1,
        modelId: "sface_opencv_zoo_v1_primary",
        preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
        phoneNumber: "+919888844444",
        enrolledAtMs: Date.now(),
      });

      assert.strictEqual(InMemoryBiometricIndex.size(), 1);
      const deleted = InMemoryBiometricIndex.delete("user_to_delete");
      assert.strictEqual(deleted, true);
      assert.strictEqual(InMemoryBiometricIndex.size(), 0);
    });
  });
});
