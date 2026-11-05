# Kelasagara Workflow Truth Map
**Generated:** 2026-09-30  
**Source:** 4-auditor parallel deep inspection of all 108 Dart files  
**Purpose:** Ground truth before any code change. Nothing here is aspirational — every item is verified against the actual file on disk.

---

## Repository Facts

| Item | Value |
|------|-------|
| Dart files | 108 |
| App version | 17.8.0+178 |
| Package name | `kelasagaara` |
| Firebase project | `kelasagara-f127a` |
| Git branch | `feature/navigation-engine-v11-hardened` |
| Firestore rules on disk | 448 lines (strict version with `isApproved()`) |
| Firestore rules deployed | **UNKNOWN** — CLI deploy blocked (403, wrong account) |
| RTDB rules | 37 lines (solid, India bounding box validated) |
| Storage rules | 45 lines — **ONLY assessment-evidence videos. Profile photos NOT covered.** |

---

## 1. Authentication Flow

```
WelcomeScreen (321 lines)
  ├── Google Sign-In → signInWithGoogle() → AuthProvider
  ├── User ID + Password → signInWithUserIdAndPassword()
  │     → query users where normalizedUserId==id → get email → signInWithEmailAndPassword()
  └── [Phone Auth: REMOVED from UI ✅]

AuthProvider._loadUserFromFirestore(uid):
  → reads users/{uid}
  → if doc missing → creates skeleton with pending_profile
  → if FirebaseException (network/permission) → 
       ⚠️ ESCAPE HATCH: stays authenticated with cached/unknown status
  → if email == 'anandaananda16919@gmail.com' →
       ⚠️ HARDCODED ADMIN: auto-promotes to role=admin, accountStatus=approved
```

**Auth methods available:**
| Method | Status |
|--------|--------|
| Google Sign-In | ✅ ACTIVE |
| User ID + Password | ✅ ACTIVE |
| Email + Password | ✅ ACTIVE (underlying) |
| Phone OTP | ❌ REMOVED from UI |

**Hidden dev mode:** 5 rapid taps on "ಕೆಲಸಗಾರ – Real App" text in WelcomeScreen — exposes dev toggle.

---

## 2. Registration State Machine

### AccountStatus Enum (Firestore string values)
| Dart Value | Firestore String | Meaning |
|-----------|-----------------|---------|
| `pendingProfile` | `pending_profile` | New user, profile form incomplete |
| `pendingFace` | `pending_face` | Profile done, face scan required |
| `pendingReview` | `pending_review` | Face done, awaiting admin approval |
| `approved` | `approved` | Full access |
| `rejected` | `rejected` | Admin denied |
| `suspended` | `suspended` | Temporarily paused |
| `blocked` | `blocked` | Permanently banned |
| `unknown` | `unknown` | Error fallback state |

### State Machine Transitions
```
NEW GOOGLE USER
  → _loadUserFromFirestore: no doc found
  → create skeleton: {role: unknown, accountStatus: pending_profile}
  → SplashScreen routes to RegistrationScreen

RegistrationScreen (1344 lines, multi-step wizard)
  → Fields: displayName, userId, email, phone (contact only), district, taluk,
            village, skills (workers), bio, dailyRate, password
  → registerWithCredentials() or updateProfile()
  → Writes to: users/{uid} (merge:true), usernames/{normalizedId}
  → Sets: accountStatus = pending_face   ← POTENTIAL DEADLOCK (see bugs)

FaceEnrollmentScreen (464 lines)
  → ML Kit local face detection: blink detection liveness
  → Image upload to Storage: ON HOLD (writes empty photoUrl: '')
  → Calls auth.setFaceVerified(true, '')
  → Firestore narrow rule: pending_face → pending_review ONLY (with faceVerified=true)

Admin Approval (AdminDashboard, tab 1)
  → Sets accountStatus = approved + writes auditLogs entry
  → Or: rejected + reason + auditLogs

SplashScreen routing:
  pendingProfile  → RegistrationScreen
  pendingFace     → FaceEnrollmentScreen
  pendingReview   → if faceVerified: HomeShell | else: PendingApprovalScreen
  approved        → HomeShell
  rejected        → RejectedScreen
  suspended/blocked → SuspendedScreen
  unknown         → RegistrationScreen
```

