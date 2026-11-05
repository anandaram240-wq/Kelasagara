// ================================================================
// KELASAGARA — Evidence Upload Service (Firebase Storage Edition)
// Uses firebase_storage — already in pubspec, no billing needed.
// Firebase Auth + Security Rules replace the Cloudflare Worker.
// R2 and Cloudflare Worker are NOT used.
// ================================================================

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ── Upload State ───────────────────────────────────────────────────
enum UploadState {
  idle,
  validating,
  uploading,
  confirming,
  done,
  failed,
  waitingForNetwork,
}

class EvidenceUploadProgress {
  final UploadState state;
  final double progress;        // 0.0–1.0
  final String message;
  final String? errorMessage;
  final String? evidenceId;
  final String? storageKey;

  const EvidenceUploadProgress({
    required this.state,
    this.progress = 0,
    this.message = '',
    this.errorMessage,
    this.evidenceId,
    this.storageKey,
  });

  bool get isDone    => state == UploadState.done;
  bool get hasFailed => state == UploadState.failed;
}

// ── Video Validation Result ────────────────────────────────────────
class VideoValidationResult {
  final bool isValid;
  final String? errorMessage;
  final double fileSizeMb;
  final String mimeType;

  const VideoValidationResult({
    required this.isValid,
    this.errorMessage,
    required this.fileSizeMb,
    this.mimeType = 'video/mp4',
  });
}

// ── Upload Service ─────────────────────────────────────────────────
class EvidenceUploadService {
  EvidenceUploadService._();
  static final EvidenceUploadService instance = EvidenceUploadService._();

  static const int _maxSizeMb = 200;

  final FirebaseFirestore _db       = FirebaseFirestore.instance;
  final FirebaseStorage   _storage  = FirebaseStorage.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Storage path pattern — no PII in path ─────────────────────
  // assessment-evidence/{uid}/{assessmentId}/{taskId}/{evidenceId}.mp4
  static String buildStoragePath(
    String uid, String assessmentId, String taskId, String evidenceId) {
    return 'assessment-evidence/$uid/$assessmentId/$taskId/$evidenceId.mp4';
  }

  // ── 1. Validate video before upload ───────────────────────────
  Future<VideoValidationResult> validateVideo(File videoFile) async {
    try {
      final stat   = await videoFile.stat();
      final sizeMb = stat.size / 1024 / 1024;

      if (sizeMb > _maxSizeMb) {
        return VideoValidationResult(
          isValid: false,
          fileSizeMb: sizeMb,
          errorMessage:
            'Video is too large (${sizeMb.toStringAsFixed(1)} MB). '
            'Maximum allowed is $_maxSizeMb MB. Record a shorter clip.',
        );
      }
      if (stat.size < 50 * 1024) { // < 50 KB — likely corrupt/empty
        return VideoValidationResult(
          isValid: false,
          fileSizeMb: sizeMb,
          errorMessage: 'Video file appears empty or corrupt. Please record again.',
        );
      }

      return VideoValidationResult(
        isValid: true,
        fileSizeMb: sizeMb,
        mimeType: 'video/mp4',
      );
    } catch (_) {
      return const VideoValidationResult(
        isValid: false,
        fileSizeMb: 0,
        errorMessage: 'Could not read video file. Please try recording again.',
      );
    }
  }

  // ── 2. Full upload pipeline ────────────────────────────────────
  Stream<EvidenceUploadProgress> uploadEvidence({
    required File videoFile,
    required String assessmentId,
    required String taskId,
    required String skillId,
    int attemptNumber = 1,
  }) async* {
    if (_uid.isEmpty) {
      yield const EvidenceUploadProgress(
        state: UploadState.failed,
        errorMessage: 'Not logged in. Please restart the app.',
      );
      return;
    }

    yield const EvidenceUploadProgress(
      state: UploadState.validating,
      message: 'Checking video...',
      progress: 0.05,
    );

    // ── Step 1: Validate ──────────────────────────────────────────
    final validation = await validateVideo(videoFile);
    if (!validation.isValid) {
      yield EvidenceUploadProgress(
        state: UploadState.failed,
        errorMessage: validation.errorMessage,
      );
      return;
    }

    // ── Step 2: Check connectivity ────────────────────────────────
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      yield const EvidenceUploadProgress(
        state: UploadState.waitingForNetwork,
        message: 'Waiting for internet...',
        progress: 0.05,
      );
      final connected = await _waitForConnectivity(
        timeout: const Duration(minutes: 5));
      if (!connected) {
        yield const EvidenceUploadProgress(
          state: UploadState.failed,
          errorMessage:
            'No internet connection. Video saved locally — try uploading again.',
        );
        return;
      }
    }

