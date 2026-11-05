import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/journey_service.dart';
import '../services/navigation_engine.dart';
import '../services/user_id_service.dart';
import '../services/worker_availability_service.dart';
import '../services/messaging/messaging_facade.dart';
import '../services/messaging/presence_service.dart';
import '../services/messaging/messaging_connectivity_service.dart';

// Backward compatibility alias: UserModel points to UserProfile
typedef UserModel = UserProfile;

// ── Auth Status ──────────────────────────────────────────────────────────────
enum AuthStatus { initial, loading, authenticated, unauthenticated, recoverableError }

// ── AuthProvider ─────────────────────────────────────────────────────────────
class AuthProvider extends ChangeNotifier {
  AuthStatus  _status      = AuthStatus.initial;
  UserProfile? _currentUser;
  String?     _error;
  Future<void>? _inFlightLoad;

  final _auth         = FirebaseAuth.instance;
  final _db           = FirebaseFirestore.instance;
  final _googleSignIn = GoogleSignIn(
    serverClientId: '993968093461-u58j0969najb0klgtlevv0qhn0v0hqov.apps.googleusercontent.com',
    // Web requires clientId (different field from serverClientId)
    clientId: kIsWeb ? '993968093461-u58j0969najb0klgtlevv0qhn0v0hqov.apps.googleusercontent.com' : null,
  );

  late final UserIdService _userIdService;

  AuthProvider() {
    _userIdService = UserIdService(db: _db);
  }

  // ── Getters ────────────────────────────────────────────────────────────────
  AuthStatus   get status          => _status;
  UserProfile? get currentUser     => _currentUser;
  bool         get isAuthenticated => _status == AuthStatus.authenticated;
  bool         get hasRecoverableError => _status == AuthStatus.recoverableError;
  bool         get isWorker        => _currentUser?.role == 'worker';
  bool         get isHirer         => _currentUser?.role == 'hirer';
  bool         get isAdmin         => _currentUser?.role == 'admin';
  bool         get faceVerified    => _currentUser?.faceVerified ?? false;
  bool         get hasFaceTemplate => faceVerified;
  bool         get skillVerified   => _currentUser?.skillVerified ?? false;
  bool         get isApproved      => _currentUser?.accountStatus == AccountStatus.approved;
  bool         get isPendingProfile {
    final u = _currentUser;
    if (u == null) return false;
    // An existing user with skills, district, or approved/reviewed status is NEVER pending profile
    if (u.skills.isNotEmpty ||
        u.district.isNotEmpty ||
        u.onboardingComplete ||
        u.isApproved ||
        u.accountStatus == AccountStatus.approved ||
        u.accountStatus == AccountStatus.pendingReview ||
        u.accountStatus == AccountStatus.pendingFace) {
      return false;
    }
    return u.accountStatus == AccountStatus.pendingProfile;
  }
  bool         get isPendingFace   => _currentUser?.accountStatus == AccountStatus.pendingFace;
  bool         get isPendingReview => _currentUser?.accountStatus == AccountStatus.pendingReview;
  bool         get isRejected      => _currentUser?.accountStatus == AccountStatus.rejected;
  bool         get isSuspended     =>
      _currentUser?.accountStatus == AccountStatus.suspended ||
      _currentUser?.accountStatus == AccountStatus.blocked;
  AccountStatus get accountStatus  => _currentUser?.accountStatus ?? AccountStatus.unknown;
  String       get name            => _currentUser?.displayName ?? _currentUser?.name ?? 'User';
  String?      get uid             => _auth.currentUser?.uid;
  String?      get error           => _error;