### HomeShell Entry Gate (158 lines)
```dart
canEnter = auth.isApproved || auth.isAdmin ||
  (auth.faceVerified && (status == pendingReview || status == unknown))
```
Workers in `pendingReview` with face verified CAN see HomeShell but cannot do anything meaningful (Firestore rules require `approved`).

---

## 3. Worker Discovery (Search)

> ⚠️ **No WorkerDiscoveryService exists.** All search logic is embedded directly in `hirer_dashboard.dart` inside `_FindWorkersSectionState._search()`.

```
HirerDashboard._search()
  → Firestore query on `users` collection:
     where role == 'worker'
     where accountStatus == 'approved'
     where isAvailable == true
     + if By Area mode: where district == _selectedDistrict
                        where taluk == _selectedTaluk  (optional)
     + if skill selected: where skills arrayContains _selectedSkill
     .limit(30)
  → Result rendered as WorkerCard list

NEARBY MODE:
  ⚠️ FAKE: drops all location filters, fetches top-30 approved workers statewide
  No GPS used. No geohashing. No distance calculation.
  No road-distance matrix.
```

**Search bugs:**
| Bug | Location | Severity |
|-----|----------|----------|
| Nearby is statewide, not GPS-based | `hirer_dashboard.dart _search()` | 🔴 Critical |
| No road-distance matrix for any result | Entire codebase | 🔴 Critical |
| No pagination (hard `.limit(30)`) | `hirer_dashboard.dart` | 🟡 Medium |
| Search logic in screen, not service | `hirer_dashboard.dart` | 🟡 Medium |
| MatrixService exists but is NEVER called for search | `services/routing/matrix_service.dart` | 🟡 Medium |

**Collections used for search:**
- `users` — primary worker search (by role=worker + filters)
- `workerProfiles` — collection EXISTS in Firestore rules but is **NEVER queried** anywhere in code. Dead collection.

---

## 4. Jobs Flow

```
HirerDashboard → PostJobScreen → JobsProvider.postJob()
  → writes to: jobs/{jobId}
  → fields: title, skill, district, taluk, village, pay, jobType, lat, lng, status=open

WorkerDashboard → JobsProvider.startListening()
  → Firestore stream: jobs where status==open .limit(150)
  → ALL client-side filtering: JobFilter (district, taluk, skill, text search, etc.)
  ⚠️ Downloads 150 raw jobs, filters in Dart — no Firestore index filters for worker feed

JobDetailScreen → applyToJob()
  → Creates: applications/{jobId}_{workerId}
  → Fields: jobId, workerId, workerName, hirerId, hirerName, jobTitle, skill, pay,
            message, status=pending, appliedAt, updatedAt
  → ✅ FIXED: jobs.applicants is NOT incremented (workers have no write permission)
```

**Firestore collections:**
- `jobs` — job postings
- `applications` — worker applications (deterministic ID: `{jobId}_{workerId}`)

---

## 5. Applications & Booking Flow

```
HirerDashboard/ApplicationsScreen → BookingService.acceptApplicant()
  → Atomic batch write:
     1. bookings/{jobId}_{workerId}: {jobId, workerId, workerName, hirerId,
           jobTitle, skill, pay, jobLat, jobLng, jobAddress, status=confirmed, ...}
     2. applications/{appId}: status = accepted
     3. jobs/{jobId}: status = filled

Booking status state machine:
  confirmed → tracking → approaching → arrived → working →
  completion_requested → completed → completion_verified
  (or cancelled at any point)

OTP flow:
  JourneyService: when distanceToJob <= 0.5km during confirmed status
    → auto-generates 4-digit arrivalOtp in booking doc
    → Worker gives code to hirer verbally
    → HirerTrackingScreen.verifyArrivalOtp() → status = working

WorkCompletionScreen (hirer-side):
  → Rating fields: quality, punctuality, safety, taskCompletion, communication
  → VerifiedWorkService.confirmCompletion() → creates VerifiedWorkRecord
```

