// lib/services/profile_media_service.dart
// Production-grade profile photo & portfolio media service for Kelasagara.
// Strictly enforces storage boundaries and size limits defined in storage.rules.

import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ProfileMediaResult {
  final bool success;
  final String? downloadUrl;
  final String? errorMessage;

  const ProfileMediaResult._({
    required this.success,
    this.downloadUrl,
    this.errorMessage,
  });

  factory ProfileMediaResult.ok(String url) =>
      ProfileMediaResult._(success: true, downloadUrl: url);

  factory ProfileMediaResult.failure(String error) =>
      ProfileMediaResult._(success: false, errorMessage: error);
}

class ProfileMediaService {
  ProfileMediaService._();
  static final ProfileMediaService instance = ProfileMediaService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  static const int kMaxAvatarSizeBytes = 5 * 1024 * 1024;    // 5 MB
  static const int kMaxPortfolioSizeBytes = 8 * 1024 * 1024; // 8 MB

  /// Pick an image from gallery or camera
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (xFile == null) return null;
      return File(xFile.path);
    } catch (e) {
      debugPrint('[ProfileMediaService] pickImage error: $e');
      return null;
    }
  }

  /// Upload public avatar photo to Firebase Storage
  /// Storage path: profile-photos/{uid}/avatar_{timestamp}.jpg
  Future<ProfileMediaResult> uploadAvatarPhoto({
    required String uid,
    required File imageFile,
  }) async {
    if (uid.trim().isEmpty) {
      return ProfileMediaResult.failure('Invalid user session');
    }

    try {
      // 1. Check local file existence and size
      if (!await imageFile.exists()) {
        return ProfileMediaResult.failure('Selected image file does not exist');
      }

      final fileSize = await imageFile.length();
      if (fileSize > kMaxAvatarSizeBytes) {
        final mb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        return ProfileMediaResult.failure(
          'Image size is $mb MB. Please select a photo under 5 MB.',
        );
      }

      // 2. Prepare storage destination
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = _storage.ref().child('profile-photos').child(uid).child(fileName);

      // 3. Upload with strict contentType metadata matching storage.rules
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedBy': uid,
          'purpose': 'avatar',
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = storageRef.putFile(imageFile, metadata);
      final snapshot = await uploadTask;

      // 4. Retrieve public download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('[ProfileMediaService] Avatar uploaded successfully: $downloadUrl');
      return ProfileMediaResult.ok(downloadUrl);
    } on FirebaseException catch (e) {
      debugPrint('[ProfileMediaService] FirebaseStorage error: ${e.code} - ${e.message}');
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        return ProfileMediaResult.failure('Permission denied uploading photo. Please try again.');
      }
      return ProfileMediaResult.failure('Upload failed: ${e.message ?? e.code}');
    } catch (e) {
      debugPrint('[ProfileMediaService] Unexpected error: $e');
      return ProfileMediaResult.failure('Could not upload photo. Please check network.');
    }
  }

  /// Upload public portfolio photo to Firebase Storage
  /// Storage path: portfolio/{uid}/item_{timestamp}.jpg
  Future<ProfileMediaResult> uploadPortfolioPhoto({
    required String uid,
    required File imageFile,
  }) async {
    if (uid.trim().isEmpty) {
      return ProfileMediaResult.failure('Invalid user session');
    }

    try {
      if (!await imageFile.exists()) {
        return ProfileMediaResult.failure('Selected image file does not exist');
      }

      final fileSize = await imageFile.length();
      if (fileSize > kMaxPortfolioSizeBytes) {
        final mb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        return ProfileMediaResult.failure(
          'Portfolio image is $mb MB. Max allowed is 8 MB.',
        );
      }

      final fileName = 'portfolio_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = _storage.ref().child('portfolio').child(uid).child(fileName);

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedBy': uid,
          'purpose': 'portfolio',
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = storageRef.putFile(imageFile, metadata);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return ProfileMediaResult.ok(downloadUrl);
    } on FirebaseException catch (e) {
      return ProfileMediaResult.failure('Upload failed: ${e.message ?? e.code}');
    } catch (e) {
      return ProfileMediaResult.failure('Could not upload portfolio item.');
    }
  }
}
