import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Timer? _trackingTimer;

  static Future<bool> requestPermission() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
    } catch (_) { return false; }
  }

  static Future<Position?> getLastKnownPosition() async {
    try {
      final granted = await requestPermission();
      if (!granted) return null;
      return await Geolocator.getLastKnownPosition();
    } catch (_) { return null; }
  }

  static Future<Position?> getFastPosition() async {
    try {
      final last = await getLastKnownPosition();
      if (last != null) return last;
      return await getCurrentPosition();
    } catch (_) { return null; }
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      final granted = await requestPermission();
      if (!granted) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) { return null; }
  }

  // V600 FIX: startTrackingBooking() is ELIMINATED.
  // It used Timer.periodic + getCurrentPosition — the worst GPS pattern.
  // This was the 3rd concurrent GPS consumer alongside JourneyService and
  // NavigationEngine, causing battery drain and GPS lock contention.
  //
  // Use JourneyService.instance.startTracking() instead.
  @Deprecated('Use JourneyService.instance.startTracking(). '
      'This method caused a 3-way GPS consumer race. '
      'Will be removed in V700.')
  static void startTrackingBooking(String bookingId) {
    assert(false,
        '[LocationService] startTrackingBooking() is disabled. '
        'Use JourneyService.instance.startTracking() instead.');
  }

  static void stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  static double calculateDistanceKm(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  static int calculateETA(double distanceKm) {
    return (distanceKm / 30 * 60).ceil(); // 30 kmph city speed
  }
}
