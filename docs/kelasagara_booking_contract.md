# Kelasagara — Booking Contract
**Phase 1 | Generated:** 2026-09-30

## Booking Lifecycle States

```
confirmed
  └─► tracking          (worker: journey started)
        └─► arrived      (worker: GPS within radius)
              └─► working            (after OTP verification)
                    └─► completion_requested  (worker: done)
                          ├─► completion_verified  (hirer: confirmed)
                          └─► disputed             (hirer: problem)
cancelled  (hirer from confirmed, or worker from completion_requested)
```

## Field Ownership by Status

| Field | Written By | When |
|---|---|---|
| hirerId | hirer | booking create |
| workerId | hirer | booking create / application accept |
| jobId | hirer | booking create |
| jobLat / jobLng / jobAddress | hirer | booking create |
| pay | hirer | booking create |
| status: tracking | worker | journey start |
| journeyStartedAt | worker | journey start |
| arrivalOtp / arrivalOtpExpiry / arrivalOtpUsed / arrivalOtpAttempts | worker | on arrival |
| status: arrived | worker | on arrival |
| arrivedAt | worker | on arrival |
| otpAttempt | hirer | OTP entry |
| arrivalVerified / arrivalVerifiedAt | hirer | OTP validation (Firestore rule enforces match) |
| status: working | worker | post OTP verification |
| workStartedAt | worker | post OTP verification |
| status: completion_requested | worker | work done |
| completionRequestedAt / completionRequestedBy | worker | work done |
| status: completion_verified | hirer | confirmation |
| completedAt / hirerConfirmedAt | hirer | confirmation |
| verifiedWorkId | hirer | confirmation (Phase 3 Cloud Fn populates) |

## Canonical OTP Schema (DEF-020 resolved)

Every booking that sets an OTP MUST write all 4 fields atomically:

```dart
{
  'arrivalOtp':         '123456',   // 6-digit string (100000–999999)
  'arrivalOtpExpiry':   Timestamp,  // now + N minutes (30 min for hirer-accept flow)
  'arrivalOtpUsed':     false,      // set true after successful verification
  'arrivalOtpAttempts': 0,          // incremented on each wrong attempt
}
```

The Firestore rule validates all three server-side:
```
request.resource.data.otpAttempt == resource.data.arrivalOtp
&& request.time < resource.data.arrivalOtpExpiry
&& resource.data.arrivalOtpUsed == false
```

**Legacy field `'otp'` must not appear in any new write.** All code paths now use `arrivalOtp`.

## Actor Separation — Completion Flow

The completion flow requires two SEPARATE actor writes:

```
Worker writes:  { status: 'completion_requested', completionRequestedAt: now }
     ↓
Firestore rule checks: resource.data.workerId == myUid()
     ↓
Hirer writes: { status: 'completion_verified', completedAt: now, hirerConfirmedAt: now }
     ↓
Firestore rule checks: resource.data.hirerId == myUid()
                    && resource.data.status == 'completion_requested'
                    && hasOnly([status, completedAt, hirerConfirmedAt, verifiedWorkId])
```

Neither actor can perform both steps. Firestore enforces this separation at the rule level.

## Booking Destination vs Live Tracking

**Destination fields** (set at booking create, immutable thereafter):
- `jobLat`, `jobLng`, `jobAddress`, `jobTitle`, `jobId`
- Stored in Firestore `bookings/{bookingId}`

**Live tracking fields** (real-time, high-frequency):
- `lat`, `lng`, `speed`, `heading`, `etaSeconds`, `seq`, `timestamp`
- Stored in RTDB at `tracking/{workerId}/{bookingId}/`
- Never written to Firestore `bookings` collection

## Immutable Fields After Create

The following booking fields can NEVER be changed by the client after the booking is created:

```
hirerId, workerId, pay, jobId, jobLat, jobLng
```

Firestore rules block these on all update paths for both worker and hirer.
Only admin can correct these fields.
