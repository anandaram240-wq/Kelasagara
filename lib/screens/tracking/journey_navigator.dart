// lib/screens/tracking/journey_navigator.dart
// Single place to navigate to WorkerJourneyScreen or HirerTrackingScreen.
// Creates a fresh JourneyProvider per tracking session (not global).
//
// Usage (from any screen):
//   JourneyNavigator.openWorker(context, booking: booking);
//   JourneyNavigator.openHirer(context, booking: booking);

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/journey_provider.dart';
import 'worker_journey_screen.dart';
import 'hirer_tracking_screen.dart';

class JourneyNavigator {
  JourneyNavigator._();

  /// Validates that coordinates are within physical range and non-zero.
  static bool isValidCoord(double lat, double lng) {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lng >= -180.0 &&
        lng <= 180.0 &&
        !(lat == 0.0 && lng == 0.0);
  }

  /// Open worker journey screen for a confirmed booking.
  /// [booking] must be a map from Firestore bookings document.
  static Future<void> openWorker(
    BuildContext context, {
    required Map<String, dynamic> booking,
    required String workerId,
  }) {
    final bookingId  = booking['bookingId']  as String? ?? booking['id'] as String? ?? '';
    final hirerId    = booking['hirerId']    as String? ?? '';
    final jobId      = booking['jobId']      as String? ?? '';    // Phase 4: for RTDB identity
    final loc        = booking['location'] as Map<String, dynamic>?;
    // Support both 'jobLat'/'jobLng', 'lat'/'lng', and 'location' map
    final destLat    = (booking['jobLat']   as num?)?.toDouble()
                    ?? (booking['lat']      as num?)?.toDouble()
                    ?? (booking['destLat']  as num?)?.toDouble()
                    ?? (loc?['lat']         as num?)?.toDouble() ?? 0.0;
    final destLng    = (booking['jobLng']   as num?)?.toDouble()
                    ?? (booking['lng']      as num?)?.toDouble()
                    ?? (booking['destLng']  as num?)?.toDouble()
                    ?? (loc?['lng']         as num?)?.toDouble() ?? 0.0;
    final jobAddress = booking['jobAddress'] as String?
                    ?? booking['address'] as String?
                    ?? (loc?['address'] as String?) ?? '';
    final jobTitle   = booking['jobTitle']   as String? ?? booking['title']   as String? ?? 'Job';
    final workerName = booking['workerName'] as String? ?? '';
    final status     = booking['status']     as String? ?? 'confirmed';

    // 1. Worker Authorization Gate: ensure caller is assigned to this booking
    final assignedWorkerId = booking['workerId'] as String? ?? '';
    if (assignedWorkerId.isNotEmpty && workerId.isNotEmpty && assignedWorkerId != workerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unauthorized: You are not the assigned worker for this job.'),
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    // 2. Booking Status Gate: active booking required
    const allowedWorkerStatuses = {'confirmed', 'tracking', 'in_progress', 'arrived'};
    if (!allowedWorkerStatuses.contains(status.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation is only available for active bookings (Current status: $status).'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    // 3. Strict coordinate validation — prevents map centering on ocean (0°, 0°) or out-of-range bounds
    if (!isValidCoord(destLat, destLng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job location is invalid or missing. Please contact the hirer.'),
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => JourneyProvider(),
          child: WorkerJourneyScreen(
            bookingId:            bookingId,
            workerId:             workerId,
            hirerId:              hirerId,
            jobId:                jobId,               // Phase 4
            destLat:              destLat,
            destLng:              destLng,
            jobAddress:           jobAddress,
            jobTitle:             jobTitle,
            workerName:           workerName,
            currentBookingStatus: status,
          ),
        ),
      ),
    );
  }

  /// Open hirer's live tracking screen for a confirmed booking.
  static Future<void> openHirer(
    BuildContext context, {
    required Map<String, dynamic> booking,
  }) {
    final bookingId  = booking['bookingId']  as String? ?? booking['id'] as String? ?? '';
    final jobId      = booking['jobId']      as String? ?? '';
    final workerId   = booking['workerId']   as String? ?? '';
    final loc        = booking['location'] as Map<String, dynamic>?;
    // Support both 'jobLat'/'jobLng', 'lat'/'lng', and 'location' map
    final destLat    = (booking['jobLat']    as num?)?.toDouble()
                    ?? (booking['lat']       as num?)?.toDouble()
                    ?? (booking['destLat']   as num?)?.toDouble()
                    ?? (loc?['lat']          as num?)?.toDouble() ?? 0.0;
    final destLng    = (booking['jobLng']    as num?)?.toDouble()
                    ?? (booking['lng']       as num?)?.toDouble()
                    ?? (booking['destLng']   as num?)?.toDouble()
                    ?? (loc?['lng']          as num?)?.toDouble() ?? 0.0;
    final jobAddress = booking['jobAddress'] as String?
                    ?? booking['address'] as String?
                    ?? (loc?['address'] as String?) ?? '';
    final jobTitle   = booking['jobTitle']   as String? ?? booking['title']   as String? ?? 'Job';
    final workerName = booking['workerName'] as String? ?? '';
    final status     = booking['status']     as String? ?? 'confirmed';

    // Status gate
    const allowedHirerStatuses = {'confirmed', 'tracking', 'in_progress', 'arrived', 'completed'};
    if (!allowedHirerStatuses.contains(status.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tracking is only available for active bookings (Current status: $status).'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    // Strict coordinate validation
    if (!isValidCoord(destLat, destLng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job site location is invalid or missing.'),
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 4),
        ),
      );
      return Future.value();
    }

    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => JourneyProvider(),
          child: HirerTrackingScreen(
            bookingId:            bookingId,
            jobId:                jobId,
            workerId:             workerId,
            destLat:              destLat,
            destLng:              destLng,
            jobAddress:           jobAddress,
            jobTitle:             jobTitle,
            workerName:           workerName,
            currentBookingStatus: status,
          ),
        ),
      ),
    );
  }
}
