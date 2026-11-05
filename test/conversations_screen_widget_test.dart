// test/conversations_screen_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelasagaara/models/user_profile.dart';
import 'package:kelasagaara/providers/auth_provider.dart';
import 'package:kelasagaara/screens/chat/conversations_screen.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _auth;
  final String? _userUid;

  MockAuthProvider({bool authenticated = true, String? uid = 'user_hirer_101'})
      : _auth = authenticated,
        _userUid = uid;

  @override
  String? get uid => _userUid;

  @override
  String get name => 'Hirer User';

  @override
  UserProfile? get currentUser => _auth
      ? UserProfile(
          uid: _userUid ?? 'user_hirer_101',
          displayName: 'Hirer User',
          role: 'hirer',
          accountStatus: AccountStatus.approved,
        )
      : null;

  @override
  bool get isAuthenticated => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ConversationsScreen renders sign-in notice when unauthenticated', (tester) async {
    final mockAuth = MockAuthProvider(authenticated: false, uid: null);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ConversationsScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Please sign in to view your messages.'), findsOneWidget);
  });

  testWidgets('ConversationsScreen renders AppBar and Kannada subtitle when authenticated', (tester) async {
    final mockAuth = MockAuthProvider(authenticated: true, uid: 'hirer_test_uid');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const ConversationsScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify AppBar header
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('ಸಂದೇಶಗಳು'), findsOneWidget);
  });
}
