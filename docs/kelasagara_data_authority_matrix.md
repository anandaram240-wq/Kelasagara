# Kelasagara — Data Authority Matrix
**Phase 1 | Generated:** 2026-09-30

## Overview
This matrix defines WHO has write authority over EVERY protected field in the Kelasagara data model.
The principle: **the client is NOT a trusted authority** for any field that affects security, reputation, or financial state.

---

## USERS/{uid} Collection

| Field | Worker (self) | Hirer (other) | Admin | Phase 3 Cloud Fn |
|---|---|---|---|---|
| displayName | ✅ WRITE | ❌ | ✅ | — |
| bio | ✅ WRITE | ❌ | ✅ | — |
| district / taluk / village | ✅ WRITE | ❌ | ✅ | — |
| skills / dailyRate | ✅ WRITE | ❌ | ✅ | — |
| userId / normalizedUserId | ✅ WRITE (once) | ❌ | ✅ | — |
| photoUrl | ✅ WRITE | ❌ | ✅ | — |
| isAvailable | ✅ WRITE | ❌ | ✅ | — |
| phone | ✅ WRITE | ❌ | ✅ | — |
| **role** | ❌ BLOCKED | ❌ | ✅ | — |
| **accountStatus** | ❌ (narrow face gate only) | ❌ | ✅ | — |
| **faceVerified** | ❌ (narrow face gate only) | ❌ | ✅ | — |
| **approvedBy / approvedAt** | ❌ BLOCKED | ❌ | ✅ | — |
| **rejectedBy / rejectedAt** | ❌ BLOCKED | ❌ | ✅ | — |
| **verifiedWorkCount** | ❌ BLOCKED | ❌ | ✅ | ✅ Phase 3 |
| **totalJobs** | ❌ BLOCKED | ❌ | ✅ | ✅ Phase 3 |
| **rating / ratingCount** | ❌ BLOCKED | ❌ | ✅ | ✅ Phase 3 |
| **suspendedBy / blockedBy** | ❌ BLOCKED | ❌ | ✅ | — |

### Narrow Face-Enrollment Gate
The Firestore rule permits **one** client-initiated protected transition:
- From: `accountStatus == 'pending_face'`
- To: `accountStatus == 'pending_review'` **AND** `faceVerified == true`
- Allowed fields in this write: `accountStatus`, `faceVerified`, `faceVerifiedAt`, `verificationStatus`, `updatedAt`
- All other protected fields remain blocked even in this write.

---

## BOOKINGS/{bookingId} Collection

| Field | Worker | Hirer | Admin |
|---|---|---|---|
| status (journey flow) | ✅ WRITE | ❌ | ✅ |
| journeyStartedAt / arrivedAt / workStartedAt | ✅ WRITE | ❌ | ✅ |
| arrivalOtp / arrivalOtpExpiry / arrivalOtpUsed / arrivalOtpAttempts | ✅ WRITE | ❌ | ✅ |
| **hirerId / workerId** | ❌ BLOCKED | ❌ | ✅ |
| **pay / jobId / jobLat / jobLng** | ❌ BLOCKED | ❌ | ✅ |
| otpAttempt | ❌ | ✅ (OTP path only) | ✅ |
| arrivalVerified / arrivalVerifiedAt | ❌ | ✅ (OTP path only) | ✅ |
| status (completion_verified) | ❌ | ✅ (after completion_requested) | ✅ |
| completedAt / hirerConfirmedAt / verifiedWorkId | ❌ | ✅ (completion path) | ✅ |

---

## VERIFIEDWORKRECORDS Collection

| Actor | Authority |
|---|---|
| Worker | ❌ NO ACCESS |
| Hirer | ❌ NO ACCESS (Phase 3: Cloud Function) |
| Admin | ✅ create, update, read |
| Phase 3 Cloud Function | ✅ create (triggered by booking completion_verified) |

**DEF-001 STATUS:** PARTIALLY FIXED.
- Hirer can now write `status: completion_verified` to the booking.
- `verifiedWorkRecords.create` and `users.verifiedWorkCount` increment are **DEFERRED** to Phase 3 Cloud Function.
- Client no longer attempts the blocked batch write that caused the silent failure.

---

## STORAGE Authority

| Path | Owner Write | Read | Admin |
|---|---|---|---|
| profile-photos/{uid}/{file} | ✅ uid=myUid, ≤5MB, image/* | ✅ any signed-in | ✅ |
| face-photos/{uid}/{file} | ✅ uid=myUid, ≤10MB, image/* | ❌ owner+admin only | ✅ |
| portfolio/{uid}/{file} | ✅ uid=myUid, ≤8MB, image/* | ✅ any signed-in | ✅ |
| assessment-evidence/{uid}/... | ✅ uid=myUid, ≤200MB, video/* | ❌ owner+admin only | ✅ |
| everything else | ❌ BLOCKED | ❌ BLOCKED | ❌ |

---

## Admin Promotion Policy

**CLIENT NEVER SELF-PROMOTES TO ADMIN.**

The previous implementation (Phase 0 finding) wrote `role: 'admin'` from the client for the hardcoded admin email. This has been removed in Phase 1.

To promote a user to admin:
1. Open Firebase Console → Firestore → users/{uid}
2. Set `role: 'admin'` and `accountStatus: 'approved'` manually
3. The client reads whatever role Firestore contains — it does not write it.

**Phase 3:** Replace with Firebase Custom Claims set by Admin SDK.
