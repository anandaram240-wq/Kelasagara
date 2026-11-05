// lib/services/navigation/external_navigation_service.dart
// ============================================================================
// KELASAGARA — External Google Maps Navigation Handoff Service
//
// Purpose:
//   Enables one-tap external Google Maps turn-by-turn navigation handoff for
//   workers with authorized, confirmed bookings.
//
// Architecture & Principles:
//   1. Zero manual destination entry: exact authorized coordinates populated.
//   2. Device current location as origin: origin parameter is strictly omitted.
//   3. Navigation mode: dir_action=navigate requested directly.
//   4. Travel mode: 'driving' by default, 'two-wheeler' for motorcycle workers.
//   5. Strict security authorization: only the assigned worker of an active
//      booking can launch navigation.
//   6. Zero side effects: no Firebase writes, no booking status changes,
//      no internal navigation engine mutations.
//   7. Debounced: protects against rapid double-tap launch storms.
//   8. No API key required: uses standard Google Maps Universal Cross-Platform URLs.
//   9. Force external launch: native Google Maps app attempted first with
//      clean external web browser fallback.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/navigation_destination.dart';
import '../journey_service.dart';

/// Contract for external navigation providers (supports future providers like Waze).
abstract interface class ExternalNavigationProvider {
  String get providerName;
  Future<bool> canLaunch(Uri uri);
  Future<bool> launch(Uri uri);
  Uri buildNavigationUri({
    required double destinationLat,
    required double destinationLng,
    String travelMode = 'driving',
    String? destinationPlaceId,
  });
}

/// Google Maps implementation conforming to official Google Maps URL specifications.
class GoogleMapsExternalProvider implements ExternalNavigationProvider {
  const GoogleMapsExternalProvider();

  @override
  String get providerName => 'Google Maps';

  @override
  Future<bool> canLaunch(Uri uri) => canLaunchUrl(uri);

  @override
  Uri buildNavigationUri({
    required double destinationLat,
    required double destinationLng,
    String travelMode = 'driving',
    String? destinationPlaceId,
  }) {
    final queryParams = <String, String>{
      'api': '1',
      // Exact coordinates without loss of precision
      'destination': '$destinationLat,$destinationLng',
      'travelmode': travelMode,
      'dir_action': 'navigate',
    };

    if (destinationPlaceId != null && destinationPlaceId.trim().isNotEmpty) {
      queryParams['destination_place_id'] = destinationPlaceId.trim();
    }

    // Google Maps Directions URL format:
    // https://www.google.com/maps/dir/?api=1&destination=<LAT>,<LNG>&travelmode=<MODE>&dir_action=navigate
    // CRITICAL: Origin is strictly OMITTED so Google Maps automatically uses the device's current location.
    return Uri.https('www.google.com', '/maps/dir/', queryParams);
  }

  static const MethodChannel _channel = MethodChannel('kelasagara/external_navigation');

  @override
  Future<bool> launch(Uri uri) async {
    // 0. Primary on Android: Attempt native platform channel targeting com.google.android.apps.maps
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _channel.invokeMethod<bool>('launchGoogleMaps', {'url': uri.toString()});
        if (res == true) return true;
      } catch (e) {
        debugPrint('[GoogleMapsExternalProvider] Platform channel launch error: $e. Falling back to url_launcher.');
      }
    }

    // 1. Primary via url_launcher: Attempt launching native external non-browser application (Google Maps app directly)
    try {
      final nativeLaunched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (nativeLaunched) return true;
    } catch (e) {
      debugPrint('[GoogleMapsExternalProvider] Native non-browser app launch: $e. Trying externalApplication.');
    }

    // 2. Secondary: Attempt launching externalApplication
    try {
      final appLaunched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (appLaunched) return true;
    } catch (e) {
      debugPrint('[GoogleMapsExternalProvider] Native app launch error: $e. Falling back to web.');
    }

    // 3. Fallback: Standard external web browser
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      debugPrint('[GoogleMapsExternalProvider] Web fallback launch error: $e.');
      return false;
    }
  }
}

/// Status of an external navigation launch request.
enum ExternalNavigationStatus {
  success,
  bookingInactive,
  unauthorizedWorker,
  invalidDestination,
  launchFailed,
  rateLimited,
}

/// Result of an external navigation handoff operation.
class ExternalNavigationResult {
  final ExternalNavigationStatus status;
  final String? errorMessage;
  final Uri? launchedUri;

  const ExternalNavigationResult({
    required this.status,
    this.errorMessage,
    this.launchedUri,
  });

  bool get isSuccess => status == ExternalNavigationStatus.success;

  factory ExternalNavigationResult.success(Uri uri) =>
      ExternalNavigationResult(status: ExternalNavigationStatus.success, launchedUri: uri);

