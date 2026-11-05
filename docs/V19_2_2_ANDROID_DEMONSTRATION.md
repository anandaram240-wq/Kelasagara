# KELASAGARA BIOMETRIC ENGINE V19.2.2: PHYSICAL ANDROID DEMONSTRATION PROTOCOL

## 1. Prerequisites
- **Target Device:** Physical Android phone (Android 10+ / API 29+) running on mobile cellular data (Jio, Airtel 4G/5G) or external Wi-Fi.
- **Release APK Artifact:** `Kelasagara-v19.2.2-release.apk` (or `Kelasagara-release.apk`).
- **SHA-256 Checksum:** `b327dce33d012f6df151c28f39de27d45842109fa6cd25b3153789c93bc40f55`.

---

## 2. University Evaluation & Live Demonstration Steps

### Step 1: Clean Installation
```bash
adb install -r Kelasagara-v19.2.2-release.apk
```
Launch the Kelasagara application from the app drawer.

### Step 2: Fresh Identity Enrollment (Worker Registration)
1. Navigate to **Worker Registration** (`/register/worker`).
2. Enter personal details (e.g., name, phone number, primary skill).
3. Tap **Next: Face Verification**.
4. Observe the interactive camera viewfinder:
   - Green alignment reticle confirms face centering.
   - Dynamic prompt appears: `"ಕಣ್ಣು ಮಿಟುಕಿಸಿ / Please blink your eyes"`.
5. Blink naturally.
6. The app automatically completes the 3-frame temporal burst, performs Zero-DNS HTTPS submission, and approves enrollment.
7. Confirm transition to the Worker Dashboard.

### Step 3: Adversarial Duplicate Account Prevention (Fraud Interception)
1. Log out or register under a new dummy phone number with a different display name.
2. Advance to the **Face Verification** step.
3. Present the **same face** previously enrolled in Step 2.
4. Blink as instructed.
5. **Expected Result:**
   - The authoritative backend detects the duplicate face in $\le 800\text{ms}$.
   - The app displays the **Duplicate Face Detected Modal** (`DuplicateAccountResolutionSheet`).
   - The modal shows the masked identity (`CASE-XXXX`, masked phone number, masked user ID) without revealing unverified personal data.
   - The user is offered resolution options: Sign in to existing account, initiate account recovery, or request manual review.
   - The new fraudulent registration is completely blocked from entering the system.

### Step 4: Cellular Network Independence Test
1. Disconnect the device from local Wi-Fi.
2. Switch exclusively to mobile cellular data (Airtel / Jio).
3. Repeat the face verification.
4. Confirm that the Zero-DNS Direct IP route (`104.16.230.132`) connects seamlessly with 0 DNS failures.
