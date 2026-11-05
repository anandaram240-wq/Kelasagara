// backend/src/tests/cryptographic_assurance.test.ts
/**
 * STAGE S7: CRYPTOGRAPHIC ASSURANCE & ADVERSARIAL TEMPLATE PROTECTION SUITE
 * 
 * Tests the hardened AES-256-GCM envelope encryption with Additional Authenticated Data (AAD):
 * 1. Positive round-trip precision verification (< 1e-5 difference).
 * 2. Ciphertext bit-flip interception (fail-closed AEAD integrity).
 * 3. Authentication tag bit-flip interception.
 * 4. Cross-tenant envelope substitution attack interception (AAD mismatch).
 * 5. Cross-user envelope substitution attack interception (AAD mismatch).
 * 6. Key-version tampering interception (AAD mismatch).
 * 7. Nonce uniqueness guarantee (96-bit CSPRNG, zero collision across iterations).
 * 8. Envelope format downgrade rejection (strict v2 policy).
 * 9. Malformed / truncated envelope encoding rejection.
 * 10. DPDPA Crypto-shredding: key destruction irrevocably prevents template recovery.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { TemplatePrivacyService, EncryptedTemplateEnvelope } from "../services/template_privacy";

describe("Stage S7: Cryptographic Assurance & Template Protection (Part 3)", () => {
  const masterKey = "master_super_secret_kms_key_for_testing_32b!";
  const tenantA = "tenant_karnataka_rural_development";
  const tenantB = "tenant_bangalore_urban_corporation";
  const user1 = "worker_uid_anand_kumar_001";
  const user2 = "worker_uid_basavaraj_002";
  const dim = 128;

  // Generate synthetic normalized 128-D embedding vector
  const embedding: number[] = new Array(dim).fill(0).map((_, i) => Math.sin(i * 0.1));
  const norm = Math.sqrt(embedding.reduce((s, x) => s + x * x, 0));
  const unitVector = embedding.map((x) => x / norm);

  it("1. Positive verification: AES-256-GCM v2_aad_gcm round-trip precision (< 1e-5)", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    assert.equal(envelope.envelopeVersion, "v2_aad_gcm");
    assert.equal(envelope.keyVersion, "k1");
    assert.equal(envelope.ivHex.length, 24); // 12 bytes = 24 hex
    assert.equal(envelope.authTagHex.length, 32); // 16 bytes = 32 hex

    const decrypted = TemplatePrivacyService.decryptTemplate(envelope, masterKey, undefined, true);
    assert.equal(decrypted.length, dim);

    let maxDiff = 0;
    for (let i = 0; i < dim; i++) {
      maxDiff = Math.max(maxDiff, Math.abs(unitVector[i] - decrypted[i]));
    }
    assert.ok(maxDiff < 1e-5, `Round-trip precision delta ${maxDiff} must be < 1e-5`);
  });

  it("2. Adversarial test: Ciphertext bit flip must fail closed", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    // Flip bit in ciphertext
    const rawCipher = Buffer.from(envelope.ciphertextHex, "hex");
    rawCipher[0] ^= 0x01; // flip lowest bit of first byte
    const corruptedEnvelope: EncryptedTemplateEnvelope = {
      ...envelope,
      ciphertextHex: rawCipher.toString("hex"),
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(corruptedEnvelope, masterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Corrupted ciphertext must trigger authentication tag verification failure"
    );
  });

  it("3. Adversarial test: Authentication tag bit flip must fail closed", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    // Flip bit in auth tag
    const rawTag = Buffer.from(envelope.authTagHex, "hex");
    rawTag[rawTag.length - 1] ^= 0x80;
    const corruptedEnvelope: EncryptedTemplateEnvelope = {
      ...envelope,
      authTagHex: rawTag.toString("hex"),
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(corruptedEnvelope, masterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Tampered authentication tag must trigger verification failure"
    );
  });

  it("4. Adversarial test: Cross-tenant ciphertext splicing must fail closed via AAD", () => {
    // Envelope legitimately created under Tenant A
    const envelopeA = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    // Attacker splices Tenant A envelope into Tenant B database record
    const splicedTenantEnvelope: EncryptedTemplateEnvelope = {
      ...envelopeA,
      tenantId: tenantB, // Substituted tenant
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(splicedTenantEnvelope, masterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Cross-tenant substitution must be intercepted by AAD mismatch"
    );
  });

  it("5. Adversarial test: Cross-user ciphertext splicing must fail closed via AAD", () => {
    // Envelope legitimately created for User 1
    const envelopeUser1 = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    // Attacker copies User 1 envelope into User 2's document
    const splicedUserEnvelope: EncryptedTemplateEnvelope = {
      ...envelopeUser1,
      uid: user2, // Substituted UID
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(splicedUserEnvelope, masterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Cross-user substitution must be intercepted by AAD mismatch"
    );
  });

  it("6. Adversarial test: Key version tampering must fail closed via AAD", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey,
      undefined,
      "k1"
    );

    // Attacker modifies key version in envelope
    const tamperedEnvelope: EncryptedTemplateEnvelope = {
      ...envelope,
      keyVersion: "k2", // Substituted key version
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(tamperedEnvelope, masterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Key version tampering must be intercepted by AAD mismatch"
    );
  });

  it("7. Security guarantee: Zero IV reuse across successive encryptions", () => {
    const ivSet = new Set<string>();
    const iterations = 500;

    for (let i = 0; i < iterations; i++) {
      const envelope = TemplatePrivacyService.encryptTemplate(
        user1,
        tenantA,
        unitVector,
        masterKey
      );
      assert.ok(!ivSet.has(envelope.ivHex), "IV collision detected! Fatal GCM flaw.");
      ivSet.add(envelope.ivHex);
    }

    assert.equal(ivSet.size, iterations, "All 500 successive encryptions must have unique 96-bit IVs");
  });

  it("8. Defense-in-depth: Reject envelope downgrade when strictV2 is enforced", () => {
    const legacyEnvelope: EncryptedTemplateEnvelope = {
      envelopeVersion: "v1_legacy",
      uid: user1,
      tenantId: tenantA,
      ciphertextHex: Buffer.alloc(dim * 4, 0xaa).toString("hex"),
      ivHex: Buffer.alloc(12, 0xbb).toString("hex"),
      authTagHex: Buffer.alloc(16, 0xcc).toString("hex"),
      keyDerivationSaltHex: Buffer.alloc(16, 0xdd).toString("hex"),
      rotated: false,
      encryptedAt: new Date().toISOString(),
    };

    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(legacyEnvelope, masterKey, undefined, true),
      /ENVELOPE_DOWNGRADE_REJECTED/,
      "Strict v2 policy must reject downgrade to legacy unauthenticated envelope"
    );
  });

  it("9. Robustness: Reject malformed IV, truncated ciphertext, and invalid hex", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    // Invalid IV length (16 bytes instead of 12 bytes / 24 hex)
    assert.throws(
      () => TemplatePrivacyService.decryptTemplate({ ...envelope, ivHex: "aabbcc" }, masterKey),
      /INVALID_IV_LENGTH/
    );

    // Invalid Auth Tag length
    assert.throws(
      () => TemplatePrivacyService.decryptTemplate({ ...envelope, authTagHex: "aabbcc" }, masterKey),
      /INVALID_AUTH_TAG_LENGTH/
    );

    // Invalid Ciphertext length (not multiple of 4 bytes)
    assert.throws(
      () => TemplatePrivacyService.decryptTemplate({ ...envelope, ciphertextHex: "aabb" }, masterKey),
      /INVALID_CIPHERTEXT/
    );
  });

  it("10. DPDPA Crypto-Shredding: Master key revocation permanently prevents recovery", () => {
    const envelope = TemplatePrivacyService.encryptTemplate(
      user1,
      tenantA,
      unitVector,
      masterKey
    );

    const revokedMasterKey = "revoked_master_key_post_shredding_token!";
    assert.throws(
      () => TemplatePrivacyService.decryptTemplate(envelope, revokedMasterKey),
      /AUTHENTICATION_TAG_VERIFICATION_FAILED/,
      "Revoked master key must unconditionally fail to decrypt template"
    );
  });
});