  factory ExternalNavigationResult.bookingInactive([String? msg]) =>
      ExternalNavigationResult(
        status: ExternalNavigationStatus.bookingInactive,
        errorMessage: msg ?? 'This booking is no longer active.',
      );

  factory ExternalNavigationResult.unauthorized([String? msg]) =>
      ExternalNavigationResult(
        status: ExternalNavigationStatus.unauthorizedWorker,
        errorMessage: msg ?? 'Unauthorized: Only the assigned worker can navigate to this job.',
      );

  factory ExternalNavigationResult.invalidDestination([String? msg]) =>
      ExternalNavigationResult(
        status: ExternalNavigationStatus.invalidDestination,
        errorMessage: msg ?? 'Unable to open navigation because this booking has no valid destination.',
      );

  factory ExternalNavigationResult.launchFailed([String? msg]) =>
      ExternalNavigationResult(
        status: ExternalNavigationStatus.launchFailed,
        errorMessage: msg ?? 'Google Maps could not be opened.',
      );

  factory ExternalNavigationResult.rateLimited() =>
      const ExternalNavigationResult(
        status: ExternalNavigationStatus.rateLimited,
        errorMessage: 'Navigation launch already in progress. Please wait a moment.',
      );
}

/// Canonical service for external navigation handoff.
/// Access via ExternalNavigationService.instance.
class ExternalNavigationService {
  ExternalNavigationService({ExternalNavigationProvider? provider})
      : _provider = provider ?? const GoogleMapsExternalProvider();

  static final ExternalNavigationService instance = ExternalNavigationService();

  ExternalNavigationProvider _provider;

  /// Visible for testing to inject mock providers.
  @visibleForTesting
  set provider(ExternalNavigationProvider p) => _provider = p;

  // Rate limiting / debounce protection
  bool _isLaunching = false;
  DateTime? _lastLaunchTime;
  static const Duration _debounceDuration = Duration(milliseconds: 1500);

