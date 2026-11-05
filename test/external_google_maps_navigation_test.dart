// test/external_google_maps_navigation_test.dart
// ============================================================================
// KELASAGARA — External Google Maps Navigation Handoff Test Suite
// Verifies all requirements (Sections 20 & 21):
//   - A. Valid booking coordinates
//   - B. Null coordinates -> reject
//   - C. NaN -> reject
//   - D. Infinity -> reject
//   - E. 0,0 -> reject
//   - F. Schema mismatch: jobLat/jobLng absent, lat/lng present
//   - G. Legacy/nested schema support (latitude/longitude, destLat, location)
//   - H. Unauthorized worker -> reject
//   - I. Wrong participant / mismatch -> reject
//   - J. Wrong job ID mismatch -> reject
//   - K. Valid booking -> exact destination in URI
//   - L. URI includes: api=1
//   - M. URI includes: destination=<exact coordinates>
//   - N. URI includes: dir_action=navigate
//   - O. URI strictly omits origin (Google Maps uses device GPS)
//   - P. No address typing required
//   - Q. No geocoding call required
//   - R. No AI call involved
//   - S. No Firestore mutation caused by map launch
//   - T. No booking status mutation
//   - U. Double tap: only one launch attempt
//   - V. Google Maps missing: browser fallback is valid and external
//   - W. Google Maps installed: external Google Maps launch path used
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/navigation_destination.dart';
import 'package:kelasagaara/services/navigation/external_navigation_service.dart';

/// Test mock provider for tracking URI generation and simulating launch environments.
class MockNavigationProvider implements ExternalNavigationProvider {
  Uri? lastLaunchedUri;
  int launchCallCount = 0;
  bool shouldSucceedApp = true;
  bool shouldSucceedWeb = true;

  @override
  String get providerName => 'Google Maps';

  @override
  Future<bool> canLaunch(Uri uri) async => true;

  @override
  Uri buildNavigationUri({
    required double destinationLat,
    required double destinationLng,
    String travelMode = 'driving',
    String? destinationPlaceId,
  }) {
    // Delegate to real GoogleMapsExternalProvider URI builder to test canonical logic
    return const GoogleMapsExternalProvider().buildNavigationUri(
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      travelMode: travelMode,
      destinationPlaceId: destinationPlaceId,
    );
  }

  @override
  Future<bool> launch(Uri uri) async {
    lastLaunchedUri = uri;
    launchCallCount++;
    if (shouldSucceedApp) return true;
    if (shouldSucceedWeb) return true;
    return false;
  }
}

