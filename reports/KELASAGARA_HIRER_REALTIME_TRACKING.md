# KELASAGARA V20.0 — HIRER REAL-TIME TRACKING & ANTI-PREMATURE ARRIVAL AUDIT

**Date:** 2026-10-25  
**Target Controllers & Presentation:**  
- `lib/features/tracking/controllers/hirer_osm_tracking_controller.dart`  
- `lib/features/tracking/data/models/tracking_state_model.dart`  
- `lib/features/tracking/presentation/widgets/live_eta_header_card.dart`  
- `lib/features/tracking/presentation/widgets/tracking_bottom_sheet.dart`  
**Automated Regression Test:** `test/v20_tracking_lifecycle_anti_premature_arrival_test.dart`

---

## 1. Root-Cause Analysis of Premature "Arrived — 0 m" Bug

### 1.1 The Failure Symptoms in User Screenshots
In `media_1792900499800_de7d4c3a.jpg` and `media_1792900499800_49acfafe.jpg`:
1. Top header card displayed: `ತಲುಪಿದ್ದಾರೆ • Worker has arrived!`
2. Top right green pill showed: `Arrived 0 m`
3. Status badge erratically flipped between `SIGNAL DELAYED • ತಡವಾಗುತ್ತಿದೆ` and `LIVE GPS • ನೇರ ಸಂಪರ್ಕ`
4. Bottom sheet OTP card displayed empty dashes: `[-][-][-][-]`

### 1.2 The Underlying Code Flaws
1. **Origin Fallback Flaw:** In `HirerOsmTrackingController._bootstrapInitialWaterfall()`:
   ```dart
   final resolvedStart = origin ?? dest;
   ```
   When the worker had not yet transmitted active GPS telemetry (`origin == null`), `resolvedStart` fell back to `dest` (the Hirer's destination coordinates).
2. **0-Meter Routing:** Recomputing the Valhalla route with `workerPos == dest` returned a distance of `0.0 m` and `eta = 0`.
3. **Flawed ETA Getter:** In `TrackingStateModel`:
   ```dart
   if (phase == JourneyLifecyclePhase.arrivedAtGate ||
       phase == JourneyLifecyclePhase.inProgress ||
       remainingDistanceMeters <= 35) {
     return 'Arrived';
   }
   ```
   Because `remainingDistanceMeters` was `0.0`, `remainingDistanceMeters <= 35` evaluated to `true`, forcing `formattedEta` to `'Arrived'` and `formattedDistance` to `'0 m'`, even when `phase == JourneyLifecyclePhase.accepted`!
4. **Seed Fix Premature Gate Transition:** In `_processIncomingWorkerFix`:
   ```dart
   if (fix.status == 'arrived' || shadow.remainingRoadDistanceMeters <= 35.0) {
     phase = JourneyLifecyclePhase.arrivedAtGate;
   }
   ```
   A static initial seed fix with 0m distance immediately converted the phase to `arrivedAtGate`.
5. **Freshness Flap:** The freshness monitor threshold was set to `age <= 10s` for live, and `age <= 20s` for dead reckoning. Normal mobile network variance (11–15s) caused rapid flapping to `SIGNAL DELAYED` and back.
6. **Missing OTP Field:** When a legacy booking had an empty or null `arrivalOtp` field, `TrackingBottomSheet` padded empty string with dashes, displaying `[-][-][-][-]`.

---

## 2. Comprehensive Architectural Fixes

### 2.1 Guarded Distance & ETA Getters in TrackingStateModel
In `lib/features/tracking/data/models/tracking_state_model.dart`:
```dart
String get formattedDistance {
  if (phase == JourneyLifecyclePhase.accepted || remainingDistanceMeters <= 0.0) {
    return '--';
  }
  if (remainingDistanceMeters < 1000) {
    return '${remainingDistanceMeters.round()} m';
  }
  return '${(remainingDistanceMeters / 1000.0).toStringAsFixed(1)} km';
}

String get formattedEta {
  if (phase == JourneyLifecyclePhase.inProgress) {
    return 'In Progress';
  }
  if (phase == JourneyLifecyclePhase.arrivedAtGate) {
    return 'Arrived';
  }
  if (phase == JourneyLifecyclePhase.accepted) {
    return 'Preparing';
  }
  if (etaMinutes <= 1) return '1 min';
  return '$etaMinutes mins';
}
```

### 2.2 Marker Separation (`hasActiveWorkerPosition`)
Added `hasActiveWorkerPosition` getter. If `phase == JourneyLifecyclePhase.accepted` and the worker coordinates match the destination within floating-point tolerance, the worker marker is suppressed so that the worker icon does not sit directly on top of the home destination marker.

### 2.3 Waterfall Bootstrap Hardening
In `HirerOsmTrackingController._bootstrapInitialWaterfall()`:
- Extracted locations from multiple booking keys (`jobLocation`, `location`, `hirerLocation`, `jobLat`/`jobLng`).
- If `origin == null` or `origin == dest`, the controller does NOT compute a 0m route. It preserves `phase = JourneyLifecyclePhase.accepted`, `remainingDistanceMeters = 0.0`, and `freshness = SignalFreshness.weakGps`.
- Self-heals missing `arrivalOtp`: generates a genuine 4-digit code and persists it to Firestore `bookings/{bookingId}` under Branch 9 permissions.

### 2.4 State Machine Gate Transition Guards
In `_processIncomingWorkerFix`:
- Prohibits seed fixes (`fix.isSeed == true`) from triggering `arrivedAtGate` or `arrivingSoon`.
- Requires `shadow.remainingRoadDistanceMeters > 0` AND `phase != JourneyLifecyclePhase.accepted` before allowing distance-based threshold transitions.

### 2.5 Hysteresis Freshness Monitoring
Updated `_startFreshnessMonitor()`:
- `age <= 15s`: `SignalFreshness.live`
- `15s < age <= 45s`: `SignalFreshness.deadReckoning`
- `age > 45s`: `SignalFreshness.delayed`
- When waiting for worker: displays calm slate badge `WAITING FOR WORKER • ಕಾಯಲಾಗುತ್ತಿದೆ` instead of alarming red warnings.

---

## 3. Verification Evidence

Automated test suite `test/v20_tracking_lifecycle_anti_premature_arrival_test.dart` passes 7 tests verifying:
1. `formattedDistance == '--'` and `formattedEta == 'Preparing'` when `remainingDistanceMeters == 0.0` and `phase == accepted`.
2. `hasActiveWorkerPosition == false` when accepted worker coordinates match destination.
3. Correct kilometer and meter formatting during active `enRoute` phase.
4. Accurate transition to `Arrived` only at `arrivedAtGate` phase.
5. In-progress phase reporting `In Progress`.
6. 4-digit OTP integrity.
