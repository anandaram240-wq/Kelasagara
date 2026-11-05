# PHASE 20.13: ACCOUNT RECOVERY & OWNERSHIP ASSURANCE
## Cryptographic and Multi-Factor Separation Between Identity Claims and Account Ownership

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Security Architect & Identity Assurance Engineer  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & INTEGRATION_TEST_VERIFIED  

---

### 1. Identity Verification vs. Account Ownership Verification

A critical conceptual vulnerability in biometric identity systems is conflating **Identity Verification** with **Account Ownership**:
- **Identity Verification** proves: *"The person standing in front of the camera matches the face stored in Profile X."*
- **Account Ownership Verification** proves: *"The person requesting access is the legitimate, authorized holder of the target account and possesses control of the account's existing recovery credentials."*

If an attacker identifies a victim's face in a database (or a duplicate detection event is flagged), the attacker must **never** be permitted to provide their own new phone number to receive a recovery OTP and claim ownership of the victim's account.

---

### 2. The Arbitrary Phone Replacement Attack

Consider this attack vector:
1. Attacker Bob registers a duplicate account. The system flags that Bob's face matches existing User Alice (`user_alice_456`).
2. Bob requests account resolution and provides his own telephone number (`+91-98765-00000`).
3. If the backend sends an OTP to `+91-98765-00000` and Bob enters it correctly, Bob has proved control over his own phone—**not Alice's account**.
4. If the system then merges Alice's account into Bob's profile, Bob has successfully stolen Alice's account, earnings, and identity history.

---

### 3. Hardened Defense: Factor-Bound OTP Dispatch

In `src/services/recovery_ownership_verifier_v13.ts`, the recovery engine enforces that SMS OTP challenges **must strictly be dispatched to the target account's pre-existing registered telephone number**:

```typescript
export async function initiateRecoveryOtpChallenge(
  session: RecoverySession,
  targetAccount: TargetAccountRecord,
  suppliedPhoneNumber?: string
): Promise<{ challengeId: string; maskedDestination: string }> {
  // If caller supplied a phone number, it MUST match the pre-existing factor
  if (suppliedPhoneNumber && suppliedPhoneNumber !== targetAccount.registeredPhoneNumber) {
    throw new SecurityError(
      'ERR_ARBITRARY_PHONE_REJECTED: Recovery OTP cannot be dispatched to an unverified arbitrary phone number.'
    );
  }

  // Strictly target the pre-existing account factor
  const targetDestination = targetAccount.registeredPhoneNumber;
  const otpCode = crypto.randomInt(100000, 999999).toString();
  const otpHmac = computeOtpHmac(session.sessionId, otpCode);

  session.otpChallenge = {
    challengeId: `ch_${crypto.randomBytes(8).toString('hex')}`,
    otpHmac,
    targetPhoneNumber: targetDestination,
    attemptsRemaining: 5,
    expiresAt: Date.now() + 10 * 60 * 1000, // 10 minutes TTL
    consumed: false,
  };

  await dispatchSmsGateway(targetDestination, otpCode);
  return {
    challengeId: session.otpChallenge.challengeId,
    maskedDestination: maskPhoneNumber(targetDestination),
  };
}
```

---

### 4. Recovery Session Security Invariants

The recovery verifier enforces five non-negotiable security bounds:

1. **Strict Factor Binding:** OTP is sent exclusively to `targetAccount.registeredPhoneNumber`. Any arbitrary replacement number is rejected with `ERR_ARBITRARY_PHONE_REJECTED`.
2. **Brute-Force Rate Limiting:** Maximum 5 verification attempts. Each incorrect attempt decrements `attemptsRemaining`. Upon reaching 0, the session is locked permanently (`ERR_OTP_LOCKED`).
3. **Session TTL Expiration:** Recovery sessions and OTP challenges expire after exactly 10 minutes (`ERR_CASE_EXPIRED`).
4. **Single-Use Consumption:** Successful OTP verification immediately marks `consumed: true`. Any replay attempt throws `ERR_OTP_ALREADY_CONSUMED`.
5. **Multi-Factor Requirement:** An opaque case reference (`CASE-...`) alone cannot authorize recovery without independent factor verification (`ERR_INSUFFICIENT_RECOVERY_FACTORS`).

---

### 5. Automated Verification Results

In `src/tests/phase20_13_privileged_backend_security.test.ts` (Tests 25–28, 32):
- **Test 25 (PASS):** Case reference alone cannot authorize recovery.
- **Test 26 (PASS):** Arbitrary phone number supplied as original-account proof is rejected with `ERR_ARBITRARY_PHONE_REJECTED`.
- **Test 27 (PASS):** Consumed OTP cannot be reused.
- **Test 28 (PASS):** Expired recovery case fails closed.
- **Test 32 (PASS):** Recovery workflow strictly halts if independent ownership verification is bypassed.
