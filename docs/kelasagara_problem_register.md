# KELASAGARA — Forensic Problem Register
**Phase:** Phase 0 Forensic Freeze  
**Classification:** P0 (Blocker) | P1 (Critical) | P2 (Major) | P3 (Minor)

---

## DEF-001 [P0] — Work Completion Batch Write Prohibited by Firestore Rules
- **Severity:** P0 (Blocker)
- **Symptom:** When a hirer taps "✅ Confirm" on `WorkCompletionScreen` after a job is finished, the screen throws an error or fails silently, and the job never transitions to completed.
- **Root Cause:** In `lib/services/verified_work_service.dart` (`confirmCompletion`), an atomic batch attempts 4 operations:
  1. `batch.set(vwRef, ...)` to `verifiedWorkRecords/{id}` — `firestore.rules` line 344 restricts create/update to `isAdmin()` only; hirers are forbidden.
  2. `batch.update(workerRef, {'verifiedWorkCount': increment(1), 'totalJobs': increment(1)})` to `users/{workerId}` — `firestore.rules` line 23 only allows `isOwner(uid) || isAdmin()`; hirer has no write access to worker profile, and even owner cannot modify `totalJobs` or `verifiedWorkCount`.
  3. `batch.set(skillRef, ...)` to `workerSkills/{workerId_skillId}` — `firestore.rules` line 263 only allows `workerId == myUid()`; hirers are forbidden.
  4. `batch.update(bookingRef, {'completedAt': now})` — `firestore.rules` line 209 explicitly forbids hirer updates from touching `'completedAt'`.
- **File:** `lib/services/verified_work_service.dart` and `firestore.rules`
- **Symbol:** `VerifiedWorkService.confirmCompletion` / `match /verifiedWorkRecords/{recordId}`
- **Dependency:** Cloud Firestore Security Rules
- **Data Source:** `verifiedWorkRecords`, `users`, `workerSkills`, `bookings`
- **Expected Behavior:** Hirer confirmation successfully records completed work, updates booking status to `'completion_verified'`, and awards verified work badges without rule violations.
- **Actual Behavior:** Entire batch commit is denied with `permission-denied`.
- **Recommended Repair:** Split authoritative badge increments to admin/backend or update `firestore.rules` to allow hirers of confirmed bookings to create `verifiedWorkRecords` and update specific booking completion fields, while isolating worker profile mutations.
- **Test Required:** Integration test running hirer `confirmCompletion` on a booking in `completion_requested` state against Firestore rules emulator.

---

## DEF-002 [P0] — Nearby Worker Search is Completely Fake (Statewide Dump)
- **Severity:** P0 (Blocker)
- **Symptom:** Selecting "📍 Nearby" in the Hirer Dashboard returns workers from distant districts (e.g. Belagavi workers shown to a hirer in Bengaluru) and displays no distance.
- **Root Cause:** In `lib/screens/home/hirer_dashboard.dart` lines 486–502, `_FindWorkersSectionState._search()` explicitly drops `district` and `taluk` filters when `_nearbyMode == true`, executing an unbounded query for the top 30 rated workers across the entire state. No GPS coordinates are obtained, no geohash bounding is performed, and no road distance matrix is computed.
- **File:** `lib/screens/home/hirer_dashboard.dart`
- **Symbol:** `_FindWorkersSectionState._search`
- **Dependency:** `Geolocator`, `MatrixService`, `cloud_firestore`
- **Data Source:** `users` collection
- **Expected Behavior:** "Nearby" mode retrieves device GPS position, queries candidates within geographic radius (e.g. 10–25 km), ranks them by real road distance via `MatrixService`, and displays actual distance on cards.
- **Actual Behavior:** Queries statewide approved workers with zero distance calculations.
- **Recommended Repair:** Extract discovery logic into a canonical `WorkerDiscoveryService`. Implement bounding box / geohash candidate filtering against device GPS coordinates, then pass results through `MatrixService.rankWorkersByDistance`.
- **Test Required:** Unit test with known GPS origin verifying only workers within radius are returned and ranked by road distance.

---

## DEF-003 [P0] — Search Result Cards Have Dead Action Callbacks & No Booking CTA
- **Severity:** P0 (Blocker)
- **Symptom:** Hirers searching for workers see results, but tapping "Message" or "View Profile" does nothing at all, and there is no button to hire or book the worker.
- **Root Cause:** In `lib/screens/home/hirer_dashboard.dart` lines 659–664, `WorkerCard` instances are instantiated with empty inline closures:
  ```dart
  onMessage: () {},
  onViewProfile: () {},
  ```
  Furthermore, `WorkerCard` contains no button or entry point for initiating a booking or direct request.
