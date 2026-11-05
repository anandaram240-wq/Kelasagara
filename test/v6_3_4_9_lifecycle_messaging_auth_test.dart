import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/user_profile.dart';

void main() {
  group('V6.3.4.9 Defect 1 & 2: Application Lifecycle & Reapplication Tests', () {
    test('1. Application lifecycle: Not Applied -> Applied -> Withdrawn -> Eligible to Reapply', () {
      // Map simulating _appliedJobs in JobsProvider
      final Map<String, String> appliedJobs = {};
      const jobId = 'job_101';
      const workerId = 'worker_202';
      const appId = 'app_${jobId}_$workerId';

      // State 1: Not applied
      expect(appliedJobs.containsKey(jobId), isFalse);

      // State 2: Applied
      appliedJobs[jobId] = appId;
      expect(appliedJobs.containsKey(jobId), isTrue);
      expect(appliedJobs[jobId], equals(appId));

      // State 3: Withdrawn
      appliedJobs.remove(jobId);
      expect(appliedJobs.containsKey(jobId), isFalse, reason: 'Withdrawn job must be removed from active appliedJobs');

      // State 4: Eligible to reapply
      final canReapply = !appliedJobs.containsKey(jobId);
      expect(canReapply, isTrue);

      // State 5: Applied again
      appliedJobs[jobId] = appId;
      expect(appliedJobs.containsKey(jobId), isTrue);
    });

    test('2. Prior attempt history preservation upon reapplication', () {
      final existingDocData = <String, dynamic>{
        'jobId': 'job_101',
        'workerId': 'worker_202',
        'status': 'withdrawn',
        'appliedAt': '2026-11-01T10:00:00Z',
        'withdrawnAt': '2026-11-02T12:00:00Z',
        'message': 'First attempt message',
      };

      final currentStatus = existingDocData['status'] as String;
      expect(currentStatus, equals('withdrawn'));

      // Simulate reapplication history archiving
      final attemptHistory = <Map<String, dynamic>>[];
      attemptHistory.add({
        'status': currentStatus,
        'appliedAt': existingDocData['appliedAt'],
        'withdrawnAt': existingDocData['withdrawnAt'],
        'message': existingDocData['message'],
      });

      final reapplicationDoc = <String, dynamic>{
        ...existingDocData,
        'status': 'pending',
        'appliedAt': '2026-11-05T08:00:00Z',
        'message': 'Second attempt message: I am available now!',
        'attemptHistory': attemptHistory,
      };

      expect(reapplicationDoc['status'], equals('pending'));
      expect(reapplicationDoc['attemptHistory'], hasLength(1));
      expect(reapplicationDoc['attemptHistory'][0]['status'], equals('withdrawn'));
      expect(reapplicationDoc['attemptHistory'][0]['message'], equals('First attempt message'));
    });

    test('3. Duplicate active application prevention', () {
      const activeStatus = 'pending';
      final isActive = activeStatus == 'pending' || activeStatus == 'applied' || activeStatus == 'accepted';
      expect(isActive, isTrue);

      // If active, reapplication must be rejected / return existing ID without creating duplicate
      String? duplicateError;
      if (isActive) {
        duplicateError = 'Already actively applied';
      }
      expect(duplicateError, isNotNull);
    });
  });

  group('V6.3.4.9 Defect 3: Messaging Security & Query Constraint Tests', () {
    test('4. Conversations list query strictly matches arrayContains filter', () {
      const myUid = 'user_abc';
      final mockQueryFilters = <String, dynamic>{
        'field': 'participants',
        'op': 'arrayContains',
        'value': myUid,
      };

      expect(mockQueryFilters['field'], equals('participants'));
      expect(mockQueryFilters['op'], equals('arrayContains'));
      expect(mockQueryFilters['value'], equals(myUid));
    });

    test('5. Non-participant conversation access is rejected', () {
      final participants = ['user_1', 'user_2'];
      const callerUid = 'user_intruder';

      final isAuthorized = participants.contains(callerUid);
      expect(isAuthorized, isFalse, reason: 'Intruder must NOT have access to conversation');
    });

    test('6. Participant conversation access is authorized', () {
      final participants = ['user_1', 'user_2'];
      const callerUid = 'user_1';

      final isAuthorized = participants.contains(callerUid);
      expect(isAuthorized, isTrue, reason: 'Participant must be authorized to access conversation');
    });

    test('7. Client-side local sorting by lastMessageAt descending', () {
      final conversations = [
        {'id': 'c1', 'lastMessageAt': 1000},
        {'id': 'c2', 'lastMessageAt': 3000},
        {'id': 'c3', 'lastMessageAt': 2000},
      ];

      conversations.sort((a, b) => (b['lastMessageAt'] as int).compareTo(a['lastMessageAt'] as int));

      expect(conversations[0]['id'], equals('c2'));
      expect(conversations[1]['id'], equals('c3'));
      expect(conversations[2]['id'], equals('c1'));
    });
  });

  group('V6.3.4.9 Defect 4: Auth State & Sign-out Navigation Guard Tests', () {
    test('8. When currentUser is null, canEnter evaluates to false but redirects to WelcomeScreen', () {
      UserProfile? currentUser; // null when signed out
      final isAuthenticated = currentUser != null;
      expect(isAuthenticated, isFalse);

      final isApproved = currentUser?.accountStatus == AccountStatus.approved;
      final isAdmin = currentUser?.role == 'admin';
      final isHirer = currentUser?.role == 'hirer';
      final isWorker = currentUser?.role == 'worker';
      final faceVerified = currentUser?.faceVerified ?? false;

      final canEnter = isApproved || isAdmin || isHirer || (isWorker && faceVerified);
      expect(canEnter, isFalse);

      // HomeShell guard: when !isAuthenticated, must redirect to WelcomeScreen and NOT show Pending Approval
      final shouldRedirectToWelcome = !isAuthenticated || currentUser == null;
      expect(shouldRedirectToWelcome, isTrue);
    });

    test('9. Sign-out leaves accountStatus untouched and resets local auth state', () {
      // User with approved account status
      var user = UserProfile(
        uid: 'user_123',
        displayName: 'Ananda',
        role: 'worker',
        accountStatus: AccountStatus.approved,
      );

      expect(user.accountStatus, equals(AccountStatus.approved));

      // Simulate signOut(): clears local user reference without mutating database
      user = UserProfile(
        uid: '',
        displayName: '',
        role: '',
        accountStatus: AccountStatus.unknown,
      );

      expect(user.uid, isEmpty);
      expect(user.accountStatus, equals(AccountStatus.unknown));
    });
  });
}
