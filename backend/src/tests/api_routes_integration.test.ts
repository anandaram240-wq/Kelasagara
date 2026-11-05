// backend/src/tests/api_routes_integration.test.ts
process.env.ALLOW_DEV_TOKEN = "true";

import assert from "assert";
import { faceRouter } from "../routes/face_routes";
import { FirestoreBiometricRepository } from "../services/firestore_biometric_repository";
import { SessionChallengeService } from "../services/session_challenge_service";
import { runFaceInference } from "../services/face_inference";

console.log("================================================================================");
console.log("            PHASE 9: SERVICES & API ROUTES INTEGRATION TEST SUITE               ");
console.log("================================================================================\n");

const testImageBuffer = Buffer.alloc(112 * 112 * 3, 128);
const testImageBase64 = testImageBuffer.toString("base64");
let testEnrolledVector: number[] = [];

// Mock repository calls for deterministic, zero-network unit test execution
FirestoreBiometricRepository.getEnrolledTemplate = async (uid: string) => {
  if (uid === "enrolled_user_123") {
    return testEnrolledVector;
  }
  return null;
};

FirestoreBiometricRepository.deleteTemplate = async (_uid: string) => {
  return;
};

function dispatchRouter(options: {
  method: string;
  url: string;
  headers?: Record<string, string>;
  body?: any;
  query?: Record<string, string>;
}): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const req: any = {
      method: options.method,
      url: options.url,
      originalUrl: `/api/biometrics${options.url}`,
      headers: options.headers || {},
      body: options.body || {},
      query: options.query || {},
      ip: "127.0.0.1",
      socket: { remoteAddress: "127.0.0.1" },
    };

    const res: any = {
      statusCode: 200,
      headers: {},
      status(code: number) {
        this.statusCode = code;
        return this;
      },
      json(data: any) {
        this.body = data;
        resolve({ status: this.statusCode, body: data });
        return this;
      },
      send(data: any) {
        this.body = data;
        resolve({ status: this.statusCode, body: data });
        return this;
      },
      setHeader(key: string, val: string) {
        this.headers[key] = val;
      },
    };

    try {
      (faceRouter as any)(req, res, (err: any) => {
        if (err) {
          reject(err);
        } else {
          resolve({ status: res.statusCode, body: res.body });
        }
      });
    } catch (err) {
      reject(err);
    }
  });
}

