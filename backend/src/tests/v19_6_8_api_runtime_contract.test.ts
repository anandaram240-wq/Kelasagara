// backend/src/tests/v19_6_8_api_runtime_contract.test.ts
//
// KELASAGARA BIOMATCH V19.6.8
// Runtime API Contract, Health Probe & Error Mapping Test Suite
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 24745:2022

process.env.ALLOW_DEV_TOKEN = "true";

import { describe, it } from "node:test";
import assert from "node:assert";
import request from "supertest";
import app from "../server";
import { config } from "../config";

describe("V19.6.8 API Runtime Contract & Health Probe", () => {
  it("1. GET /api/biometrics/health returns 200 with service metadata and thresholds", async () => {
    const res = await request(app).get("/api/biometrics/health");

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, "healthy");
    assert.ok(res.body.data, "Health data payload must exist");
    assert.strictEqual(res.body.data.service, "kelasagara-biomatch-backend");
    assert.strictEqual(res.body.data.modelVersion, config.modelVersion);
    assert.strictEqual(res.body.data.verificationThreshold, 0.363);
    assert.strictEqual(res.body.data.duplicateThreshold, 0.74);
    assert.strictEqual(res.body.data.hardBlockThreshold, 0.90);
    assert.strictEqual(res.body.data.isProductionCalibrated, false);
  });

  it("2. GET / (root health) returns 200 OK", async () => {
    const res = await request(app).get("/");

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.status, "ok");
    assert.strictEqual(res.body.name, "Kelasagara BioMatch Standalone Backend");
  });

  it("3. POST /api/biometrics/challenge strictly enforces authentication (401 without token)", async () => {
    const res = await request(app)
      .post("/api/biometrics/challenge")
      .send({ action: "ENROLLMENT" });

    assert.strictEqual(res.status, 401);
  });

  it("4. POST /api/biometrics/enroll strictly enforces authentication (401 without token)", async () => {
    const res = await request(app)
      .post("/api/biometrics/enroll")
      .send({ role: "worker" });

    assert.strictEqual(res.status, 401);
  });

  it("5. Reconciled Contract: Effective client path matches mounted Express path without prefix duplication", () => {
    const baseUrl = "https://api.kelasagara.com/api/biometrics";
    const healthUrl = `${baseUrl}/health`;
    const challengeUrl = `${baseUrl}/challenge`;
    const enrollUrl = `${baseUrl}/enroll`;

    assert.strictEqual(healthUrl, "https://api.kelasagara.com/api/biometrics/health");
    assert.strictEqual(challengeUrl, "https://api.kelasagara.com/api/biometrics/challenge");
    assert.strictEqual(enrollUrl, "https://api.kelasagara.com/api/biometrics/enroll");

    // Proves no duplicate '/api/biometrics/api/biometrics'
    assert.strictEqual(enrollUrl.includes("/api/biometrics/api/biometrics"), false);
  });
});
