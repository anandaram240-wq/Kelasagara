# Kelasagara — Security Data Contract
**Phase 1 | Generated:** 2026-09-30

## Principles

1. **The client is NOT trusted authority** for security, reputation, or financial fields.
2. **Firestore rules are the enforcement layer**, not client-side validation.
3. **No client-side privilege escalation.** Admin role must be set via Firebase Console or Admin SDK.
4. **Partial writes must not fail silently.** If a batch contains a blocked write, the batch fails. Separate the writes.
5. **Network errors must not grant access.** An unauthenticated or unknown-status user must not enter the dashboard.

---

## Defect Resolutions — Phase 1

### DEF-001: Work Completion Batch Blocked by Rules
**Status:** PARTIALLY FIXED

**Root Cause:** `VerifiedWorkService.confirmCompletion()` used a single batch that wrote to:
- `bookings/{id}` (hirer-allowed ✅)
- `verifiedWorkRecords/{id}` (admin-only ❌ — BLOCKED)
- `users/{workerId}` increment (admin-only ❌ — BLOCKED)

Batch fails if any write is blocked → completion always failed silently.

**Fix Applied:**
- Separated the booking status update into its own `update()` call
- Added a hirer-completion rule to `firestore.rules`:
  - Condition: `resource.data.status == 'completion_requested'`
  - Allowed write: `hasOnly(['status', 'completedAt', 'hirerConfirmedAt', 'verifiedWorkId'])`
  - Target status: `completion_verified`
- Removed `verifiedWorkRecords.create` and `users.increment` from the client
- These are DEFERRED to Phase 3 Cloud Function

**Remaining:** verifiedWorkRecords creation and worker badge increment are blocked at client level. Phase 3 Cloud Function will listen to `bookings/{id}` `status == completion_verified` and create the record.

---

### DEF-004: Storage Rules Block Profile and Face Photos
**Status:** FIXED

**Root Cause:** `storage.rules` had only the `assessment-evidence` path plus a catch-all deny. Profile photo and face photo uploads were silently blocked at the Firebase Storage layer.

**Fix Applied:** Added to `storage.rules`:
- `profile-photos/{uid}/{file}` — owner write (≤5MB, image/*), any signed-in read
- `face-photos/{uid}/{file}` — owner write (≤10MB, image/*), owner+admin read, admin delete
- `portfolio/{uid}/{file}` — owner write (≤8MB, image/*), any signed-in read

**Verification:** Rules file updated. `firebase deploy --only storage` is required to apply (blocked until deployment account issue is resolved).

---

### DEF-009: Public Worker Discovery Blocked
**Status:** FIXED

**Root Cause:** `users/{uid}` read rule was `isOwner(uid) || isAdmin()`. Hirers could not read any worker profile, making the worker search screen non-functional.

**Fix Applied:**
```
allow read: if isOwner(uid)
  || isAdmin()
  || (isApproved()
      && resource.data.role == 'worker'
      && resource.data.accountStatus == 'approved');
```

**Security boundary:** Only approved users can read approved worker profiles. Unapproved, suspended, or rejected worker profiles are not discoverable. Hirer profiles remain private (not in the approved worker read path).

> [!IMPORTANT]
> Sensitive data (government IDs, biometrics, Aadhaar) must NOT be stored in `users/{uid}`.
> Use `workerRegistrations/{uid}` (admin-only read) for those fields.

---

### DEF-020: OTP Field Name Inconsistency
**Status:** FIXED

**Root Cause:** Three code paths wrote `'otp'` (4-digit). Two wrote `'arrivalOtp'` (6-digit). The Firestore rule validates `arrivalOtp` — so OTP verification always failed from the legacy paths. Workers on the legacy path could never start work.

**Fix Applied:** All three legacy OTP writes now use the canonical schema:
```dart
{
  'arrivalOtp':         otp,    // 6-digit string
  'arrivalOtpExpiry':   Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 30))),
  'arrivalOtpUsed':     false,
  'arrivalOtpAttempts': 0,
}
```

**Files fixed:**
- `lib/screens/applications/applications_screen.dart` (write line ~269 + read line ~374)
- `lib/screens/home/hirer_dashboard.dart` (write line ~214)
- `lib/services/firebase_service.dart` (write line ~103 + read line ~139)

---

### DEF-AdminPromotion: Client-Side Admin Self-Promotion
**Status:** FIXED

**Root Cause:** `auth_provider.dart._loadUserFromFirestore()` checked if the email was the hardcoded admin email and then directly wrote `role: 'admin', accountStatus: 'approved', faceVerified: true` to Firestore from the client. This is a client-side privilege escalation.

**Fix Applied:** Client-side promotion write removed entirely. The client now only reads what Firestore contains. A `debugPrint` logs a discrepancy for the developer to manually fix via Firebase Console.

**Phase 3:** Replace with Firebase Custom Claims + Admin SDK for proper server-side admin assignment.

---

### DEF-HomeShell: Unapproved Users Can Enter Dashboard
**Status:** FIXED

**Root Cause (Part 1):** `home_shell.dart` bypass:
```dart
// OLD — dangerous
final canEnter = auth.isApproved || auth.isAdmin ||
    (auth.faceVerified && (status == AccountStatus.pendingReview || status == AccountStatus.unknown));
```
This let `pendingReview` and `unknown` users into the full dashboard.

**Root Cause (Part 2):** `auth_provider.dart` catch blocks set `_status = AuthStatus.authenticated` even on `permission-denied` FirebaseException, which can set `AccountStatus.unknown` but still mark the session as authenticated.

**Fix Applied (Part 1):**
```dart
// NEW — safe
final canEnter = auth.isApproved || auth.isAdmin;
```

**Fix Applied (Part 2):** Catch blocks now:
- `permission-denied` → `_status = AuthStatus.unauthenticated`
- Network error with cached state → preserve `_status = AuthStatus.authenticated`
- Network error without any cached state → `_status = AuthStatus.unauthenticated`

---

### DEF-010: HirerTrackingScreen Passes bookingId as jobId
**Status:** FIXED

**Root Cause:** `_buildCompletionBanner` in `HirerTrackingScreen` passed `jobId: widget.bookingId` to `WorkCompletionScreen`. The booking document ID was being used where the job document ID was required. This poisoned the `verifiedWorkRecords` data.

**Fix Applied:**
- Added `final String jobId` and `final String workerId` fields to `HirerTrackingScreen`
- `JourneyNavigator.openHirer()` reads `booking['jobId']` and `booking['workerId']` and passes them through
- `WorkCompletionScreen` now receives the correct `jobId`

---

## Remaining Deferred Items

| Item | Status | Phase |
|---|---|---|
| verifiedWorkRecords creation from hirer | DEFERRED — admin/Cloud Function only | Phase 3 |
| verifiedWorkCount / totalJobs increment | DEFERRED — admin/Cloud Function only | Phase 3 |
| Firebase Custom Claims for admin | DEFERRED | Phase 3 |
| firebase deploy (403 wrong account) | BLOCKED — manual Firebase Console paste required | — |
| skillId on HirerTrackingScreen | PARTIALLY FIXED — defaults to 'general' | Phase 2 |
