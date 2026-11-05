# KELASAGARA V20.0 — WORKER BACKGROUND GPS & GOOGLE MAPS INTEGRATION REPORT

**Date:** 2026-10-25  
**Target Services:**  
- `lib/features/tracking/services/google_maps_navigation_launcher.dart`  
- `lib/features/tracking/services/worker_telemetry_service.dart`  
- `lib/screens/tracking/worker_journey_screen.dart`  
- `android/app/src/main/AndroidManifest.xml`  
**Automated Regression Test:** `test/v20_worker_gmaps_navigation_launcher_test.dart`

---

## 1. Objective

Enable workers to navigate using external Google Maps turn-by-turn navigation while Kelasagara continues streaming accurate GPS telemetry in the background, without termination by Android Doze mode, app switching, or OS memory pressure.

---

## 2. Implementation Architecture

### 2.1 Android Manifest & Intent Package Visibility
In `android/app/src/main/AndroidManifest.xml`:
- Foreground Service Type:
  ```xml
  <service
      android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
      android:foregroundServiceType="location"
      android:exported="false"/>
  ```
- Package Visibility for Android 11+ (API 30+):
  Added `google.navigation` and `com.google.android.apps.maps` to `<queries>` so that `canLaunchUrl(Uri.parse('google.navigation:...'))` evaluates to `true`:
  ```xml
  <queries>
      <intent>
          <action android:name="android.intent.action.VIEW"/>
          <data android:scheme="google.navigation"/>
      </intent>
      <package android:name="com.google.android.apps.maps"/>
  </queries>
  ```

### 2.2 Navigation Intent Orchestrator
In `lib/features/tracking/services/google_maps_navigation_launcher.dart`:
1. **Firestore State Transition:** Updates `bookings/{bookingId}` to `status: 'tracking'` and stamps `journeyStartedAt: FieldValue.serverTimestamp()`, conforming to Transition 1 of `firestore.rules`.
2. **Foreground Service Initialization:** Starts `WorkerTelemetryService` with ongoing notification:
   - Notification Title: `ಕೆಲಸಗಾರ ಲೈವ್ ಟ್ರ್ಯಾಕಿಂಗ್ • Live Journey Active`
   - Notification Text: `Sharing live road ETA with Hirer. Tap to return to journey.`
3. **External Google Maps Launch:**
   - Primary (Android): `google.navigation:q=$lat,$lng&mode=l` (Two-Wheeler mode, optimized for Indian city traffic and two-wheeler workers)
   - Fallback (iOS): `comgooglemaps://?daddr=$lat,$lng&directionsmode=two-wheeler`
   - Universal Web/App: `https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=two-wheeler&dir_action=navigate`

### 2.3 User Interface in WorkerJourneyScreen
In `lib/screens/tracking/worker_journey_screen.dart`:
- Added bilingual action buttons:
  - Primary button: **"Navigate to Work • ಕೆಲಸದ ಸ್ಥಳಕ್ಕೆ ಹೊರಡಿ"**
  - External navigation: **"Navigate with Google Maps • ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ 🗺"**
- Tapping either action ensures the background telemetry service is running before backgrounding the app.

---

## 3. Background Telemetry Resilience

1. **Battery Optimization Bypass:** `WorkerTelemetryService` prompts the worker once to whitelist Kelasagara from aggressive battery killer daemons (`requestIgnoreBatteryOptimization`).
2. **2D Kalman Filtering:** Reduces multipath GPS jitter and smooths coordinates (`KalmanLatLngFilter`).
3. **Adaptive Cadence:** 1.2s cadence when traveling > 0.8 m/s; 5s heartbeat when stationary.
4. **Offline Ring Buffer:** Queues up to 25 telemetry fixes in memory if network connectivity drops, flushing immediately upon RTDB re-connection.
5. **Server Disconnect Hook:** RTDB `.info/connected` sets `isOnline: false` atomically via `onDisconnect()` if connection terminates abruptly.
6. **Graceful Teardown:** When the worker reaches the work site and enters the Arrival OTP in `WorkerOtpVerificationSheet`, `stopTracking()` stops the foreground service cleanly.

---

## 4. Verification Evidence

Automated test `test/v20_worker_gmaps_navigation_launcher_test.dart` confirms:
1. `GoogleMapsTravelMode.twoWheeler` defines intent mode `'l'` and universal mode name `'two-wheeler'`.
2. Coordinate precision formatted to 6 decimal places: `google.navigation:q=12.971598,77.594562&mode=l`.
3. Universal deep-link construction with proper query parameter serialization.