**Firestore collections:**
- `bookings` — active bookings
- `ratings` — post-completion ratings
- `verifiedWorkRecords` — verified job completion records

---

## 6. Chat Flow

```
ChatBookingService → ChatScreen
  → Collection: conversations/{uid1_uid2_jobId}
  → Sub-collection: conversations/{convId}/messages/{msgId}
  → Atomic batch: write message + update conversation lastMessage + unreadCount
```

---

## 7. Worker Navigation Flow

```
JourneyNavigator.openWorker(context, booking)
  → reads: destLat = booking['jobLat'] ?? booking['lat']
           destLng = booking['jobLng'] ?? booking['lng']
  → guard: if destLat==0 && destLng==0 → red SnackBar, abort
  → pushes: WorkerJourneyScreen(booking, destLat, destLng)

WorkerJourneyScreen (1239 lines)
  → _isMapReady guard: all MapController calls gated ✅ (grey screen fix applied)
  → Map tiles: CartoDB Voyager with OSM fallback
  → Reads NavState stream from NavigationEngine.instance.stream

JourneyProvider (763 lines)
  → initWorker(booking): sets up RTDB listener on liveTracking/$bookingId
  → Delegates GPS to JourneyService.startTracking()
  → Receives location via onWorkerLocationUpdate callback
  → State machine: idle → tracking → arrived → completed → error

JourneyService (339 lines) [SINGLETON]
  → Manages foreground service + single Geolocator stream
  → _sessionToken: guarantees only ONE active stream
  → Feeds: JourneyProvider (callback) + NavigationEngine.feedGpsPosition()
  → Writes to RTDB: liveTracking/$bookingId

NavigationEngine (911 lines) [GLOBAL SINGLETON ⚠️]
  → Receives GPS via feedGpsPosition()
  → Manages: route progress, off-route detection, rerouting, arrival
  → Emits: Stream<NavState> (broadcast)
  → NavState: snapped coords, heading, speed, ETA, remainingMeters, currentStep

RoutingOrchestrator (559 lines) [SINGLETON]
  → 4 providers: Mapbox, Valhalla, OSRM, ORS
  → Strategy: Hedged Concurrent Racing (primary+secondary race, tertiary fallback)
  → Cache: 0.01° bucket (~1km precision), TTL-based
  → forceRefresh: bypasses cache ✅
```

**RTDB path:** `liveTracking/$bookingId`  
**RTDB fields:** lat, lng, accuracy, heading, speed, etaSeconds, remainingMeters, stepInstruction, stepInstructionKn, arrivalStatus, sessionId, seq, timestamp

---

## 8. Hirer Live Tracking Flow

```
HirerTrackingScreen (674 lines)
  → reads RTDB: liveTracking/$bookingId (worker's live position)
  → reads booking: jobLat/jobLng (job site position)
  → displays: worker position marker (from RTDB) + job site marker (from booking)
  ✅ No coordinate mismatch in HirerTrackingScreen itself

JourneyNavigator.openHirer(context, booking)
  → pushes HirerTrackingScreen with booking data
  → Uses jobLat/jobLng for destination marker ✅
```

---

## 9. Voice Flow

```
VoiceCommandCenterScreen
  → VoiceEngine (73 lines) — thin facade
  → VoiceSessionManager (790 lines) — manages session lifecycle

NLU Tier architecture:
  1. FastLocalCommandRouter (567 lines) — regex matching, zero-network
  2. GroqNluService (393 lines) — Groq Llama-3.1-70B structured JSON intent
  3. GeminiLiveProvider — fallback for ambiguous intents
  4. VoiceService (101 lines) — legacy simple regex (still active)

VoiceToolRegistry (909 lines)
  → registered tools: searchWorkersNearby, searchWorkersByDistrict, getWorkerProfile, etc.
  → ⚠️ FAKE GPS FALLBACK: if GPS unavailable → uses hardcoded Hassan coords (13.0060, 76.0954)
  → ⚠️ COORDINATE BUG: _launchNavigation(worker) sets destLat=worker.latitude/destLng=worker.longitude
       Worker is navigated to the WORKER'S OWN POSITION instead of the job site
```