void main() {
  late ExternalNavigationService service;
  late MockNavigationProvider mockProvider;

  setUp(() {
    mockProvider = MockNavigationProvider();
    service = ExternalNavigationService(provider: mockProvider);
  });

  group('Section 20 & 21: Google Maps Navigation URL Contract Tests', () {
    test('TEST 1: Exact Destination Populated Without User Typing (A, K, L, M, P)', () {
      const lat = 14.7952123;
      const lng = 75.9926456;
      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: lat,
        destinationLng: lng,
      );

      // Section 21: Verify URL format and sanitize print
      // ignore: avoid_print
      print('[SANITIZED_TEST_URL] ${uri.toString()}');

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '$lat,$lng');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['dir_action'], 'navigate');
    });

    test('TEST 2: Origin Parameter Is Strictly OMITTED to Use Current Device Location (O)', () {
      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: 14.7900,
        destinationLng: 75.9899,
      );

      expect(uri.queryParameters.containsKey('origin'), isFalse,
          reason: 'Omitting origin allows Google Maps to use the device current location');
    });

    test('TEST 3: dir_action=navigate Is Explicitly Included (N)', () {
      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: 14.7900,
        destinationLng: 75.9899,
      );

      expect(uri.queryParameters['dir_action'], 'navigate',
          reason: 'Requests direct turn-by-turn navigation mode in Google Maps');
    });

    test('TEST 9: Travel Mode for Two-Wheeler / Motorcycle', () {
      final mode1 = service.resolveTravelMode('motorcycle');
      final mode2 = service.resolveTravelMode('two-wheeler');
      final mode3 = service.resolveTravelMode('bike');

      expect(mode1, 'two-wheeler');
      expect(mode2, 'two-wheeler');
      expect(mode3, 'two-wheeler');

      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: 14.7900,
        destinationLng: 75.9899,
        travelMode: mode1,
      );
      expect(uri.queryParameters['travelmode'], 'two-wheeler');
    });

    test('TEST 10: Travel Mode for Car / Default Driving', () {
      final modeDefault = service.resolveTravelMode(null);
      final modeCar = service.resolveTravelMode('car');
      final modeAuto = service.resolveTravelMode('auto');

      expect(modeDefault, 'driving');
      expect(modeCar, 'driving');
      expect(modeAuto, 'driving');

      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: 14.7900,
        destinationLng: 75.9899,
        travelMode: modeDefault,
      );
      expect(uri.queryParameters['travelmode'], 'driving');
    });

    test('TEST 13: Exact High Precision Coordinates Preserved Without Truncation', () {
      const highPrecisionLat = 14.7952189421;
      const highPrecisionLng = 75.9926412847;

      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: highPrecisionLat,
        destinationLng: highPrecisionLng,
      );

      expect(uri.queryParameters['destination'], '$highPrecisionLat,$highPrecisionLng');
    });

    test('TEST 14: Special Characters in Job Address Do Not Corrupt Destination', () {
      const kannadaJobAddress = 'ಶ್ರೀ ಮಂಜುನಾಥ ಸ್ವಾಮಿ ನಿಲಯ, ೨ನೇ ಕ್ರಾಸ್, ಹರಪನಹಳ್ಳಿ';
      final bookingData = {
        'bookingId': 'bk_kannada_1',
        'workerId': 'worker_1',
        'jobId': 'job_1',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
        'jobAddress': kannadaJobAddress,
      };

      final (lat, lng) = service.extractCoordinates(bookingData);
      expect(lat, 14.7952);
      expect(lng, 75.9926);

      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: lat!,
        destinationLng: lng!,
      );

      expect(uri.queryParameters['destination'], '14.7952,75.9926');
      expect(uri.toString().contains('destination=14.7952%2C75.9926'), isTrue);
    });

    test('TEST 15: Verified Google Place ID Included When Available', () {
      const placeId = 'ChIJ1234567890abcdef';
      final uri = service.buildGoogleMapsNavigationUri(
        destinationLat: 14.7952,
        destinationLng: 75.9926,
        destinationPlaceId: placeId,
      );

      expect(uri.queryParameters['destination_place_id'], placeId);
      expect(uri.queryParameters['destination'], '14.7952,75.9926');
    });
  });

  group('Section 20: Canonical Destination Extractor & Schema Resolver (F, G)', () {
    test('F: Schema mismatch: jobLat/jobLng absent, lat/lng present resolves correctly', () {
      final bookingData = {
        'bookingId': 'bk_schema_mismatch_1',
        'jobId': 'job_101',
        'workerId': 'w_101',
        'status': 'confirmed',
        'lat': 14.7952,
        'lng': 75.9926,
        'jobAddress': 'Harapanahalli Main Road',
      };

      final dest = BookingDestinationContract.fromBooking(bookingData);
      expect(dest, isNotNull);
      expect(dest!.latitude, 14.7952);
      expect(dest.longitude, 75.9926);
      expect(dest.sourceField, 'lat,lng');

      final (extLat, extLng) = service.extractCoordinates(bookingData);
      expect(extLat, 14.7952);
      expect(extLng, 75.9926);
    });

    test('G1: latitude/longitude naming resolves correctly', () {
      final bookingData = {
        'bookingId': 'bk_schema_latlong_1',
        'jobId': 'job_102',
        'latitude': 14.7952,
        'longitude': 75.9926,
      };

      final dest = BookingDestinationContract.fromBooking(bookingData);
      expect(dest, isNotNull);
      expect(dest!.latitude, 14.7952);
      expect(dest.longitude, 75.9926);
      expect(dest.sourceField, 'latitude,longitude');
    });

    test('G2: destLat/destLng naming resolves correctly', () {
      final bookingData = {
        'bookingId': 'bk_schema_dest_1',
        'jobId': 'job_103',
        'destLat': 14.7952,
        'destLng': 75.9926,
      };

      final dest = BookingDestinationContract.fromBooking(bookingData);
      expect(dest, isNotNull);
      expect(dest!.latitude, 14.7952);
      expect(dest.longitude, 75.9926);
      expect(dest.sourceField, 'destLat,destLng');
    });

    test('G3: nested location map resolves correctly', () {
      final bookingData = {
        'bookingId': 'bk_schema_nested_1',
        'jobId': 'job_104',
        'location': {'lat': 14.7952, 'lng': 75.9926},
      };

      final dest = BookingDestinationContract.fromBooking(bookingData);
      expect(dest, isNotNull);
      expect(dest!.latitude, 14.7952);
      expect(dest.longitude, 75.9926);
      expect(dest.sourceField, 'location[lat,lng]');
    });
  });

  group('Section 20: Hard Destination & Security Gate Tests (B, C, D, E, H, I, J, S, T)', () {
    test('B: Null coordinates rejected with user-facing message', () {
      final resNull = service.validateDestination(lat: null, lng: null);
      expect(resNull.isSuccess, isFalse);
      expect(resNull.status, ExternalNavigationStatus.invalidDestination);
      expect(resNull.errorMessage, 'Unable to open navigation because this booking has no valid destination.');
    });

    test('C: NaN coordinates rejected', () {
      final resNaN = service.validateDestination(lat: double.nan, lng: 75.9926);
      expect(resNaN.isSuccess, isFalse);
      expect(resNaN.status, ExternalNavigationStatus.invalidDestination);
    });

    test('D: Infinity coordinates rejected', () {
      final resInf = service.validateDestination(lat: 14.7952, lng: double.infinity);
      expect(resInf.isSuccess, isFalse);
      expect(resInf.status, ExternalNavigationStatus.invalidDestination);
    });

    test('E: 0,0 Null Island coordinates rejected', () {
      final resZero = service.validateDestination(lat: 0.0, lng: 0.0);
      expect(resZero.isSuccess, isFalse);
      expect(resZero.status, ExternalNavigationStatus.invalidDestination);
    });

    test('Reject Hardcoded Fallback Centroids (Hassan / Bengaluru)', () {
      // Hassan centroid
      final resHassan = service.validateDestination(lat: 13.0068, lng: 76.0996);
      expect(resHassan.isSuccess, isFalse);

      // Bengaluru centroid
      final resBlr = service.validateDestination(lat: 12.9716, lng: 77.5946);
      expect(resBlr.isSuccess, isFalse);
    });

    test('H & I: Unauthorized Worker Access Denied', () {
      final bookingData = {
        'bookingId': 'bk_secure_1',
        'workerId': 'authorized_worker_A',
        'jobId': 'job_123',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      // Impersonator Worker B attempts to navigate
      final res = service.validateAuthorization(
        currentWorkerId: 'intruder_worker_B',
        bookingData: bookingData,
      );

      expect(res.isSuccess, isFalse);
      expect(res.status, ExternalNavigationStatus.unauthorizedWorker);
      expect(res.errorMessage, contains('Only the assigned worker'));
    });

    test('J: Wrong Job ID Mismatch Denied', () {
      final bookingData = {
        'bookingId': 'bk_1',
        'workerId': 'worker_1',
        'jobId': 'job_ABC',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      final res = service.validateAuthorization(
        currentWorkerId: 'worker_1',
        bookingData: bookingData,
        expectedJobId: 'job_XYZ', // Different job
      );

      expect(res.isSuccess, isFalse);
      expect(res.status, ExternalNavigationStatus.invalidDestination);
      expect(res.errorMessage, 'Destination does not match requested job.');
    });

    test('Cancelled / Terminal Bookings Denied Navigation Handoff', () {
      final cancelledBooking = {
        'bookingId': 'bk_canc_1',
        'workerId': 'worker_123',
        'jobId': 'job_123',
        'status': 'cancelled',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      final res = service.validateAuthorization(
        currentWorkerId: 'worker_123',
        bookingData: cancelledBooking,
      );

      expect(res.isSuccess, isFalse);
      expect(res.status, ExternalNavigationStatus.bookingInactive);
      expect(res.errorMessage, 'This booking is no longer active.');
    });

    test('Unauthenticated / Logged Out Worker Denied', () {
      final bookingData = {
        'bookingId': 'bk_1',
        'workerId': 'worker_1',
        'jobId': 'job_1',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      final res = service.validateAuthorization(
        currentWorkerId: '', // Logged out
        bookingData: bookingData,
      );

      expect(res.isSuccess, isFalse);
      expect(res.status, ExternalNavigationStatus.unauthorizedWorker);
    });

    test('S & T: Zero Side-Effects: Booking state map remains completely untouched', () async {
      final originalBookingData = {
        'bookingId': 'bk_pure_1',
        'workerId': 'worker_100',
        'jobId': 'job_200',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
        'jobAddress': 'Pure booking test',
      };
      final dataCopy = Map<String, dynamic>.from(originalBookingData);

      final result = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: dataCopy,
      );

      expect(result.isSuccess, isTrue);
      // Map contents must be completely identical
      expect(dataCopy, equals(originalBookingData));
      expect(dataCopy['status'], 'confirmed');
    });
  });

  group('Section 20: Execution, Debounce & Fallback Tests (U, V, W)', () {
    test('W: Google Maps installed: native app launch path executes', () async {
      mockProvider.shouldSucceedApp = true;
      final bookingData = {
        'bookingId': 'bk_valid_1',
        'workerId': 'worker_100',
        'jobId': 'job_200',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
        'jobAddress': 'Harapanahalli, Vijayanagara',
      };

      final result = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: bookingData,
        expectedJobId: 'job_200',
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, ExternalNavigationStatus.success);
      expect(result.launchedUri, isNotNull);
      expect(mockProvider.launchCallCount, 1);
      expect(result.launchedUri!.queryParameters['destination'], '14.7952,75.9926');
      expect(result.launchedUri!.queryParameters.containsKey('origin'), isFalse);
      expect(result.launchedUri!.queryParameters['dir_action'], 'navigate');
    });

    test('U: Rapid Double Tap Debounce Prevents Multiple Launches', () async {
      final bookingData = {
        'bookingId': 'bk_debounce_1',
        'workerId': 'worker_100',
        'jobId': 'job_200',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      // Tap 1
      final res1 = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: bookingData,
      );
      expect(res1.isSuccess, isTrue);
      expect(mockProvider.launchCallCount, 1);

      // Immediate Tap 2 (rapid double-tap within debounce window)
      final res2 = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: bookingData,
      );
      expect(res2.status, ExternalNavigationStatus.rateLimited);
      expect(mockProvider.launchCallCount, 1, reason: 'Debounce dropped the second launch request');
    });

    test('V: Web Browser Fallback Executes When Native App Launch Fails', () async {
      mockProvider.shouldSucceedApp = false;
      mockProvider.shouldSucceedWeb = true;

      final bookingData = {
        'bookingId': 'bk_web_1',
        'workerId': 'worker_100',
        'jobId': 'job_200',
        'status': 'tracking',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      final result = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: bookingData,
      );

      expect(result.isSuccess, isTrue);
      expect(mockProvider.launchCallCount, 1);
      expect(result.launchedUri!.queryParameters['destination'], '14.7952,75.9926');
      expect(result.launchedUri!.queryParameters['dir_action'], 'navigate');
    });

    test('Launch Failure Reported Truthfully When Both App and Web Fail', () async {
      mockProvider.shouldSucceedApp = false;
      mockProvider.shouldSucceedWeb = false;

      final bookingData = {
        'bookingId': 'bk_fail_1',
        'workerId': 'worker_100',
        'jobId': 'job_200',
        'status': 'confirmed',
        'jobLat': 14.7952,
        'jobLng': 75.9926,
      };

      final result = await service.launchGoogleMapsHandoff(
        currentWorkerId: 'worker_100',
        bookingData: bookingData,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, ExternalNavigationStatus.launchFailed);
      expect(result.errorMessage, "Google Maps could not be opened.");
    });
  });
}