- **File:** `lib/screens/home/hirer_dashboard.dart` & `lib/widgets/worker_card.dart`
- **Symbol:** `_FindWorkersSectionState.build` / `WorkerCard`
- **Dependency:** `ChatScreen`, `ProfileScreen`, `BookingService`
- **Data Source:** Search candidate list
- **Expected Behavior:** Tapping "Message" opens `ChatScreen` with the worker. Tapping "View Profile" opens a dedicated worker profile preview. Tapping "Book / Hire" initiates the booking workflow.
- **Actual Behavior:** User taps produce zero feedback or navigation.
- **Recommended Repair:** Implement callbacks linking `onMessage` to `ChatScreen`, `onViewProfile` to a worker public profile screen, and add a primary CTA for booking.
- **Test Required:** Widget test ensuring tapping "Message" pushes `ChatScreen` and tapping "View Profile" pushes worker details.

---

## DEF-004 [P0] — Firebase Storage Rules Block All Profile & Face Photo Uploads
- **Severity:** P0 (Blocker)
- **Symptom:** Workers cannot upload profile photos, and face verification cannot upload liveness photo captures to Firebase Storage.
- **Root Cause:** In `storage.rules`, the only permitted path is `assessment-evidence/{uid}/{assessmentId}/{taskId}/{filename}`. The default catch-all rule `match /{allPaths=**} { allow read, write: if false; }` denies every other path, including `profile-photos/`, `face-photos/`, and registration documents.
- **File:** `storage.rules`
- **Symbol:** `service firebase.storage`
- **Dependency:** Firebase Storage SDK
- **Data Source:** Firebase Storage bucket
- **Expected Behavior:** Authenticated users can upload their own profile photo and face enrollment verification image to designated paths (`profile-photos/{uid}/...`).
- **Actual Behavior:** Any upload to non-assessment paths is immediately rejected with Storage unauthorized exception.
- **Recommended Repair:** Add secure rules for `profile-photos/{uid}/{filename}` and `face-photos/{uid}/{filename}` with size limits (e.g. $\le 5\text{MB}$) and image MIME checks (`image/.*`).
- **Test Required:** Storage security rules test verifying an authenticated user can upload their own avatar and cannot write to another user's avatar path.

---

## DEF-005 [P0] — Voice Navigation Routes Hirer to Worker's Position as Worker
- **Severity:** P0 (Blocker)
- **Symptom:** When a hirer uses voice to search workers and triggers navigation, the app opens `WorkerJourneyScreen` with the worker's home/registered coordinates as the destination.
- **Root Cause:** In `lib/screens/voice/voice_command_center_screen.dart` lines 145–163:
  ```dart
  void _launchNavigation(WorkerCandidate worker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerJourneyScreen(
          bookingId: 'voice_nav_${DateTime.now().millisecondsSinceEpoch}',
          workerId: worker.workerId,
          hirerId: auth.uid ?? 'hirer_voice',
          destLat: worker.latitude,
          destLng: worker.longitude,
          ...
        ),
      ),
    );
  }
  ```
  `WorkerJourneyScreen` is designed for workers traveling to a job site. Launching it from a hirer voice command causes the hirer's device to publish live GPS tracking to RTDB as if they are the worker, navigating toward the worker.
- **File:** `lib/screens/voice/voice_command_center_screen.dart`
- **Symbol:** `_VoiceCommandCenterScreenState._launchNavigation`
- **Dependency:** `WorkerJourneyScreen`, `JourneyProvider`
- **Data Source:** `WorkerCandidate`
- **Expected Behavior:** Hirer voice command should either show the worker's location on a map or open `HirerTrackingScreen` for an active booking.
- **Actual Behavior:** Inverts roles and routes hirer using worker navigation engine.
- **Recommended Repair:** Disallow direct navigation from voice search without a confirmed booking; route to worker profile or booking confirmation.
- **Test Required:** Voice integration test verifying voice navigation CTA checks role and destination validity.

---

## DEF-006 [P0] — Voice Worker Search Ignores Account Approval Status
- **Severity:** P0 (Blocker)
- **Symptom:** Voice search ("find painter") returns unapproved, rejected, or suspended workers.
- **Root Cause:** In `lib/services/voice/voice_tool_registry.dart` line 258:
  ```dart
  final snapshot = await db.collection('users')
      .where('role', isEqualTo: 'worker')
      .where('isAvailable', isEqualTo: true)
      .limit(50)
      .get();
  ```
  The query is missing `.where('accountStatus', isEqualTo: 'approved')`.
