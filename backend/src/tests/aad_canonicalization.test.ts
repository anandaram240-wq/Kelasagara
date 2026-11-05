// backend/src/tests/aad_canonicalization.test.ts
/**
 * AAD CANONICALIZATION & KMS ENVELOPE ENCRYPTION REGRESSION SUITE (Stage S8 / Work Package S8-C).
 * Enforces Invariants:
 * - INV-01: Envelope Integrity
 * - INV-02: Context Binding (No delimiter shifting / field boundary collision)
 * - INV-03: No Plaintext Key Persistence
 * - INV-04: Strict Version Selection (Downgrade rejection)
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import { TemplatePrivacyService } from "../services/template_privacy";
import { LocalDevKeyProvider, CloudKmsKeyProvider } from "../services/kms_key_provider";

describe("Stage S8: AAD Canonicalization & KMS Envelope Encryption", () => {
  const dummyEmbedding = Array.from({ length: 128 }, (_, i) => Math.sin(i + 1) * 0.1);

  it("TEST 1: Demonstrates delimiter collision in legacy pipe-delimited AAD", () => {
    // Delimiter collision case:
    // Tenant: "tenantA|user", UID: "123"
    // vs.
    // Tenant: "tenantA", UID: "user|123"
    const legacyAad1 = TemplatePrivacyService.buildLegacyAAD("v2_aad_gcm", "tenantA|user", "123", "k1");
    const legacyAad2 = TemplatePrivacyService.buildLegacyAAD("v2_aad_gcm", "tenantA", "user|123", "k1");

    assert.strictEqual(
      legacyAad1.toString("utf8"),
      legacyAad2.toString("utf8"),
      "VULNERABILITY REPRODUCED: Pipe-delimited AAD exhibits identical bytes for boundary-shifted fields"
    );
  });

  it("TEST 2: Proves length-prefixed binary canonical AAD prevents field boundary shifting", () => {
    const canonicalAad1 = TemplatePrivacyService.buildCanonicalAAD({
      envelopeVersion: "v3_kms_gcm",
      tenantId: "tenantA|user",
      uid: "123",
      keyVersion: "k1",
    });

    const canonicalAad2 = TemplatePrivacyService.buildCanonicalAAD({
      envelopeVersion: "v3_kms_gcm",
      tenantId: "tenantA",
      uid: "user|123",
      keyVersion: "k1",
    });

    assert.notStrictEqual(
      canonicalAad1.toString("hex"),
      canonicalAad2.toString("hex"),
      "REMEDIATION VERIFIED: Length-prefixed encoding produces distinct byte sequences for boundary-shifted inputs"
    );
  });

  it("TEST 3: Generates and verifies v3_kms_gcm envelope with LocalDevKeyProvider", () => {
    const keyProvider = new LocalDevKeyProvider();
    const envelope = TemplatePrivacyService.encryptTemplate(
      "user_alpha_123",
      "tenant_retail_01",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider,
      "BIOMETRIC_AUTH_V1"
    );

    assert.strictEqual(envelope.envelopeVersion, "v3_kms_gcm");
    assert.strictEqual(envelope.schemaVersion, 3);
    assert.ok(envelope.wrappedDekHex && envelope.wrappedDekHex.length === 120, "Wrapped DEK must be 60 bytes (120 hex chars)");
    assert.strictEqual(envelope.ciphertextHex.length, 1024, "128-D FP32 ciphertext must be 512 bytes (1024 hex chars)");
    assert.strictEqual(envelope.ivHex.length, 24, "AES-GCM IV must be 96 bits (24 hex chars)");
    assert.strictEqual(envelope.authTagHex.length, 32, "AES-GCM tag must be 128 bits (32 hex chars)");

    // Decrypt and verify exact recovery
    const decrypted = TemplatePrivacyService.decryptTemplate(
      envelope,
      undefined,
      undefined,
      true,
      keyProvider
    );

    assert.strictEqual(decrypted.length, 128);
    for (let i = 0; i < 128; i++) {
      assert.ok(Math.abs(decrypted[i] - dummyEmbedding[i]) < 1e-6, `Index ${i} float deviation exceeds epsilon`);
    }
  });

  it("TEST 4: Rejects v3_kms_gcm envelope if tenant context is modified (Context Binding INV-02)", () => {
    const keyProvider = new LocalDevKeyProvider();
    const envelope = TemplatePrivacyService.encryptTemplate(
      "user_victim",
      "tenant_legitimate",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    // Attacker modifies tenant to an unauthorized tenant
    const tamperedTenantEnvelope = { ...envelope, tenantId: "tenant_adversary" };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(tamperedTenantEnvelope, undefined, undefined, true, keyProvider),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Must reject envelope when tenant context does not match wrapped DEK / ciphertext AAD"
    );
  });

  it("TEST 5: Rejects v3_kms_gcm envelope if user UID context is modified (INV-02)", () => {
    const keyProvider = new LocalDevKeyProvider();
    const envelope = TemplatePrivacyService.encryptTemplate(
      "user_victim",
      "tenant_alpha",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    const tamperedUserEnvelope = { ...envelope, uid: "user_adversary" };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(tamperedUserEnvelope, undefined, undefined, true, keyProvider),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Must reject envelope when UID context does not match wrapped DEK / ciphertext AAD"
    );
  });

  it("TEST 6: Rejects v3_kms_gcm envelope if ciphertext or auth tag is corrupted (INV-01)", () => {
    const keyProvider = new LocalDevKeyProvider();
    const envelope = TemplatePrivacyService.encryptTemplate(
      "user_secure",
      "tenant_omega",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    // Corrupt one bit of ciphertext
    const corruptedCiphertext =
      (envelope.ciphertextHex[0] === "a" ? "b" : "a") + envelope.ciphertextHex.slice(1);
    const corruptedCipherEnvelope = { ...envelope, ciphertextHex: corruptedCiphertext };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(corruptedCipherEnvelope, undefined, undefined, true, keyProvider),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Must reject bit-flipped ciphertext"
    );

    // Corrupt one bit of auth tag
    const corruptedTag =
      (envelope.authTagHex[0] === "a" ? "b" : "a") + envelope.authTagHex.slice(1);
    const corruptedTagEnvelope = { ...envelope, authTagHex: corruptedTag };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(corruptedTagEnvelope, undefined, undefined, true, keyProvider),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Must reject bit-flipped auth tag"
    );
  });

  it("TEST 7: Downgrade Protection (INV-04) strictly rejects v1/v2 envelopes when minEnvelopeVersion is v3", () => {
    const masterKey = "master_key_secret_for_legacy_testing_only_32b";
    const legacyV2Envelope = TemplatePrivacyService.encryptTemplate(
      "user_legacy",
      "tenant_old",
      dummyEmbedding,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    // When policy mandates v3_kms_gcm, attempting to decrypt a v2 envelope must fail
    assert.throws(
      () =>
        TemplatePrivacyService.decryptTemplate(
          legacyV2Envelope,
          masterKey,
          undefined,
          false,
          undefined,
          "v3_kms_gcm"
        ),
      /ENVELOPE_DOWNGRADE_REJECTED/,
      "Must reject legacy envelope when minEnvelopeVersion is v3_kms_gcm"
    );
  });

  it("TEST 8: Backward-compatible migration decrypts legacy v2 envelope when permitted", () => {
    const masterKey = "master_key_secret_for_legacy_testing_only_32b";
    const legacyV2Envelope = TemplatePrivacyService.encryptTemplate(
      "user_legacy_ok",
      "tenant_old_ok",
      dummyEmbedding,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    // Decrypting without minEnvelopeVersion=v3 succeeds for backward-compatible migration
    const decrypted = TemplatePrivacyService.decryptTemplate(
      legacyV2Envelope,
      masterKey,
      undefined,
      true
    );

    assert.strictEqual(decrypted.length, 128);
    assert.ok(Math.abs(decrypted[0] - dummyEmbedding[0]) < 1e-6);
  });

  it("TEST 9: CloudKmsKeyProvider throws explicit KMS_UNAVAILABLE_ERROR when GCP credentials are unset", async () => {
    const kmsProvider = new CloudKmsKeyProvider({
      projectId: "kelasagara-f127a",
      locationId: "asia-south1",
      keyRingId: "biomatch-ring",
      keyId: "template-kek",
    });

    const dek = Buffer.alloc(32, 0x42);
    const context = Buffer.from("test_context");

    // In local environment without GOOGLE_APPLICATION_CREDENTIALS, wrapDek throws explicit unavailable error
    await assert.rejects(
      async () => await kmsProvider.wrapDek(dek, context),
      /KMS_UNAVAILABLE_ERROR \(UNVERIFIED-LIVE\)/,
      "Must cleanly fail-closed with UNVERIFIED-LIVE error rather than silently defaulting to insecure plaintext"
    );
  });

  it("TEST 10: Nonce uniqueness: Generates distinct IVs across 1,000 successive encryptions", () => {
    const keyProvider = new LocalDevKeyProvider();
    const ivSet = new Set<string>();
    const N = 1000;

    for (let i = 0; i < N; i++) {
      const env = TemplatePrivacyService.encryptTemplate(
        `user_${i}`,
        "tenant_main",
        dummyEmbedding,
        undefined,
        undefined,
        "k1",
        "v3_kms_gcm",
        keyProvider
      );
      assert.ok(!ivSet.has(env.ivHex), `Duplicate IV detected at trial ${i}`);
      ivSet.add(env.ivHex);
    }

    assert.strictEqual(ivSet.size, N, "All 1,000 generated IVs must be strictly unique (CSPRNG 96-bit)");
  });
});
