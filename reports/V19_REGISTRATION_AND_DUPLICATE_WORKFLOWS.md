# V19 Registration and Duplicate Workflows

## 1. Journey A: New Worker/Hirer Registration & Mandatory Gating
1. **Basic Details Completion:** User enters name, contact number, role, trade credentials in `RegistrationScreen`.
2. **Mandatory Biometric Navigation:** `RegistrationScreen` advances to `FaceEnrollmentScreen`. Account remains in `PENDING_FACE` state.
3. **Challenge Acquisition:** App queries `/api/biometrics/challenge` (or Callable fallback) obtaining a single-use 60s ticket with 32-byte nonce.
4. **Hardware Capture & Temporal Liveness:** Captures 3 frames satisfying $F_1 \to F_2 (\text{Apex Closed}) \to F_3 (\text{Reopened})$.
5. **Authoritative Server Matching:** Backend executes YuNet alignment $\to$ SFace 128-D extraction $\to$ 1:N scan against `InMemoryBiometricIndex`.
6. **Enrollment Finalization:** If candidate similarity $< 0.74$, commits envelope to `biometric_vault/{uid}` and marks `faceVerified: true` in `users/{uid}`.

## 2. Journey B: Duplicate Account Interception (Anti-Fraud)
1. **Scenario:** A user previously enrolled under `UID_A` attempts to register a new account under `UID_B` using a different SIM or name.
2. **1:N Candidate Discovery:** Backend scan discovers similarity $S \ge 0.74$.
   - **$S \ge 0.90$ (Hard Block):** Unmistakable duplicate. Registration is blocked immediately.
   - **$0.74 \le S < 0.90$ (Flagged Review):** Borderline match routed to administrative review queue (`biometric_review_queue`).
3. **Anti-Enumeration & Privacy Policy:**
   - Raw similarity score, victim UID, and full profile details are strictly withheld from the untrusted client.
   - The response returns a masked hint: `KLS-{masked_uid}-{phone_last4}`.
   - Client renders `DuplicateDetectedSheet` displaying:
     * Masked ID: `KLS-xK9***wXy-5177`
     * Masked Phone: `+91 ******5177`
     * Actionable advice: "If this is your account, log in with your original mobile number."
4. **Rate Limiting:** Repeated probe attempts with distinct credentials but identical facial geometry trigger IP/Device-level rate limits and audit log events (`CROSS_ACCOUNT_HARD_BLOCK`).

## 3. Journey C & D: Retroactive Setup and 1:1 Verification
- **Retroactive Banner:** Legacy users who created accounts prior to biometric enforcement receive `RetroactiveEnrollmentBanner` across their dashboard and profile.
- **Profile Re-Enrollment (`FaceReEnrollTile`):** Users who experience changes in appearance (haircut, spectacles, beard growth, weight change) can trigger re-enrollment from `ProfileScreen`. The 1:N check suppresses self-collision by ignoring the caller's existing `uid`.
- **1:1 Login Verification:** Returning workers verifying shifts query `/api/biometrics/verify-1to1`. The backend extracts probe embedding and compares directly against the stored `biometric_vault/{uid}` envelope using the genuine threshold $\tau_{1:1} = 0.363$.
