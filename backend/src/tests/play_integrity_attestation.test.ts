// backend/src/tests/play_integrity_attestation.test.ts
/**
 * Test Suite: Google Play Integrity Device Attestation & Request Hash Binding (Stage S8 / Work Package S8-B).
 *
 * Exercises:
 * - Canonical requestHash = SHA-256(nonce || uid || action || captureDigest) computation & verification.
 * - Package name enforcement: com.kelasagara.app vs attacker spoofed package names.
 * - Token freshness & expiration enforcement (<= 180,000 ms).
 * - Multi-tier integrity verdicts: MEETS_STRONG_INTEGRITY, MEETS_DEVICE_INTEGRITY, MEETS_BASIC_INTEGRITY.
 * - Interception and blocking of emulators, rooted devices, and Frida/Xposed hooking environments.
 * - Strict production guard: dev-bypass rejection when NODE_ENV=production.
 * - GooglePlayIntegrityVerifier fail-closed UNVERIFIED-LIVE handling when cloud credentials are unconfigured.
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import crypto from "crypto";
import {
  DeviceAttestationService,
  FakePlayIntegrityVerifier,
  GooglePlayIntegrityVerifier,
} from "../services/device_attestation";

describe("Stage S8: Google Play Integrity Device Attestation (Work Package S8-B)", () => {
  const nonce = "chal_91e80ce6ae5b10a2410a89";
  const uid = "usr_karnataka_worker_441";
  const action = "ENROLLMENT";
  const dummyImage = Buffer.alloc(112 * 112 * 3, 128);
  const captureDigest = crypto.createHash("sha256").update(dummyImage).digest("hex");

  // ── TEST 1: Canonical requestHash Computation & Verification ──────────────
  it("PIA-01: computes canonical requestHash and verifies identical binding", () => {
    const computedHash = DeviceAttestationService.computeRequestHash(
      nonce,
      uid,
      action,
      captureDigest
    );

    assert.strictEqual(typeof computedHash, "string");
    assert.strictEqual(computedHash.length, 64, "SHA-256 hex hash must be exactly 64 characters");

    // Must match manual canonical formulation
    const manualCanonical = `${nonce}:${uid}:${action}:${captureDigest}`;
    const manualHash = crypto.createHash("sha256").update(Buffer.from(manualCanonical, "utf-8")).digest("hex");
    assert.strictEqual(computedHash, manualHash, "Canonical string formulation must match exactly");

    // Verification check succeeds
    const isVerified = DeviceAttestationService.verifyRequestHash(
      computedHash,
      nonce,
      uid,
      action,
      captureDigest
    );
    assert.strictEqual(isVerified, true, "Valid requestHash must verify cleanly");

    // Mismatched nonce fails
    const tamperedNonce = DeviceAttestationService.verifyRequestHash(
      computedHash,
      "chal_tampered_attacker_nonce",
      uid,
      action,
      captureDigest
    );
    assert.strictEqual(tamperedNonce, false, "Mismatched nonce must fail verification");

    // Mismatched capture digest fails
    const tamperedDigest = DeviceAttestationService.verifyRequestHash(
      computedHash,
      nonce,
      uid,
      action,
      "d000000000000000000000000000000000000000000000000000000000000000"
    );
    assert.strictEqual(tamperedDigest, false, "Mismatched capture digest must fail verification");
  });

  // ── TEST 2: Deterministic FakePlayIntegrityVerifier Verdict Tiers ───────────
  it("PIA-02: evaluates integrity verdict tiers (Strong, Device, Basic)", async () => {
    const verifier = new FakePlayIntegrityVerifier();
    const expectedHash = DeviceAttestationService.computeRequestHash(
      nonce,
      uid,
      action,
      captureDigest
    );

    // 1. Strong Integrity
    const strongToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_STRONG_INTEGRITY", "MEETS_DEVICE_INTEGRITY"] },
      requestDetails: { requestHash: expectedHash, timestampMillis: Date.now() },
    });
    const strongRes = await verifier.verify(strongToken, expectedHash);
    assert.strictEqual(strongRes.isValid, true);
    assert.strictEqual(strongRes.verdict, "MEETS_STRONG_INTEGRITY");

    // 2. Device Integrity
    const deviceToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      requestDetails: { requestHash: expectedHash, timestampMillis: Date.now() },
    });
    const deviceRes = await verifier.verify(deviceToken, expectedHash);
    assert.strictEqual(deviceRes.isValid, true);
    assert.strictEqual(deviceRes.verdict, "MEETS_DEVICE_INTEGRITY");

    // 3. Basic Integrity
    const basicToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY"] },
      requestDetails: { requestHash: expectedHash, timestampMillis: Date.now() },
    });
    const basicRes = await verifier.verify(basicToken, expectedHash);
    assert.strictEqual(basicRes.isValid, true);
    assert.strictEqual(basicRes.verdict, "MEETS_BASIC_INTEGRITY");
  });

  // ── TEST 3: Package Name Spoofing Interception ──────────────────────────────
  it("PIA-03: rejects tokens issued for rogue or re-packaged apps", async () => {
    const verifier = new FakePlayIntegrityVerifier({ expectedPackageName: "com.kelasagara.app" });
    const expectedHash = DeviceAttestationService.computeRequestHash(
      nonce,
      uid,
      action,
      captureDigest
    );

    const rogueToken = JSON.stringify({
      appIntegrity: { packageName: "com.attacker.repackaged.biomatch" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      requestDetails: { requestHash: expectedHash, timestampMillis: Date.now() },
    });

    const rogueRes = await verifier.verify(rogueToken, expectedHash);
    assert.strictEqual(rogueRes.isValid, false);
    assert.strictEqual(rogueRes.verdict, "EMULATOR_HOOKING_DETECTED");
    assert.ok(rogueRes.error?.includes("PACKAGE_NAME_MISMATCH"));
  });

  // ── TEST 4: Token Freshness & Expiration (Replay Window) ───────────────────
  it("PIA-04: rejects stale attestation tokens exceeding maximum age limit", async () => {
    const verifier = new FakePlayIntegrityVerifier({ maxAgeMs: 180000 }); // 3 min
    const expectedHash = DeviceAttestationService.computeRequestHash(
      nonce,
      uid,
      action,
      captureDigest
    );

    const staleTimestamp = Date.now() - (4 * 60 * 1000); // 4 minutes ago
    const staleToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      requestDetails: { requestHash: expectedHash, timestampMillis: staleTimestamp },
    });

    const staleRes = await verifier.verify(staleToken, expectedHash);
    assert.strictEqual(staleRes.isValid, false);
    assert.strictEqual(staleRes.verdict, "EMULATOR_HOOKING_DETECTED");
    assert.ok(staleRes.error?.includes("TOKEN_EXPIRED"));
  });

  // ── TEST 5: Mismatched requestHash Binding Interception ─────────────────────
  it("PIA-05: detects and blocks tokens with mismatched requestHash", async () => {
    const verifier = new FakePlayIntegrityVerifier();
    const attackerHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    const expectedHash = DeviceAttestationService.computeRequestHash(
      nonce,
      uid,
      action,
      captureDigest
    );

    const mismatchedToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
      requestDetails: { requestHash: attackerHash, timestampMillis: Date.now() },
    });

    const mismatchRes = await verifier.verify(mismatchedToken, expectedHash);
    assert.strictEqual(mismatchRes.isValid, false);
    assert.strictEqual(mismatchRes.verdict, "EMULATOR_HOOKING_DETECTED");
    assert.ok(mismatchRes.error?.includes("REQUEST_HASH_MISMATCH"));
  });

  // ── TEST 6: Hooked / Emulated Environments Interception ───────────────────
  it("PIA-06: catches Frida, Xposed hooking, and emulated device signatures", async () => {
    const verifier = new FakePlayIntegrityVerifier();

    const hookedRes1 = await verifier.verify("test_emulator_hook_frida_gadget");
    assert.strictEqual(hookedRes1.isValid, false);
    assert.strictEqual(hookedRes1.verdict, "EMULATOR_HOOKING_DETECTED");

    const hookedRes2 = await verifier.verify("mock_token_with_hooked_env_payload");
    assert.strictEqual(hookedRes2.isValid, false);
    assert.strictEqual(hookedRes2.verdict, "EMULATOR_HOOKING_DETECTED");

    // Token with empty or failed device recognition verdicts
    const emptyVerdictToken = JSON.stringify({
      appIntegrity: { packageName: "com.kelasagara.app" },
      deviceIntegrity: { deviceRecognitionVerdict: ["UNTRUSTED_EMULATOR"] },
      requestDetails: { timestampMillis: Date.now() },
    });
    const emptyRes = await verifier.verify(emptyVerdictToken);
    assert.strictEqual(emptyRes.isValid, false);
    assert.strictEqual(emptyRes.verdict, "EMULATOR_HOOKING_DETECTED");
    assert.ok(emptyRes.error?.includes("INSUFFICIENT_DEVICE_INTEGRITY"));
  });

  // ── TEST 7: Production Guard Rejects Dev Bypass (Invariant I-26) ────────────
  it("PIA-07: strictly blocks allowDevBypass in production environment", async () => {
    const originalEnv = process.env.NODE_ENV;
    try {
      process.env.NODE_ENV = "production";

      const syncRes = DeviceAttestationService.verifyDeviceIntegrity(undefined, true);
      assert.strictEqual(syncRes.isValid, false);
      assert.strictEqual(syncRes.verdict, "EMULATOR_HOOKING_DETECTED");
      assert.ok(syncRes.reason?.includes("Invariant I-26"));

      const asyncRes = await DeviceAttestationService.verifyPlayIntegrityTokenAsync(undefined, {
        allowDevBypass: true,
      });
      assert.strictEqual(asyncRes.isValid, false);
      assert.strictEqual(asyncRes.verdict, "EMULATOR_HOOKING_DETECTED");
      assert.ok(asyncRes.error?.includes("Invariant I-26"));
    } finally {
      process.env.NODE_ENV = originalEnv;
    }
  });

  // ── TEST 8: Live GooglePlayIntegrityVerifier Fail-Closed (UNVERIFIED-LIVE) ─
  it("PIA-08: GooglePlayIntegrityVerifier fails closed as UNVERIFIED-LIVE without credentials", async () => {
    const originalCreds = process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_KEY;
    const originalGac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    try {
      delete process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_KEY;
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;

      const liveVerifier = new GooglePlayIntegrityVerifier();
      const liveRes = await liveVerifier.verify("any_sample_token");

      assert.strictEqual(liveRes.isValid, false);
      assert.strictEqual(liveRes.isLiveAttestation, true);
      assert.ok(
        liveRes.error?.includes("UNVERIFIED-LIVE"),
        "Missing live credentials must be reported as UNVERIFIED-LIVE"
      );
    } finally {
      if (originalCreds) process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_KEY = originalCreds;
      if (originalGac) process.env.GOOGLE_APPLICATION_CREDENTIALS = originalGac;
    }
  });
});