- **File:** `lib/services/voice/voice_tool_registry.dart`
- **Symbol:** `VoiceToolRegistry.searchWorkersNearby`
- **Dependency:** Cloud Firestore
- **Data Source:** `users` collection
- **Expected Behavior:** Only workers with `accountStatus == 'approved'` are returned by any search interface.
- **Actual Behavior:** Returns any worker document where `isAvailable == true`, including accounts in `pending_review` or `rejected`.
- **Recommended Repair:** Add `.where('accountStatus', isEqualTo: 'approved')` to the Firestore query.
- **Test Required:** Query test verifying unapproved worker documents are excluded from voice candidate results.

---

## DEF-007 [P0] — Voice `createBooking` Generates Malformed Document Breaking Navigation
- **Severity:** P0 (Blocker)
- **Symptom:** A booking created via voice command cannot be navigated or tracked; clicking "Journey" shows "Job location not available."
- **Root Cause:** In `lib/services/voice/voice_tool_registry.dart` lines 542–551, `createBooking` writes a bare document with only `hirerId`, `workerId`, `workerName`, `skill`, `status`. It omits `jobId`, `jobLat`, `jobLng`, `jobAddress`, and `pay`. When `JourneyNavigator.openWorker` inspects `jobLat`/`jobLng`, it finds 0.0 and aborts with "Job location not available."
- **File:** `lib/services/voice/voice_tool_registry.dart`
- **Symbol:** `VoiceToolRegistry.createBooking`
- **Dependency:** `JourneyNavigator`, `chat_booking_service`
- **Data Source:** `bookings` collection
- **Expected Behavior:** Voice booking must conform to canonical `Booking` schema with valid job coordinates.
- **Actual Behavior:** Incomplete document written to Firestore.
- **Recommended Repair:** Unify voice booking with `BookingService.acceptApplicant` or require explicit job coordinates.
- **Test Required:** Contract test ensuring all booking creation paths satisfy `BookingDestinationContract`.

---

## DEF-008 [P0] — Voice Tool Falls Back to Hardcoded Hassan Coordinates on GPS Timeout
- **Severity:** P0 (Blocker)
- **Symptom:** A user in Bengaluru or Mysuru using voice without GPS permissions is told about workers located in Hassan.
- **Root Cause:** In `lib/services/voice/voice_tool_registry.dart` lines 234–237:
  ```dart
  // Fallback default center: Hassan, Karnataka
  userLat = 13.0060;
  userLng = 76.0954;
  ```
- **File:** `lib/services/voice/voice_tool_registry.dart`
- **Symbol:** `VoiceToolRegistry.searchWorkersNearby`
- **Dependency:** `LocationService`
- **Data Source:** Hardware GPS
- **Expected Behavior:** If GPS is unavailable, return an explicit error prompt asking the user to enable location or specify an area/district.
- **Actual Behavior:** Silently fakes location as Hassan.
- **Recommended Repair:** Remove hardcoded fallback; return `{'success': false, 'error': 'GPS location required. Please specify a district.'}`.
- **Test Required:** Unit test simulating null GPS position ensuring error response instead of Hassan coordinates.

---

## DEF-009 [P1] — Public Discovery Query Blocked if Strict `firestore.rules` Deployed
- **Severity:** P1 (Critical)
- **Symptom:** Hirers searching for workers get a `permission-denied` Firestore error if the strict rules on disk are deployed to Firebase Console.
- **Root Cause:** In `firestore.rules` line 23:
  ```javascript
  match /users/{uid} {
    allow read: if isOwner(uid) || isAdmin();
  ```
  Users can only read their own document or if they are admin. A hirer searching `collection('users').where('role', '==', 'worker')` will be blocked because they do not own the worker documents.
- **File:** `firestore.rules`
- **Symbol:** `match /users/{uid}`
- **Dependency:** Cloud Firestore Security Rules
- **Data Source:** `users` collection
- **Expected Behavior:** Signed-in users can read public marketplace fields of approved workers, or public worker profiles must exist in an open collection.
- **Actual Behavior:** Blanket read restriction on `users/{uid}` blocks worker discovery.
- **Recommended Repair:** Either allow public read of approved worker profiles in `users/{uid}` (`allow read: if isSignedIn() && (isOwner(uid) || isAdmin() || (resource.data.role == 'worker' && resource.data.accountStatus == 'approved'))`), or synchronize to a dedicated `publicWorkerProfiles` collection.
- **Test Required:** Security rules test verifying a signed-in hirer can read an approved worker's profile and cannot read an unapproved worker or private fields.

