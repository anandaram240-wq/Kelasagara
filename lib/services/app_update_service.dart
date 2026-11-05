// lib/services/app_update_service.dart
// ================================================================
// KELASAGARA — In-App Update Check Service
//
// Flow:
//   1. On app launch, read Firestore appConfig/version
//   2. Compare latestBuildNumber with current app build number
//   3. If newer → show UpdateDialog (Update Now / Not Now)
//   4. If forceUpdate: true → no "Not Now" button
//   5. "Update Now" → opens downloadUrl via url_launcher
//
// Admin sets version in Firestore:
//   Collection: appConfig  Document: version
//   Fields:
//     latestBuildNumber: 179       (int)
//     latestVersion:     "17.9.0"  (String, display only)
//     downloadUrl:       "https://…" (direct APK link)
//     releaseNotes:      "Bug fixes and new features"
//     forceUpdate:       false    (bool)
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  final int    currentBuildNumber;
  final String currentVersion;
  final int    latestBuildNumber;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool   forceUpdate;
  final bool   updateAvailable;

  const AppVersionInfo({
    required this.currentBuildNumber,
    required this.currentVersion,
    required this.latestBuildNumber,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.updateAvailable,
  });
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  final _db = FirebaseFirestore.instance;

  /// Check for updates. Returns null if no update or if check fails.
  Future<AppVersionInfo?> checkForUpdate() async {
    try {
      // Get current app build number
      final info      = await PackageInfo.fromPlatform();
      final currentBn = int.tryParse(info.buildNumber) ?? 0;
      final currentVer= info.version;

      // Read remote version doc
      final snap = await _db.collection('appConfig').doc('version').get();
      if (!snap.exists) {
        debugPrint('[AppUpdate] appConfig/version doc not found — skipping update check');
        return null;
      }

      final data             = snap.data()!;
      final latestBn         = (data['latestBuildNumber'] as num?)?.toInt() ?? 0;
      final latestVer        = data['latestVersion']  as String? ?? '';
      final downloadUrl      = data['downloadUrl']    as String? ?? '';
      final releaseNotes     = data['releaseNotes']   as String? ?? 'New version available.';
      final forceUpdate      = data['forceUpdate']    as bool? ?? false;
      final updateAvailable  = latestBn > currentBn;

      debugPrint('[AppUpdate] current=$currentBn latest=$latestBn updateAvailable=$updateAvailable');

      return AppVersionInfo(
        currentBuildNumber: currentBn,
        currentVersion:     currentVer,
        latestBuildNumber:  latestBn,
        latestVersion:      latestVer,
        downloadUrl:        downloadUrl,
        releaseNotes:       releaseNotes,
        forceUpdate:        forceUpdate,
        updateAvailable:    updateAvailable,
      );
    } catch (e) {
      debugPrint('[AppUpdate] Error checking update: $e');
      return null;
    }
  }
}
