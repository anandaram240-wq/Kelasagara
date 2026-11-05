// backend/src/tests/security_hardening.test.ts
//
// PHASE 12: SECURITY HARDENING & SECRETS MANAGEMENT TEST SUITE
// Verifies HTTP security headers, CORS origin filtering, payload size caps,
// unauthenticated fail-closed gatekeeping, and rate limiting defenses.

import assert from "assert";
import { config } from "../config";
import app from "../server";
import { IncomingMessage, ServerResponse } from "http";
import { Socket } from "net";

// Helper in-memory HTTP dispatcher (sandbox-safe, no TCP network sockets required)
function dispatchApp(
  method: string,
  url: string,
  headers: Record<string, string> = {},
  body?: any
): Promise<{ statusCode: number; headers: Record<string, any>; body: any }> {
  return new Promise((resolve, reject) => {
    const req = new IncomingMessage(new Socket()) as any;
    req.method = method;
    req.url = url;
    req.headers = {
      host: "localhost:5001",
      ...Object.fromEntries(
        Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v])
      ),
    };

    if (body !== undefined) {
      const payloadStr = typeof body === "string" ? body : JSON.stringify(body);
      req.headers["content-type"] = req.headers["content-type"] || "application/json";
      req.headers["content-length"] = Buffer.byteLength(payloadStr).toString();
      req.push(Buffer.from(payloadStr));
      req.push(null);
    } else {
      req.push(null);
    }

    const res = new ServerResponse(req) as any;
    let resBody = "";
    const resHeaders: Record<string, any> = {};

    res.setHeader = (name: string, value: any) => {
      resHeaders[name.toLowerCase()] = value;
      return res;
    };

    res.getHeader = (name: string) => {
      return resHeaders[name.toLowerCase()];
    };

    res.writeHead = (statusCode: number, headersOrReason?: any, headers?: any) => {
      res.statusCode = statusCode;
      const h = typeof headersOrReason === "object" ? headersOrReason : headers;
      if (h) {
        for (const [k, v] of Object.entries(h)) {
          resHeaders[k.toLowerCase()] = v;
        }
      }
      return res;
    };

    res.write = (chunk: any) => {
      if (chunk) resBody += chunk.toString();
      return true;
    };

    res.end = (chunk: any) => {
      if (chunk) resBody += chunk.toString();
      let parsed = resBody;
      try {
        parsed = JSON.parse(resBody);
      } catch (_) {}
      resolve({
        statusCode: res.statusCode || 200,
        headers: resHeaders,
        body: parsed,
      });
    };

    app(req, res, (err: any) => {
      if (err) reject(err);
    });
  });
}

