# KELASAGARA — Forensic Data Contract Map
**Phase:** Phase 0 Forensic Freeze  
**Package:** `kelasagaara` (v17.8.0+178)  
**Database Engines:** Cloud Firestore + Firebase Realtime Database (RTDB)

---

## 1. Cloud Firestore Collection Contracts

### A. `users` Collection (Primary Profile & Identity)
**Path:** `users/{uid}`  
**Primary Model:** `UserProfile` (`lib/models/user_profile.dart`)

| Field Name | Type | Authoritative Writer | Client Writable? | Description / Allowed Values |
| :--- | :--- | :--- | :--- | :--- |
| `uid` | String | Client (Auth) | At create only | Firebase Auth UID (Private Internal ID) |
| `userId` | String | Client (Claim) | Via claim transaction | Public unique handle (e.g. `ravi_painter`) |
| `normalizedUserId`| String | Client (Service) | Auto-derived | Lowercase alphanumeric sanitized index |
| `displayName` | String | Client | Yes | User display name |
| `name` | String | Client | Yes | Alias for `displayName` (backward compatibility) |
| `email` | String | Client (Auth) | At create only | Auth email or `@auth.kelasagaara.in` |
| `phone` | String | Client | Yes | 10-digit contact mobile number (NOT for auth) |
| `role` | String | Client (Create) | Create ONLY | `'worker'`, `'hirer'`, or `'admin'` (Immutable post-create) |
| `accountStatus` | String | Authority (Admin) | Narrow gate | `'pending_profile'`, `'pending_face'`, `'pending_review'`, `'approved'`, `'rejected'`, `'suspended'`, `'blocked'` |
| `district` | String | Client | Yes | Karnataka district name (e.g. `'Hassan'`) |
| `taluk` | String | Client | Yes | Karnataka taluk name (e.g. `'Arsikere'`) |
| `village` | String | Client | Yes | Optional village / locality text |
| `skills` | Array<String> | Client | Yes | Occupational skill IDs from `kJobCategories` |
| `dailyRate` | Integer | Client | Yes | Wage rate per day in INR (default: 700) |
| `bio` | String | Client | Yes | Worker self-description |
| `photoUrl` | String | Client | Yes | Public profile avatar image URL |
| `facePhotoUrl` | String | Client | Yes | Reference face capture from liveness enrollment |
| `faceVerified` | Boolean | Authority (Gate) | Narrow gate | `true` if ML Kit blink liveness succeeded |
| `skillVerified` | Boolean | Admin | No | `true` if practical/knowledge assessment passed |
| `isAvailable` | Boolean | Worker | Yes | Active availability toggle (`true` = searchable) |
| `totalJobs` | Integer | System | No | Total completed and confirmed jobs count |
| `rating` | Number | System | No | Derived average rating (1.0 to 5.0) |
| `ratingSum` | Number | System | No | Cumulative rating points |
| `totalRatings` | Integer | System | No | Count of received reviews |
| `verifiedWorkCount`| Integer | System | No | Authoritative count of verified jobs |
| `rejectionReason`| String | Admin | No | Reason recorded by admin if rejected |
| `suspensionReason`| String | Admin | No | Reason recorded by admin if suspended |
| `fcmToken` | String | Client | Yes | Firebase Cloud Messaging push token |
| `onboardingComplete`| Boolean | System | No | `true` once status reaches `'approved'` |
| `approvedAt` | Timestamp | Admin | No | Timestamp of admin approval |
| `approvedBy` | String | Admin | No | Admin UID who granted approval |
| `createdAt` | Timestamp | Server | No | Initial document creation timestamp |
| `updatedAt` | Timestamp | Server | Yes | Document last modified timestamp |

---

### B. `usernames` Collection (Global Handle Uniqueness)
**Path:** `usernames/{normalizedUserId}`  
**Service:** `lib/services/user_id_service.dart`

| Field Name | Type | Description |
| :--- | :--- | :--- |
| `uid` | String | Owner Firebase Auth UID |
| `claimedAt` | Timestamp | Timestamp when the handle was claimed |

---

### C. `jobs` Collection (Hirer Job Postings)
**Path:** `jobs/{jobId}`  
**Model:** `Job` (`lib/providers/jobs_provider.dart`)

