// backend/src/tests/test_liveness_injection_bypass.test.ts
import assert from "assert";
import { SessionChallengeService } from "../services/session_challenge_service";

async function runRedteamInjectionBypassSuite() {
  console.log("====================================================");
  console.log("🛡️ REDTEAM: INJECTION & LIVENESS BYPASS ADVERSARIAL SUITE");
  console.log("====================================================");

  SessionChallengeService.reset();

  // ── TEST 1: Normal Legitimate Challenge-Response Flow
  console.log("Executing Test 1: Legitimate challenge generation and consumption...");
  const legitimate = SessionChallengeService.issueChallenge("worker_777", "enrollment");
  assert.ok(legitimate.challengeId.startsWith("chal_"));
  assert.strictEqual(legitimate.nonce.length, 64);
  assert.strictEqual(legitimate.uid, "worker_777");

  // Consume legitimately
  SessionChallengeService.validateAndConsume(
    legitimate.challengeId,
    legitimate.nonce,
    "worker_777",
    "enrollment"
  );
  console.log("✔ Test 1: Legitimate challenge-response passed successfully.");

  // ── TEST 2: Replay Attack (Attacker intercepts and resubmits same nonce)
  console.log("Executing Test 2: Attacker attempts replay of consumed nonce (Invariant I-05)...");
  let replayBlocked = false;
  try {
    SessionChallengeService.validateAndConsume(
      legitimate.challengeId,
      legitimate.nonce,
      "worker_777",
      "enrollment"
    );
  } catch (err: any) {
    replayBlocked = true;
    assert.ok(
      err.message.includes("does not exist") || err.message.includes("Replay attack"),
      `Expected replay detection, got: ${err.message}`
    );
  }
  assert.strictEqual(replayBlocked, true, "Replay attack must be strictly rejected!");
  console.log("✔ Test 2: Replay attack successfully intercepted and blocked (Invariant I-05).");

  // ── TEST 3: Cross-User Token Forgery / Identity Impersonation (Invariant I-04)
  console.log("Executing Test 3: Attacker attempts to use victim's challenge (Invariant I-04)...");
  const victimChallenge = SessionChallengeService.issueChallenge("victim_uid_888", "enrollment");
  let impersonationBlocked = false;
  try {
    // Attacker sends victim's challengeId and nonce under attacker's authenticated UID
    SessionChallengeService.validateAndConsume(
      victimChallenge.challengeId,
      victimChallenge.nonce,
      "attacker_uid_999", // Mismatched UID
      "enrollment"
    );
  } catch (err: any) {
    impersonationBlocked = true;
    assert.ok(err.message.includes("Identity mismatch"), `Expected identity mismatch, got: ${err.message}`);
  }
  assert.strictEqual(impersonationBlocked, true, "Impersonation of challenge must be rejected!");
  console.log("✔ Test 3: Cross-user challenge theft blocked via strict identity binding (Invariant I-04).");

  // ── TEST 4: Action Mismatch (Replaying verification nonce for enrollment)
  console.log("Executing Test 4: Attacker attempts cross-action replay (verification -> enrollment)...");
  const stepUpChallenge = SessionChallengeService.issueChallenge("worker_777", "verification");
  let actionMismatchBlocked = false;
  try {
    SessionChallengeService.validateAndConsume(
      stepUpChallenge.challengeId,
      stepUpChallenge.nonce,
      "worker_777",
      "enrollment" // Attempted for enrollment instead of verification
    );
  } catch (err: any) {
    actionMismatchBlocked = true;
    assert.ok(err.message.includes("Action mismatch"), `Expected action mismatch, got: ${err.message}`);
  }
  assert.strictEqual(actionMismatchBlocked, true, "Cross-action challenge misuse must be blocked!");
  console.log("✔ Test 4: Cross-action replay blocked (Invariant I-05).");

  // ── TEST 5: Tampered Cryptographic Nonce
  console.log("Executing Test 5: Attacker tampers with nonce string...");
  const validChal = SessionChallengeService.issueChallenge("worker_123", "enrollment");
  let tamperedNonceBlocked = false;
  try {
    SessionChallengeService.validateAndConsume(
      validChal.challengeId,
      "forged_nonce_random_string",
      "worker_123",
      "enrollment"
    );
  } catch (err: any) {
    tamperedNonceBlocked = true;
    assert.ok(err.message.includes("nonce mismatch"), `Expected nonce mismatch, got: ${err.message}`);
  }
  assert.strictEqual(tamperedNonceBlocked, true, "Tampered nonce must be blocked!");
  console.log("✔ Test 5: Tampered nonce rejected (Invariant I-05).");

  console.log("====================================================");
  console.log("🎉 ALL REDTEAM INJECTION & LIVENESS BYPASS TESTS PASSED!");
  console.log("====================================================");
}

runRedteamInjectionBypassSuite().catch((err) => {
  console.error("❌ Redteam test suite failed:", err);
  process.exit(1);
});