    // ── Step 3: Create Firestore evidence record ──────────────────
    final evidenceId = _db.collection('assessmentEvidence').doc().id;
    final storagePath = buildStoragePath(_uid, assessmentId, taskId, evidenceId);

    yield EvidenceUploadProgress(
      state: UploadState.uploading,
      message: 'Preparing secure upload...',
      progress: 0.1,
      evidenceId: evidenceId,
      storageKey: storagePath,
    );

    await _db.collection('assessmentEvidence').doc(evidenceId).set({
      'assessmentId':  assessmentId,
      'workerId':      _uid,
      'skillId':       skillId,
      'taskId':        taskId,
      'attemptNumber': attemptNumber,
      'status':        'uploading',
      'storageKey':    storagePath,
      'aiStatus':      'pending',
      'reviewStatus':  'pending',
      'createdAt':     FieldValue.serverTimestamp(),
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    // ── Step 4: Upload to Firebase Storage (resumable built-in) ──
    // Firebase Storage SDK handles resumable uploads automatically.
    // Security Rules (storage.rules) enforce:
    //   - Only authenticated worker can upload their own evidence
    //   - Max file size 200MB
    //   - video/* MIME type only
    final ref = _storage.ref(storagePath);
    final metadata = SettableMetadata(
      contentType: validation.mimeType,
      customMetadata: {
        'workerId':     _uid,
        'assessmentId': assessmentId,
        'taskId':       taskId,
        'evidenceId':   evidenceId,
        'skillId':      skillId,
      },
    );

    UploadTask? uploadTask;
    try {
      uploadTask = ref.putFile(videoFile, metadata);

      // Stream progress from Firebase SDK
      await for (final snapshot in uploadTask.snapshotEvents) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        // Map: 0.1 → 0.85 range during upload
        final displayProgress = 0.1 + (progress * 0.75);

        yield EvidenceUploadProgress(
          state: UploadState.uploading,
          message: 'Uploading... ${(progress * 100).round()}%',
          progress: displayProgress,
          evidenceId: evidenceId,
          storageKey: storagePath,
        );

        if (snapshot.state == TaskState.error) {
          throw Exception('Upload task failed with state: error');
        }
        if (snapshot.state == TaskState.success) break;
      }

      // Confirm upload success
      final finalSnapshot = await uploadTask;
      if (finalSnapshot.state != TaskState.success) {
        throw Exception('Upload did not complete successfully');
      }
    } catch (e) {
      await _db.collection('assessmentEvidence').doc(evidenceId).update({
        'status':    'failed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      yield EvidenceUploadProgress(
        state: UploadState.failed,
        errorMessage:
          'Upload interrupted. Video saved on device — please try again.',
        evidenceId: evidenceId,
      );
      return;
    }

    // ── Step 5: Confirm in Firestore ──────────────────────────────
    yield EvidenceUploadProgress(
      state: UploadState.confirming,
      message: 'Verifying upload...',
      progress: 0.92,
      evidenceId: evidenceId,
      storageKey: storagePath,
    );

    final sizeMb = validation.fileSizeMb;

    await _db.collection('assessmentEvidence').doc(evidenceId).update({
      'status':    'uploaded',
      'fileSizeMb': sizeMb,
      'uploadedAt': FieldValue.serverTimestamp(),
      'updatedAt':  FieldValue.serverTimestamp(),
    });

    // Add to assessment's evidenceIds list
    await _db.collection('skillAssessments').doc(assessmentId).update({
      'evidenceIds': FieldValue.arrayUnion([evidenceId]),
      'status':      'evidence_collection',
      'updatedAt':   FieldValue.serverTimestamp(),
    });

    yield EvidenceUploadProgress(
      state: UploadState.done,
      message: '✅ Video uploaded securely',
      progress: 1.0,
      evidenceId: evidenceId,
      storageKey: storagePath,
    );
  }

  // ── Get download URL for playback ──────────────────────────────
  // Firebase Storage generates a time-limited URL automatically.
  // Security Rules enforce: only worker owner + admin can download.
  Future<String?> getPlaybackUrl(String storagePath) async {
    try {
      return await _storage.ref(storagePath).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  // ── Connectivity wait helper ───────────────────────────────────
  Future<bool> _waitForConnectivity({required Duration timeout}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await Future.delayed(const Duration(seconds: 3));
      final result = await Connectivity().checkConnectivity();
      if (!result.contains(ConnectivityResult.none)) return true;
    }
    return false;
  }
}
