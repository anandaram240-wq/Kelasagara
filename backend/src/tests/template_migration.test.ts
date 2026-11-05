// backend/src/tests/template_migration.test.ts
/**
 * TEMPLATE MIGRATION STATE MACHINE TESTS (Stage S8 / Work Package S8-C / Section 5).
 * Enforces Invariants INV-04 (Strict Version Selection) and INV-09 (Migration Safety).
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import { TemplatePrivacyService } from "../services/template_privacy";
import { LocalDevKeyProvider } from "../services/kms_key_provider";
import { TemplateMigrationService } from "../services/template_migration";

describe("Stage S8: Template Migration State Machine & Safety", () => {
  const masterKey = "master_key_secret_for_legacy_testing_only_32b";
  const keyProvider = new LocalDevKeyProvider();
  const dummyEmbedding = Array.from({ length: 128 }, (_, i) => Math.cos(i + 1) * 0.15);

  it("MIG-01: Dry-run migration previews v2 -> v3 conversion without altering original", async () => {
    const v2Envelope = TemplatePrivacyService.encryptTemplate(
      "worker_dry_01",
      "tenant_karnataka",
      dummyEmbedding,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    const result = await TemplateMigrationService.migrateRecord(v2Envelope, {
      masterKeySecret: masterKey,
      keyProvider,
      dryRun: true,
    });

    assert.strictEqual(result.state, "VERIFIED");
    assert.strictEqual(result.sourceVersion, "v2_aad_gcm");
    assert.strictEqual(result.targetVersion, "v3_kms_gcm");
    assert.ok(result.migratedEnvelope);
    assert.strictEqual(result.migratedEnvelope!.envelopeVersion, "v3_kms_gcm");
  });

  it("MIG-02: Live migration commits valid v3_kms_gcm record and preserves vector fidelity", async () => {
    const v2Envelope = TemplatePrivacyService.encryptTemplate(
      "worker_live_01",
      "tenant_karnataka",
      dummyEmbedding,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    const result = await TemplateMigrationService.migrateRecord(v2Envelope, {
      masterKeySecret: masterKey,
      keyProvider,
      dryRun: false,
    });

    assert.strictEqual(result.state, "COMMITTED");
    assert.ok(result.migratedEnvelope);
    assert.strictEqual(result.migratedEnvelope!.envelopeVersion, "v3_kms_gcm");

    // Decrypt the newly committed envelope with v3 strict mode
    const decrypted = await TemplatePrivacyService.decryptTemplateAsync(
      result.migratedEnvelope!,
      keyProvider,
      undefined,
      "v3_kms_gcm"
    );

    assert.strictEqual(decrypted.length, 128);
    for (let i = 0; i < 128; i++) {
      assert.ok(Math.abs(decrypted[i] - dummyEmbedding[i]) < 1e-6);
    }
  });

  it("MIG-03: Re-migrating an already-migrated v3 record is idempotent and safely skipped", async () => {
    const v3Envelope = await TemplatePrivacyService.encryptTemplateAsync(
      "worker_already_v3",
      "tenant_karnataka",
      dummyEmbedding,
      keyProvider
    );

    const result = await TemplateMigrationService.migrateRecord(v3Envelope, {
      keyProvider,
      dryRun: false,
    });

    assert.strictEqual(result.state, "COMMITTED");
    assert.strictEqual(result.sourceVersion, "v3_kms_gcm");
    assert.strictEqual(result.targetVersion, "v3_kms_gcm");
  });

  it("MIG-04: Migration fails safely when source ciphertext is corrupted without damaging state", async () => {
    const v2Envelope = TemplatePrivacyService.encryptTemplate(
      "worker_corrupt",
      "tenant_karnataka",
      dummyEmbedding,
      masterKey,
      undefined,
      "k1",
      "v2_aad_gcm"
    );

    // Corrupt ciphertext
    const corrupted = { ...v2Envelope, ciphertextHex: "badc0ffee" + v2Envelope.ciphertextHex.slice(9) };

    const result = await TemplateMigrationService.migrateRecord(corrupted, {
      masterKeySecret: masterKey,
      keyProvider,
      dryRun: false,
    });

    assert.strictEqual(result.state, "FAILED");
    assert.ok(result.error?.includes("Migration failed at state DECRYPTED"));
  });

  it("MIG-05: Batch migration handles heterogeneous envelope batches", async () => {
    const env1 = TemplatePrivacyService.encryptTemplate("w1", "t1", dummyEmbedding, masterKey, undefined, "k1", "v2_aad_gcm");
    const env2 = TemplatePrivacyService.encryptTemplate("w2", "t1", dummyEmbedding, masterKey, undefined, "k1", "v2_aad_gcm");
    const env3 = await TemplatePrivacyService.encryptTemplateAsync("w3", "t1", dummyEmbedding, keyProvider);

    const batchRes = await TemplateMigrationService.migrateBatch([env1, env2, env3], {
      masterKeySecret: masterKey,
      keyProvider,
      dryRun: false,
    });

    assert.strictEqual(batchRes.totalDiscovered, 3);
    assert.strictEqual(batchRes.totalMigrated, 2);
    assert.strictEqual(batchRes.totalSkipped, 1);
    assert.strictEqual(batchRes.totalFailed, 0);
  });
});
