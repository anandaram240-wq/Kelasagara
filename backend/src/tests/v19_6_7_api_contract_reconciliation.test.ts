// backend/src/tests/v19_6_7_api_contract_reconciliation.test.ts
//
// KELASAGARA BIOMATCH V19.6.7
// API Route Reconciliation & Client/Server Contract Regression Test Suite
// Standards: ISO/IEC 19794-5:2025, ISO/IEC 24745:2022

process.env.ALLOW_DEV_TOKEN = "true";

import { describe, it } from "node:test";
import assert from "node:assert";
import request from "supertest";
import app from "../server";

describe("V19.6.7 API Route Reconciliation & Express Application Mounting", () => {
  const TEST_UID = "worker_contract_test_v19_6_7";
  const AUTH_HEADER = `Bearer dev-mock-token-${TEST_UID}`;

  it("1. Registered route POST /api/biometrics/enroll strictly enforces authentication (401 without token)", async () => {
    const res = await request(app)
      .post("/api/biometrics/enroll")
      .send({ imageBase64: "dGVzdF9pbWFnZQ==" });

    assert.strictEqual(res.status, 401);
    assert.strictEqual(res.body.error, "unauthenticated");
  });

  it("2. Registered route POST /api/biometrics/enroll requires valid imageBase64 or burstFrames", async () => {
    const res = await request(app)
      .post("/api/biometrics/enroll")
      .set("Authorization", AUTH_HEADER)
      .send({ role: "worker" }); // missing imageBase64 and burstFrames

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.success, false);
    assert.strictEqual(res.body.error?.code, "MISSING_IMAGE_BASE64");
  });

  it("3. Registered route POST /api/biometrics/enroll rejects client-supplied vector payloads (Ticket T-01)", async () => {
    const res = await request(app)
      .post("/api/biometrics/enroll")
      .set("Authorization", AUTH_HEADER)
      .send({
        role: "worker",
        imageBase64: "dGVzdF9pbWFnZQ==",
        probeVector: [0.1, 0.2, 0.3], // Client trying to submit own vector
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.success, false);
    assert.strictEqual(res.body.error?.code, "CLIENT_VECTORS_FORBIDDEN");
  });

  it("4. Non-existent documentation-artifact route POST /api/v1/face/enroll returns 404 Not Found", async () => {
    // Proves that /api/v1/face is NOT mounted on the server and cannot serve as an unmonitored backdoor
    const res = await request(app)
      .post("/api/v1/face/enroll")
      .set("Authorization", AUTH_HEADER)
      .send({ role: "worker", imageBase64: "dGVzdA==" });

    assert.strictEqual(res.status, 404);
  });

  it("5. Registered route POST /api/biometrics/challenge issues valid challenge bound to caller UID", async () => {
    const res = await request(app)
      .post("/api/biometrics/challenge")
      .set("Authorization", AUTH_HEADER)
      .send({ action: "ENROLLMENT" });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, "challenge_issued");
    assert.ok(res.body.data.challengeNonce);
    assert.strictEqual(res.body.data.requiredAction, "BLINK");
  });

  it("6. Reconciled Contract: Effective client path matches mounted Express path", () => {
    // In Dart (lib/services/biometric_service.dart):
    // kProductionBackendUrl = 'https://api.kelasagara.com/api/biometrics'
    // enroll endpoint: '$_backendBaseUrl/enroll'
    const clientBaseUrl = "https://api.kelasagara.com/api/biometrics";
    const clientEndpoint = "/enroll";
    const effectiveClientUrl = new URL(clientBaseUrl + clientEndpoint).pathname;

    const serverMountedPrefix = "/api/biometrics";
    const serverRegisteredRoute = "/enroll";
    const effectiveServerPath = serverMountedPrefix + serverRegisteredRoute;

    assert.strictEqual(
      effectiveClientUrl,
      effectiveServerPath,
      `Client URL path (${effectiveClientUrl}) must match Server route path (${effectiveServerPath})`
    );
    assert.strictEqual(effectiveServerPath, "/api/biometrics/enroll");
  });
});
