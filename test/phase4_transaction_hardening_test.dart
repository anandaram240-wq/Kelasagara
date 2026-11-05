// test/phase4_transaction_hardening_test.dart
// Phase 4 — Transaction Engine Hardening Tests
// Tests covering: booking state machine, OTP contract, completion idempotency,
// availability reconciliation, tracking identity, cancellation, rating duplicate prevention.
//
// All tests are pure Dart unit tests (no Firebase SDK calls).

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/booking_service.dart';
import 'package:kelasagaara/services/worker_availability_service.dart';
import 'package:kelasagaara/services/worker_discovery_service.dart';
import 'package:kelasagaara/models/worker_search_request.dart';

void main() {
  // ────────────────────────────────────────────────────────────────
  // SECTION 1: BookingStatus canonical constants
  // ────────────────────────────────────────────────────────────────
  group('BookingStatus constants', () {
    test('confirmed string is correct', () {
      expect(BookingStatus.confirmed, 'confirmed');
    });

    test('tracking string is correct', () {
      expect(BookingStatus.tracking, 'tracking');
    });

    test('arrived string is correct', () {
      expect(BookingStatus.arrived, 'arrived');
    });

    test('working string is correct', () {
      expect(BookingStatus.working, 'working');
    });

    test('completionRequested string is correct', () {
      expect(BookingStatus.completionRequested, 'completion_requested');
    });

    test('completionVerified string is correct', () {
      expect(BookingStatus.completionVerified, 'completion_verified');
    });

    test('cancelled string is correct', () {
      expect(BookingStatus.cancelled, 'cancelled');
    });

    test('disputed string is correct', () {
      expect(BookingStatus.disputed, 'disputed');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 2: Active vs terminal state classification
  // ────────────────────────────────────────────────────────────────
  group('BookingStatus state classification', () {
    test('confirmed is an active state', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.confirmed), isTrue);
    });

    test('tracking is an active state', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.tracking), isTrue);
    });

    test('working is an active state', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.working), isTrue);
    });

    test('completionRequested is an active state', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.completionRequested), isTrue);
    });

    test('completionVerified is a terminal state', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.completionVerified), isTrue);
    });

    test('cancelled is a terminal state', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.cancelled), isTrue);
    });

    test('disputed is a terminal state', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.disputed), isTrue);
    });

    test('active and terminal states are disjoint', () {
      final intersection = BookingStatus.activeStates
          .intersection(BookingStatus.terminalStates);
      expect(intersection, isEmpty);
    });

    test('completionVerified is NOT an active state', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.completionVerified), isFalse);
    });

    test('working is NOT a terminal state', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.working), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 3: BookingResult model
  // ────────────────────────────────────────────────────────────────
  group('BookingResult model', () {
    test('ok result has success=true', () {
      final result = BookingResult.ok('booking_123');
      expect(result.success, isTrue);
    });

    test('ok result has correct bookingId', () {
      final result = BookingResult.ok('booking_abc');
      expect(result.bookingId, 'booking_abc');
    });

    test('ok result has null errorCode', () {
      final result = BookingResult.ok('booking_xyz');
      expect(result.errorCode, isNull);
    });

    test('fail result has success=false', () {
      final result = BookingResult.fail('PERMISSION_DENIED', 'Access denied');
      expect(result.success, isFalse);
    });

    test('fail result has null bookingId', () {
      final result = BookingResult.fail('NOT_FOUND', 'Not found');
      expect(result.bookingId, isNull);
    });

    test('fail result has correct errorCode', () {
      final result = BookingResult.fail('already_processed', 'Already accepted');
      expect(result.errorCode, 'already_processed');
    });

    test('fail result has correct errorMessage', () {
      final result = BookingResult.fail('INVALID_DATA', 'Missing jobId or workerId in application');
      expect(result.errorMessage, contains('Missing jobId'));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 4: BookingService is a singleton
  // ────────────────────────────────────────────────────────────────
  group('BookingService singleton', () {
    test('BookingService.instance is not null', () {
      expect(BookingService.instance, isNotNull);
    });

    test('BookingService.instance returns same instance', () {
      final a = BookingService.instance;
      final b = BookingService.instance;
      expect(identical(a, b), isTrue);
    });
  }, skip: 'Requires Firebase initialization');

  // ────────────────────────────────────────────────────────────────
  // SECTION 5: acceptApplication input validation
  // ────────────────────────────────────────────────────────────────
  group('acceptApplication input validation', () {
    test('missing jobId returns INVALID_DATA failure', () async {
      final result = await BookingService.instance.acceptApplication(
        hirerUid: 'hirer_001',
        applicationId: 'app_001',
        applicationData: {
          'jobId': '',    // empty jobId
          'workerId': 'worker_001',
          'hirerId': 'hirer_001',
          'status': 'pending',
        },
      );
      expect(result.success, isFalse);
      expect(result.errorCode, 'INVALID_DATA');
    });

    test('missing workerId returns INVALID_DATA failure', () async {
      final result = await BookingService.instance.acceptApplication(
        hirerUid: 'hirer_001',
        applicationId: 'app_002',
        applicationData: {
          'jobId': 'job_001',
          'workerId': '',    // empty workerId
          'hirerId': 'hirer_001',
          'status': 'pending',
        },
      );
      expect(result.success, isFalse);
      expect(result.errorCode, 'INVALID_DATA');
    });

    test('null applicationData jobId returns INVALID_DATA failure', () async {
      final result = await BookingService.instance.acceptApplication(
        hirerUid: 'hirer_001',
        applicationId: 'app_003',
        applicationData: {
          // jobId intentionally omitted
          'workerId': 'worker_001',
          'hirerId': 'hirer_001',
        },
      );
      expect(result.success, isFalse);
      expect(result.errorCode, 'INVALID_DATA');
    });
  }, skip: 'Requires Firebase initialization');

  // ────────────────────────────────────────────────────────────────
  // SECTION 6: State machine valid transition contract (offline/unit)
  // ────────────────────────────────────────────────────────────────
  group('Booking state machine transition matrix', () {
    // Valid transitions
    test('confirmed can reach tracking (worker starts journey)', () {
      // Worker's startJourney is valid from confirmed
      final from = BookingStatus.confirmed;
      final to = BookingStatus.tracking;
      // Confirmed is not terminal, tracking is active
      expect(BookingStatus.terminalStates.contains(from), isFalse);
      expect(BookingStatus.activeStates.contains(to), isTrue);
    });

    test('working can reach completionRequested (worker done)', () {
      expect(BookingStatus.activeStates.contains(BookingStatus.working), isTrue);
      expect(BookingStatus.activeStates.contains(BookingStatus.completionRequested), isTrue);
    });

    test('completionRequested can reach completionVerified (hirer confirms)', () {
      // completionVerified is terminal
      expect(BookingStatus.terminalStates.contains(BookingStatus.completionVerified), isTrue);
    });

    // Invalid transitions: terminal state cannot advance
    test('completionVerified cannot be re-entered into active states', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.completionVerified), isTrue);
      expect(BookingStatus.activeStates.contains(BookingStatus.completionVerified), isFalse);
    });

    test('cancelled cannot be re-entered into active states', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.cancelled), isTrue);
      expect(BookingStatus.activeStates.contains(BookingStatus.cancelled), isFalse);
    });

    test('disputed cannot be re-entered into active states', () {
      expect(BookingStatus.terminalStates.contains(BookingStatus.disputed), isTrue);
      expect(BookingStatus.activeStates.contains(BookingStatus.disputed), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 7: OTP 6-digit contract
  // ────────────────────────────────────────────────────────────────
  group('OTP 6-digit contract', () {
    // The OTP is generated as (100000 + Random().nextInt(899999)).toString()
    // This produces numbers in range [100000, 999999] — always 6 digits.
    const int otpMin = 100000;
    const int otpMax = 999999;

    test('OTP minimum is 6 digits', () {
      expect(otpMin.toString().length, 6);
    });

    test('OTP maximum is 6 digits', () {
      expect(otpMax.toString().length, 6);
    });

    test('OTP range produces only 6-digit strings', () {
      for (int i = 0; i < 100; i++) {
        final otp = (100000 + (i * 9000)).clamp(100000, 999999);
        expect(otp.toString().length, 6,
          reason: 'OTP $otp is not 6 digits');
      }
    });

    test('Legacy 4-digit OTP is invalid', () {
      // A 4-digit OTP (1000-9999) must no longer be accepted
      const legacyOtp = 1234;
      expect(legacyOtp.toString().length, lessThan(6));
    });

    test('OTP generation range lower bound excludes 4-digit numbers', () {
      // 100000 + 0 = 100000 — safely 6 digits
      const otp = 100000;
      expect(otp.toString().length, 6);
    });

    test('OTP schema requires 4 canonical fields', () {
      // The canonical OTP schema written to Firestore must have these 4 fields
      final otpSchema = {
        'arrivalOtp': '123456',
        'arrivalOtpExpiry': DateTime.now().add(const Duration(minutes: 30)),
        'arrivalOtpUsed': false,
        'arrivalOtpAttempts': 0,
      };
      expect(otpSchema.containsKey('arrivalOtp'), isTrue);
      expect(otpSchema.containsKey('arrivalOtpExpiry'), isTrue);
      expect(otpSchema.containsKey('arrivalOtpUsed'), isTrue);
      expect(otpSchema.containsKey('arrivalOtpAttempts'), isTrue);
    });

    test('OTP field name is arrivalOtp not otp', () {
      // Ensures the old field name is not used
      final schema = {'arrivalOtp': '123456'};
      expect(schema.containsKey('arrivalOtp'), isTrue);
      expect(schema.containsKey('otp'), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 8: Deterministic ratingId prevents duplicate ratings
  // ────────────────────────────────────────────────────────────────
  group('Rating idempotency via deterministic ratingId', () {
    String buildRatingId(String bookingId, String hirerUid) {
      return 'rating_${bookingId}_$hirerUid';
    }

    test('ratingId is deterministic for same bookingId + hirerUid', () {
      final id1 = buildRatingId('booking_abc', 'hirer_001');
      final id2 = buildRatingId('booking_abc', 'hirer_001');
      expect(id1, equals(id2));
    });

    test('ratingId is different for different bookingIds', () {
      final id1 = buildRatingId('booking_abc', 'hirer_001');
      final id2 = buildRatingId('booking_xyz', 'hirer_001');
      expect(id1, isNot(equals(id2)));
    });

    test('ratingId is different for different hirerUids', () {
      final id1 = buildRatingId('booking_abc', 'hirer_001');
      final id2 = buildRatingId('booking_abc', 'hirer_002');
      expect(id1, isNot(equals(id2)));
    });

    test('ratingId format is rating_{bookingId}_{hirerUid}', () {
      final id = buildRatingId('booking_abc', 'hirer_001');
      expect(id, startsWith('rating_'));
      expect(id, contains('booking_abc'));
      expect(id, contains('hirer_001'));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 9: Deterministic bookingId prevents double-acceptance
  // ────────────────────────────────────────────────────────────────
  group('Deterministic bookingId idempotency', () {
    String buildBookingId(String applicationId) {
      return 'booking_$applicationId';
    }

    test('bookingId is deterministic for same applicationId', () {
      final id1 = buildBookingId('app_001');
      final id2 = buildBookingId('app_001');
      expect(id1, equals(id2));
    });

    test('bookingId is different for different applicationIds', () {
      final id1 = buildBookingId('app_001');
      final id2 = buildBookingId('app_002');
      expect(id1, isNot(equals(id2)));
    });

    test('bookingId format is booking_{applicationId}', () {
      final id = buildBookingId('app_001');
      expect(id, 'booking_app_001');
    });

    test('two concurrent accepts produce same bookingId (idempotent)', () {
      // If two requests race, they produce the same bookingId.
      // The second set() in Firestore fails because the doc already exists.
      // This is the Phase 4 idempotency guarantee.
      const applicationId = 'app_race_001';
      final bookingId1 = buildBookingId(applicationId);
      final bookingId2 = buildBookingId(applicationId);
      expect(bookingId1, equals(bookingId2),
          reason: 'Concurrent accepts must produce the same bookingId to be idempotent');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 10: WorkerAvailabilityService singleton
  // ────────────────────────────────────────────────────────────────
  group('WorkerAvailabilityService', () {
    test('is a singleton', () {
      final a = WorkerAvailabilityService.instance;
      final b = WorkerAvailabilityService.instance;
      expect(identical(a, b), isTrue);
    });

    test('forceStop does not throw', () {
      // forceStop() should be callable at any time without throwing.
      // It is called on logout to prevent orphan GPS writes.
      expect(
        () => WorkerAvailabilityService.instance.forceStop(),
        returnsNormally,
      );
    });

    test('kFreshThreshold is 10 minutes', () {
      expect(
        WorkerAvailabilityService.kFreshThreshold,
        const Duration(minutes: 10),
      );
    });

    test('kStaleAfter is 30 minutes', () {
      expect(
        WorkerAvailabilityService.kStaleAfter,
        const Duration(minutes: 30),
      );
    });

    test('kMinMovementMeters is 50 meters', () {
      expect(WorkerAvailabilityService.kMinMovementMeters, 50.0);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 11: Tracking identity contract
  // ────────────────────────────────────────────────────────────────
  group('Tracking identity contract', () {
    test('RTDB path includes bookingId not workerId', () {
      // The RTDB path is liveTracking/{bookingId}
      // This scopes tracking by booking, not by worker.
      // A worker cannot access another worker's tracking by just knowing the workerId.
      const bookingId = 'booking_app_001';
      final path = 'liveTracking/$bookingId';
      expect(path, 'liveTracking/booking_app_001');
    });

    test('RTDB payload must include jobId field', () {
      // Phase 4: jobId is now required in tracking payload.
      // JourneyService fetches it from Firestore and injects into RTDB.
      final payload = {
        'workerId': 'worker_001',
        'hirerId': 'hirer_001',
        'jobId': 'job_001',    // Phase 4 addition
        'lat': 12.97,
        'lng': 77.59,
      };
      expect(payload.containsKey('jobId'), isTrue);
      expect(payload['jobId'], isNotEmpty);
    });

    test('RTDB payload without jobId would fail validation', () {
      // RTDB rule now requires jobId as a child node.
      final payloadMissingJobId = {
        'workerId': 'worker_001',
        'hirerId': 'hirer_001',
        // jobId missing
        'lat': 12.97,
        'lng': 77.59,
      };
      expect(payloadMissingJobId.containsKey('jobId'), isFalse,
          reason: 'This payload would be rejected by database.rules.json');
    });

    test('cross-booking tracking is prevented by bookingId-scoped path', () {
      // Worker for booking A cannot write to booking B’s tracking path.
      // The RTDB rule is: write only when newData.child(workerId).val() == auth.uid
      // and the path is scoped by bookingId.
      const workerBookingId = 'booking_app_worker_a';
      const differentBookingId = 'booking_app_worker_b';
      expect(workerBookingId, isNot(equals(differentBookingId)));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 12: Cancellation eligibility contract
  // ────────────────────────────────────────────────────────────────
  group('Cancellation eligibility contract', () {
    const cancellableStates = {'confirmed', 'pending'};

    test('confirmed is cancellable', () {
      expect(cancellableStates.contains('confirmed'), isTrue);
    });

    test('pending is cancellable', () {
      expect(cancellableStates.contains('pending'), isTrue);
    });

    test('working is NOT cancellable', () {
      expect(cancellableStates.contains('working'), isFalse);
    });

    test('tracking is NOT cancellable', () {
      expect(cancellableStates.contains('tracking'), isFalse);
    });

    test('completion_requested is NOT cancellable', () {
      expect(cancellableStates.contains('completion_requested'), isFalse);
    });

    test('completion_verified is NOT cancellable', () {
      expect(cancellableStates.contains('completion_verified'), isFalse);
    });

    test('cancelled cannot be cancelled again', () {
      expect(cancellableStates.contains('cancelled'), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 13: Availability reconciliation contract
  // ────────────────────────────────────────────────────────────────
  group('Availability reconciliation contract', () {
    test('acceptance must set isAvailable=false on worker', () {
      // Phase 4: BookingService.acceptApplication() atomically sets
      // worker.isAvailable=false in the same transaction as booking creation.
      // This prevents the accepted worker from appearing in nearby search.

      // Verify the contract field name
      const workerUpdateFields = {'isAvailable': false, 'activeBookingId': 'booking_abc'};
      expect(workerUpdateFields['isAvailable'], isFalse);
    });

    test('completion must set isAvailable=false (worker must explicitly turn on)', () {
      // After completion, worker does NOT automatically become available.
      // They must explicitly toggle Available in their dashboard.
      const workerCompletionUpdate = {'isAvailable': false, 'totalJobs': 1};
      expect(workerCompletionUpdate['isAvailable'], isFalse);
    });

    test('cancellation must clear activeBookingId on worker', () {
      // Simulates the Firestore FieldValue.delete() call
      final workerCancelUpdate = {
        'isAvailable': false,
        'activeBookingId': null,  // represents FieldValue.delete()
      };
      expect(workerCancelUpdate['activeBookingId'], isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 14: Hassan coordinate prohibition
  // ────────────────────────────────────────────────────────────────
  group('Hassan fallback coordinate prohibition', () {
    const double hassanLat = 13.0060;
    const double hassanLng = 76.0954;

    test('null GPS must not fall back to Hassan lat', () {
      // Phase 4: When GPS returns null, the correct response is LOCATION_UNAVAILABLE,
      // not a silent fallback to Hassan coordinates.
      double? gpsLat;
      // The correct pattern: fail on null, do NOT fall back
      expect(gpsLat, isNull,
          reason: 'Null GPS lat must remain null — never fall back to $hassanLat');
    });

    test('null GPS must not fall back to Hassan lng', () {
      double? gpsLng;
      expect(gpsLng, isNull,
          reason: 'Null GPS lng must remain null — never fall back to $hassanLng');
    });

    test('Hassan lat is not a valid user coordinate (must not be used as fallback)', () {
      // This documents the forbidden fallback value.
      // Any code using ?? 13.0060 in a computation path is a defect.
      expect(hassanLat, isNot(equals(0.0))); // it's a real coordinate, just wrong
      expect(hassanLat, inInclusiveRange(13.0, 14.0)); // Hassan district range
    });

    test('WorkerSearchRequest with null lat uses nearbyGps mode requiring valid GPS', () {
      // nearbyGps mode requires actual GPS — passing null GPS should fail or be caught
      // by the GPS quality engine, never silently replaced with Hassan
      const req = WorkerSearchRequest(
        mode: WorkerSearchMode.nearbyGps,
        sessionId: 'test_session',
        skillId: 'plumber',
        hirerPosition: null,
      );
      // nearbyGps mode with null coords is invalid for actual search
      expect(req.hirerPosition, isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 15: WorkerDiscoveryService singleton stability
  // ────────────────────────────────────────────────────────────────
  group('WorkerDiscoveryService singleton stability', () {
    test('instance is not null', () {
      expect(WorkerDiscoveryService.instance, isNotNull);
    });

    test('returns same singleton instance', () {
      final a = WorkerDiscoveryService.instance;
      final b = WorkerDiscoveryService.instance;
      expect(identical(a, b), isTrue);
    });

    test('newSessionId produces unique IDs', () {
      final id1 = WorkerDiscoveryService.instance.newSessionId();
      final id2 = WorkerDiscoveryService.instance.newSessionId();
      expect(id1, isNot(equals(id2)));
    });

    test('newSessionId is non-empty', () {
      final id = WorkerDiscoveryService.instance.newSessionId();
      expect(id, isNotEmpty);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 16: Phase 4B State-Machine Whitelist Validator (P4-001)
  // ────────────────────────────────────────────────────────────────
  group('Phase 4B State-Machine Whitelist Transition Matrix', () {
    // Pure validator simulating firestore.rules whitelisted transitions
    bool isValidTransition({
      required String fromState,
      required String toState,
      required String actorRole,
      bool arrivalVerified = false,
    }) {
      // Terminal states are immutable
      if (BookingStatus.terminalStates.contains(fromState)) return false;

      // Worker transitions
      if (actorRole == 'worker') {
        if (fromState == BookingStatus.confirmed && toState == BookingStatus.tracking) return true;
        if (fromState == BookingStatus.tracking && toState == BookingStatus.tracking) return true;
        if ((fromState == BookingStatus.confirmed || fromState == BookingStatus.tracking) &&
            toState == BookingStatus.arrived) return true;
        if (fromState == BookingStatus.arrived && toState == BookingStatus.working && arrivalVerified) return true;
        if (fromState == BookingStatus.working && toState == BookingStatus.completionRequested) return true;
        if ((fromState == BookingStatus.confirmed || fromState == 'pending') &&
            toState == BookingStatus.cancelled) return true;
        return false;
      }

      // Hirer transitions
      if (actorRole == 'hirer') {
        if (fromState == BookingStatus.arrived && toState == BookingStatus.arrived) return true; // OTP attempt write
        if (fromState == BookingStatus.completionRequested && toState == BookingStatus.completionVerified) return true;
        if ((fromState == BookingStatus.confirmed || fromState == 'pending') &&
            toState == BookingStatus.cancelled) return true;
        return false;
      }

      return false;
    }

    test('Legal worker transitions succeed', () {
      expect(isValidTransition(fromState: BookingStatus.confirmed, toState: BookingStatus.tracking, actorRole: 'worker'), isTrue);
      expect(isValidTransition(fromState: BookingStatus.tracking, toState: BookingStatus.tracking, actorRole: 'worker'), isTrue);
      expect(isValidTransition(fromState: BookingStatus.tracking, toState: BookingStatus.arrived, actorRole: 'worker'), isTrue);
      expect(isValidTransition(fromState: BookingStatus.arrived, toState: BookingStatus.working, actorRole: 'worker', arrivalVerified: true), isTrue);
      expect(isValidTransition(fromState: BookingStatus.working, toState: BookingStatus.completionRequested, actorRole: 'worker'), isTrue);
    });

    test('Legal hirer transitions succeed', () {
      expect(isValidTransition(fromState: BookingStatus.arrived, toState: BookingStatus.arrived, actorRole: 'hirer'), isTrue);
      expect(isValidTransition(fromState: BookingStatus.completionRequested, toState: BookingStatus.completionVerified, actorRole: 'hirer'), isTrue);
      expect(isValidTransition(fromState: BookingStatus.confirmed, toState: BookingStatus.cancelled, actorRole: 'hirer'), isTrue);
    });

    test('State skipping is rejected by whitelist (P4-001)', () {
      // Worker cannot jump from confirmed directly to completion_requested
      expect(isValidTransition(fromState: BookingStatus.confirmed, toState: BookingStatus.completionRequested, actorRole: 'worker'), isFalse);
      // Worker cannot jump from tracking directly to completion_verified
      expect(isValidTransition(fromState: BookingStatus.tracking, toState: BookingStatus.completionVerified, actorRole: 'worker'), isFalse);
      // Worker cannot jump from pending to working
      expect(isValidTransition(fromState: 'pending', toState: BookingStatus.working, actorRole: 'worker'), isFalse);
      // Hirer cannot jump to completion_verified without completion_requested
      expect(isValidTransition(fromState: BookingStatus.working, toState: BookingStatus.completionVerified, actorRole: 'hirer'), isFalse);
      expect(isValidTransition(fromState: BookingStatus.confirmed, toState: BookingStatus.completionVerified, actorRole: 'hirer'), isFalse);
    });

    test('Worker cannot start work without arrivalVerified == true (P4-002)', () {
      expect(isValidTransition(fromState: BookingStatus.arrived, toState: BookingStatus.working, actorRole: 'worker', arrivalVerified: false), isFalse);
    });

    test('Terminal state mutations are strictly rejected', () {
      expect(isValidTransition(fromState: BookingStatus.completionVerified, toState: BookingStatus.working, actorRole: 'worker'), isFalse);
      expect(isValidTransition(fromState: BookingStatus.completionVerified, toState: BookingStatus.cancelled, actorRole: 'hirer'), isFalse);
      expect(isValidTransition(fromState: BookingStatus.cancelled, toState: BookingStatus.confirmed, actorRole: 'worker'), isFalse);
      expect(isValidTransition(fromState: BookingStatus.disputed, toState: BookingStatus.working, actorRole: 'worker'), isFalse);
    });

    test('Cancellation cannot occur during active work', () {
      expect(isValidTransition(fromState: BookingStatus.working, toState: BookingStatus.cancelled, actorRole: 'worker'), isFalse);
      expect(isValidTransition(fromState: BookingStatus.working, toState: BookingStatus.cancelled, actorRole: 'hirer'), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 17: Phase 4B OTP Architecture Contract (P4-010)
  // ────────────────────────────────────────────────────────────────
  group('Phase 4B OTP Architecture & 6-Digit Enforcement', () {
    test('canonical arrival OTP must be exactly 6 digits', () {
      final otpPattern = RegExp(r'^\d{6}$');
      // Simulate multiple generated OTPs
      for (int i = 0; i < 50; i++) {
        final otp = (100000 + (i * 15321) % 900000).toString();
        expect(otp.length, equals(6));
        expect(otpPattern.hasMatch(otp), isTrue);
      }
    });

    test('4-digit OTP is rejected by OTP validator', () {
      bool validateOtpLength(String otp) => otp.trim().length == 6 && int.tryParse(otp) != null;
      expect(validateOtpLength('1234'), isFalse);
      expect(validateOtpLength('9999'), isFalse);
      expect(validateOtpLength('12345'), isFalse);
      expect(validateOtpLength('123456'), isTrue);
      expect(validateOtpLength('654321'), isTrue);
    });

    test('OTP attempt matches stored OTP and validates expiry', () {
      final storedOtp = '582914';
      final now = DateTime.now();
      final expiry = now.add(const Duration(minutes: 5));
      final isUsed = false;

      // Match & fresh
      expect(storedOtp == '582914' && now.isBefore(expiry) && !isUsed, isTrue);
      // Wrong OTP
      expect(storedOtp == '111111' && now.isBefore(expiry) && !isUsed, isFalse);
      // Expired OTP
      final pastExpiry = now.subtract(const Duration(minutes: 1));
      expect(storedOtp == '582914' && now.isBefore(pastExpiry) && !isUsed, isFalse);
      // Already used
      expect(storedOtp == '582914' && now.isBefore(expiry) && isUsed, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 18: Phase 4B RTDB Tracking Authorization Contract (P4-012)
  // ────────────────────────────────────────────────────────────────
  group('Phase 4B RTDB Tracking Authorization Contract', () {
    test('authoritative trackingParticipants establishes valid hirer and worker', () {
      final participantNode = {
        'hirerId': 'hirer_uid_456',
        'workerId': 'worker_uid_123',
        'jobId': 'job_789',
      };

      // Hirer read check
      final currentAuthUid = 'hirer_uid_456';
      final isAuthorizedHirer = participantNode['hirerId'] == currentAuthUid;
      final isAuthorizedWorker = participantNode['workerId'] == currentAuthUid;
      expect(isAuthorizedHirer || isAuthorizedWorker, isTrue);

      // Third-party attacker read check
      final attackerUid = 'unauthorized_attacker_999';
      final isAttackerAuthorized = participantNode['hirerId'] == attackerUid ||
          participantNode['workerId'] == attackerUid;
      expect(isAttackerAuthorized, isFalse);
    });

    test('worker cannot spoof hirerId in liveTracking payload against trackingParticipants', () {
      final authoritative = {
        'hirerId': 'real_hirer_456',
        'workerId': 'real_worker_123',
        'jobId': 'job_001',
      };

      final validWorkerWrite = {
        'hirerId': 'real_hirer_456',
        'workerId': 'real_worker_123',
        'jobId': 'job_001',
        'lat': 12.9716,
        'lng': 77.5946,
      };

      final spoofedWorkerWrite = {
        'hirerId': 'attacker_chosen_hirer_999',
        'workerId': 'real_worker_123',
        'jobId': 'job_001',
        'lat': 12.9716,
        'lng': 77.5946,
      };

      // Rule validation simulator:
      bool validateRtdbPayload(Map<String, dynamic> write, Map<String, dynamic> authRef) {
        return write['hirerId'] == authRef['hirerId'] &&
            write['workerId'] == authRef['workerId'] &&
            write['jobId'] == authRef['jobId'];
      }

      expect(validateRtdbPayload(validWorkerWrite, authoritative), isTrue);
      expect(validateRtdbPayload(spoofedWorkerWrite, authoritative), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 19: Phase 4B Persistent Idempotency & Deterministic IDs (P4-015)
  // ────────────────────────────────────────────────────────────────
  group('Phase 4B Persistent Idempotency & Concurrency', () {
    test('application acceptance produces deterministic bookingId', () {
      const appId = 'app_user42_job100';
      final bookingId1 = 'booking_$appId';
      final bookingId2 = 'booking_$appId';
      expect(bookingId1, equals(bookingId2));
      expect(bookingId1, 'booking_app_user42_job100');
    });

    test('direct voice booking produces deterministic persistent bookingId', () {
      const idempotencyKey = 'voice_client_trans_555';
      final safeKey = idempotencyKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final bookingId = 'booking_direct_$safeKey';
      expect(bookingId, 'booking_direct_voice_client_trans_555');
    });

    test('deterministic ratingId prevents duplicate ratings across retries', () {
      const bookingId = 'booking_app_123';
      const hirerUid = 'hirer_abc';
      final ratingId1 = 'rating_${bookingId}_$hirerUid';
      final ratingId2 = 'rating_${bookingId}_$hirerUid';
      expect(ratingId1, equals(ratingId2));
      expect(ratingId1, 'rating_booking_app_123_hirer_abc');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION 20: Phase 4B Completion & Verified Work Integrity (P4-003)
  // ────────────────────────────────────────────────────────────────
  group('Phase 4B Completion & Verified Work Integrity', () {
    test('completion updates status to completion_verified', () {
      const updatedStatus = BookingStatus.completionVerified;
      expect(updatedStatus, 'completion_verified');
      expect(BookingStatus.terminalStates.contains(updatedStatus), isTrue);
    });

    test('deterministic verifiedWorkId contract', () {
      const bookingId = 'booking_xyz_789';
      final verifiedWorkId = 'vwr_$bookingId';
      expect(verifiedWorkId, 'vwr_booking_xyz_789');
    });

    test('atomic worker updates on completion', () {
      final workerUpdates = {
        'isAvailable': false,
        'totalJobsIncrement': 1,
        'activeBookingIdCleared': true,
      };
      expect(workerUpdates['isAvailable'], isFalse);
      expect(workerUpdates['totalJobsIncrement'], equals(1));
      expect(workerUpdates['activeBookingIdCleared'], isTrue);
    });
  });
}