| Field Name | Type | Description / Constraints |
| :--- | :--- | :--- |
| `id` | String | Firestore document ID |
| `title` | String | Job title in English |
| `titleKn` | String | Optional Kannada title |
| `skill` | String | Skill ID required (from `kJobCategories`) |
| `hirerId` | String | UID of hirer who posted the job |
| `hirerName` | String | Hirer display name |
| `district` | String | District of job site |
| `taluk` | String | Taluk of job site |
| `village` | String | Village/locality of job site |
| `pay` | Integer | Offered daily wage in INR |
| `jobType` | String | `'Daily Wage'`, `'Contract'`, etc. |
| `lat` | Number | Latitude of job site (WGS84) |
| `lng` | Number | Longitude of job site (WGS84) |
| `location` | Map | Nested location: `{'address': String, 'district': String, ...}` |
| `status` | String | `'open'`, `'filled'`, `'completed'`, `'cancelled'` |
| `applicants` | Integer | Cached applicant counter (read-only for workers) |
| `urgent` | Boolean | Urgent job flag |
| `verified` | Boolean | Verified employer badge flag |
| `postedAt` | Timestamp | Server creation timestamp |
| `createdAt` | Timestamp | Alias timestamp |

---

### D. `applications` Collection (Job Applications)
**Path:** `applications/{jobId}_{workerId}` (Deterministic ID)  
**Provider:** `lib/providers/jobs_provider.dart`

| Field Name | Type | Description / Constraints |
| :--- | :--- | :--- |
| `jobId` | String | Target job document ID |
| `workerId` | String | Applicant worker UID |
| `workerName` | String | Worker display name |
| `hirerId` | String | Job owner hirer UID |
| `hirerName` | String | Hirer display name |
| `jobTitle` | String | Title of job applied to |
| `skill` | String | Primary skill of the application |
| `pay` | Integer | Agreed daily rate in INR |
| `message` | String | Optional cover note from worker |
| `status` | String | `'pending'`, `'accepted'`, `'rejected'`, `'worker_cancelled'` |
| `bookingId` | String | Created booking ID once accepted (`${jobId}_${workerId}`) |
| `appliedAt` | Timestamp | Timestamp when application was submitted |
| `updatedAt` | Timestamp | Timestamp of last status change |

---

### E. `bookings` Collection (Active Contracts)
**Path:** `bookings/{jobId}_{workerId}`  
**Service:** `lib/services/chat_booking_service.dart` / `JourneyNavigator`

| Field Name | Type | Description / Constraints |
| :--- | :--- | :--- |
| `jobId` | String | Related job document ID |
| `workerId` | String | Assigned worker UID |
| `workerName` | String | Worker display name |
| `hirerId` | String | Hiring party UID |
| `hirerName` | String | Hirer display name |
| `jobTitle` | String | Title of work to be performed |
| `skill` | String | Occupational skill category |
| `pay` | Integer | Agreed payment amount |
| `jobLat` | Number | Target job latitude (Normalized Destination) |
| `jobLng` | Number | Target job longitude (Normalized Destination) |
| `jobAddress` | String | Human readable street/locality address |
| `status` | String | `'confirmed'`, `'tracking'`, `'approaching'`, `'arrived'`, `'working'`, `'completion_requested'`, `'completion_verified'`, `'cancelled'` |
| `arrivalOtp` | String | 4-digit arrival handshake verification code |
| `arrivalOtpExpiry`| Timestamp | Expiry window for arrival OTP |
| `arrivalOtpUsed` | Boolean | Flag preventing OTP replay attacks |
| `arrivalVerified` | Boolean | True once hirer verifies the arrival OTP |
| `arrivalVerifiedAt`| Timestamp| Timestamp when arrival was verified |
| `confirmedAt` | Timestamp | Timestamp when booking was accepted |
| `journeyStartedAt`| Timestamp| Worker journey initiation timestamp |
| `arrivedAt` | Timestamp | Physical geofence arrival timestamp |
| `workStartedAt` | Timestamp | Post-OTP work initiation timestamp |
| `completionRequestedAt`| Timestamp| Worker request for job sign-off |
| `completedAt` | Timestamp | Final job completion timestamp |
| `verifiedWorkId` | String | ID of the resulting `verifiedWorkRecords` document |
| `createdAt` | Timestamp | Document creation timestamp |

---

### F. `conversations` and `messages` (Chat Subsystem)
**Parent Path:** `conversations/{uid1_uid2_jobId}`  
**Sub-collection:** `conversations/{convId}/messages/{msgId}`

#### Parent Document:
- `participants`: `Array<String>` containing `[workerId, hirerId]`
- `jobId`: String
- `jobTitle`: String
- `lastMessage`: String
- `lastMessageAt`: Timestamp
- `lastSenderId`: String
- `unreadCount_${recipientUid}`: Integer

#### Message Document:
- `senderId`: String
- `senderName`: String
- `text`: String
- `timestamp`: Timestamp
- `seenBy`: `Array<String>`

---

### G. `verifiedWorkRecords` Collection
**Path:** `verifiedWorkRecords/{recordId}`  
**Model:** `VerifiedWorkRecord` (`lib/models/verified_work_record.dart`)

