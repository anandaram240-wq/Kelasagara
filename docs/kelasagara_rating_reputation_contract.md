# Kelasagara — Rating & Reputation Contract
**Phase 4B Hardened | Engine Version: 11**

---

## 1. Overview & Single Reputation Path

All ratings and reviews in Kelasagara must follow ONE canonical path:
```
BookingService.instance.submitRating(...)
```
Direct writes to `ratings/{ratingId}` or uncoordinated increments to `users/{workerId}` are prohibited.

---

## 2. Deterministic Rating Identity & Idempotency

### Deterministic ID Pattern
```dart
final ratingId = 'rating_${bookingId}_${hirerUid}';
```
Because the document ID is derived deterministically from the `bookingId` and the rating hirer's UID:
1. A hirer cannot submit multiple ratings for the same completed booking.
2. Network retries, timeout recoveries, or rapid duplicate taps overwrite the existing deterministic document rather than appending duplicate ratings or inflating review counts.

---

## 3. Rating Schema & Validation

```dart
{
  'ratingId': 'rating_${bookingId}_${hirerUid}',
  'bookingId': bookingId,
  'hirerId': hirerUid,
  'workerId': workerUid,
  'jobId': jobId,
  'rating': 5,                     // Integer or double: 1.0 to 5.0
  'review': 'Excellent work!',      // Optional string: max 1000 characters
  'createdAt': FieldValue.serverTimestamp(),
  'updatedAt': FieldValue.serverTimestamp(),
}
```

### Security Rule Constraints
- `request.auth.uid == request.resource.data.hirerId`
- `request.resource.data.rating >= 1 && request.resource.data.rating <= 5`
- The booking referenced in `bookingId` must have `status == 'completion_verified'`.

---

## 4. Atomic Worker Reputation Recalculation

When a rating is submitted:
1. The new rating document is written to `ratings/{ratingId}`.
2. The worker document at `users/{workerId}` is updated atomically:
   - If previous reviews exist:
     $$\text{newRating} = \frac{(\text{currentRating} \times \text{totalReviews}) + \text{newScore}}{\text{totalReviews} + 1}$$
   - `totalReviews` is incremented by 1.
   - `updatedAt` is refreshed.
3. This guarantees that `rating` and `totalReviews` on `users/{workerId}` reflect the true mathematical average of all submitted reviews.