---

## 10. Security Rules — Ground Truth

### Firestore (448 lines, STRICT version on disk)

| Collection | Read | Create | Update | Delete |
|-----------|------|--------|--------|--------|
| `users` | owner \| admin | owner + role≠admin + status=pending_profile | owner (cannot change role/approvedBy/faceVerified except narrow face transition) | false |
| `usernames` | signed-in | signed-in + uid matches | admin | false |
| `jobs` | isApproved() \| admin | isApproved() + isHirer() | admin \| owning hirer | admin |
| `applications` | admin \| own workerId \| own hirerId | isApproved() + isWorker() | admin \| worker (withdraw) \| hirer (accept/reject) | false |
| `conversations` | admin \| participant | isApproved() + participant | participant | false |
| `bookings` | admin \| workerId \| hirerId | isApproved() + isHirer() | admin \| worker (journey fields) \| hirer (OTP verify) | false |
| `ratings` | public | isApproved() + isHirer() | false | false |
| `auditLogs` | admin | admin | admin | (none) |

> ⚠️ **CRITICAL:** These strict rules are on DISK but may NOT be deployed on Firebase Console. The `firebase deploy` command fails with 403 (wrong account). Whatever was last manually pasted into Firebase Console is what's actually enforced. This MUST be verified and the disk version deployed.

### RTDB (37 lines, solid)
- Path: `liveTracking/$bookingId`
- Read: worker OR hirer of that booking
- Write: worker of that booking only
- Validates: India bounding box (lat 6-37, lng 68-97)

### Storage (45 lines)
- Path: `assessment-evidence/{uid}/{...}` — videos only, 200MB max
- ⚠️ **Profile photos, face photos, portfolio images: NOT covered by storage rules**
- Any upload of profile/face photos currently BLOCKED or hitting the default-deny rule

---

## 11. Discovered Bugs — Prioritized

### 🔴 Critical (breaks core workflow)

| # | Bug | File | Lines | Impact |
|---|-----|------|-------|--------|
| B1 | Nearby search is FAKE — returns top-30 statewide | `hirer_dashboard.dart` | `_search()` | Worker discovery completely broken for nearby mode |
| B2 | Storage rules don't cover profile/face photos | `storage.rules` | all | Face enrollment photo upload blocked; profile photos blocked |
| B3 | Firestore strict rules may not be deployed | Firebase Console | — | Everything may be running on old permissive rules OR broken by strict rules not meant to be enforced yet |
| B4 | Voice: GPS unavailable → hardcoded Hassan coordinates | `voice_tool_registry.dart` | ~450 | Users anywhere get Hassan results when GPS is off |
| B5 | Voice: `_launchNavigation` routes worker to their OWN position | `voice_tool_registry.dart` | `_launchNavigation()` | Navigation launched from voice goes to wrong destination |

### 🟡 Medium (degrades quality, doesn't fully block)

| # | Bug | File | Impact |
|---|-----|------|--------|
| B6 | Global singletons risk session bleed on logout | `NavigationEngine`, `JourneyService`, `RoutingOrchestrator` | Worker A's route visible to Worker B on shared device |
| B7 | No pagination in worker search (hard limit 30/150) | `jobs_provider.dart`, `hirer_dashboard.dart` | Misses workers; high read cost |
| B8 | WorkerDiscoveryService does not exist — logic in screen | `hirer_dashboard.dart` | Untestable, impossible to reuse for voice |
| B9 | Dead `workerProfiles` collection — written but never queried | Multiple | Wasted writes, confused data model |
| B10 | Worker job feed downloads 150 jobs, filters in Dart | `jobs_provider.dart` | Inefficient, misses jobs beyond limit |
| B11 | No road-distance matrix for ANY worker search result | Entire codebase | "Nearby" distances are completely absent from UI |
| B12 | Hardcoded admin email in client code | `auth_provider.dart:76` | Admin role escalation via email change |

