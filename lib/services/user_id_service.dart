// lib/services/user_id_service.dart
// Production-grade Atomic User ID Registry, Validation & Suggestion Service
// Architected for Kelasagara Identity Foundation (Change 2)

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserIdValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? normalized;

  const UserIdValidationResult({
    required this.isValid,
    this.errorMessage,
    this.normalized,
  });
}

class UserIdService {
  final FirebaseFirestore _db;

  UserIdService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  static const int minLength = 3;
  static const int maxLength = 20;

  // Comprehensive reserved words list (Section 74)
  static const Set<String> reservedUserIds = {
    'admin', 'administrator', 'root', 'support', 'help', 'kelasagara',
    'kelasagaara', 'official', 'moderator', 'system', 'security', 'billing',
    'api', 'test', 'dev', 'developer', 'guest', 'user', 'superadmin',
    'null', 'undefined', 'settings', 'login', 'logout', 'auth', 'signup',
    'register', 'terms', 'privacy', 'about', 'contact', 'staff', 'owner',
    'manager', 'operator', 'verified', 'certified', 'service', 'karnataka',
    'govt', 'government', 'police', 'bocw', 'eshram', 'app', 'dashboard',
  };

  // Blocklist for abusive / inappropriate usernames
  static const Set<String> abusiveWords = {
    'fake', 'scam', 'fraud', 'cheat', 'hacker', 'spam', 'abuse',
  };

  /// Deterministic normalization: trim whitespace and convert to lowercase
  static String normalize(String userId) {
    return userId.trim().toLowerCase();
  }