| Field Name | Type | Description |
| :--- | :--- | :--- |
| `workerId` | String | Worker UID |
| `hirerId` | String | Hirer UID who confirmed |
| `jobId` | String | Job document ID |
| `bookingId` | String | Booking document ID |
| `skillId` | String | Skill ID evaluated |
| `workStatus` | String | `'completed'` |
| `hirerConfirmation`| Boolean | Must be `true` |
| `qualityScore` | Number | Rating out of 5.0 |
| `punctualityScore`| Number | Rating out of 5.0 |
| `safetyScore` | Number | Rating out of 5.0 |
| `taskCompletionScore`| Number | Rating out of 5.0 |
| `communicationScore`| Number | Rating out of 5.0 |
| `wouldHireAgain` | Boolean | Recommendation flag |
| `reviewComments` | String | Written hirer testimonial |
| `reviewStatus` | String | `'verified'` |
| `createdAt` | Timestamp | Server timestamp |

---

## 2. Firebase Realtime Database (RTDB) Contract

**Path:** `liveTracking/$bookingId`  
**Security Rule Gate:** `database.rules.json` (bounded to India coordinates)

| Key | Type | Description |
| :--- | :--- | :--- |
| `workerId` | String | Worker UID publishing location |
| `hirerId` | String | Hirer UID authorized to subscribe |
| `lat` / `latitude` | Number | Worker live latitude (WGS84: 6.0 to 37.0) |
| `lng` / `longitude`| Number | Worker live longitude (WGS84: 68.0 to 97.0) |
| `accuracy` | Number | Horizontal accuracy in meters ($0 \le x \le 5000$) |
| `heading` | Number | Course in degrees ($0 \le x \le 360$) |
| `speed` | Number | Velocity in km/h ($0 \le x \le 300$) |
| `snapped` | Boolean | True if coordinate is snapped to road |
| `etaSeconds` | Number | Estimated seconds remaining to job destination |
| `remainingMeters`| Number | Estimated road distance remaining in meters |
| `currentStepInstruction`| String | Turn maneuver instruction in English |
| `currentStepInstructionKn`| String | Turn maneuver instruction in Kannada |
| `arrivalStatus` | String | `'en_route'`, `'arrived'`, or `'completed'` |
| `trackingStatus`| String | `'active'`, `'paused'`, or `'stopped'` |
| `sessionId` | String | Unique tracking session token |
| `seq` | Integer | Monotonically increasing sequence number |
| `timestamp` | Number | Epoch milliseconds from GPS fix |
| `updatedAt` | Number | Server timestamp of RTDB write |

---

## 3. IDENTIFIED CONTRACT CONTRADICTIONS & DISCREPANCIES

### 1. `lat` / `lng` vs `jobLat` / `jobLng`
- In `jobs` collection: Coordinates are stored as `lat` and `lng`.
- In `bookings` collection: `BookingService.acceptApplicant` stores them as `jobLat` and `jobLng`.
- In `JourneyNavigator`: The navigator must check all 3 variants (`jobLat`, `lat`, `destLat`) to avoid crashing or centering on (0, 0).
- In `voice_tool_registry.dart`: `createBooking` writes neither, resulting in `0.0, 0.0`.

### 2. OTP Field Name: `'otp'` vs `'arrivalOtp'`
- `applications_screen.dart` line 270 updates booking with `{'otp': otp}`.
- `journey_provider.dart` line 421 and `firestore.rules` line 192 check `arrivalOtp`.
- Result: Hirer OTP verification fails because the field names do not match.

### 3. Job ID Corruption in `HirerTrackingScreen`
- `HirerTrackingScreen` line 250 passes `jobId: widget.bookingId`.
- This records `${jobId}_${workerId}` into `verifiedWorkRecords.jobId` instead of the clean `jobId`.

### 4. Hardcoded Skill ID in Completion
- `HirerTrackingScreen` line 251 passes `skillId: 'general'`.
- The canonical taxonomy in `kJobCategories` defines `plumber`, `electrician`, `mason`, `carpenter`, `painter`, etc. There is no category `'general'`, corrupting skill-specific reputation badges.

### 5. `pendingReview` State Gating Split-Brain
- `SplashScreen` line 71: If `accountStatus == pendingReview` and `faceVerified == true`, routes to `HomeShell`.
- `HomeShell` line 83: Allows entry if `auth.faceVerified && (status == pendingReview)`.
- `firestore.rules` line 95: Blocks reading open jobs unless `isApproved() || isAdmin()`.
- Result: The user enters the app dashboard but is greeted with Firestore `permission-denied` errors and blank feeds.