### 🟢 Low (code quality, not user-facing)

| # | Bug | File | Impact |
|---|-----|------|--------|
| B13 | Hidden dev mode (5-tap) in production build | `welcome_screen.dart` | Dev features exposed to end users |
| B14 | Offline escape hatch keeps user authenticated on network error | `auth_provider.dart:146-181` | Unknown-status user gets HomeShell access |
| B15 | `workerProfiles` Firestore rules — dead collection | `firestore.rules` | Rules complexity for unused collection |
| B16 | Voice deprecation warnings in `voice_service.dart` | `voice_service.dart:49-53` | Future build failures |
| B17 | Face photo upload ON HOLD, writes empty string to Firestore | `face_enrollment_screen.dart:192` | No face photo stored despite UI showing "verified" |

---

## 12. Screen → Provider → Service → Collection Map

| Screen | Provider | Service | Firestore | RTDB | Security Rule |
|--------|----------|---------|-----------|------|---------------|
| WelcomeScreen | AuthProvider | — | users | — | users.create |
| RegistrationScreen | AuthProvider | UserIdService | users, usernames | — | users.create/update |
| FaceEnrollmentScreen | AuthProvider | — | users | — | users.update (narrow) |
| SplashScreen | AuthProvider | — | users (read) | — | users.read |
| HomeShell | AuthProvider | — | — | — | — |
| WorkerDashboard | JobsProvider | — | jobs | — | jobs.read (isApproved) |
| HirerDashboard | — (inline) | — | users (search) | — | users.read |
| JobDetailScreen | JobsProvider | — | applications | — | applications.create |
| ApplicationsScreen | JobsProvider | BookingService | applications, bookings, jobs | — | applications.update, bookings.create |
| ChatScreen | — | ChatBookingService | conversations, messages | — | conversations.read/update |
| WorkerJourneyScreen | JourneyProvider | JourneyService, NavigationEngine, RoutingOrchestrator | bookings | liveTracking | bookings.update |
| HirerTrackingScreen | — | — | bookings | liveTracking (read) | bookings.read |
| WorkCompletionScreen | — | VerifiedWorkService | bookings, verifiedWorkRecords | — | bookings.update |
| VoiceCommandCenterScreen | — | VoiceEngine, VoiceSessionManager, VoiceToolRegistry | users (search) | — | users.read |
| AdminDashboard | — | — | users, auditLogs | — | users.update (admin) |
| ProfileScreen | AuthProvider | — | users | — | users.update |
| RouteDiagnosticScreen | — | RouteDiagnosticsService | — | — | — |

---

## 13. What Works vs What Is Broken

### ✅ Works (verified in code)
- Google Sign-In
- User ID + Password login
- Registration wizard (multi-step form)
- Face enrollment (ML Kit liveness, Firestore narrow-rule transition)
- Admin approval/rejection with audit log
- Job posting by hirers
- Job apply by workers (after our fix removing jobs.update)
- Booking creation (accept application → atomic batch)
- OTP-based arrival verification
- Chat messaging
- Worker navigation (GPS stream, route, map)
- Navigation engine (progress, off-route detection, rerouting)
- RTDB live tracking write (worker) + read (hirer)
- Route diagnostic screen
- Work completion + rating

### ❌ Broken / Not Working
- **Nearby worker search** — completely fake (no GPS, returns statewide)
- **Road distance/ETA** for worker cards — zero implementation
- **Voice → correct navigation destination** — routes to worker position, not job
- **Voice → GPS unavailable** — uses hardcoded Hassan coordinates
- **Profile/face photo upload** — storage rules block it
- **Worker search pagination** — none
- **Voice → real Firestore search integration** — GroqNlu calls real service, but GPS fallback corrupts results

---

## 14. Canonical Domain Model — Current State