---

## DEF-010 [P1] — `HirerTrackingScreen` Passes `bookingId` as `jobId` and Hardcodes Skill `'general'`
- **Severity:** P1 (Critical)
- **Symptom:** Completed work records store corrupted job IDs (`{jobId}_{workerId}` instead of real `jobId`) and skill is always recorded as `'general'`, breaking skill-specific reputation tracking.
- **Root Cause:** In `lib/screens/tracking/hirer_tracking_screen.dart` lines 246–254:
  ```dart
  WorkCompletionScreen(
    bookingId: widget.bookingId,
    workerId: prov.workerId ?? '',
    hirerId: prov.hirerId ?? '',
    jobId: widget.bookingId, // <--- Bug
    skillId: 'general',      // <--- Bug
    workerName: widget.workerName,
    jobTitle: widget.jobTitle,
  )
  ```
- **File:** `lib/screens/tracking/hirer_tracking_screen.dart`
- **Symbol:** `_HirerTrackingScreenState._buildCompletionBanner`
- **Dependency:** `WorkCompletionScreen`, `VerifiedWorkService`
- **Data Source:** Booking state
- **Expected Behavior:** Passes the real `jobId` and `skillId` from the booking document.
- **Actual Behavior:** Overwrites `jobId` with `bookingId` and sets `skillId` to `'general'`.
- **Recommended Repair:** Store `jobId` and `skillId` on `JourneyProvider` when loading booking data and pass them into `WorkCompletionScreen`.
- **Test Required:** Unit test checking navigation arguments passed to `WorkCompletionScreen`.

---

## DEF-011 [P1] — Worker Job Feed Downloads 150 Unfiltered Jobs into Memory
- **Severity:** P1 (Critical)
- **Symptom:** High read volume and potential memory overhead; workers cannot see jobs beyond the first 150 created if local filters eliminate them.
- **Root Cause:** In `lib/providers/jobs_provider.dart` line 258:
  ```dart
  _db.collection('jobs').where('status', isEqualTo: 'open').limit(150).snapshots()
  ```
  All user filters (district, taluk, skill, wage, urgency) are executed purely client-side in Dart via `filteredJobs`.
- **File:** `lib/providers/jobs_provider.dart`
- **Symbol:** `JobsProvider.startListening` / `JobsProvider.filteredJobs`
- **Dependency:** Cloud Firestore
- **Data Source:** `jobs` collection
- **Expected Behavior:** Firestore query incorporates primary server-side filters (district, skill) to return only relevant jobs.
- **Actual Behavior:** Raw dump of 150 jobs filtered in memory.
- **Recommended Repair:** Dynamically construct Firestore query with `.where('district', isEqualTo: ...)` and `.where('skill', isEqualTo: ...)`.
- **Test Required:** Benchmark test verifying query returns only filtered jobs without exceeding read limits.

---

## DEF-012 [P1] — Global Navigation & Tracking Singletons Risk Cross-User Session Bleed
- **Severity:** P1 (Critical)
- **Symptom:** If Worker A logs out and Worker B logs in on the same physical device, Worker B can see Worker A's active route, booking state, or GPS tracking buffer.
- **Root Cause:** `NavigationEngine.instance`, `JourneyService.instance`, and `RoutingOrchestrator.instance` are process-wide global singletons that hold in-memory mutable state (`_bookingId`, `_route`, `_sessionId`, `_cached`). `AuthProvider.signOut()` attempts to stop them, but if logout occurs abruptly or fails, state is retained.
- **File:** `lib/services/navigation_engine.dart`, `lib/services/journey_service.dart`
- **Symbol:** `NavigationEngine.instance`, `JourneyService.instance`
- **Dependency:** In-memory static state
- **Data Source:** Device memory
- **Expected Behavior:** Navigation and tracking sessions are scoped strictly to the active authenticated session / booking lifecycle and fully disposed upon session termination.
- **Actual Behavior:** Global singletons maintain dirty state across logins.
- **Recommended Repair:** Implement a formal `reset()` method on all singletons and enforce explicit cleanup in `AuthProvider.signOut()` and `WelcomeScreen` initialization.
- **Test Required:** Integration test verifying all tracking and navigation state is cleared after logout.

---

