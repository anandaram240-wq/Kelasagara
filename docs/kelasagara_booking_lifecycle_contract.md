# Kelasagara — Booking Lifecycle Contract
**Phase 4B Hardened | Engine Version: 11**

---

## 1. Overview & Single Canonical Authority

In Kelasagara, all booking operations MUST flow through the singleton service:
```dart
BookingService.instance
```
All UI screens, legacy adapters, and voice tool registries MUST delegate directly to `BookingService.instance`. Direct writes to the `bookings/{bookingId}` Firestore collection outside of `BookingService` are strictly forbidden.

---

## 2. Canonical State Machine

```
              [Direct Booking / Application Accept]
                                │
                                ▼
                           confirmed
                                │
                    (Worker starts journey)
                                │
                                ▼
                            tracking
                                │
                    (Worker arrives at geo fence)
                                │
                                ▼
                            arrived
                                │
                   (Hirer verifies 6-digit OTP)
                                │
                                ▼
                            working
                                │
                     (Worker requests finish)
                                │
                                ▼
                      completion_requested
                                │
                     (Hirer confirms finish)
                                │
                                ▼
                      completion_verified  <-- [TERMINAL]
```

### Cancellation & Terminal States
- **Cancellable from:** `pending` or `confirmed` ONLY.
- **Cancelled state:** `cancelled` (Terminal).
- **Dispute state:** `disputed` (Terminal).
- **Terminal state rule:** Once a booking enters `completion_verified`, `cancelled`, or `disputed`, NO further transitions or updates are permitted.

---

## 3. Strict State Transition Matrix

| Current State | Target State | Authorized Actor | Prerequisites / Required Fields |
|---|---|---|---|
| `confirmed` | `tracking` | Worker (`isWorker`) | `journeyStartedAt` timestamp written |
| `tracking` | `tracking` | Worker (`isWorker`) | Periodic ETA / telemetry updates |
| `confirmed` / `tracking` | `arrived` | Worker (`isWorker`) | `arrivedAt` timestamp, 6-digit `arrivalOtp` generated |
| `arrived` | `arrived` | Hirer (`isHirer`) | OTP validation attempt (`otpAttempt`, `arrivalVerified`, `arrivalOtpUsed`) |
| `arrived` | `working` | Worker (`isWorker`) | **Must satisfy `arrivalVerified == true`**; writes `workStartedAt` |
| `working` | `completion_requested` | Worker (`isWorker`) | Writes `completionRequestedAt`, `completionRequestedBy` |
| `completion_requested` | `completion_verified` | Hirer (`isHirer`) | Writes `completedAt`, `hirerConfirmedAt`, `verifiedWorkId` |
| `confirmed` / `pending` | `cancelled` | Hirer or Worker | Writes `cancelledAt`, `cancelledBy`, `cancelReason` |

Any transition not in this matrix is rejected by `firestore.rules`. State-skipping (e.g. `confirmed` directly to `working` or `working` directly to `completion_verified`) is impossible.

---

## 4. Canonical OTP Lifecycle (6-Digit Strict)

1. **Generation:** When a booking is created or when worker reaches `arrived`, `BookingService._generateOtp()` creates an exact 6-digit string (`100000` to `999999`). Inline 4-digit generators (`Random().nextInt(9000) + 1000`) are completely eradicated.
2. **Atomic Schema:**
   ```dart
   {
     'arrivalOtp': '123456',              // 6 digits
     'arrivalOtpExpiry': Timestamp,       // now + 30 minutes
     'arrivalOtpUsed': false,             // boolean flag
     'arrivalOtpAttempts': 0              // integer counter
   }
   ```
3. **Verification:** Hirer provides the OTP. The verification write atomically asserts that `otpAttempt == arrivalOtp`, `request.time < arrivalOtpExpiry`, and `!arrivalOtpUsed`, setting `arrivalVerified = true` and `arrivalOtpUsed = true`.
4. **Transition Gate:** The worker CANNOT transition from `arrived` to `working` unless `arrivalVerified == true`.

---

## 5. Idempotent Booking Creation

- **Application Acceptance:**
  - Booking Document ID: `booking_${applicationId}` (Deterministic).
  - Transaction checks that the application has not already been accepted and the worker is available.
  - Updates worker `isAvailable = false` and `activeBookingId = bookingId`.
  - Seeds RTDB `trackingParticipants/{bookingId}`.
- **Direct Voice Booking:**
  - Booking Document ID: `booking_direct_${idempotencyKey}`.
  - If existing document exists, returns existing booking without creating duplicate.
  - Seeds RTDB `trackingParticipants/{bookingId}`.

---

## 6. Verification and Regression Checklist

- [x] State skipping rejected by security rules.
- [x] Worker cannot start work without verified OTP (`arrivalVerified == true`).
- [x] 6-digit OTP strictly enforced.
- [x] Terminal states locked down against modification.
- [x] Full test coverage in `test/phase4_transaction_hardening_test.dart`.