  // ── Init — listen to Firebase auth state ──────────────────────────────────
  Future<void> init() async {
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _loadUserFromFirestore(user.uid);
      } else {
        _status = AuthStatus.unauthenticated;
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _loadUserFromFirestore(String uid) async {
    if (_inFlightLoad != null) {
      await _inFlightLoad;
      return;
    }
    final completer = Completer<void>();
    _inFlightLoad = completer.future;

    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        _status = AuthStatus.unauthenticated;
        _currentUser = null;
        _error = 'No active authentication session.';
        notifyListeners();
        return;
      }

      const adminEmails = ['anandaananda16919@gmail.com'];
      final email = (firebaseUser.email ?? '').toLowerCase();
      final isAdminEmail = adminEmails.contains(email);

      try {
        final doc = await _db.collection('users').doc(uid).get();

        if (doc.exists) {
          final data = doc.data()!;

          // Admin promotion is done via Firebase Console / Admin SDK only.
          // The client never self-promotes — it just reads what Firestore says.
          _currentUser = UserProfile.fromMap(uid, data);
          if (isAdminEmail && data['role'] != 'admin') {
            // Log the discrepancy — admin must be promoted via Firebase Console
            debugPrint('[Auth] SECURITY: Admin email detected but role is not admin. '
                'Set role=admin in Firebase Console for uid=$uid');
          }

          // Automatic migration check for legacy accounts missing username
          if (_currentUser != null && _currentUser!.userId.isNotEmpty) {
            unawaited(_userIdService.migrateExistingUserIfNeeded(
              uid: uid,
              currentUserId: _currentUser!.userId,
              displayName: _currentUser!.displayName,
              email: _currentUser!.email,
            ));
          }

          // Sync legacy status if needed
          if (data['accountStatus'] == null && _currentUser!.accountStatus == AccountStatus.approved) {
            unawaited(_db.collection('users').doc(uid).set({
              'accountStatus': AccountStatus.approved.value,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)));
          }
        } else {
          // First-time user via third party (Google/Phone)
          final bare = {
            'displayName':   firebaseUser.displayName ?? (isAdminEmail ? 'Admin' : ''),
            'name':          firebaseUser.displayName ?? (isAdminEmail ? 'Admin' : ''),
            'email':         email,
            'phone':         firebaseUser.phoneNumber ?? '',
            'role':          'worker',  // Admin role must be set via Firebase Console
            'userId':        '',
            'normalizedUserId': '',
            'accountStatus': AccountStatus.pendingProfile.value,
            'faceVerified':  false,
            'isAvailable':   false,
            'totalJobs':     0,
            'ratingSum':     0,
            'totalRatings':  0,
            'dailyRate':     700,
            'skills':        [],
            'approvedAt':    null,
            'approvedBy':    null,
            'createdAt':     FieldValue.serverTimestamp(),
            'updatedAt':     FieldValue.serverTimestamp(),
          };
          await _db.collection('users').doc(uid).set(bare);
          _currentUser = UserProfile.fromMap(uid, bare);
          if (isAdminEmail) debugPrint('[Auth] SECURITY: Admin email on new account — set role=admin in Firebase Console for uid=$uid');
        }

        // Initialize Messaging Subsystem (E2EE keys, outbox), RTDB presence, and connectivity
        unawaited(MessagingFacade.instance.initialize(uid));
        unawaited(PresenceService.instance.initialize(uid));
        MessagingConnectivityService.instance.initialize();

        _status = AuthStatus.authenticated;
        _error = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('uid', uid);
        notifyListeners();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'insufficient-permissions') {
          // Rules blocked access — set status to unauthenticated so user cannot enter app
          debugPrint('[Auth] Firestore PERMISSION DENIED for uid=$uid: ${e.message}');
          try {
            await _auth.signOut();
            await _googleSignIn.signOut();
          } catch (_) {}
          _currentUser = null;
          _status = AuthStatus.unauthenticated;
          _error = 'Account access denied. Please contact support.';
        } else {
          // Network/quota/timeout — preserve existing known state if we have one
          debugPrint('[Auth] Firestore network error for uid=$uid: ${e.code} ${e.message}');
          if (_currentUser != null && _currentUser!.accountStatus != AccountStatus.unknown) {
            // We have a cached state — keep authenticated with existing user
            _status = AuthStatus.authenticated;
          } else {
            // No known state — recoverable profile loading state: retain Firebase identity
            _currentUser = UserProfile(
              uid: uid,
              displayName: firebaseUser.displayName ?? 'User',
              email: firebaseUser.email ?? '',
              accountStatus: AccountStatus.unknown,
            );
            _status = AuthStatus.recoverableError;
            _error = 'Network error loading profile. Please check connection and retry.';
          }
        }
        notifyListeners();
      } catch (e) {
        debugPrint('[Auth] Unexpected error loading user doc uid=$uid: $e');
        if (_currentUser != null && _currentUser!.accountStatus != AccountStatus.unknown) {
          _status = AuthStatus.authenticated;
        } else {
          _currentUser = UserProfile(
            uid: uid,
            displayName: firebaseUser.displayName ?? 'User',
            email: firebaseUser.email ?? '',
            accountStatus: AccountStatus.unknown,
          );
          _status = AuthStatus.recoverableError;
          _error = 'Error loading profile. Please retry.';
        }
        notifyListeners();
      }
    } finally {
      _inFlightLoad = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  // ── Reload user doc ──────────────────────────────────────────────────────
  Future<void> reload() async {
    final u = _auth.currentUser;
    if (u != null) await _loadUserFromFirestore(u.uid);
  }

  // ── Retry profile loading on recoverable network error ───────────────────
  Future<bool> retryProfileLoad() async {
    final u = _auth.currentUser;
    if (u == null) {
      _status = AuthStatus.unauthenticated;
      _currentUser = null;
      _error = 'No active authentication session. Please sign in again.';
      notifyListeners();
      return false;
    }
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();
    await _loadUserFromFirestore(u.uid);
    return _status == AuthStatus.authenticated;
  }

  // ── User ID & Password Account Registration (Section 26 & 27) ────────────
  Future<bool> registerWithCredentials({
    required String rawUserId,
    required String password,
    required String displayName,
    required String role,
    String? email,
    String? phone,
    String district = '',
    String taluk = '',
    String village = '',
    List<String> skills = const [],
    int dailyRate = 700,
    int experienceYears = 0,
    String experienceLevel = '',
    int serviceRadiusKm = 15,
    String bio = '',
    String photoUrl = '',
  }) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      // 1. Validate User ID structure
      final valRes = UserIdService.validate(rawUserId);
      if (!valRes.isValid) {
        throw Exception(valRes.errorMessage ?? 'Invalid User ID format');
      }

      // 2. Validate Password strength
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters');
      }

      // 3. Pre-check availability
      final available = await _userIdService.checkUserIdAvailability(rawUserId);
      if (!available) {
        throw Exception('User ID "@$rawUserId" is already taken. Please choose another.');
      }

      // 4. Create authoritative Firebase Auth account
      // If no custom email provided, generate deterministic auth domain identifier
      final authEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim()
          : '${valRes.normalized!}@auth.kelasagaara.in';

      final userCred = await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final uid = userCred.user!.uid;

      // 5. Atomically claim User ID in Firestore transaction
      await _userIdService.claimUserIdAtomically(rawUserId: rawUserId, uid: uid);

      // 6. Initialize profile document
      final profileData = {
        'uid': uid,
        'userId': rawUserId.trim(),
        'normalizedUserId': valRes.normalized!,
        'displayName': displayName.trim(),
        'name': displayName.trim(),
        'email': (email != null && email.trim().isNotEmpty) ? email.trim() : '',
        'phone': phone?.trim() ?? '',
        'role': role == 'hirer' ? 'hirer' : 'worker',
        'district': district.trim(),
        'taluk': taluk.trim(),
        'village': village.trim(),
        'skills': skills,
        'dailyRate': dailyRate,
        'experienceYears': experienceYears,
        'experienceLevel': experienceLevel,
        'serviceRadiusKm': serviceRadiusKm,
        'bio': bio.trim(),
        'photoUrl': photoUrl.trim(),
        'facePhotoUrl': '',
        'isAvailable': false,
        // Both Workers and Hirers require face liveness verification.
        'accountStatus': AccountStatus.pendingFace.value,
        'onboardingComplete': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('users').doc(uid).set(profileData, SetOptions(merge: true));
      await _loadUserFromFirestore(uid);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Google Sign-In ───────────────────────────────────────────────────────
  Future<bool> signInWithGoogle() async {
    try {
      _status = AuthStatus.loading;
      _error  = null;
      notifyListeners();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _error  = 'Google Sign-In was cancelled or not authorized.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        _error  = 'Firebase authentication failed: No user returned.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }

      await _loadUserFromFirestore(user.uid);
      if (_status != AuthStatus.authenticated) {
        _error ??= 'Profile authentication failed. Please try again.';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Auth] Google Sign-In exception: $e');
      _error  = 'Google Sign-In failed: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Email + Password Sign-In ─────────────────────────────────────────────
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _error  = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = switch (e.code) {
        'user-not-found'  => 'No account found for this email.',
        'wrong-password'  => 'Incorrect password. Try again.',
        'invalid-email'   => 'Invalid email address.',
        'user-disabled'   => 'This account has been disabled.',
        _                 => 'Sign in failed: ${e.message}',
      };
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── User ID + Password Sign-In ────────────────────────────────────────────
  // Looks up email from Firestore by normalizedUserId, then signs in.
  Future<bool> signInWithUserIdAndPassword({
    required String rawUserId,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _error  = null;
    notifyListeners();
    try {
      final normalized = rawUserId.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      // Look up the user document by normalized userId
      final snap = await _db
          .collection('users')
          .where('normalizedUserId', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        _error = 'No account found for @$rawUserId. Check your User ID.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
      final data  = snap.docs.first.data();
      final email = (data['email'] as String?)?.trim() ?? '';
      // Fallback: use the deterministic auth domain email used during registration
      final authEmail = email.isNotEmpty ? email : '$normalized@auth.kelasagaara.in';
      return await signInWithEmailAndPassword(email: authEmail, password: password);
    } catch (e) {
      _error  = 'Sign in failed. Check your User ID and password.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Set Face Verified (ML Kit callback) ──────────────────────────────────
  // ── Set Face Verified (ML Kit liveness callback) ─────────────────────────
  // Uses the narrow Firestore rule that permits the specific
  // pending_face → pending_review transition when faceVerified=true.
  // IMPORTANT: Do NOT add other protected fields (role, approvedBy, rating…).
  // The rule only permits this exact transition payload.
  Future<void> setFaceVerified(bool verified, String photoUrl) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('Not authenticated');

    // Guard: only apply if currently at pending_face status
    final currentStatus = _currentUser?.accountStatus;
    if (currentStatus != AccountStatus.pendingFace && currentStatus != null) {
      // Already advanced — idempotent no-op
      debugPrint('[Auth] setFaceVerified: already at $currentStatus, skipping');
      return;
    }

    // Minimal write matching the narrow Firestore rule:
    // resource.data.accountStatus == 'pending_face'
    // && request.resource.data.accountStatus == 'pending_review'
    // && request.resource.data.faceVerified == true
    await _db.collection('users').doc(u.uid).update({
      'faceVerified':              verified,
      'faceVerifiedAt':            FieldValue.serverTimestamp(),
      'accountStatus':             AccountStatus.pendingReview.value,
      'verificationStatus':        'face_done',
      'faceLivenessCompleted':     verified,
      'faceVerificationTimestamp': FieldValue.serverTimestamp(),
      'faceVerificationMethod':    'mlkit_blink_liveness_v1',
      'faceVerificationVersion':   '1.0.0',
      'updatedAt':                 FieldValue.serverTimestamp(),
      // photoUrl / facePhotoUrl deferred until Storage upload is implemented
    });

    _currentUser = _currentUser?.copyWith(
      faceVerified:  verified,
      accountStatus: AccountStatus.pendingReview,
    );
    notifyListeners();
  }

  // ── Set Hirer Face Verified (ML Kit liveness callback) ───────────────────
  // Uses the narrow Firestore rule that permits the specific
  // pending_face → approved transition for hirers when faceVerified=true.
  Future<void> setHirerFaceVerified(bool verified) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('Not authenticated');

    final currentStatus = _currentUser?.accountStatus;
    if (currentStatus != AccountStatus.pendingFace && currentStatus != null) {
      debugPrint('[Auth] setHirerFaceVerified: already at $currentStatus, skipping');
      return;
    }

    await _db.collection('users').doc(u.uid).update({
      'faceVerified':              verified,
      'faceVerifiedAt':            FieldValue.serverTimestamp(),
      'accountStatus':             AccountStatus.approved.value,
      'verificationStatus':        'face_done',
      'faceLivenessCompleted':     verified,
      'faceVerificationTimestamp': FieldValue.serverTimestamp(),
      'faceVerificationMethod':    'mlkit_blink_liveness_v1',
      'faceVerificationVersion':   '1.0.0',
      'updatedAt':                 FieldValue.serverTimestamp(),
    });

    _currentUser = _currentUser?.copyWith(
      faceVerified:  verified,
      accountStatus: AccountStatus.approved,
    );
    notifyListeners();
  }

  /// Reloads the current user profile from Firestore and notifies listeners.
  /// Used after server-side Cloud Function operations that mutate user state.
  Future<void> refreshCurrentUser() async {
    final u = _auth.currentUser;
    if (u == null) return;
    try {
      final doc = await _db.collection('users').doc(u.uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUser = UserProfile.fromMap(u.uid, doc.data()!);
        notifyListeners();
        debugPrint('[Auth] refreshCurrentUser: successfully refreshed profile for ${u.uid}');
      }
    } catch (e) {
      debugPrint('[Auth] refreshCurrentUser error: $e');
    }
  }

  // ── User ID Availability & Claiming ──────────────────────────────────────
  Future<bool> checkUserIdAvailability(String rawUserId) async {
    return await _userIdService.checkUserIdAvailability(rawUserId);
  }

  Future<List<String>> getUserIdSuggestions(String rawUserId) async {
    return await _userIdService.generateAvailableSuggestions(rawUserId);
  }

  Future<void> claimUserId(String rawUserId) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('User not authenticated');
    await _userIdService.claimUserIdAtomically(rawUserId: rawUserId, uid: u.uid);
    _currentUser = _currentUser?.copyWith(
      userId: rawUserId.trim(),
      normalizedUserId: UserIdService.normalize(rawUserId),
    );
    notifyListeners();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) throw Exception('Email address is required');
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ── Send Password Reset by User ID or Email ──────────────────────────────
  Future<String> sendPasswordResetForUserIdOrEmail(String rawIdentifier) async {
    final clean = rawIdentifier.trim();
    if (clean.isEmpty) throw Exception('Please enter your User ID or Email');

    String targetEmail = '';
    if (clean.contains('@') && !clean.startsWith('@')) {
      targetEmail = clean;
    } else {
      final normalized = clean.replaceAll('@', '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      final snap = await _db
          .collection('users')
          .where('normalizedUserId', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        throw Exception('No account found for @$clean. Check your User ID.');
      }
      final data = snap.docs.first.data();
      final email = (data['email'] as String?)?.trim() ?? '';
      if (email.isEmpty) {
        throw Exception('No email address registered for @$clean.');
      }
      targetEmail = email;
    }

    await _auth.sendPasswordResetEmail(email: targetEmail);
    return targetEmail;
  }

  // ── Set / Link Password for Currently Signed-In User ─────────────────────
  // Enables Google-authenticated users to also log in with @userId and password
  Future<void> setPasswordForCurrentUser(String password) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('Not authenticated');

    final email = (u.email != null && u.email!.trim().isNotEmpty)
        ? u.email!.trim()
        : '${_currentUser?.normalizedUserId ?? u.uid}@auth.kelasagaara.in';

    try {
      final cred = EmailAuthProvider.credential(email: email, password: password);
      await u.linkWithCredential(cred);
      debugPrint('[Auth] Linked email/password credential to user ${u.uid}');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked' || e.code == 'credential-already-in-use') {
        await u.updatePassword(password);
        debugPrint('[Auth] Updated password for already-linked user ${u.uid}');
      } else {
        try {
          await u.updatePassword(password);
        } catch (_) {
          debugPrint('[Auth] Warning setting password: ${e.code} ${e.message}');
        }
      }
    } catch (e) {
      try {
        await u.updatePassword(password);
      } catch (_) {}
    }
  }

  // ── Update Profile (Registration & Editing with Security Boundaries) ─────
  // Separates user-editable fields from system-authoritative fields (Section 35)
  Future<void> updateProfile({
    required String name,
    required String role,
    required String district,
    required String taluk,
    String village = '',
    required List<String> skills,
    int dailyRate = 700,
    int experienceYears = 0,
    String experienceLevel = '',
    int serviceRadiusKm = 15,
    String? userId,
    String? phone,
    String? bio,
    String? photoUrl,
  }) async {
    final u = _auth.currentUser;
    if (u == null) return;

    if (userId != null && userId.trim().isNotEmpty) {
      await _userIdService.claimUserIdAtomically(rawUserId: userId, uid: u.uid);
    }

    final resolvedRole = role == 'hirer' ? 'hirer' : 'worker';

    final data = <String, dynamic>{
      'displayName': name.trim(),
      'name': name.trim(),
      // Always ensure role is explicitly synchronized
      'role': resolvedRole,
      'district': district.trim(),
      'taluk': taluk.trim(),
      'village': village.trim(),
      'skills': skills,
      'dailyRate': dailyRate,
      'experienceYears': experienceYears,
      'experienceLevel': experienceLevel,
      'serviceRadiusKm': serviceRadiusKm,
      if (userId != null) 'userId': userId.trim(),
      if (userId != null) 'normalizedUserId': UserIdService.normalize(userId),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (bio != null) 'bio': bio.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl.trim(),
      // Both Workers and Hirers advance from pendingProfile → pendingFace for face enrollment.
      if (_currentUser?.accountStatus == AccountStatus.pendingProfile ||
          _currentUser?.accountStatus == AccountStatus.unknown ||
          _currentUser?.accountStatus == null)
        'accountStatus': AccountStatus.pendingFace.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(u.uid).set(data, SetOptions(merge: true));

    // Determine final accountStatus for in-memory state
    AccountStatus? newStatus;
    if (_currentUser?.accountStatus == AccountStatus.pendingProfile ||
        _currentUser?.accountStatus == AccountStatus.unknown ||
        _currentUser?.accountStatus == null) {
      newStatus = AccountStatus.pendingFace;
    } else {
      newStatus = _currentUser?.accountStatus;
    }

    _currentUser = _currentUser?.copyWith(
      displayName: name.trim(),
      name: name.trim(),
      role: role == 'hirer' ? 'hirer' : 'worker',
      district: district.trim(),
      taluk: taluk.trim(),
      village: village.trim(),
      skills: skills,
      dailyRate: dailyRate,
      experienceYears: experienceYears,
      experienceLevel: experienceLevel,
      serviceRadiusKm: serviceRadiusKm,
      userId: userId?.trim(),
      normalizedUserId: userId != null ? UserIdService.normalize(userId) : null,
      phone: (phone != null && phone.trim().isNotEmpty) ? phone.trim() : _currentUser?.phone,
      bio: bio?.trim(),
      photoUrl: photoUrl?.trim(),
      accountStatus: newStatus,
    );
    notifyListeners();
  }

  /// Update strictly user-editable fields without risk of altering authoritative fields
  Future<void> updateEditableProfile({
    String? displayName,
    String? userId,
    String? bio,
    List<String>? languages,
    String? district,
    String? taluk,
    String? village,
    List<String>? skills,
    int? dailyRate,
    int? experienceYears,
    String? experienceLevel,
    int? serviceRadiusKm,
    String? photoUrl,
  }) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final updates = <String, dynamic>{
      if (displayName != null) 'displayName': displayName.trim(),
      if (displayName != null) 'name': displayName.trim(),
      if (userId != null && userId.trim().isNotEmpty) ...{
        'userId': userId.trim(),
        'normalizedUserId': UserIdService.normalize(userId),
      },
      if (bio != null) 'bio': bio.trim(),
      if (languages != null) 'languages': languages,
      if (district != null) 'district': district.trim(),
      if (taluk != null) 'taluk': taluk.trim(),
      if (village != null) 'village': village.trim(),
      if (skills != null) 'skills': skills,
      if (dailyRate != null) 'dailyRate': dailyRate,
      if (experienceYears != null) 'experienceYears': experienceYears,
      if (experienceLevel != null) 'experienceLevel': experienceLevel,
      if (serviceRadiusKm != null) 'serviceRadiusKm': serviceRadiusKm,
      if (photoUrl != null) 'photoUrl': photoUrl.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(u.uid).update(updates);
    _currentUser = _currentUser?.copyWith(
      displayName: displayName?.trim(),
      name: displayName?.trim(),
      userId: userId != null && userId.trim().isNotEmpty ? userId.trim() : null,
      normalizedUserId: userId != null && userId.trim().isNotEmpty ? UserIdService.normalize(userId) : null,
      bio: bio?.trim(),
      languages: languages,
      district: district?.trim(),
      taluk: taluk?.trim(),
      village: village?.trim(),
      skills: skills,
      dailyRate: dailyRate,
      experienceYears: experienceYears,
      experienceLevel: experienceLevel,
      serviceRadiusKm: serviceRadiusKm,
      photoUrl: photoUrl?.trim(),
    );
    notifyListeners();
  }

  Future<void> updateAvailability(bool available) async {
    final u = _auth.currentUser;
    if (u == null || _currentUser == null) return;
    await _db.collection('users').doc(u.uid).update({
      'isAvailable': available,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _currentUser = _currentUser!.copyWith(isAvailable: available);
    notifyListeners();
  }

  Future<void> signOut() async {
    _currentUser = null;
    _status      = AuthStatus.unauthenticated;
    notifyListeners();

    // Phase 4: Stop GPS availability stream to prevent orphan background writes after logout
    try {
      WorkerAvailabilityService.instance.forceStop();
    } catch (e) {
      debugPrint('[Auth] WorkerAvailabilityService.forceStop error: $e');
    }

    try {
      unawaited(JourneyService.instance.stopTracking());
      unawaited(NavigationEngine.instance.stop());
      unawaited(PresenceService.instance.goOffline());
    } catch (e) {
      debugPrint('[Auth] Error stopping tracking during signOut: $e');
    }

    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('[Auth] Error during auth signOut: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('uid');
    } catch (_) {}
  }
}

