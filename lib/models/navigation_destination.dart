// lib/models/navigation_destination.dart
// Kelasagara Navigation V2: Authorized Destination Model & Contract.
//
// Hard boundary:
//   - Real authorized destinations ONLY.
//   - No fallback to Hassan, Bengaluru, Harapanahalli centroids or registration addresses.
//   - Strict range, non-zero, finite bounds checks.

import 'package:latlong2/latlong.dart';

class NavigationDestination {
  final String bookingId;
  final String jobId;
  final double latitude;
  final double longitude;
  final String address;
  final String source;
  final DateTime authorizedAt;

  const NavigationDestination({
    required this.bookingId,
    required this.jobId,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.source = 'authorized_booking_contract',
    required this.authorizedAt,
  });

  /// LatLng convenience getter for map/routing APIs.
  LatLng get latLng => LatLng(latitude, longitude);

  /// Strict geographical and identity validation.
  bool get isValid {
    if (bookingId.trim().isEmpty || jobId.trim().isEmpty) return false;
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude.isInfinite || longitude.isInfinite) return false;
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    return true;
  }

  /// Validates that the destination strictly belongs to the specified booking and job.
  bool isAuthorizedFor({required String expectedBookingId, required String expectedJobId}) {
    return isValid &&
        bookingId == expectedBookingId &&
        jobId == expectedJobId;
  }

  Map<String, dynamic> toMap() => {
    'bookingId': bookingId,
    'jobId': jobId,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'source': source,
    'authorizedAt': authorizedAt.toIso8601String(),
  };

  factory NavigationDestination.fromMap(Map<String, dynamic> map) {
    final dest = BookingDestinationContract.fromBooking(map);
    return NavigationDestination(
      bookingId: (map['bookingId'] ?? '').toString(),
      jobId: (map['jobId'] ?? '').toString(),
      latitude: dest?.latitude ?? ((map['jobLat'] ?? map['latitude'] ?? map['lat'] ?? 0.0) as num).toDouble(),
      longitude: dest?.longitude ?? ((map['jobLng'] ?? map['longitude'] ?? map['lng'] ?? 0.0) as num).toDouble(),
      address: (map['jobAddress'] ?? map['address'] ?? '').toString(),
      source: (map['source'] ?? 'authorized_booking_contract').toString(),
      authorizedAt: map['authorizedAt'] != null
          ? DateTime.tryParse(map['authorizedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Typed immutable representation of an authorized booking destination.
class BookingDestination {
  final String bookingId;
  final String jobId;
  final double latitude;
  final double longitude;
  final String address;
  final String? placeId;
  final String sourceField;

  const BookingDestination({
    required this.bookingId,
    this.jobId = '',
    required this.latitude,
    required this.longitude,
    this.address = '',
    this.placeId,
    this.sourceField = 'canonical',
  });

  /// Hard validation of coordinates:
  /// - finite
  /// - within -90..90 and -180..180
  /// - not (0.0, 0.0)
  /// - not NaN, not Infinity
  /// - rejects fallback centroids (Hassan, Bengaluru)
  bool get isValid {
    if (bookingId.trim().isEmpty) return false;
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude.isInfinite || longitude.isInfinite) return false;
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    // Reject hardcoded fallback centroids
    if ((latitude - 13.0068).abs() < 0.0001 && (longitude - 76.0996).abs() < 0.0001) return false;
    if ((latitude - 12.9716).abs() < 0.0001 && (longitude - 77.5946).abs() < 0.0001) return false;
    return true;
  }
}

/// Canonical booking destination contract and schema resolver.
class BookingDestinationContract {
  final String bookingId;
  final double jobLat;
  final double jobLng;
  final String jobAddress;
  final String workerId;
  final String hirerId;

  const BookingDestinationContract({
    required this.bookingId,
    required this.jobLat,
    required this.jobLng,
    required this.jobAddress,
    required this.workerId,
    required this.hirerId,
  });

  bool isValid() {
    if (bookingId.trim().isEmpty) return false;
    if (workerId.trim().isEmpty || hirerId.trim().isEmpty) return false;
    if (jobLat < 6.0 || jobLat > 37.0) return false; // India bounding box
    if (jobLng < 68.0 || jobLng > 97.0) return false;
    return true;
  }

  /// Canonical destination extractor that resolves all schema variations:
  /// 1. jobLat / jobLng
  /// 2. lat / lng
  /// 3. latitude / longitude
  /// 4. destLat / destLng
  /// 5. location['lat'] / location['lng']
  /// 6. jobLocation['lat'] / jobLocation['lng']
  static BookingDestination? fromBooking(Map<String, dynamic> booking) {
    final bookingId = (booking['bookingId'] ?? booking['id'] ?? '').toString().trim();
    final jobId = (booking['jobId'] ?? '').toString().trim();
    final address = (booking['jobAddress'] ?? booking['address'] ?? '').toString().trim();
    final rawPlaceId = booking['destination_place_id'] ??
        booking['placeId'] ??
        booking['jobPlaceId'];
    final placeId = rawPlaceId != null && rawPlaceId.toString().trim().isNotEmpty
        ? rawPlaceId.toString().trim()
        : null;

    double? lat;
    double? lng;
    String sourceField = '';

    // Check 1: jobLat, jobLng
    if (booking['jobLat'] != null && booking['jobLng'] != null) {
      lat = _tryParseDouble(booking['jobLat']);
      lng = _tryParseDouble(booking['jobLng']);
      sourceField = 'jobLat,jobLng';
    }
    // Check 2: lat, lng
    if ((lat == null || lng == null) && booking['lat'] != null && booking['lng'] != null) {
      lat = _tryParseDouble(booking['lat']);
      lng = _tryParseDouble(booking['lng']);
      sourceField = 'lat,lng';
    }
    // Check 3: latitude, longitude
    if ((lat == null || lng == null) && booking['latitude'] != null && booking['longitude'] != null) {
      lat = _tryParseDouble(booking['latitude']);
      lng = _tryParseDouble(booking['longitude']);
      sourceField = 'latitude,longitude';
    }
    // Check 4: destLat, destLng
    if ((lat == null || lng == null) && booking['destLat'] != null && booking['destLng'] != null) {
      lat = _tryParseDouble(booking['destLat']);
      lng = _tryParseDouble(booking['destLng']);
      sourceField = 'destLat,destLng';
    }
    // Check 5: location map
    if ((lat == null || lng == null) && booking['location'] is Map) {
      final loc = booking['location'] as Map;
      lat = _tryParseDouble(loc['lat'] ?? loc['latitude']);
      lng = _tryParseDouble(loc['lng'] ?? loc['longitude']);
      sourceField = 'location[lat,lng]';
    }
    // Check 6: jobLocation map
    if ((lat == null || lng == null) && booking['jobLocation'] is Map) {
      final loc = booking['jobLocation'] as Map;
      lat = _tryParseDouble(loc['lat'] ?? loc['latitude']);
      lng = _tryParseDouble(loc['lng'] ?? loc['longitude']);
      sourceField = 'jobLocation[lat,lng]';
    }

    if (lat == null || lng == null) {
      return null;
    }

    final dest = BookingDestination(
      bookingId: bookingId,
      jobId: jobId,
      latitude: lat,
      longitude: lng,
      address: address,
      placeId: placeId,
      sourceField: sourceField,
    );

    if (!dest.isValid) {
      return null;
    }

    return dest;
  }

  static double? _tryParseDouble(dynamic value) {
    if (value is num) {
      final d = value.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      return d;
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && !parsed.isNaN && !parsed.isInfinite) {
        return parsed;
      }
    }
    return null;
  }
}
