# Kelasagara — Write Ownership
**Phase 1 | Generated:** 2026-09-30

## Collection Write Ownership Table

| Collection | Path | Create | Update | Delete |
|---|---|---|---|---|
| users | users/{uid} | owner (bare profile, role≠admin, status=pending_profile) | owner (safe fields only) OR admin OR narrow face gate | ❌ nobody |
| usernames | usernames/{normalizedId} | owner (self-uid, createdAt required) | admin | ❌ nobody |
| jobs | jobs/{jobId} | approved hirer (own hirerId, status=open) | hirer (own) or admin | hirer (own) or admin |
| applications | applications/{appId} | approved worker (own workerId, status=pending) | hirer (accept/reject own) or admin | admin |
| bookings | bookings/{bookingId} | approved hirer (own hirerId) | see booking contract | ❌ nobody |
| conversations | conversations/{id} | approved (either party) | either party (message subcollection) | ❌ |
| ratings | ratings/{ratingId} | approved hirer | ❌ | ❌ |
| verifiedWorkRecords | verifiedWorkRecords/{id} | ❌ admin only | admin | ❌ |
| auditLogs | auditLogs/{logId} | admin | admin | ❌ |
| workerSkills | workerSkills/{id} | worker (own) or admin | worker (own) or admin | admin |
| workerRegistrations | workerRegistrations/{uid} | owner | owner or admin | ❌ |
| skillAssessments | skillAssessments/{id} | worker (own) | worker or admin | ❌ |
| assessmentEvidence | assessmentEvidence/{id} | worker (own) | worker or admin | ❌ |

## Storage Write Ownership

| Path Pattern | Write | Read | Delete |
|---|---|---|---|
| profile-photos/{uid}/* | owner (uid match), ≤5MB, image/* | any signed-in | owner or admin |
| face-photos/{uid}/* | owner (uid match), ≤10MB, image/* | owner or admin | admin only |
| portfolio/{uid}/* | owner (uid match), ≤8MB, image/* | any signed-in | owner or admin |
| assessment-evidence/{uid}/**/*.* | owner (uid match), ≤200MB, video/* | owner or admin | admin |
| ** (catch-all) | ❌ | ❌ | ❌ |

## Key Security Principles Enforced in Phase 1

### 1. Role cannot be self-assigned
- Firestore rule on `users/{uid}` create: `request.resource.data.role != 'admin'`
- Firestore rule on `users/{uid}` update: `!('role' in affectedKeys())`
- Client code (`auth_provider.dart`): admin email detected → `debugPrint` only, no write

### 2. accountStatus transitions are server-controlled
- Normal update: `!('accountStatus' in affectedKeys())`
- Face gate (the one exception): only `pending_face → pending_review` with simultaneous `faceVerified: true`
- All other transitions: admin only via Firebase Console or Admin SDK

### 3. Reputation fields cannot be self-inflated
- `verifiedWorkCount`, `totalJobs`, `rating`, `ratingCount` — blocked on all client update paths for users/{uid}
- Firestore rule: `!('verifiedWorkCount' in affectedKeys()) && !('rating' in affectedKeys()) && !('totalJobs' in affectedKeys())`

### 4. Work completion requires actor separation
- Worker requests completion: `status: completion_requested` — only worker can write this
- Hirer confirms completion: `status: completion_verified` — only hirer can write this, only after `completion_requested`
- Neither actor can do both steps — enforced by separate Firestore rule branches with actor checks

### 5. OTP is worker-generated only
- Worker writes `arrivalOtp` schema to booking on arrival
- Hirer submits `otpAttempt` — Firestore rule validates equality server-side (no client trust)
- Hirer CANNOT write `arrivalOtp`; worker CANNOT write `otpAttempt`
- OTP validation is purely server-side in the Firestore rule, not in client code

### 6. Booking origin fields are immutable post-create
- `hirerId`, `workerId`, `pay`, `jobId`, `jobLat`, `jobLng` are blocked on all update paths for both worker and hirer
- Only admin can correct these via Firebase Console

### 7. Worker profiles are discoverable only when approved
- Hirer can read `users/{uid}` only when: caller `isApproved()` AND target `role == 'worker'` AND target `accountStatus == 'approved'`
- Unapproved, suspended, rejected worker profiles return permission-denied to hirers
- This prevents discovery of workers who have not completed the approval process

### 8. HomeShell access is strictly gated
- `canEnter = auth.isApproved || auth.isAdmin` — no bypasses
- Network errors with unknown state → `_status = AuthStatus.unauthenticated`
- Users see the "Account Pending Approval" screen until explicitly approved by admin
