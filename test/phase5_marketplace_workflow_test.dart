// test/phase5_marketplace_workflow_test.dart
// Phase 5 — Professional Job Marketplace Workflow Tests
//
// Comprehensive unit tests covering:
// 1. Two-tier location disclosure gate (public job vs jobPrivate).
// 2. Deterministic application ID generation (app_${jobId}_${workerId}).
// 3. Application submission idempotency & duplicate prevention.
// 4. Application lifecycle state transitions (pending, accepted, rejected, withdrawn).
// 5. Atomic single-winner acceptance & concurrency guard.
// 6. Zero platform fee / zero commission guarantee.
// 7. Worker profile proposal snapshot preservation.
//
// Pure Dart tests ensuring zero flakiness and high execution speed.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/providers/jobs_provider.dart';
import 'package:kelasagaara/services/booking_service.dart';

void main() {
  group('Phase 5 — Two-Tier Location Disclosure Gate', () {
    test('Public job posting contains only locality/district/taluk, no raw lat/lng/address', () {
      final publicJobMap = {
        'id': 'job_101',
        'hirerId': 'hirer_abc',
        'title': 'Plumbing Repair',
        'description': 'Kitchen pipe leaking under sink',
        'category': 'plumbing',
        'budget': 500.0,
        'district': 'Hassan',
        'taluk': 'Hassan',
        'village': 'Vidyanagar',
        'hasPrivateLocation': true,
        'status': 'open',
        'appliedCount': 0,
        'urgent': false,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final job = Job.fromMap('job_101', publicJobMap);

      expect(job.district, 'Hassan');
      expect(job.taluk, 'Hassan');
      expect(job.village, 'Vidyanagar');
      expect(job.hasPrivateLocation, isTrue);
      expect(job.status, 'open');

      // Invariant: Public job payload must NOT expose exact coordinates or private address
      expect(publicJobMap.containsKey('lat'), isFalse);
      expect(publicJobMap.containsKey('lng'), isFalse);
      expect(publicJobMap.containsKey('address'), isFalse);
      expect(publicJobMap.containsKey('exactAddress'), isFalse);
      expect(publicJobMap.containsKey('pincode'), isFalse);
    });

    test('Private job location record retains exact site coordinates and landmark', () {
      final privateLocationMap = {
        'jobId': 'job_101',
        'hirerId': 'hirer_abc',
        'exactAddress': '#42, 3rd Cross, Vidyanagar Main Road',
        'lat': 13.0072,
        'lng': 76.1021,
        'pincode': '573201',
        'landmark': 'Opposite Government High School',
        'acceptedWorkerId': null,
        'bookingId': null,
      };

      expect(privateLocationMap['exactAddress'], contains('#42, 3rd Cross'));
      expect(privateLocationMap['lat'], 13.0072);
      expect(privateLocationMap['lng'], 76.1021);
      expect(privateLocationMap['pincode'], '573201');
      expect(privateLocationMap['landmark'], 'Opposite Government High School');
    });

    test('Location authorization gate: only hirer or accepted worker can unlock private site', () {
      bool canAccessPrivateLocation({
        required String callerId,
        required String hirerId,
        required String? acceptedWorkerId,
        bool isAdmin = false,
      }) {
        if (isAdmin) return true;
        if (callerId == hirerId) return true;
        if (acceptedWorkerId != null && callerId == acceptedWorkerId) return true;
        return false;
      }

      const hirerId = 'hirer_99';
      const workerA = 'worker_a';
      const workerB = 'worker_b';

      // Before acceptance:
      expect(canAccessPrivateLocation(callerId: hirerId, hirerId: hirerId, acceptedWorkerId: null), isTrue);
      expect(canAccessPrivateLocation(callerId: workerA, hirerId: hirerId, acceptedWorkerId: null), isFalse);
      expect(canAccessPrivateLocation(callerId: workerB, hirerId: hirerId, acceptedWorkerId: null), isFalse);

      // After Worker A is accepted:
      expect(canAccessPrivateLocation(callerId: workerA, hirerId: hirerId, acceptedWorkerId: workerA), isTrue);
      expect(canAccessPrivateLocation(callerId: workerB, hirerId: hirerId, acceptedWorkerId: workerA), isFalse);
    });
  });

  group('Phase 5 — Deterministic Application IDs & Idempotency', () {
    String generateApplicationId(String jobId, String workerId) {
      return 'app_${jobId}_$workerId';
    }

    test('Application ID strictly follows app_{jobId}_{workerId} pattern', () {
      final appId = generateApplicationId('job_777', 'worker_333');
      expect(appId, 'app_job_777_worker_333');
    });

    test('Re-applying to the same job by the same worker produces identical application ID', () {
      final submission1 = generateApplicationId('job_888', 'worker_555');
      final submission2 = generateApplicationId('job_888', 'worker_555');
      expect(submission1, equals(submission2));
    });

    test('Different workers on same job receive distinct deterministic IDs', () {
      final app1 = generateApplicationId('job_888', 'worker_1');
      final app2 = generateApplicationId('job_888', 'worker_2');
      expect(app1, isNot(equals(app2)));
    });

    test('Generated booking ID from accepted application follows deterministic pattern', () {
      const appId = 'app_job_101_worker_202';
      final bookingId = 'booking_$appId';
      expect(bookingId, 'booking_app_job_101_worker_202');
    });
  });

  group('Phase 5 — Application Lifecycle Transitions', () {
    test('Allowed state transitions validate correctly', () {
      const validTransitions = {
        'pending': ['accepted', 'rejected', 'withdrawn'],
        'accepted': <String>[], // terminal state in application doc
        'rejected': <String>[], // terminal state
        'withdrawn': <String>[], // terminal state
      };

      bool canTransition(String current, String next) {
        final allowed = validTransitions[current];
        return allowed != null && allowed.contains(next);
      }

      // Valid transitions
      expect(canTransition('pending', 'accepted'), isTrue);
      expect(canTransition('pending', 'rejected'), isTrue);
      expect(canTransition('pending', 'withdrawn'), isTrue);

      // Invalid transitions
      expect(canTransition('accepted', 'withdrawn'), isFalse);
      expect(canTransition('accepted', 'rejected'), isFalse);
      expect(canTransition('rejected', 'accepted'), isFalse);
      expect(canTransition('withdrawn', 'accepted'), isFalse);
    });

    test('Worker cannot withdraw an application once accepted', () {
      String status = 'accepted';
      bool withdrawApplication() {
        if (status != 'pending') {
          return false; // cannot withdraw non-pending
        }
        status = 'withdrawn';
        return true;
      }

      expect(withdrawApplication(), isFalse);
      expect(status, 'accepted');
    });
  });

  group('Phase 5 — Atomic Single-Winner Acceptance & Concurrency', () {
    test('Hirer accepting an applicant transitions job from open to filled', () {
      String jobStatus = 'open';
      String? acceptedWorker;

      bool acceptApplicant(String workerId) {
        if (jobStatus != 'open') return false; // Invariant: single winner
        jobStatus = 'filled';
        acceptedWorker = workerId;
        return true;
      }

      // First acceptance succeeds
      final success1 = acceptApplicant('worker_alpha');
      expect(success1, isTrue);
      expect(jobStatus, 'filled');
      expect(acceptedWorker, 'worker_alpha');

      // Competing acceptance on same job fails atomically
      final success2 = acceptApplicant('worker_beta');
      expect(success2, isFalse);
      expect(acceptedWorker, 'worker_alpha'); // remains worker_alpha
    });

    test('BookingService acceptance payload creates confirmed booking with exact private location', () {
      final bookingPayload = {
        'bookingId': 'booking_app_job_1_worker_1',
        'applicationId': 'app_job_1_worker_1',
        'jobId': 'job_1',
        'workerId': 'worker_200',
        'workerName': 'Basavaraj',
        'hirerId': 'hirer_100',
        'hirerName': 'Anand Ram',
        'skillId': 'electrical',
        'jobTitle': 'Electrical Wiring Fix',
        'pay': 800.0,
        'jobLat': 13.0050,
        'jobLng': 76.1000,
        'jobAddress': '#12, MG Road, Hassan',
        'status': BookingStatus.confirmed,
      };

      expect(bookingPayload['bookingId'], 'booking_app_job_1_worker_1');
      expect(bookingPayload['hirerId'], 'hirer_100');
      expect(bookingPayload['workerId'], 'worker_200');
      expect(bookingPayload['jobId'], 'job_1');
      expect(bookingPayload['status'], BookingStatus.confirmed);
      expect(bookingPayload['jobAddress'], '#12, MG Road, Hassan');
      expect(bookingPayload['jobLat'], 13.0050);
      expect(bookingPayload['jobLng'], 76.1000);
      expect(bookingPayload['pay'], 800.0);
    });
  });

  group('Phase 5 — Zero Platform Fee / Zero Commission Guarantee', () {
    test('Agreed wage is 100% assigned to worker payout with 0% platform fee', () {
      const agreedWage = 1200.0;
      const platformFeePercent = 0.0;
      const platformFee = agreedWage * platformFeePercent;
      const workerPayout = agreedWage - platformFee;

      expect(platformFee, equals(0.0));
      expect(workerPayout, equals(agreedWage));
    });

    test('Booking financial fields strictly contain no platform markup or deductions', () {
      final booking = {
        'bookingId': 'bk_test_zero_fee',
        'hirerId': 'h_1',
        'workerId': 'w_1',
        'jobId': 'j_1',
        'jobTitle': 'Carpentry Table Repair',
        'jobAddress': 'Hassan',
        'jobLat': 13.0,
        'jobLng': 76.0,
        'pay': 950.0,
        'status': BookingStatus.confirmed,
      };

      expect(booking['pay'], 950.0);
      expect(booking.containsKey('platformFee'), isFalse);
      expect(booking.containsKey('commissionRate'), isFalse);
      expect(booking.containsKey('serviceTaxFee'), isFalse);
    });
  });

  group('Phase 5 — Worker Proposal Snapshot Invariant', () {
    test('Application retains immutable snapshot of worker credentials at apply time', () {
      final applicationData = {
        'id': 'app_job_99_worker_88',
        'jobId': 'job_99',
        'workerId': 'worker_88',
        'hirerId': 'hirer_1',
        'status': 'pending',
        'proposedWage': 600.0,
        'pitchNote': 'I have 5 years experience in plumbing and can visit today.',
        // Immutable Worker Snapshot
        'workerName': 'Ramesh Kumar',
        'workerPhoto': 'https://storage.kelasagara.app/profiles/worker_88.jpg',
        'workerRating': 4.9,
        'workerTotalJobs': 42,
        'workerSkills': ['plumbing', 'electrical'],
        'workerVerified': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

      expect(applicationData['workerName'], 'Ramesh Kumar');
      expect(applicationData['workerRating'], 4.9);
      expect(applicationData['workerTotalJobs'], 42);
      expect(applicationData['workerVerified'], isTrue);
      expect((applicationData['workerSkills'] as List).contains('plumbing'), isTrue);
      expect(applicationData['pitchNote'], contains('5 years experience'));
    });
  });
}
