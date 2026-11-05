# Kelasagara — Completion Integrity Contract
**Phase 4B Hardened | Engine Version: 11**

---

## 1. The Canonical Completion Status

### Problem Statement
In previous iterations, multiple strings were used interchangeably to denote a finished job:
- `'done'`
- `'completed'`
- `'completion_verified'`

This led to query fragmentation, missed metrics in worker dashboards, and corrupted profile job counts.

### The Canonical Standard
In Phase 4B:
- **`BookingStatus.completionVerified` (`'completion_verified'`) is the ONLY status representing a completed job.**
- Legacy `'done'` and `'completed'` have been excised from all query clauses, status filters, and voice tool evaluations.

---

## 2. Atomic Completion Batch

When a hirer confirms job completion via `BookingService.instance.confirmCompletion(...)`, all mutations execute atomically in a single Firestore `WriteBatch`:

1. **Booking Document (`bookings/{bookingId}`):**
   ```dart
   {
     'status': 'completion_verified',
     'completedAt': FieldValue.serverTimestamp(),
     'hirerConfirmedAt': FieldValue.serverTimestamp(),
     'verifiedWorkId': 'verified_work_$bookingId',
     'updatedAt': FieldValue.serverTimestamp(),
   }
   ```
2. **Worker User Document (`users/{workerId}`):**
   ```dart
   {
     'totalJobs': FieldValue.increment(1),
     'isAvailable': false,
     'activeBookingId': '',
     'updatedAt': FieldValue.serverTimestamp(),
   }
   ```
3. **Verified Work Record (`verified_work/verified_work_$bookingId`):**
   - Deterministic ID guarantees idempotency.
   - Captures verified skill, timestamps, hirer and worker IDs.
4. **Rating Record (`ratings/rating_${bookingId}_${hirerUid}`):**
   - Deterministic ID prevents duplicate review submissions.

---

## 3. Availability & Active Booking Reconciliation

Upon completion:
- `isAvailable` is set to `false`. A worker is NOT automatically set to available; they must explicitly toggle availability on when ready for their next engagement.
- `activeBookingId` is reset to `''`. This frees the worker's status so future applications or direct bookings can be accepted.

---

## 4. Verification and Contract Invariants

- **Idempotency:** Calling `confirmCompletion()` multiple times on the same booking is guarded; once the booking status is `completion_verified`, subsequent calls exit gracefully with `BookingResult.ok`.
- **Integrity:** `verifiedWorkId` links the booking to its immutable proof-of-work artifact.
