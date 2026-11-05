// lib/features/tracking/services/google_maps_navigation_launcher.dart
// Production-grade native Google Maps launcher with background isolate handshake.
// Guarantees WorkerTelemetryService foreground isolate is running BEFORE launching
// Google Maps in Two-Wheeler (mode=l) or Driving (mode=d) mode.

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'worker_telemetry_service.dart';

enum GoogleMapsTravelMode {
  twoWheeler('l', 'two-wheeler'), // Best for Indian bikes/scooters
  driving('d', 'driving'),
  walking('w', 'walking');

  final String androidIntentCode;
  final String universalModeName;
  const GoogleMapsTravelMode(this.androidIntentCode, this.universalModeName);
}

class GoogleMapsNavigationLauncher {
  GoogleMapsNavigationLauncher._();
  static final GoogleMapsNavigationLauncher instance =
      GoogleMapsNavigationLauncher._();

  /// 1. Starts/verifies the Doze-proof background GPS isolate
  /// 2. Launches native Google Maps turn-by-turn navigation to [destination]
  Future<bool> startBackgroundTrackingAndLaunchGoogleMaps({
    required String bookingId,
    required String workerId,
    required LatLng destination,
    String? destinationLabel,
    GoogleMapsTravelMode travelMode = GoogleMapsTravelMode.twoWheeler,
  }) async {
    // Step 1: Transition Firestore booking status to tracking and ensure
    // background telemetry service is actively broadcasting to RTDB
    // BEFORE Kelasagaara goes into the background behind Google Maps.
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
        'status': 'tracking',
        'journeyStartedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[GoogleMapsLauncher] Firestore tracking update notice: $e');
    }

    await WorkerTelemetryService.instance.startTracking(
      bookingId: bookingId,
      workerId: workerId,
      destination: destination,
      status: 'on_the_way',
    );

    final lat = destination.latitude.toStringAsFixed(6);
    final lng = destination.longitude.toStringAsFixed(6);

    // Step 2: Try native Android Google Maps Turn-by-Turn Intent first
    if (!kIsWeb && Platform.isAndroid) {
      final androidNavUri = Uri.parse(
        'google.navigation:q=$lat,$lng&mode=${travelMode.androidIntentCode}',
      );
      if (await canLaunchUrl(androidNavUri)) {
        return launchUrl(
          androidNavUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      }
    }

    // Step 3: Try iOS native comgooglemaps:// scheme
    if (!kIsWeb && Platform.isIOS) {
      final iosNavUri = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=${travelMode.universalModeName}',
      );
      if (await canLaunchUrl(iosNavUri)) {
        return launchUrl(
          iosNavUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      }
    }

    // Step 4: Universal Google Maps Deep-Link Fallback (opens Google Maps app or browser)
    final universalUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&travelmode=${travelMode.universalModeName}'
      '&dir_action=navigate',
    );

    return launchUrl(
      universalUri,
      mode: LaunchMode.externalApplication,
    );
  }
}