## DEF-013 [P1] — `MatrixService` Never Integrated into Hirer Dashboard Search
- **Severity:** P1 (Critical)
- **Symptom:** Hirer search cards never show road distance or estimated travel duration, showing only `distanceKm: null`.
- **Root Cause:** `MatrixService` exists in `lib/services/routing/matrix_service.dart` and supports multi-worker road distance calculation, but is only invoked in `voice_tool_registry.dart`. `_FindWorkersSectionState._search()` in `hirer_dashboard.dart` never invokes it.
- **File:** `lib/screens/home/hirer_dashboard.dart`
- **Symbol:** `_FindWorkersSectionState._search`
- **Dependency:** `MatrixService`
- **Data Source:** `RoutingOrchestrator`
- **Expected Behavior:** Candidate workers returned from Firestore are passed to `MatrixService.rankWorkersByDistance` to populate `distanceKm` and road ETA on `WorkerCard`.
- **Actual Behavior:** `WorkerCard` receives `distanceKm = null`.
- **Recommended Repair:** Pipe search candidate coordinates through `MatrixService.instance.rankWorkersByDistance` before rendering.
- **Test Required:** Unit test verifying `WorkerCard` renders formatted road distance and ETA when `MatrixService` returns ranks.

---

## DEF-014 [P1] — Face Enrollment Bypasses Photo Upload ("ON HOLD")
- **Severity:** P1 (Critical)
- **Symptom:** Workers who complete face liveness verification have no reference photo saved in their profile (`photoUrl: ''` / `facePhotoUrl: ''`), so hirers and admins see blank avatars.
- **Root Cause:** In `lib/screens/auth/face_enrollment_screen.dart` line 192, photo upload to Firebase Storage is commented out with note `// Photo upload is ON HOLD`, calling `auth.setFaceVerified(true, '')`.
- **File:** `lib/screens/auth/face_enrollment_screen.dart`
- **Symbol:** `_FaceEnrollmentScreenState._captureAndSave`
- **Dependency:** Firebase Storage, `storage.rules`
- **Data Source:** Camera frame
- **Expected Behavior:** Captured face frame is uploaded to Firebase Storage and the download URL is saved in `facePhotoUrl`.
- **Actual Behavior:** Saves an empty string `''` as the photo URL.
- **Recommended Repair:** Enable Storage rules for `face-photos/{uid}/` and upload compressed JPEG capture before calling `setFaceVerified`.
- **Test Required:** Liveness completion test confirming a valid Storage URL is persisted in `users/{uid}.facePhotoUrl`.

---

## DEF-015 [P1] — Unsafe Offline Network Fallback Bypasses Approval Gate
- **Severity:** P1 (Critical)
- **Symptom:** If a network interruption occurs during startup, a newly registered or unapproved user can bypass gatekeeping and access `HomeShell`.
- **Root Cause:** In `lib/providers/auth_provider.dart` lines 146–181:
  ```dart
  } on FirebaseException catch (e) {
    ...
    _currentUser = UserProfile(
      uid: uid,
      displayName: firebaseUser.displayName ?? 'User',
      email: firebaseUser.email ?? '',
      accountStatus: _currentUser?.accountStatus ?? AccountStatus.unknown,
    );
    _status = AuthStatus.authenticated;
    notifyListeners();
  }
  ```
  `HomeShell` line 83 checks: `(auth.faceVerified && (status == AccountStatus.pendingReview || status == AccountStatus.unknown))`. An unknown status user is allowed to render the shell.
- **File:** `lib/providers/auth_provider.dart` & `lib/screens/home/home_shell.dart`
- **Symbol:** `AuthProvider._loadUserFromFirestore` / `HomeShell.build`
- **Dependency:** Network connectivity
- **Data Source:** Firestore
- **Expected Behavior:** Network error during startup should show an explicit offline retry screen, not an authenticated shell.
- **Actual Behavior:** Fallback user object grants shell access.
- **Recommended Repair:** Differentiate network failure from authenticated profile state; display a connection error / retry UI instead of marking authenticated.
- **Test Required:** Unit test simulating Firestore timeout verifying user is not marked authenticated with `unknown` status.

---

## DEF-016 [P2] — Hardcoded Admin Email in Client Code Allows Role Escalation
- **Severity:** P2 (Major)
- **Symptom:** Hardcoded email grant in client application.
- **Root Cause:** In `lib/providers/auth_provider.dart` line 76:
  `const adminEmails = ['anandaananda16919@gmail.com'];`
  If a user signs in with this email, the client directly executes a Firestore update promoting the document to `role: 'admin'`.