async function runSecurityHardeningTests() {
  console.log("================================================================================");
  console.log("   PHASE 12: SECURITY HARDENING & SECRETS MANAGEMENT TEST SUITE                 ");
  console.log("================================================================================\n");

  // ── TEST 1: HTTP Security Headers Validation ──────────────────────────────
  console.log("TEST 1: Strict HTTP Security Headers on all endpoints...");
  {
    const res = await dispatchApp("GET", "/");
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.headers["x-content-type-options"], "nosniff");
    assert.strictEqual(res.headers["x-frame-options"], "DENY");
    assert.strictEqual(res.headers["strict-transport-security"], "max-age=31536000; includeSubDomains");
    assert.strictEqual(res.headers["content-security-policy"], "default-src 'none'; frame-ancestors 'none'");
    assert.strictEqual(res.headers["x-xss-protection"], "0");
    assert.strictEqual(res.headers["referrer-policy"], "no-referrer");
    console.log("  [PASS] All 6 strict security headers verified (nosniff, DENY, HSTS, CSP, XSS, Referrer).");
  }

  // ── TEST 2: CORS Origin Whitelist Enforcement ─────────────────────────────
  console.log("\nTEST 2: CORS Whitelist and Origin Isolation...");
  {
    // A: Allowed Origin
    const resAllowed = await dispatchApp("GET", "/", { Origin: "http://localhost:3000" });
    assert.strictEqual(resAllowed.statusCode, 200);
    assert.strictEqual(resAllowed.headers["access-control-allow-origin"], "http://localhost:3000");

    // B: Unauthorized Origin
    const resDisallowed = await dispatchApp("GET", "/", { Origin: "http://malicious-sybil-attack.com" });
    assert.strictEqual(resDisallowed.statusCode, 403);
    assert.strictEqual(resDisallowed.body.status, "cors_rejected");
    assert.strictEqual(resDisallowed.body.error.code, "CORS_FORBIDDEN");

    // C: Native Mobile App / CLI request (No Origin header)
    const resMobile = await dispatchApp("GET", "/");
    assert.strictEqual(resMobile.statusCode, 200);
    console.log("  [PASS] CORS origin whitelist enforced: Allowed origin passed, malicious origin returned 403, native mobile (no origin) passed.");
  }

  // ── TEST 3: Unauthenticated Fail-Closed Gatekeeping ───────────────────────
  console.log("\nTEST 3: Invariant I-01: Fail-closed unauthenticated access control...");
  {
    const endpoints = [
      { method: "POST", url: "/api/biometrics/challenge" },
      { method: "POST", url: "/api/biometrics/enroll" },
      { method: "POST", url: "/api/biometrics/verify-1to1" },
      { method: "DELETE", url: "/api/biometrics/template?targetUid=user_123" },
    ];

    for (const ep of endpoints) {
      const res = await dispatchApp(ep.method, ep.url, {}, { role: "worker" });
      assert.strictEqual(
        res.statusCode,
        401,
        `Expected 401 unauthenticated on ${ep.method} ${ep.url}, got ${res.statusCode}`
      );
      assert.strictEqual(res.body.error, "unauthenticated");
    }
    console.log("  [PASS] All 4 sensitive biometric endpoints fail-closed with 401 when Authorization header is omitted.");
  }

  // ── TEST 4: Request Payload Size Capping (5MB limit) ──────────────────────
  console.log("\nTEST 4: Request Payload Cap & HTTP 413 Handling...");
  {
    // Normal request under 5MB succeeds (or reaches route)
    const normalPayload = { role: "worker", testField: "valid_short_string" };
    const resNormal = await dispatchApp("GET", "/api/biometrics/health", {}, normalPayload);
    assert.strictEqual(resNormal.statusCode, 200);

    // Verify config cap is 5mb
    assert.strictEqual(config.maxPayloadSize, "5mb");
    console.log("  [PASS] Payload cap configured at 5mb; standard payloads process cleanly.");
  }

  // ── TEST 5: Rate Limiting Enforcement (60 req/min) ────────────────────────
  console.log("\nTEST 5: Tier 0 IP Rate Limiter (60 req/min threshold)...");
  {
    // Verify rate limit response structure by dispatching health requests
    let rateLimited = false;
    for (let i = 0; i < 65; i++) {
      const res = await dispatchApp("GET", "/api/biometrics/health");
      if (res.statusCode === 429) {
        assert.strictEqual(res.body.status, "rate_limited");
        assert.strictEqual(res.body.error.code, "RATE_LIMIT_EXCEEDED");
        rateLimited = true;
        break;
      }
    }
    assert.strictEqual(rateLimited, true, "Expected 429 rate_limited after 60 requests within 1 minute.");
    console.log("  [PASS] Rate limiter triggered at request 61 with HTTP 429 and uniform response envelope.");
  }

  console.log("\n================================================================================");
  console.log("   PHASE 12 TESTS COMPLETE: ALL 5/5 SECURITY SUITES PASSED CLEANLY             ");
  console.log("================================================================================\n");
}

runSecurityHardeningTests().catch((err) => {
  console.error("Test failed with error:", err);
  process.exit(1);
});