These classes EXIST in the codebase:
```
UserProfile         → lib/models/user_profile.dart (459 lines)
WorkLocation        → lib/models/work_location.dart (77 lines)
LiveLocation        → lib/models/live_location.dart (142 lines) — RTDB transport
JourneyState        → lib/models/journey_state.dart (518 lines) — navigation state
RouteResult         → lib/models/route_result.dart (438 lines)
SkillPassport       → lib/models/skill_passport.dart (380 lines)
SkillAssessment     → lib/models/skill_assessment.dart (291 lines)
AssessmentEvidence  → lib/models/assessment_evidence.dart (234 lines)
VerifiedWorkRecord  → lib/models/verified_work_record.dart (138 lines)
WorkerRegistration  → lib/models/worker_registration.dart (155 lines)
CredentialRecord    → lib/models/credential_record.dart (257 lines)
SkillBadge          → lib/models/skill_badge.dart (159 lines)
VoiceSessionState   → lib/models/voice_session_state.dart (223 lines)
VerificationAuditLog → lib/models/verification_audit_log.dart (106 lines)
```

These DO NOT have model classes (handled as raw Maps):
```
Job         → inline in jobs_provider.dart
Application → inline in jobs_provider.dart + chat_booking_service.dart
Booking     → inline in chat_booking_service.dart (uses JourneySessionContract)
```

---

## 15. Phase 0 Freeze Status

Before any code is written, the following must be verified end-to-end:

| Workflow | Code Exists | Actually Works | Blocker |
|----------|-------------|----------------|---------|
| 1. Authentication | ✅ | ✅ | — |
| 2. Registration | ✅ | ⚠️ | Storage rules block photo upload |
| 3. Verification (face) | ✅ | ⚠️ | Photo stored as '' — liveness works, photo doesn't |
| 4. Admin approval | ✅ | ✅ | Depends on deployed Firestore rules |
| 5. Worker discovery | ✅ | ❌ | Nearby is fake. No distance. |
| 6. Profile | ✅ | ⚠️ | No photo display (empty photoUrl) |
| 7. Job apply | ✅ | ✅ | Fixed (removed jobs.update) |
| 8. Chat | ✅ | ✅ | — |
| 9. Booking | ✅ | ✅ | — |
| 10. Worker navigation | ✅ | ✅ | Grey screen fixed |
| 11. Hirer live tracking | ✅ | ✅ | Coordinate mapping correct |
| 12. Job completion | ✅ | ✅ | — |
| 13. Rating/review | ✅ | ✅ | — |
| Voice (post-core) | ✅ | ❌ | Fake GPS, wrong destination |

---

## 16. Recommended Fix Priority (Smallest Safe Fixes)

### Fix 1 — Deploy Firestore rules (IMMEDIATE, no code change)
**Action:** Open Firebase Console → copy `firestore.rules` → paste → Publish  
**Why:** The strict rules on disk may not be live. This is the single most impactful action.

### Fix 2 — Storage rules: add profile photo paths (SMALL CODE CHANGE)
**File:** `storage.rules`  
**Action:** Add rules for `profile-photos/{uid}/` and `face-photos/{uid}/`  
**Impact:** Unblocks face photo upload and profile photo display

### Fix 3 — Voice: remove hardcoded Hassan fallback (SMALL CODE CHANGE)
**File:** `lib/services/voice/voice_tool_registry.dart`  
**Action:** If GPS unavailable → show error "Location unavailable. Enable GPS or choose a district." instead of using Hassan coords

### Fix 4 — Voice: fix `_launchNavigation` destination (SMALL CODE CHANGE)
**File:** `lib/services/voice/voice_tool_registry.dart`  
**Action:** `_launchNavigation` must use `booking['jobLat']`/`booking['jobLng']` not `worker.latitude`/`worker.longitude`

### Fix 5 — Nearby search: use actual GPS (MEDIUM)
**File:** `lib/screens/home/hirer_dashboard.dart`  
**Action:** Get device GPS position, use Firestore geohash filtering or pass `originLat/originLng` for post-query distance sort

### Fix 6 — Extract WorkerDiscoveryService (MEDIUM, enables everything else)
**File:** new `lib/services/worker_discovery_service.dart`  
**Action:** Move `_search()` logic out of dashboard into standalone service — required for voice search integration and testability

---

*This document is the single source of truth. Update it whenever a bug is fixed or a new fact is discovered.*