- **File:** `lib/providers/auth_provider.dart`
- **Symbol:** `AuthProvider._loadUserFromFirestore`
- **Dependency:** Client auth state
- **Data Source:** `users` collection
- **Expected Behavior:** Admin authorization must be governed server-side via Firebase Custom Claims, not hardcoded strings in client code.
- **Actual Behavior:** Client code auto-promotes hardcoded email.
- **Recommended Repair:** Remove client promotion; manage admin role via Firebase Admin SDK or custom claims.
- **Test Required:** Verification that changing client email does not permit self-elevation to admin.

---

## DEF-017 [P2] — Hidden Dev Mode Accessible in Production
- **Severity:** P2 (Major)
- **Symptom:** Five taps on the title in `WelcomeScreen` reveals a secret developer mode menu.
- **Root Cause:** `lib/screens/auth/welcome_screen.dart` lines 232–252 tracks `_tapCount` and triggers a secret UI toggle without `kDebugMode` checks.
- **File:** `lib/screens/auth/welcome_screen.dart`
- **Symbol:** `_WelcomeScreenState._buildLogo`
- **Dependency:** Flutter framework
- **Data Source:** User gestures
- **Expected Behavior:** Developer mode triggers must be completely compiled out or gated behind `kDebugMode`.
- **Actual Behavior:** Available in release builds.
- **Recommended Repair:** Wrap gesture handler in `if (kDebugMode)`.
- **Test Required:** Release build inspection ensuring tap sequence is inactive.

---

## DEF-018 [P2] — Duplicate Orphan File `lib/screens/jobs/applications_screen.dart`
- **Severity:** P2 (Major)
- **Symptom:** Two different files named `applications_screen.dart` exist in the repository, causing confusion during maintenance.
- **Root Cause:** `lib/screens/jobs/applications_screen.dart` (51 lines) is a stub reading only memory maps. The real implementation is `lib/screens/applications/applications_screen.dart` (427 lines).
- **File:** `lib/screens/jobs/applications_screen.dart`
- **Symbol:** `ApplicationsScreen`
- **Dependency:** Project tree
- **Data Source:** Filesystem
- **Expected Behavior:** Exactly one canonical `ApplicationsScreen`.
- **Actual Behavior:** Two conflicting files with identical class names in different directories.
- **Recommended Repair:** Safely remove the orphaned 51-line stub file in `lib/screens/jobs/`.
- **Test Required:** Flutter analyze confirming no dangling imports after removal.

---

## DEF-019 [P2] — Dead Collection `workerProfiles` Defined in Rules but Unused
- **Severity:** P2 (Major)
- **Symptom:** Firestore rules define permissions for `workerProfiles/{userId}`, but no code in the application writes to or reads from it.
- **Root Cause:** Legacy schema relic. All worker data was consolidated into `users/{uid}`, leaving `workerProfiles` orphaned.
- **File:** `firestore.rules`
- **Symbol:** `match /workerProfiles/{userId}`
- **Dependency:** Cloud Firestore
- **Data Source:** Firestore rules
- **Expected Behavior:** Rules match actual active database schema.
- **Actual Behavior:** Dead rule block creates false expectation of a secondary collection.
- **Recommended Repair:** Remove `workerProfiles` block from `firestore.rules` or document deprecation.
- **Test Required:** Codebase grep verifying zero references to `workerProfiles`.

---

## DEF-020 [P2] — OTP Naming Discrepancy Across Booking Handshake Files
- **Severity:** P2 (Major)
- **Symptom:** Inconsistent arrival verification field names between booking creation and tracking.
- **Root Cause:** In `lib/screens/applications/applications_screen.dart` line 270, the arrival code is stored as:
  `await bookings.doc(bookingId).update({'otp': otp, ...});`
  Meanwhile, `journey_provider.dart` line 421 and `firestore.rules` line 192 expect `'arrivalOtp'`.
- **File:** `lib/screens/applications/applications_screen.dart` & `lib/providers/journey_provider.dart`
- **Symbol:** `'otp'` vs `'arrivalOtp'`
- **Dependency:** `bookings` schema
- **Data Source:** Firestore
- **Expected Behavior:** Single canonical field name (`arrivalOtp`) across all services.
- **Actual Behavior:** Writes `'otp'` in one file and expects `'arrivalOtp'` in another.
- **Recommended Repair:** Standardize strictly on `arrivalOtp`.
- **Test Required:** Integration test verifying arrival OTP generated by hirer is verified by worker without field mismatch.
