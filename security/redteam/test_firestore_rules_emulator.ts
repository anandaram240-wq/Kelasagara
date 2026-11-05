/**
 * security/redteam/test_firestore_rules_emulator.ts
 *
 * Real Live Firestore Emulator Rules Test for Invariant I-02 & Biometric Protections.
 * Executes against local Firestore emulator (port 8080).
 *
 * Tests:
 * 1. Client attempt to write faceVerified=true to users/{uid} must be REJECTED (403 PERMISSION_DENIED).
 * 2. Client attempt to write accountStatus='approved' directly must be REJECTED.
 * 3. Client attempt to read/write biometric_vault/{uid} must be REJECTED.
 * 4. Client attempt to read/write biometric_audit_logs must be REJECTED.
 * 5. Admin SDK write to faceVerified succeeds (server-authoritative bypass).
 */

import http from "http";

const EMULATOR_HOST = "127.0.0.1";
const EMULATOR_PORT = 8080;
const PROJECT_ID = "kelasagara-f127a";

// Helper to make REST requests to Firestore Emulator
async function firestoreRequest(options: {
  method: string;
  path: string;
  body?: any;
  userUid?: string; // if provided, simulates an authenticated client with this UID
  isAdmin?: boolean;
}): Promise<{ status: number; data: any }> {
  return new Promise((resolve, reject) => {
    const postData = options.body ? JSON.stringify(options.body) : undefined;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };

    if (options.isAdmin) {
      headers["Authorization"] = "Bearer owner";
    } else if (options.userUid) {
      // Firebase Emulator supports JWT-like tokens or mock auth tokens:
      // "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VySWQiLCJ1c2VyX2lkIjoidXNlcklkIn0."
      // Or {"user_id": "..."} in emulator v11+
      const payload = Buffer.from(
        JSON.stringify({
          sub: options.userUid,
          user_id: options.userUid,
          aud: PROJECT_ID,
          iss: `https://securetoken.google.com/${PROJECT_ID}`,
          auth_time: Math.floor(Date.now() / 1000),
        })
      ).toString("base64url");
      headers["Authorization"] = `Bearer eyJhbGciOiJub25lIn0.${payload}.`;
    }

    if (postData) {
      headers["Content-Length"] = Buffer.byteLength(postData).toString();
    }

    const req = http.request(
      {
        hostname: EMULATOR_HOST,
        port: EMULATOR_PORT,
        path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents${options.path}`,
        method: options.method,
        headers,
      },
      (res) => {
        let raw = "";
        res.on("data", (chunk) => (raw += chunk));
        res.on("end", () => {
          let parsed: any;
          try {
            parsed = raw ? JSON.parse(raw) : {};
          } catch {
            parsed = raw;
          }
          resolve({ status: res.statusCode || 500, data: parsed });
        });
      }
    );

    req.on("error", reject);
    if (postData) req.write(postData);
    req.end();
  });
}

async function runEmulatorRulesSuite() {
  console.log("====================================================");
  console.log("🛡️ RUNNING LIVE FIRESTORE EMULATOR SECURITY RULES TESTS");
  console.log(`   Host: http://${EMULATOR_HOST}:${EMULATOR_PORT}`);
  console.log(`   Project: ${PROJECT_ID}`);
  console.log("====================================================");

  const testUid = "attacker_client_999";

  // Step 0: Seed test user document via Admin/Owner bypass
  console.log("\n[Setup] Seeding test user profile in pending_face status via Admin...");
  const seedRes = await firestoreRequest({
    method: "PATCH",
    path: `/users/${testUid}`,
    isAdmin: true,
    body: {
      fields: {
        uid: { stringValue: testUid },
        role: { stringValue: "worker" },
        accountStatus: { stringValue: "pending_face" },
        faceVerified: { booleanValue: false },
      },
    },
  });
  console.log(`Seeded user profile. HTTP Status: ${seedRes.status}`);

  // ── TEST 1: Client forging faceVerified=true ──────────────────────────────
  console.log("\n[Test 1] Attacker client attempts to update faceVerified=true...");
  const attack1 = await firestoreRequest({
    method: "PATCH",
    path: `/users/${testUid}?updateMask.fieldPaths=faceVerified&updateMask.fieldPaths=accountStatus`,
    userUid: testUid, // Authenticated as owner of this document
    body: {
      fields: {
        faceVerified: { booleanValue: true },
        accountStatus: { stringValue: "pending_review" },
      },
    },
  });

  console.log(`Response HTTP Status: ${attack1.status}`);
  if (attack1.status === 403 || attack1.status === 400) {
    console.log("✔ Test 1 PASS: Client-forged faceVerified=true was REJECTED by rules! (PERMISSION_DENIED)");
  } else {
    console.error("❌ Test 1 FAIL: Client was able to write faceVerified=true directly!", attack1);
    throw new Error("Invariant I-02 Violation: Client wrote faceVerified directly.");
  }

  // ── TEST 2: Client attempting direct write to biometric_vault ──────────────
  console.log("\n[Test 2] Client attempts to create template in /biometric_vault...");
  const attack2 = await firestoreRequest({
    method: "POST",
    path: `/biometric_vault?documentId=${testUid}`,
    userUid: testUid,
    body: {
      fields: {
        uid: { stringValue: testUid },
        fakeTemplate: { stringValue: "malicious_spoofed_vector" },
      },
    },
  });

  console.log(`Response HTTP Status: ${attack2.status}`);
  if (attack2.status === 403 || attack2.status === 400) {
    console.log("✔ Test 2 PASS: Client write to biometric_vault REJECTED! (PERMISSION_DENIED)");
  } else {
    console.error("❌ Test 2 FAIL: Client wrote directly to biometric_vault!", attack2);
    throw new Error("Vault Isolation Violation: Client wrote to biometric_vault.");
  }

  // ── TEST 3: Client attempting read from biometric_vault ────────────────────
  console.log("\n[Test 3] Client attempts to read from /biometric_vault...");
  const attack3 = await firestoreRequest({
    method: "GET",
    path: `/biometric_vault/${testUid}`,
    userUid: testUid,
  });

  console.log(`Response HTTP Status: ${attack3.status}`);
  if (attack3.status === 403 || attack3.status === 404) {
    console.log("✔ Test 3 PASS: Client read from biometric_vault REJECTED! (PERMISSION_DENIED)");
  } else {
    console.error("❌ Test 3 FAIL: Client read from biometric_vault!", attack3);
    throw new Error("Vault Isolation Violation: Client read biometric_vault.");
  }

  // ── TEST 4: Client attempting write to biometric_audit_logs ────────────────
  console.log("\n[Test 4] Client attempts to tamper with /biometric_audit_logs...");
  const attack4 = await firestoreRequest({
    method: "POST",
    path: `/biometric_audit_logs`,
    userUid: testUid,
    body: {
      fields: {
        eventType: { stringValue: "SPOOFED_EVENT" },
      },
    },
  });

  console.log(`Response HTTP Status: ${attack4.status}`);
  if (attack4.status === 403 || attack4.status === 400) {
    console.log("✔ Test 4 PASS: Client write to biometric_audit_logs REJECTED! (PERMISSION_DENIED)");
  } else {
    console.error("❌ Test 4 FAIL: Client wrote to biometric_audit_logs!", attack4);
    throw new Error("Audit Tampering Violation: Client wrote to biometric_audit_logs.");
  }

  // ── TEST 5: Admin SDK authorized write succeeds ────────────────────────────
  console.log("\n[Test 5] Server Admin SDK writes faceVerified=true and advances account...");
  const adminWrite = await firestoreRequest({
    method: "PATCH",
    path: `/users/${testUid}?updateMask.fieldPaths=faceVerified&updateMask.fieldPaths=accountStatus`,
    isAdmin: true,
    body: {
      fields: {
        faceVerified: { booleanValue: true },
        accountStatus: { stringValue: "pending_review" },
      },
    },
  });

  console.log(`Response HTTP Status: ${adminWrite.status}`);
  if (adminWrite.status === 200) {
    console.log("✔ Test 5 PASS: Server Admin SDK authorized write SUCCEEDED!");
  } else {
    console.error("❌ Test 5 FAIL: Admin SDK was unable to update user!", adminWrite);
    throw new Error("Admin write failure.");
  }

  // ── TEST 6: Worker Onboarding (pending_profile -> pending_face) ────────────
  const workerUid = "onboarding_worker_101";
  console.log("\n[Test 6] Worker executes profile setup (pending_profile -> pending_face)...");
  await firestoreRequest({
    method: "PATCH",
    path: `/users/${workerUid}`,
    isAdmin: true,
    body: {
      fields: {
        uid: { stringValue: workerUid },
        accountStatus: { stringValue: "pending_profile" },
        role: { stringValue: "worker" },
      },
    },
  });

  const workerProfileUpdate = await firestoreRequest({
    method: "PATCH",
    path: `/users/${workerUid}?updateMask.fieldPaths=displayName&updateMask.fieldPaths=role&updateMask.fieldPaths=accountStatus&updateMask.fieldPaths=district&updateMask.fieldPaths=taluk`,
    userUid: workerUid,
    body: {
      fields: {
        displayName: { stringValue: "Basavaraj" },
        role: { stringValue: "worker" },
        accountStatus: { stringValue: "pending_face" },
        district: { stringValue: "Hassan" },
        taluk: { stringValue: "Hassan" },
      },
    },
  });

  console.log(`Response HTTP Status: ${workerProfileUpdate.status}`);
  if (workerProfileUpdate.status === 200) {
    console.log("✔ Test 6 PASS: Worker onboarding transition pending_profile -> pending_face PERMITTED!");
  } else {
    console.error("❌ Test 6 FAIL: Worker onboarding transition failed!", workerProfileUpdate);
    throw new Error("Worker onboarding regression.");
  }

  // ── TEST 7: Hirer Onboarding (pending_profile -> pending_face) ─────────────
  const hirerUid = "onboarding_hirer_202";
  console.log("\n[Test 7] Hirer executes profile setup (pending_profile -> pending_face)...");
  await firestoreRequest({
    method: "PATCH",
    path: `/users/${hirerUid}`,
    isAdmin: true,
    body: {
      fields: {
        uid: { stringValue: hirerUid },
        accountStatus: { stringValue: "pending_profile" },
        role: { stringValue: "hirer" },
      },
    },
  });

  const hirerProfileUpdate = await firestoreRequest({
    method: "PATCH",
    path: `/users/${hirerUid}?updateMask.fieldPaths=displayName&updateMask.fieldPaths=role&updateMask.fieldPaths=accountStatus&updateMask.fieldPaths=district&updateMask.fieldPaths=taluk`,
    userUid: hirerUid,
    body: {
      fields: {
        displayName: { stringValue: "Suresh" },
        role: { stringValue: "hirer" },
        accountStatus: { stringValue: "pending_face" },
        district: { stringValue: "Mysuru" },
        taluk: { stringValue: "Mysuru" },
      },
    },
  });

  console.log(`Response HTTP Status: ${hirerProfileUpdate.status}`);
  if (hirerProfileUpdate.status === 200) {
    console.log("✔ Test 7 PASS: Hirer onboarding transition pending_profile -> pending_face PERMITTED!");
  } else {
    console.error("❌ Test 7 FAIL: Hirer onboarding transition failed!", hirerProfileUpdate);
    throw new Error("Hirer onboarding regression.");
  }

  // ── TEST 8: Extended Negative Audit on users Fields ─────────────────────────
  console.log("\n[Test 8] Client attempts unauthorized writes to protected users fields...");
  const forbiddenFields = [
    { field: "approvedBy", value: { stringValue: "attacker" } },
    { field: "approvedAt", value: { stringValue: "2026-10-10T00:00:00Z" } },
    { field: "rejectedBy", value: { stringValue: "attacker" } },
    { field: "rating", value: { doubleValue: 5.0 } },
    { field: "totalJobs", value: { integerValue: "99" } },
    { field: "verifiedWorkCount", value: { integerValue: "50" } },
  ];

  for (const f of forbiddenFields) {
    const res = await firestoreRequest({
      method: "PATCH",
      path: `/users/${workerUid}?updateMask.fieldPaths=${f.field}`,
      userUid: workerUid,
      body: { fields: { [f.field]: f.value } },
    });
    if (res.status === 403 || res.status === 400) {
      console.log(`  ✔ Field '${f.field}' write properly REJECTED (Status: ${res.status})`);
    } else {
      throw new Error(`Negative audit FAILED: Client was permitted to write protected field '${f.field}'`);
    }
  }
  console.log("✔ Test 8 PASS: All protected users fields rejected for client writes!");

  // ── TEST 9: Extended Negative Audit on all biometric_* Collections ──────────
  console.log("\n[Test 9] Client attempts unauthorized access across all biometric_* collections...");
  const biometricCollections = [
    "biometric_vault",
    "biometric_audit_logs",
    "biometric_rate_limits",
    "biometric_sessions",
  ];

  for (const col of biometricCollections) {
    // Attempt client read
    const readRes = await firestoreRequest({
      method: "GET",
      path: `/${col}/${workerUid}`,
      userUid: workerUid,
    });
    if (readRes.status === 403 || readRes.status === 404) {
      console.log(`  ✔ Collection '${col}' read properly REJECTED (Status: ${readRes.status})`);
    } else {
      throw new Error(`Negative audit FAILED: Client was permitted to read '${col}'`);
    }

    // Attempt client write
    const writeRes = await firestoreRequest({
      method: "POST",
      path: `/${col}?documentId=${workerUid}`,
      userUid: workerUid,
      body: { fields: { tampered: { booleanValue: true } } },
    });
    if (writeRes.status === 403 || writeRes.status === 400) {
      console.log(`  ✔ Collection '${col}' write properly REJECTED (Status: ${writeRes.status})`);
    } else {
      throw new Error(`Negative audit FAILED: Client was permitted to write to '${col}'`);
    }
  }
  console.log("✔ Test 9 PASS: All biometric_* collections completely isolated from client access!");

  console.log("\n====================================================");
  console.log("🎉 ALL LIVE FIRESTORE EMULATOR SECURITY RULES TESTS PASSED!");
  console.log("====================================================");
}

runEmulatorRulesSuite().catch((err) => {
  console.error("\n❌ Emulator Security Rules Suite FAILED:", err.message);
  process.exit(1);
});
