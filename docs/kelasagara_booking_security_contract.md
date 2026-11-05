# Kelasagara — Booking Security Contract
**Phase 4B Hardened | Engine Version: 11**

---

## 1. Overview & Security Philosophy

The Kelasagara transaction security model relies on a strict zero-trust principle:
1. The client is never trusted to maintain lifecycle ordering or validate constraints.
2. Every mutation must pass a whitelisted branch in `firestore.rules`.
3. State transitions and permitted fields (`hasOnly()`) are validated server-side.
4. Terminal states are immutable.

---

## 2. Firestore Rule Matrix (`bookings/{bookingId}`)

In `firestore.rules`, updates to `bookings/{bookingId}` are governed by granular rule conditions:

```
allow update: if isAuthenticated() && (
  // 1. Worker begins tracking (confirmed -> tracking)
  (isWorker(resource.data.workerId)
    && resource.data.status == 'confirmed'
    && request.resource.data.status == 'tracking'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'journeyStartedAt', 'updatedAt']))
  ||
  // 2. Worker updates active tracking telemetry (tracking -> tracking)
  (isWorker(resource.data.workerId)
    && resource.data.status == 'tracking'
    && request.resource.data.status == 'tracking'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['etaSeconds', 'remainingM', 'currentLat', 'currentLng', 'updatedAt']))
  ||
  // 3. Worker arrives at destination (confirmed/tracking -> arrived)
  (isWorker(resource.data.workerId)
    && (resource.data.status == 'tracking' || resource.data.status == 'confirmed')
    && request.resource.data.status == 'arrived'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'arrivedAt', 'arrivalOtp', 'arrivalOtpExpiry',
                   'arrivalOtpUsed', 'arrivalOtpAttempts', 'updatedAt']))
  ||
  // 4. Hirer verifies OTP upon arrival (arrived -> arrived)
  (isHirer(resource.data.hirerId)
    && resource.data.status == 'arrived'
    && request.resource.data.status == 'arrived'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['otpAttempt', 'arrivalVerified', 'arrivalVerifiedAt',
                   'arrivalOtpUsed', 'arrivalOtpAttempts', 'updatedAt'])
    && (
      (request.resource.data.otpAttempt == resource.data.arrivalOtp
        && request.time < resource.data.arrivalOtpExpiry
        && resource.data.arrivalOtpUsed == false
        && request.resource.data.arrivalVerified == true
        && request.resource.data.arrivalOtpUsed == true)
      ||
      (request.resource.data.arrivalVerified == false
        && request.resource.data.arrivalOtpAttempts == resource.data.arrivalOtpAttempts + 1)
    ))
  ||
  // 5. Worker transitions arrived -> working (ONLY IF arrivalVerified == true)
  (isWorker(resource.data.workerId)
    && resource.data.status == 'arrived'
    && resource.data.arrivalVerified == true
    && request.resource.data.status == 'working'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'workStartedAt', 'updatedAt']))
  ||
  // 6. Worker requests completion (working -> completion_requested)
  (isWorker(resource.data.workerId)
    && resource.data.status == 'working'
    && request.resource.data.status == 'completion_requested'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'completionRequestedAt', 'completionRequestedBy', 'updatedAt']))
  ||
  // 7. Hirer verifies completion (completion_requested -> completion_verified)
  (isHirer(resource.data.hirerId)
    && resource.data.status == 'completion_requested'
    && request.resource.data.status == 'completion_verified'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'completedAt', 'hirerConfirmedAt', 'verifiedWorkId', 'updatedAt']))
  ||
  // 8. Cancellation (pending/confirmed -> cancelled)
  ((isHirer(resource.data.hirerId) || isWorker(resource.data.workerId))
    && (resource.data.status == 'pending' || resource.data.status == 'confirmed')
    && request.resource.data.status == 'cancelled'
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status', 'cancelledAt', 'cancelledBy', 'cancelReason', 'updatedAt']))
  ||
  // Admin emergency override
  isAdmin()
);
```

---

## 3. Worker User Document Protection (`users/{uid}`)

### The Defect (P4-003)
Previously, in `firestore.rules`, the hirer completion update rule allowing hirers to update `totalJobs` on a worker profile was nested inside `isOwner(uid) && (...)`. Since `hirer != worker`, `isOwner(uid)` evaluated to `false`, causing all atomic completion writes by hirers to fail with a permission-denied error.

### The Fix
The rule is now a separate top-level OR branch:
```
allow update: if isOwner(uid) && (...)
  // Top-level hirer completion update
  || (isAuthenticated() && isApproved() && isHirer()
      && request.resource.data.diff(resource.data).affectedKeys()
           .hasOnly(['totalJobs', 'rating', 'totalReviews', 'updatedAt']))
  || isAdmin();
```

---

## 4. RTDB Tracking Authorization Contract (`liveTracking` & `trackingParticipants`)

To eliminate the vulnerability where a rogue worker could write a spoofed `hirerId` into RTDB `liveTracking/{bookingId}`:
1. `trackingParticipants/{bookingId}` is created by the Hirer upon booking creation:
   ```json
   {
     "hirerId": "hirer_uid",
     "workerId": "worker_uid",
     "createdAt": 1727780000000
   }
   ```
2. RTDB write rule for `liveTracking/{bookingId}`:
   - Worker must match `trackingParticipants/$bookingId/workerId`.
   - `newData.child('hirerId').val() === root.child('trackingParticipants').child($bookingId).child('hirerId').val()`.
   - Any spoofed hirer payload is instantly rejected.
