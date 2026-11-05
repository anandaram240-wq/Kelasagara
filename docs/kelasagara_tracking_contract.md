# Kelasagara — Tracking Contract
**Phase 1 | Generated:** 2026-09-30

## RTDB Live Tracking Path

```
tracking/{workerId}/{bookingId}/
  ├── lat         double   WGS84 latitude
  ├── lng         double   WGS84 longitude
  ├── speed       double   m/s (from Geolocator.Position.speed)
  ├── heading     double   degrees (0–360)
  ├── accuracy    double   meters
  ├── etaSeconds  int      seconds remaining to destination
  ├── remainingM  double   meters remaining
  ├── seq         int      monotonic sequence number (prevents replay)
  └── timestamp   int      Unix milliseconds
```

**Write authority:** Worker only (`uid == workerId`, enforced by database.rules.json)
**Read authority:** Worker OR Hirer who owns this booking

## Firestore Booking Coordinate Contract

| Field | Type | Authority | Notes |
|---|---|---|---|
| jobLat | double | hirer (create only) | Job destination latitude |
| jobLng | double | hirer (create only) | Job destination longitude |
| destLat | double | alias for jobLat | Used in some legacy screens |
| destLng | double | alias for jobLng | Used in some legacy screens |

**Valid range:** lat [6.0, 37.0], lng [68.0, 97.0] (India bounding box)
**Invalid:** (0.0, 0.0), NaN, Infinite

## DEF-010 Resolution: HirerTrackingScreen Field Confusion

**Previous bug:**
```dart
WorkCompletionScreen(
  jobId:   widget.bookingId,  // WRONG — bookingId ≠ jobId
  skillId: 'general',         // WRONG — hardcoded
)
```

**Fixed:** `HirerTrackingScreen` now carries `jobId` and `workerId` as explicit constructor fields.

`JourneyNavigator.openHirer()` reads these from the booking document:
```dart
final jobId    = booking['jobId']    as String? ?? '';
final workerId = booking['workerId'] as String? ?? '';
```

`WorkCompletionScreen` now receives the correct `jobId`. `skillId: 'general'` remains as a safe default — Phase 2 should pass the actual skillId from the booking document.

## GPS Quality Engine

GPS fixes are classified before being written to RTDB or used for routing.

| Classification | Condition | Usable | Quality Score |
|---|---|---|---|
| INVALID | accuracy > 100m OR (0,0) OR NaN/Infinite | No | 0.0 |
| MOCK_SUSPECTED | `isMocked == true` | No | 0.0 |
| GPS_JUMP | implied speed > 200 km/h since last fix | No | 0.0 |
| DUPLICATE | same coords within 500ms of prior fix | No | 0.0 |
| LOW_ACCURACY | accuracy 50–100m | No | 0.3 |
| STALE | age > 15s | Yes (warning) | 0.4 |
| GOOD | accuracy 15–50m, age < 15s | Yes | 0.8 |
| LIVE | accuracy < 15m, age < 3s | Yes | 1.0 |

Bad GPS fixes are rejected before:
- Writing to RTDB
- Sending to Valhalla/OSRM for routing
- Triggering off-route detection
- Triggering arrival detection

## Off-Route Detection State Machine

```
ON_ROUTE
  └─► SUSPECTED_OFF_ROUTE   (distance > 50m from nearest polyline point)
        ├─► ON_ROUTE         (false alarm — distance drops below 30m)
        └─► CONFIRMED_OFF_ROUTE  (>80m for 6 consecutive ticks)
              └─► REROUTING  (new route request sent)
                    ├─► BACK_ON_ROUTE    (new route accepted, distance < 30m)
                    └─► CONFIRMED_OFF_ROUTE  (reroute failed, try again)
```

Max reroute attempts: 3. After 3 failures, show manual navigation fallback message.

## Navigation Engine — Camera Conflict Prevention

The map camera is controlled programmatically during navigation. User panning is temporarily blocked (AbsorbPointer) while the engine is moving the camera. This prevents the Flutter map `move()` feedback loop where a programmatic camera move triggers `onPositionChanged`, which triggers another move.

Camera control is released when:
- User explicitly taps the "re-center" button
- Navigation ends (arrived or cancelled)