  /// Client-side and server-side structural validation
  static UserIdValidationResult validate(String rawUserId) {
    final normalized = normalize(rawUserId);

    if (normalized.isEmpty) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID cannot be empty',
      );
    }

    if (normalized.length < minLength) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID must be at least $minLength characters',
      );
    }

    if (normalized.length > maxLength) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID must not exceed $maxLength characters',
      );
    }

    // Must start with a letter (a-z)
    final startsWithLetter = RegExp(r'^[a-z]');
    if (!startsWithLetter.hasMatch(normalized)) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID must start with a letter (a-z)',
      );
    }

    // Must end with a letter or digit (no trailing separator)
    final endsWithAlphaNum = RegExp(r'[a-z0-9]$');
    if (!endsWithAlphaNum.hasMatch(normalized)) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID cannot end with an underscore or dot',
      );
    }

    // Allowed characters: lowercase letters, numbers, underscore, dot
    final allowedCharsRegex = RegExp(r'^[a-z0-9_.]+$');
    if (!allowedCharsRegex.hasMatch(normalized)) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID can only contain letters, numbers, underscores, and dots',
      );
    }

    // No consecutive separators: __, .., ._, _.
    if (normalized.contains('__') ||
        normalized.contains('..') ||
        normalized.contains('._') ||
        normalized.contains('_.')) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'User ID cannot have consecutive separators (._, .., __)',
      );
    }

    // Check reserved names
    if (reservedUserIds.contains(normalized)) {
      return const UserIdValidationResult(
        isValid: false,
        errorMessage: 'This User ID is reserved and cannot be claimed',
      );
    }

    // Check abusive terms
    for (final term in abusiveWords) {
      if (normalized.contains(term)) {
        return const UserIdValidationResult(
          isValid: false,
          errorMessage: 'This User ID contains inappropriate or restricted words',
        );
      }
    }

    return UserIdValidationResult(isValid: true, normalized: normalized);
  }

  /// Pre-check if normalized User ID is currently available in Firestore
  Future<bool> checkUserIdAvailability(String rawUserId) async {
    final validation = validate(rawUserId);
    if (!validation.isValid) return false;

    try {
      final doc = await _db.collection('usernames').doc(validation.normalized).get();
      return !doc.exists;
    } catch (e) {
      // In case of network failure, do not falsely report available
      return false;
    }
  }

  /// Suggestion engine: When User ID is taken, generates safe candidate alternatives
  /// and authoritatively verifies their availability against Firestore.
  /// Never invents availability.
  Future<List<String>> generateAvailableSuggestions(String rawUserId, {int maxCount = 3}) async {
    final normalized = normalize(rawUserId);
    if (normalized.isEmpty) return [];

    // Strip trailing numbers/separators to extract clean base
    var cleanBase = normalized.replaceAll(RegExp(r'[\d_.]+$'), '');
    if (cleanBase.length < 3) cleanBase = normalized;
    if (cleanBase.length > 14) cleanBase = cleanBase.substring(0, 14);

    final currentYear = DateTime.now().year % 100; // e.g. 25
    final rng = Random();
    final candidates = <String>[];

    // Candidate variants
    final patterns = [
      '${cleanBase}_$currentYear',
      '${cleanBase}_ka',
      '$cleanBase${rng.nextInt(90) + 10}',
      '${cleanBase}_work',
      '$cleanBase.${rng.nextInt(90) + 10}',
      '${cleanBase}_pro',
    ];

    for (final p in patterns) {
      final valid = validate(p);
      if (valid.isValid && !candidates.contains(valid.normalized)) {
        candidates.add(valid.normalized!);
      }
    }

    // Authoritatively check each candidate against Firestore
    final verified = <String>[];
    for (final candidate in candidates) {
      if (verified.length >= maxCount) break;
      try {
        final doc = await _db.collection('usernames').doc(candidate).get();
        if (!doc.exists) {
          verified.add(candidate);
        }
      } catch (_) {
        // Skip on check error
      }
    }

    return verified;
  }

  /// Lookup User ID mapping to retrieve account identity (UID & metadata)
  Future<Map<String, dynamic>?> lookupByUserId(String rawUserId) async {
    final normalized = normalize(rawUserId);
    if (normalized.isEmpty) return null;

    try {
      final doc = await _db.collection('usernames').doc(normalized).get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  /// Atomically claim User ID in a Firestore Transaction
  /// Prevents race conditions: if two users attempt to claim the same ID concurrently,
  /// exactly one succeeds and the second fails.
  Future<void> claimUserIdAtomically({
    required String rawUserId,
    required String uid,
  }) async {
    final validation = validate(rawUserId);
    if (!validation.isValid) {
      throw Exception(validation.errorMessage ?? 'Invalid User ID');
    }

    final normalized = validation.normalized!;
    final usernameRef = _db.collection('usernames').doc(normalized);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(usernameRef);
      if (snap.exists) {
        final existingUid = snap.data()?['uid'];
        if (existingUid != uid) {
          throw Exception('User ID "@$rawUserId" has already been taken by another user');
        }
      }

      // Claim in authoritative usernames collection
      tx.set(usernameRef, {
        'uid': uid,
        'userId': rawUserId.trim(),
        'normalizedUserId': normalized,
        'createdAt': snap.exists ? (snap.data()?['createdAt'] ?? FieldValue.serverTimestamp()) : FieldValue.serverTimestamp(),
        'claimedAt': FieldValue.serverTimestamp(),
      });

      // Update user document if it already exists in Firestore
      final userSnap = await tx.get(userRef);
      if (userSnap.exists) {
        tx.set(userRef, {
          'userId': rawUserId.trim(),
          'normalizedUserId': normalized,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  /// Safe migration helper for existing users who do not have an authoritative User ID
  Future<bool> migrateExistingUserIfNeeded({
    required String uid,
    required String? currentUserId,
    required String? displayName,
    required String? email,
  }) async {
    if (currentUserId != null && currentUserId.trim().isNotEmpty) {
      final val = validate(currentUserId);
      if (val.isValid) {
        // Check if username doc exists
        final doc = await _db.collection('usernames').doc(val.normalized!).get();
        if (doc.exists && doc.data()?['uid'] == uid) {
          return true; // Already authoritatively claimed
        } else if (!doc.exists) {
          // Claim it now
          await claimUserIdAtomically(rawUserId: currentUserId, uid: uid);
          return true;
        }
      }
    }
    return false; // Needs migration flow
  }
}
