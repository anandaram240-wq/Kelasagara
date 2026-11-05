import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelasagaara/models/user_profile.dart';
import 'package:kelasagaara/providers/auth_provider.dart';
import 'package:kelasagaara/screens/chat/chat_screen.dart';
import 'package:kelasagaara/services/messaging/messaging_outbox_service.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  String? get uid => 'hirer_uid_123';

  @override
  String get name => 'Ramesh Hirer';

  @override
  UserProfile? get currentUser => const UserProfile(
        uid: 'hirer_uid_123',
        displayName: 'Ramesh Hirer',
        role: 'hirer',
        accountStatus: AccountStatus.approved,
      );

  @override
  bool get isAuthenticated => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    MessagingOutboxService.instance.cancelPendingRetries();
  });

  testWidgets('ChatScreen renders AppBar, job context, composer, and quick replies', (tester) async {
    final mockAuth = MockAuthProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ChatScreen(
            workerName: 'Manjunath Plumber',
            jobTitle: 'Plumbing Repair',
            otherUserId: 'worker_uid_456',
            jobId: 'job_plumbing_789',
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();

    // Verify AppBar contains worker name
    expect(find.text('Manjunath Plumber'), findsOneWidget);

    // Verify job context header
    expect(find.textContaining('Re: Plumbing Repair'), findsOneWidget);

    // Verify quick replies
    expect(find.text('30 ನಿಮಿಷದಲ್ಲಿ ಬರುತ್ತೇನೆ'), findsOneWidget);

    // Verify diagnostics icon button
    expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
  });

  testWidgets('ChatScreen Send button is alive, clears composer, and handles optimistic tap', (tester) async {
    final mockAuth = MockAuthProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ChatScreen(
            workerName: 'Raja',
            jobTitle: 'Electrician',
            otherUserId: 'worker_uid_raja',
            jobId: 'job_raja_001',
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify input text field is found
    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);

    // Type "HI"
    await tester.enterText(inputFinder, 'HI');
    expect(find.text('HI'), findsOneWidget);

    // Find the send button icon (Icons.send_rounded)
    final sendButtonFinder = find.byIcon(Icons.send_rounded);
    expect(sendButtonFinder, findsOneWidget);

    // Tap Send button
    await tester.tap(sendButtonFinder);
    await tester.pump();

    // Verify composer is cleared immediately
    final textField = tester.widget<TextField>(inputFinder);
    expect(textField.controller?.text, isEmpty);

    // Cancel outbox retry timers before exiting test to satisfy timersPending invariant
    MessagingOutboxService.instance.cancelPendingRetries();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ChatScreen finite bootstrap timer transitions away from Connecting...', (tester) async {
    final mockAuth = MockAuthProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ChatScreen(
            workerName: 'Raja',
            jobTitle: 'Electrician',
            otherUserId: 'worker_uid_raja',
            jobId: 'job_raja_002',
          ),
        ),
      ),
    );

    await tester.pump();

    // Advance virtual clock past 3 seconds
    await tester.pump(const Duration(seconds: 4));

    // After 3 seconds bootstrap, presence subtitle must NOT be permanently stuck on 'Connecting...'
    // It should display 'Offline' when no active RTDB connection is established in test environment.
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Connecting...'), findsNothing);
  });

  testWidgets('ChatScreen shows honest Direct Marketplace Chat empty state and location button', (tester) async {
    final mockAuth = MockAuthProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ChatScreen(
            workerName: 'Shankar',
            jobTitle: 'Carpentry',
            otherUserId: 'worker_uid_shankar',
            jobId: 'job_carpentry_01',
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify honest marketplace chat banner (no false E2EE lock)
    expect(find.text('Direct Marketplace Chat'), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.textContaining('Messages are securely delivered in real-time'), findsOneWidget);

    // Verify location share button in composer
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);

    // Verify quick reply chip is present
    expect(find.text('30 ನಿಮಿಷದಲ್ಲಿ ಬರುತ್ತೇನೆ'), findsOneWidget);

    // Advance clock to clean up bootstrap timer
    await tester.pump(const Duration(seconds: 4));
  });
}
