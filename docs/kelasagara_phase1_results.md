# Kelasagara — Phase 1 Results
**Phase:** Security + Data Boundary + Canonical Contract Repair
**Completed:** 2026-09-30
**Branch:** feature/navigation-engine-v11-hardened
**Flutter analyze:** ✅ Exit code 0 (221 pre-existing info/warning issues, 0 errors)
**Tests:** ✅ 39/39 Phase 1 security contract tests pass

---

## Summary

Phase 1 has established a trustworthy data and authorization foundation. Six defects in the security/data layer have been resolved. The Firestore rules, Storage rules, client code, and documentation are now consistent with the principle that **the client is not a trusted authority**.

---

## Defects Resolved

| Defect | Description | Status | Files Changed |
|---|---|---|---|
| DEF-001 | Work completion batch blocked by rules | PARTIALLY FIXED | `verified_work_service.dart`, `firestore.rules` |
| DEF-004 | Storage rules block profile/face photos | FIXED | `storage.rules` |
| DEF-009 | Public worker discovery blocked | FIXED | `firestore.rules` |
| DEF-010 | HirerTrackingScreen passes bookingId as jobId | FIXED | `hirer_tracking_screen.dart`, `journey_navigator.dart` |
| DEF-020 | OTP field name inconsistency (`otp` vs `arrivalOtp`) | FIXED | `applications_screen.dart`, `hirer_dashboard.dart`, `firebase_service.dart` |
| DEF-AdminPromotion | Client-side admin self-promotion | FIXED | `auth_provider.dart` |
| DEF-HomeShell | Unapproved/unknown users enter dashboard | FIXED | `home_shell.dart`, `auth_provider.dart` |

---

## Files Changed

### Dart Code
| File | Change |
|---|---|
| `lib/providers/auth_provider.dart` | Removed admin self-promotion write; fixed offline fallback to set `unauthenticated` on permission-denied and stateless network errors |
| `lib/screens/home/home_shell.dart` | Removed `pendingReview`/`unknown` bypass from `canEnter`; removed unused import |
| `lib/screens/applications/applications_screen.dart` | OTP field: `'otp'` → canonical `arrivalOtp` schema (write + read) |
| `lib/screens/home/hirer_dashboard.dart` | OTP field: `'otp'` → canonical `arrivalOtp` schema |
| `lib/services/firebase_service.dart` | OTP field: `'otp'` → canonical `arrivalOtp` schema (write + read) |
| `lib/services/verified_work_service.dart` | Split batch: booking update separated from admin-only `verifiedWorkRecords` create; `verifiedWorkRecords` write removed from client |
| `lib/screens/tracking/hirer_tracking_screen.dart` | Added `jobId` + `workerId` constructor fields; `WorkCompletionScreen` receives correct `jobId` |
| `lib/screens/tracking/journey_navigator.dart` | `openHirer()` reads and passes `jobId` + `workerId` from booking document |

### Rules
| File | Change |
|---|---|
| `firestore.rules` | DEF-009: added approved-worker read path; DEF-001: added hirer-completion update branch; improved booking update rule comments |
| `storage.rules` | DEF-004: added `profile-photos`, `face-photos`, `portfolio` paths with ownership/size/MIME constraints |

### Tests
| File | Result |
|---|---|
| `test/phase1_security_contract_test.dart` | **NEW** — 39 tests, all pass |
| `test/formal_contracts_test.dart` | Pre-existing — still pass |
| `test/auth_identity_registration_test.dart` | Pre-existing — 67 tests, all pass |

### Documentation
| File | Status |
|---|---|
| `docs/kelasagara_data_authority_matrix.md` | NEW |
| `docs/kelasagara_security_data_contract.md` | NEW |
| `docs/kelasagara_booking_contract.md` | NEW |
| `docs/kelasagara_tracking_contract.md` | NEW |
| `docs/kelasagara_write_ownership.md` | NEW |

---

## Verification Results

### flutter analyze
```
Exit code: 0
221 issues (all info/pre-existing warnings, 0 errors)
```

The 2 warnings in `test/v800_enterprise_navigation_test.dart` (unused imports) are pre-existing and not introduced by Phase 1.

### flutter test (Phase 1 security tests)
```
39/39 tests passed
```

Coverage:
- Booking state machine (11 tests including 4 attack tests)
- Account status state machine (9 tests including 5 attack tests)
- Authority field protection (7 tests including 6 attack tests)
- OTP canonicalization (5 tests)
- Booking destination contract (4 tests)
- HomeShell access guard (3 tests including 2 attack tests)

### flutter test (regression)
```
formal_contracts_test.dart: all passed
auth_identity_registration_test.dart: 67/67 passed
```

---

## Deployment Note

> [!WARNING]
> **firebase deploy is blocked (403 wrong account).**
> The updated `firestore.rules` and `storage.rules` are correct on disk but have NOT been deployed.
> To apply:
> 1. Open Firebase Console → Firestore → Rules tab
> 2. Paste the full content of `firestore.rules`
> 3. Open Firebase Console → Storage → Rules tab
> 4. Paste the full content of `storage.rules`
> 5. Publish both

---

## DEF-001 Detailed Resolution Note

**What works after Phase 1:**
- Worker can request completion (`status: completion_requested`) ✅
- Hirer can confirm completion (`status: completion_verified`) ✅ (new rule)
- Rating document is created ✅ (non-fatal write to `ratings` collection)

**What is DEFERRED to Phase 3:**
- `verifiedWorkRecords` document creation ❌ (admin-only rule, requires Cloud Function)
- `users/{workerId}.verifiedWorkCount` increment ❌ (admin-only, requires Cloud Function)
- `users/{workerId}.totalJobs` increment ❌ (admin-only, requires Cloud Function)
- `workerSkills/{id}.verifiedJobCount` increment ❌ (admin-only, requires Cloud Function)

**Phase 3 design:** A Cloud Function listens to `bookings/{id}` writes where `status` transitions to `completion_verified`. It then atomically creates the `verifiedWorkRecords` document and increments the worker's counters using the Admin SDK (bypasses client rules).

---

## Remaining Open Defects (Not in Phase 1 Scope)

| DEF | Description | Phase |
|---|---|---|
| DEF-002 | Worker search filter unreliable (district/taluk) | Phase 2 |
| DEF-003 | Nearby worker discovery unreliable (no geohash) | Phase 2 |
| DEF-005 | Navigation rerouting flaps | Phase 2 |
| DEF-006 | Voice command integration not observable | Phase 2 |
| DEF-007 | Profile not presented as marketplace profile | Phase 2 |
| DEF-008 | Admin approval dashboard incomplete | Phase 2 |
| DEF-011 | skillId on completion defaults to 'general' | Phase 2 |
| DEF-012 | Face photo URL not written to Firestore after Storage upload | Phase 2 |
| DEF-015 | verifiedWorkRecords + counter increment (Cloud Function) | Phase 3 |

---

## Phase 1 — COMPLETE. DO NOT START PHASE 2 AUTOMATICALLY.
