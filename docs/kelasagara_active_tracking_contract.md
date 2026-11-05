# Kelasagara — Active Tracking Contract
**Phase 4B Hardened | Engine Version: 11**

---

## 1. Dual Realtime Architecture: Firestore vs RTDB

Kelasagara maintains a strict separation between low-frequency transactional metadata and high-frequency live tracking data:

| Dimension | Firestore (`bookings/{bookingId}`) | Realtime Database (`liveTracking/{bookingId}`) |
|---|---|---|
| **Data Type** | Booking state, destination coords, OTP, ratings | Ephemeral GPS coordinates, speed, heading, ETA |
| **Write Frequency** | On state transition only (low frequency, transactional) | Continuous 1–3 second intervals while navigating |
| **Persistence** | Permanent audit record | Ephemeral during active tracking |
| **Cost Profile** | Pay-per-document-write | Pay-per-bandwidth |

---

## 2. Realtime Database Path Authority

### Authoritative Participant Mapping
Before any tracking begins, the booking creation establishes participant mapping at:
```
trackingParticipants/{bookingId}/
  ├── hirerId:    "hirer_uid"
  ├── workerId:   "worker_uid"
  └── createdAt:  1727780000000
```
- **Write:** Restricted to the authorized hirer upon booking creation (`newData.child('hirerId').val() === auth.uid`).
- **Read:** Authorized participants only (`auth.uid === data.child('hirerId').val() || auth.uid === data.child('workerId').val()`).

### Live Telemetry Node
During transit, telemetry is streamed to:
```
liveTracking/{bookingId}/
  ├── lat:         12.9716,      // Latitude (India bounds)
  ├── lng:         77.5946,      // Longitude (India bounds)
  ├── speed:       4.2,          // m/s
  ├── heading:     180.0,        // degrees (0-360)
  ├── accuracy:    8.5,          // metres
  ├── etaSeconds:  450,          // seconds
  ├── remainingM:  2400.0,       // metres
  ├── seq:         142,          // Monotonic sequence counter
  ├── timestamp:   1727780450000,// Unix ms
  ├── workerId:    "worker_uid", // Must match trackingParticipants
  ├── hirerId:     "hirer_uid",  // Must match trackingParticipants
  └── jobId:       "job_123"     // Must match booking jobId
```

---

## 3. Strict Coordinate & Fallback Policy

- **No Hardcoded Hassan Fallback:** The previous fallback coordinates (`13.0060, 76.0954` - Hassan, Karnataka) have been completely removed from operational logic.
- **Null / Zero GPS Handling:**
  - If GPS fix cannot be obtained, functions return `null` or `0.0, 0.0`.
  - UI maps display a "GPS Unavailable" state or center on the regional default (Bengaluru: `12.9716, 77.5946`) strictly as a visual camera default with no operational search queries performed against it.
- **Bounding Box Validation:**
  - `lat` must be between `6.0` and `37.0`.
  - `lng` must be between `68.0` and `97.0`.
  - Coords outside India bounds or `(0.0, 0.0)` are rejected by RTDB rules.

---

## 4. Journey Lifecycle Management

- **Start:** `JourneyService.instance.startTracking(...)` initializes telemetry, validates destination, increments `_sessionToken`, and subscribes to GPS.
- **In-Transit:** Telemetry is written directly to `liveTracking/{bookingId}`.
- **Stop:** `JourneyService.instance.stopTracking()` cancels location streams, resets `_jobId = ''`, `_bookingId = ''`, and invalidates session tokens to discard any trailing in-flight GPS updates.
