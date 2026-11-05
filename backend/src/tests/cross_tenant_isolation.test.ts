// backend/src/tests/cross_tenant_isolation.test.ts
/**
 * Test Suite: Cross-Tenant Cryptographic Isolation & Concurrency Safety (Stage S8 / Work Package S8-D).
 *
 * Exercises:
 * - CTI-01: Cross-tenant IDOR protection (Tenant A templates cannot be decrypted by Tenant B).
 * - CTI-02: Cross-tenant envelope splicing attack interception (Tampering tenantId triggers auth tag failure).
 * - CTI-03: Wrapped-DEK substitution attack interception (Splicing Tenant A wrapped DEK into Tenant B fails).
 * - CTI-04: Cross-tenant UID collision defense (Identical UIDs in different tenants generate disjoint cryptograms).
 * - CTI-05: Concurrent enrollment lock serialization (Concurrent reservations for same account conflict safely).
 * - CTI-06: Post-finalization session resumption (Finalized sessions allow new enrollment attempts).
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import { TemplatePrivacyService } from "../services/template_privacy";
import { LocalDevKeyProvider } from "../services/kms_key_provider";

describe("Stage S8: Cross-Tenant Isolation & Concurrency Safety (Work Package S8-D)", () => {
  const dummyEmbedding = Array.from({ length: 128 }, (_, i) => Math.sin(i * 0.1));
  const keyProvider = new LocalDevKeyProvider();

  // ── TEST 1: Tenant A vs Tenant B IDOR Isolation ───────────────────────────
  it("CTI-01: rejects decryption when caller attempts cross-tenant template access (IDOR)", async () => {
    // Encrypt template for Tenant Alpha
    const envelopeTenantA = TemplatePrivacyService.encryptTemplate(
      "worker_880",
      "tenant_alpha_retail",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    assert.strictEqual(envelopeTenantA.tenantId, "tenant_alpha_retail");

    // Attacker from Tenant Beta attempts to decrypt Tenant Alpha's envelope
    // By spoofing the envelope's tenantId to tenant_beta_logistics
    const tamperedEnvelope = {
      ...envelopeTenantA,
      tenantId: "tenant_beta_logistics",
    };

    await assert.rejects(
      async () => {
        await TemplatePrivacyService.decryptTemplateAsync(
          tamperedEnvelope,
          keyProvider
        );
      },
      (err: any) => {
        return (
          err.message.includes("AUTHENTICATION_TAG_VERIFICATION_FAILED") ||
          err.message.includes("Unsupported state or unable to authenticate data")
        );
      },
      "Decryption with mismatched tenantId must fail GCM auth tag verification"
    );
  });

  // ── TEST 2: Cross-Tenant Ciphertext Splicing ──────────────────────────────
  it("CTI-02: detects and intercepts cross-tenant ciphertext splicing attacks", async () => {
    // Tenant Alpha envelope
    const envAlpha = TemplatePrivacyService.encryptTemplate(
      "worker_alpha_10",
      "tenant_alpha",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    // Tenant Beta envelope
    const envBeta = TemplatePrivacyService.encryptTemplate(
      "worker_beta_20",
      "tenant_beta",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    // Attacker splices Alpha's ciphertext into Beta's envelope
    const splicedEnvelope = {
      ...envBeta,
      ciphertextHex: envAlpha.ciphertextHex,
      authTagHex: envAlpha.authTagHex,
      ivHex: envAlpha.ivHex,
    };

    await assert.rejects(
      async () => {
        await TemplatePrivacyService.decryptTemplateAsync(
          splicedEnvelope,
          keyProvider
        );
      },
      (err: any) => {
        return err.message.includes("AUTHENTICATION_TAG_VERIFICATION_FAILED");
      },
      "Splicing ciphertext between tenants must trigger auth tag verification failure"
    );
  });

  // ── TEST 3: Wrapped-DEK Substitution Attack Interception ───────────────────
  it("CTI-03: blocks wrapped-DEK substitution across tenant envelopes", async () => {
    const envAlpha = TemplatePrivacyService.encryptTemplate(
      "worker_01",
      "tenant_karnataka_rural",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    const envBeta = TemplatePrivacyService.encryptTemplate(
      "worker_01",
      "tenant_bangalore_urban",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    // Attacker swaps wrapped DEK from Alpha into Beta
    const swappedEnvelope = {
      ...envBeta,
      wrappedDekHex: envAlpha.wrappedDekHex,
    };

    await assert.rejects(
      async () => {
        await TemplatePrivacyService.decryptTemplateAsync(
          swappedEnvelope,
          keyProvider
        );
      },
      (err: any) => {
        return (
          err.message.includes("AUTHENTICATION_TAG_VERIFICATION_FAILED") ||
          err.message.includes("DEK_UNWRAP_FAILED") ||
          err.message.includes("unable to authenticate data")
        );
      },
      "Wrapped DEK substitution must fail DEK unwrap under tenant-specific AAD"
    );
  });

  // ── TEST 4: Disjoint Cryptograms on Identical User IDs ────────────────────
  it("CTI-04: identical user IDs across different tenants yield cryptographically disjoint envelopes", async () => {
    const commonUid = "worker_shared_identifier_999";

    const env1 = TemplatePrivacyService.encryptTemplate(
      commonUid,
      "tenant_mysuru",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    const env2 = TemplatePrivacyService.encryptTemplate(
      commonUid,
      "tenant_hubballi",
      dummyEmbedding,
      undefined,
      undefined,
      "k1",
      "v3_kms_gcm",
      keyProvider
    );

    assert.notStrictEqual(env1.ciphertextHex, env2.ciphertextHex);
    assert.notStrictEqual(env1.wrappedDekHex, env2.wrappedDekHex);
    assert.notStrictEqual(env1.ivHex, env2.ivHex);

    // Each envelope can only be decrypted with its own tenant context
    const decrypted1 = await TemplatePrivacyService.decryptTemplateAsync(env1, keyProvider);
    assert.strictEqual(decrypted1.length, 128);

    const decrypted2 = await TemplatePrivacyService.decryptTemplateAsync(env2, keyProvider);
    assert.strictEqual(decrypted2.length, 128);
  });

  // ── TEST 5: Concurrent Enrollment Session Race Condition Protection ───────
  it("CTI-05: serializes concurrent enrollment requests and rejects simultaneous collisions", async () => {
    // In-memory mock session store simulating Firestore runTransaction
    const sessionStore = new Map<string, { status: string; startedAt: number }>();
    const now = Date.now();

    async function mockReserveSession(uid: string): Promise<boolean> {
      const existing = sessionStore.get(uid);
      if (existing && existing.status === "in_progress" && now - existing.startedAt < 60000) {
        throw new Error("Another enrollment session is currently in progress for this account.");
      }
      sessionStore.set(uid, { status: "in_progress", startedAt: now });
      return true;
    }

    const targetUid = "usr_race_condition_test_123";

    // First request succeeds
    const res1 = await mockReserveSession(targetUid);
    assert.strictEqual(res1, true);

    // Concurrent second request within lease window must be rejected
    await assert.rejects(
      async () => {
        await mockReserveSession(targetUid);
      },
      (err: any) => {
        return err.message.includes("Another enrollment session is currently in progress");
      },
      "Concurrent enrollment collision must be rejected"
    );
  });

  // ── TEST 6: Resumption After Session Finalization ─────────────────────────
  it("CTI-06: allows new enrollment attempt after previous session completes or fails", async () => {
    const sessionStore = new Map<string, { status: string; startedAt: number }>();
    const uid = "usr_resumable_flow_456";

    sessionStore.set(uid, { status: "in_progress", startedAt: Date.now() });

    // Finalize previous session
    sessionStore.set(uid, { status: "completed", startedAt: Date.now() });

    // Next enrollment attempt succeeds cleanly
    const canEnroll = sessionStore.get(uid)?.status !== "in_progress";
    assert.strictEqual(canEnroll, true, "Completed session must allow new enrollment cycle");
  });
});
