/**
 * security/redteam/test_liveness_injection_bypass.ts
 *
 * Runner for Redteam Injection & Liveness Bypass Adversarial Suite.
 * Invokes the backend test suite verifying Invariants I-04, I-05, and I-21.
 */

const { execSync } = require("child_process");
const path = require("path");

try {
  const backendDir = path.resolve(__dirname, "../../backend");
  const testScript = path.resolve(backendDir, "src/tests/test_liveness_injection_bypass.test.ts");
  console.log(`[Redteam] Spawning injection bypass test: ${testScript}`);
  const out = execSync(`npx ts-node "${testScript}"`, {
    cwd: backendDir,
    encoding: "utf-8",
  });
  console.log(out);
  console.log("[Redteam] Injection bypass test completed successfully.");
} catch (err: any) {
  console.error("[Redteam] Injection bypass test failed:", err.message);
  process.exit(1);
}