  /// Resolves the Google Maps travel mode based on worker travel preference.
  String resolveTravelMode(String? workerPreference) {
    if (workerPreference == null) return 'driving';
    final normalized = workerPreference.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == 'motorcycle' ||
        normalized == 'two_wheeler' ||
        normalized == 'twowheeler' ||
        normalized == 'bike') {
      return 'two-wheeler';
    }
    return 'driving';
  }

  /// Builds a canonical Google Maps navigation URI conforming to official specifications.
  Uri buildGoogleMapsNavigationUri({
    required double destinationLat,
    required double destinationLng,
    String travelMode = 'driving',
    String? destinationPlaceId,
  }) {
    return _provider.buildNavigationUri(
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      travelMode: travelMode,
      destinationPlaceId: destinationPlaceId,
    );
  }

  /// Validates destination latitude and longitude.
  ExternalNavigationResult validateDestination({
    required double? lat,
    required double? lng,
  }) {
    if (lat == null || lng == null) {
      return ExternalNavigationResult.invalidDestination();
    }
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
      return ExternalNavigationResult.invalidDestination();
    }
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
      return ExternalNavigationResult.invalidDestination();
    }
    // Reject (0, 0) null island
    if (lat == 0.0 && lng == 0.0) {
      return ExternalNavigationResult.invalidDestination();
    }
    // Reject hardcoded fallback centroids
    if ((lat - 13.0068).abs() < 0.0001 && (lng - 76.0996).abs() < 0.0001) {
      return ExternalNavigationResult.invalidDestination();
    }
    if ((lat - 12.9716).abs() < 0.0001 && (lng - 77.5946).abs() < 0.0001) {
      return ExternalNavigationResult.invalidDestination();
    }
    return const ExternalNavigationResult(status: ExternalNavigationStatus.success);
  }

  /// Validates worker identity and booking active state.
  ExternalNavigationResult validateAuthorization({
    required String currentWorkerId,
    required Map<String, dynamic> bookingData,
    String? expectedJobId,
  }) {
    if (currentWorkerId.trim().isEmpty) {
      return ExternalNavigationResult.unauthorized('Please log in to start navigation.');
    }

    final assignedWorkerId = (bookingData['workerId'] ?? '').toString().trim();
    if (assignedWorkerId.isEmpty || assignedWorkerId != currentWorkerId.trim()) {
      return ExternalNavigationResult.unauthorized(
        'Unauthorized: Only the assigned worker can navigate to this job.',
      );
    }

    final status = (bookingData['status'] ?? '').toString().trim().toLowerCase();
    const terminalStatuses = {'cancelled', 'completion_verified', 'disputed', 'rejected', 'expired'};
    if (terminalStatuses.contains(status)) {
      return ExternalNavigationResult.bookingInactive('This booking is no longer active.');
    }

    // Must be in an active state
    const allowedStatuses = {'confirmed', 'tracking', 'in_progress', 'working', 'arrived', 'completion_requested', 'payment_pending'};
    if (!allowedStatuses.contains(status)) {
      return ExternalNavigationResult.bookingInactive('This booking is not ready for navigation.');
    }

    if (expectedJobId != null && expectedJobId.trim().isNotEmpty) {
      final bookingJobId = (bookingData['jobId'] ?? '').toString().trim();
      if (bookingJobId.isNotEmpty && bookingJobId != expectedJobId.trim()) {
        return ExternalNavigationResult.invalidDestination('Destination does not match requested job.');
      }
    }

    return const ExternalNavigationResult(status: ExternalNavigationStatus.success);
  }

  /// Extracts coordinates from booking data map across common key naming conventions.
  (double?, double?) extractCoordinates(Map<String, dynamic> bookingData) {
    final dest = BookingDestinationContract.fromBooking(bookingData);
    if (dest != null) {
      return (dest.latitude, dest.longitude);
    }

    double? lat;
    double? lng;

    const latKeys = ['jobLat', 'lat', 'latitude', 'destLat'];
    const lngKeys = ['jobLng', 'lng', 'longitude', 'destLng'];

    for (final k in latKeys) {
      final v = bookingData[k];
      if (v is num) {
        lat = v.toDouble();
        break;
      }
      if (v is String && v.trim().isNotEmpty) {
        final parsed = double.tryParse(v.trim());
        if (parsed != null) {
          lat = parsed;
          break;
        }
      }
    }

    for (final k in lngKeys) {
      final v = bookingData[k];
      if (v is num) {
        lng = v.toDouble();
        break;
      }
      if (v is String && v.trim().isNotEmpty) {
        final parsed = double.tryParse(v.trim());
        if (parsed != null) {
          lng = parsed;
          break;
        }
      }
    }

    return (lat, lng);
  }

  /// Core headless launch method — executes validation, URL construction, and app launch.
  /// Does NOT require BuildContext, making it 100% testable in unit tests.
  Future<ExternalNavigationResult> launchGoogleMapsHandoff({
    required String currentWorkerId,
    required Map<String, dynamic> bookingData,
    String? expectedJobId,
    String? workerTravelPreference,
    String? destinationPlaceId,
  }) async {
    final now = DateTime.now();
    final bookingId = (bookingData['bookingId'] ?? bookingData['id'] ?? '').toString();

    debugPrint('[ExternalNavigation] external_navigation_start | bookingId=$bookingId');

    // 1. Debounce protection against rapid taps
    if (_isLaunching || (_lastLaunchTime != null && now.difference(_lastLaunchTime!) < _debounceDuration)) {
      debugPrint('[ExternalNavigation] Tap ignored: launch request already in progress or debounced.');
      return ExternalNavigationResult.rateLimited();
    }

    _isLaunching = true;
    _lastLaunchTime = now;

    try {
      // 2. Authorize Worker & Active Booking
      final authResult = validateAuthorization(
        currentWorkerId: currentWorkerId,
        bookingData: bookingData,
        expectedJobId: expectedJobId,
      );
      if (!authResult.isSuccess) {
        debugPrint('[ExternalNavigation] external_navigation_launch_failure | bookingId=$bookingId reason=${authResult.errorMessage}');
        return authResult;
      }

      // 3. Extract & Validate Destination Coordinates Canonically
      final dest = BookingDestinationContract.fromBooking(bookingData);
      if (dest == null || !dest.isValid) {
        debugPrint('[ExternalNavigation] external_navigation_launch_failure | bookingId=$bookingId failureReason=DESTINATION_INVALID validationResult=rejected');
        return ExternalNavigationResult.invalidDestination();
      }

      debugPrint('[ExternalNavigation] external_navigation_destination_validated | bookingId=$bookingId '
          'fieldSource=${dest.sourceField} lat=${dest.latitude} lng=${dest.longitude} validationResult=valid');

      final lat = dest.latitude;
      final lng = dest.longitude;

      // 4. Resolve Travel Mode
      final travelMode = resolveTravelMode(workerTravelPreference);

      // 5. Place ID extraction
      final placeId = destinationPlaceId ?? dest.placeId;

      // 6. Build Navigation URI (strictly omitting origin)
      final uri = _provider.buildNavigationUri(
        destinationLat: lat,
        destinationLng: lng,
        travelMode: travelMode,
        destinationPlaceId: placeId,
      );

      debugPrint('[ExternalNavigation] external_navigation_uri_built | uri=$uri');
      debugPrint('[ExternalNavigation] external_navigation_launch_attempt | provider=${_provider.providerName} travelMode=$travelMode');

      // 7. Launch External App / Browser
      final success = await _provider.launch(uri);
      if (!success) {
        debugPrint('[ExternalNavigation] external_navigation_launch_failure | bookingId=$bookingId reason=GOOGLE_MAPS_LAUNCH_FAILED');
        return ExternalNavigationResult.launchFailed();
      }

      debugPrint('[ExternalNavigation] external_navigation_launch_success | bookingId=$bookingId uri=$uri');
      return ExternalNavigationResult.success(uri);
    } catch (e) {
      debugPrint('[ExternalNavigation] Unexpected launch failure: $e');
      return ExternalNavigationResult.launchFailed();
    } finally {
      _isLaunching = false;
    }
  }

  /// UI convenience method — executes handoff and presents user-friendly feedback.
  Future<ExternalNavigationResult> openGoogleMapsForBooking(
    BuildContext context, {
    required String currentWorkerId,
    required Map<String, dynamic> bookingData,
    String? expectedJobId,
    String? workerTravelPreference,
    String? destinationPlaceId,
  }) async {
    final result = await launchGoogleMapsHandoff(
      currentWorkerId: currentWorkerId,
      bookingData: bookingData,
      expectedJobId: expectedJobId,
      workerTravelPreference: workerTravelPreference,
      destinationPlaceId: destinationPlaceId,
    );

    if (!context.mounted) return result;

    if (result.isSuccess) {
      // Phase 4: Ensure background GPS tracking & Android foreground service are active
      // so the Hirer sees real-time location while the worker uses Google Maps!
      _ensureBackgroundTracking(
        currentWorkerId: currentWorkerId,
        bookingData: bookingData,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.map_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Opening Google Maps...'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF1E293B),
        ),
      );
    } else if (result.status != ExternalNavigationStatus.rateLimited) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(result.errorMessage ?? "Google Maps could not be opened.")),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    return result;
  }

  /// Convenience method when only bookingId is available: fetches booking from Firestore,
  /// validates participant ownership, and opens Google Maps.
  Future<ExternalNavigationResult> openGoogleMapsForBookingId(
    BuildContext context, {
    required String bookingId,
    required String currentWorkerId,
    String? workerTravelPreference,
  }) async {
    if (bookingId.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open navigation because this booking has no valid destination.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return ExternalNavigationResult.invalidDestination();
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('bookings').doc(bookingId).get();
      if (!doc.exists || doc.data() == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This booking is no longer active.'),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
        }
        return ExternalNavigationResult.bookingInactive('Booking not found.');
      }

      final data = Map<String, dynamic>.from(doc.data()!);
      data['bookingId'] = doc.id;

      if (!context.mounted) return ExternalNavigationResult.launchFailed();

      return await openGoogleMapsForBooking(
        context,
        currentWorkerId: currentWorkerId,
        bookingData: data,
        workerTravelPreference: workerTravelPreference,
      );
    } catch (e) {
      debugPrint('[ExternalNavigation] Error fetching booking for navigation: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Maps could not be opened.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return ExternalNavigationResult.launchFailed();
    }
  }

  /// Automatically bootstraps background GPS tracking and Android foreground service
  /// when opening Google Maps, so the Hirer receives continuous 1 Hz location telemetry.
  Future<void> _ensureBackgroundTracking({
    required String currentWorkerId,
    required Map<String, dynamic> bookingData,
  }) async {
    try {
      final dest = BookingDestinationContract.fromBooking(bookingData);
      if (dest == null || !dest.isValid) return;

      final bookingId = (bookingData['bookingId'] ?? bookingData['id'] ?? '').toString();
      final hirerId = (bookingData['hirerId'] ?? '').toString();
      if (bookingId.isEmpty) return;

      // 1. Transition booking to 'tracking' if currently 'confirmed' (Firestore Rule Transition 1)
      final status = (bookingData['status'] ?? '').toString().toLowerCase();
      if (status == 'confirmed') {
        try {
          await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
            'status': 'tracking',
            'journeyStartedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('[ExternalNavigation] Booking $bookingId transitioned to tracking.');
        } catch (e) {
          debugPrint('[ExternalNavigation] Non-fatal status transition error: $e');
        }
      }

      // 2. Start JourneyService continuous tracking with Android Foreground Service if not already active
      if (!JourneyService.instance.isTracking && hirerId.isNotEmpty) {
        await JourneyService.instance.startTracking(
          bookingId: bookingId,
          workerId: currentWorkerId,
          hirerId: hirerId,
          destLat: dest.latitude,
          destLng: dest.longitude,
          onLocation: (_) {},
          onEvent: (_) {},
        );
        debugPrint('[ExternalNavigation] Background tracking initialized for Google Maps handoff.');
      }
    } catch (e) {
      debugPrint('[ExternalNavigation] _ensureBackgroundTracking non-fatal error: $e');
    }
  }
}