async function runTests() {
  let passedCount = 0;

  // Initialize test enrolled vector from authoritative neural inference
  testEnrolledVector = await runFaceInference(testImageBuffer);

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 1: GET /health returns 200 with uniform response structure
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 1: GET /api/biometrics/health probe...");
  {
    const res = await dispatchRouter({
      method: "GET",
      url: "/health",
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, "healthy");
    assert.strictEqual(res.body.data.tier, "RESEARCH_ONLY");
    assert.strictEqual(res.body.data.database, "Cloud Firestore Asia-South1 Only");
    assert.ok(res.body.serverTimestamp);

    passedCount++;
    console.log("  [PASS] Health probe returned uniform 200 payload.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2: POST /challenge enforces authentication
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2: POST /api/biometrics/challenge authentication requirement...");
  {
    // Missing auth header
    const resUnauth = await dispatchRouter({
      method: "POST",
      url: "/challenge",
      body: { action: "ENROLLMENT" },
    });
    assert.strictEqual(resUnauth.status, 401);
    assert.strictEqual(resUnauth.body.error, "unauthenticated");

    // Valid dev auth header with invalid action
    const resBadAction = await dispatchRouter({
      method: "POST",
      url: "/challenge",
      headers: { "x-dev-uid": "test_uid_001" },
      body: { action: "INVALID_ACTION" },
    });
    assert.strictEqual(resBadAction.status, 400);
    assert.strictEqual(resBadAction.body.error.code, "INVALID_ACTION");

    passedCount++;
    console.log("  [PASS] Authentication and action validation enforced.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2B: Ticket T-01: Client Vector Rejection (fixes D1)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2B: Ticket T-01: Client vector submission rejection (400 Bad Request)...");
  {
    // 1. Submit embedding in /enroll -> 400 CLIENT_VECTORS_FORBIDDEN
    const resEnrollEmbedding = await dispatchRouter({
      method: "POST",
      url: "/enroll",
      headers: { "x-dev-uid": "test_uid_001" },
      body: {
        role: "worker",
        imageBase64: testImageBase64,
        embedding: new Array(128).fill(0.1),
      },
    });
    assert.strictEqual(resEnrollEmbedding.status, 400);
    assert.strictEqual(resEnrollEmbedding.body.error.code, "CLIENT_VECTORS_FORBIDDEN");

    // 2. Submit probeVector in /verify-1to1 -> 400 CLIENT_VECTORS_FORBIDDEN
    const resVerifyProbeVector = await dispatchRouter({
      method: "POST",
      url: "/verify-1to1",
      headers: { "x-dev-uid": "test_uid_001" },
      body: {
        role: "worker",
        imageBase64: testImageBase64,
        probeVector: new Array(128).fill(0.1),
      },
    });
    assert.strictEqual(resVerifyProbeVector.status, 400);
    assert.strictEqual(resVerifyProbeVector.body.error.code, "CLIENT_VECTORS_FORBIDDEN");

    // 3. Submit landmarks in /verify-login -> 400 CLIENT_VECTORS_FORBIDDEN
    const resVerifyLandmarks = await dispatchRouter({
      method: "POST",
      url: "/verify-login",
      headers: { "x-dev-uid": "test_uid_001" },
      body: {
        role: "worker",
        imageBase64: testImageBase64,
        landmarks: [1, 2, 3],
      },
    });
    assert.strictEqual(resVerifyLandmarks.status, 400);
    assert.strictEqual(resVerifyLandmarks.body.error.code, "CLIENT_VECTORS_FORBIDDEN");

    // 4. Missing imageBase64 in /verify-1to1 -> 400 MISSING_IMAGE_BASE64
    const resMissingImage = await dispatchRouter({
      method: "POST",
      url: "/verify-1to1",
      headers: { "x-dev-uid": "test_uid_001" },
      body: {
        role: "worker",
      },
    });
    assert.strictEqual(resMissingImage.status, 400);
    assert.strictEqual(resMissingImage.body.error.code, "MISSING_IMAGE_BASE64");

    passedCount++;
    console.log("  [PASS] All client-supplied vector payloads strictly rejected with 400 Bad Request.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 3: Issue Challenge Nonce with 60s TTL (Invariant I-04)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 3: Issue challenge nonce bound to caller UID (Invariant I-04)...");
  let enrollmentNonce = "";
  {
    const res = await dispatchRouter({
      method: "POST",
      url: "/challenge",
      headers: { "x-dev-uid": "test_uid_001" },
      body: { action: "ENROLLMENT" },
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, "challenge_issued");
    assert.ok(res.body.data.challengeNonce);
    assert.strictEqual(res.body.data.action, "ENROLLMENT");
    assert.strictEqual(res.body.data.ttlSeconds, 60);

    enrollmentNonce = res.body.data.challengeNonce;
    passedCount++;
    console.log(`  [PASS] Challenge nonce issued cleanly: ${enrollmentNonce.substring(0, 16)}...\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 4: Challenge Nonce Cross-Action & Replay Protection (Invariant I-05)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 4: Invariant I-05: Nonce replay & cross-action rejection...");
  {
    // Attempt to use ENROLLMENT nonce for VERIFICATION endpoint
    const resCrossAction = await dispatchRouter({
      method: "POST",
      url: "/verify-1to1",
      headers: { "x-dev-uid": "test_uid_001" },
      body: {
        challengeNonce: enrollmentNonce,
        imageBase64: testImageBase64,
        role: "worker",
      },
    });

    assert.strictEqual(resCrossAction.status, 403);
    assert.strictEqual(resCrossAction.body.error.code, "INVALID_CHALLENGE_NONCE");

    passedCount++;
    console.log("  [PASS] Cross-action challenge theft strictly blocked (Invariant I-05).\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 5: Constant-Time Latency Padding & Uniform Responses (Invariant I-08, I-23)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 5: Invariants I-08 & I-23: Constant-Time Latency Bucketing...");
  {
    const startMs = Date.now();
    const res = await dispatchRouter({
      method: "POST",
      url: "/verify-1to1",
      headers: { "x-dev-uid": "non_enrolled_user_999" },
      body: {
        imageBase64: testImageBase64,
        role: "worker",
      },
    });

    const elapsedMs = Date.now() - startMs;
    // Not enrolled should return 404
    assert.strictEqual(res.status, 404);
    assert.strictEqual(res.body.error.code, "NOT_ENROLLED");
    assert.ok(res.body.serverTimestamp);

    // Latency should be padded to at least ~100ms
    assert.ok(
      elapsedMs >= 100,
      `Expected padded latency >= 100ms, got ${elapsedMs}ms`
    );

    passedCount++;
    console.log(`  [PASS] Latency padding observed: ${elapsedMs}ms (oracle-resistant).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 6: Successful 1:1 Facial Verification Flow
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 6: Successful 1:1 Verification with Valid Nonce...");
  {
    // Issue verification nonce
    const challengeRes = await dispatchRouter({
      method: "POST",
      url: "/challenge",
      headers: { "x-dev-uid": "enrolled_user_123" },
      body: { action: "VERIFICATION" },
    });
    const verifNonce = challengeRes.body.data.challengeNonce;

    const resMatch = await dispatchRouter({
      method: "POST",
      url: "/verify-1to1",
      headers: { "x-dev-uid": "enrolled_user_123" },
      body: {
        challengeNonce: verifNonce,
        imageBase64: testImageBase64,
        role: "worker",
      },
    });

    assert.strictEqual(resMatch.status, 200);
    assert.strictEqual(resMatch.body.success, true);
    assert.strictEqual(resMatch.body.status, "verified");
    assert.strictEqual(resMatch.body.data.isMatch, true);
    assert.ok(resMatch.body.data.similarity > 0.99);

    passedCount++;
    console.log("  [PASS] 1:1 facial verification match succeeded with cosine similarity ~ 1.000.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 7: DPDPA Right to Erasure Authorization Isolation (Invariant I-24)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 7: DPDPA Section 12 Right-to-Erasure Access Control...");
  {
    // Attempt to delete another user's template without admin role
    const resForbidden = await dispatchRouter({
      method: "DELETE",
      url: "/template?targetUid=victim_user_xyz",
      headers: { "x-dev-uid": "attacker_user_abc" },
      query: { targetUid: "victim_user_xyz" },
    });

    assert.strictEqual(resForbidden.status, 403);
    assert.strictEqual(resForbidden.body.error.code, "FORBIDDEN");

    // Attempt to delete own template
    const resOwn = await dispatchRouter({
      method: "DELETE",
      url: "/template?targetUid=own_user_abc",
      headers: { "x-dev-uid": "own_user_abc" },
      query: { targetUid: "own_user_abc" },
    });

    assert.strictEqual(resOwn.status, 200);
    assert.strictEqual(resOwn.body.success, true);
    assert.strictEqual(resOwn.body.status, "deleted");

    passedCount++;
    console.log("  [PASS] Cross-user template deletion blocked (403); own template deletion succeeded (200).\n");
  }

  console.log("================================================================================");
  console.log(`   PHASE 9 TESTS COMPLETE: ALL ${passedCount}/${passedCount} SUITES PASSED CLEANLY   `);
  console.log("================================================================================\n");
}

runTests().catch((err) => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
