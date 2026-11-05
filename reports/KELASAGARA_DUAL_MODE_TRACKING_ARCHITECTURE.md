# KELASAGARA V20.0 — DUAL-MODE TRACKING ARCHITECTURE

**Date:** 2026-10-25  
**Baseline Git Commit:** `9eebb98`  
**Milestone:** V20.0 Delivery-Style Live Worker Tracking  
**Author:** Google Antigravity (Gemini 3.8 Flash High)

---

## 1. Executive Summary

Kelasagara V20.0 implements an enterprise dual-mode live worker navigation and tracking system inspired by tier-1 e-commerce and delivery applications (e.g., Swiggy, Uber, Urban Company). It seamlessly reconciles two asymmetrical navigation environments:
1. **Mode A (Worker Navigation):** Native Android external Google Maps turn-by-turn navigation running concurrently with a continuous, battery-optimized Android foreground service (`flutter_foreground_task`) streaming high-precision 1Hz-cadence GPS telemetry to Firebase Realtime Database and Cloud Firestore.
2. **Mode B (Hirer In-App Tracking):** An OpenStreetMap-powered live tracking interface built on `flutter_map` with 60fps Hermite-spline kinematics, dynamic OSM road-locking, Valhalla shadow routing, and resilient map tile delivery that completely eliminates unauthenticated CARTO watermarks.

---

## 2. Dual-Mode Architecture & Component Topology

```
   ┌─────────────────────────────────────────────────────────────┐
   │                   MODE A: WORKER DEVICE                     │
   │                                                             │
   │   ┌────────────────────────┐      ┌─────────────────────┐   │
   │   │  WorkerJourneyScreen   │      │ External Google Maps│   │
   │   │  (Job Address / PIN)   │      │ (Turn-by-turn Nav)  │   │
   │   └───────────┬────────────┘      └──────────▲──────────┘   │
   │               │ "Navigate to Work"           │ Intent       │
   │               ▼                              │ Launch       │
   │   ┌──────────────────────────────────────────┴──────────┐   │
   │   │         GoogleMapsNavigationLauncher                │   │
   │   └──────────────────────┬──────────────────────────────┘   │
   │                          │ Transitions Status: 'tracking'   │
   │                          ▼                                  │
   │   ┌─────────────────────────────────────────────────────┐   │
   │   │      WorkerTelemetryService / Foreground Service     │   │
   │   │      (Android foregroundServiceType="location")     │   │
   │   │      • 2D Kalman Filter                             │   │
   │   │      • 5-Point Rolling Micro-Trail                  │   │
   │   │      • Offline Ring Buffer (25 fixes)               │   │
   │   └──────────────────────┬──────────────────────────────┘   │
   └──────────────────────────┼──────────────────────────────────┘
                              │ 1Hz Secure Broadcast
                              ▼
   ┌─────────────────────────────────────────────────────────────┐
   │             FIREBASE INFRASTRUCTURE CLOUD BUS               │
   │                                                             │
   │   • Realtime Database: liveTracking/{bookingId}             │
   │   • Cloud Firestore:   bookings/{bookingId}                 │
   │     - status: 'confirmed' -> 'tracking' -> 'arrived'        │
   │     - arrivalOtp: 4-digit code (Hirer -> Worker gate)       │
   └──────────────────────────┬──────────────────────────────────┘
                              │ Realtime Reactive Stream
                              ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                   MODE B: HIRER DEVICE                      │
   │                                                             │
   │   ┌─────────────────────────────────────────────────────┐   │
   │   │         HirerOsmTrackingController                  │   │
   │   │   • Anti-Premature Arrival Protection               │   │
   │   │   • Adaptive Valhalla OSM Shadow Routing            │   │
   │   │   • Hermite Spline 60fps Interpolator               │   │
   │   │   • Signal Freshness Monitor (15s/45s/stale)        │   │
   │   └──────────────────────┬──────────────────────────────┘   │
   │                          │ Animated State Model             │
   │                          ▼                                  │
   │   ┌─────────────────────────────────────────────────────┐   │
   │   │            HirerTrackingScreen                      │   │
   │   │   • Resilient OSM Standard Tiles (No Watermark)     │   │
   │   │   • © OpenStreetMap contributors Attribution        │   │
   │   │   • Live ETA Header Card (Kannada / English)        │   │
   │   │   • Tracking Bottom Sheet (4-Digit Arrival OTP)     │   │
   │   └─────────────────────────────────────────────────────┘   │
   └─────────────────────────────────────────────────────────────┘
```

---

## 3. Data Flow & Booking Lifecycle Progression

The tracking lifecycle follows a 5-stage formal state machine:

| Stage | Firestore `status` | RTDB `status` | Hirer Header Badge | Arrival OTP State |
| :--- | :--- | :--- | :--- | :--- |
| **1. Preparing** | `confirmed` | `isSeed: true` | `WAITING FOR WORKER • ಕಾಯಲಾಗುತ್ತಿದೆ` | Generated & displayed to Hirer (`[4] [8] [2] [1]`) |
| **2. En Route** | `tracking` | `on_the_way` | `LIVE GPS • ನೇರ ಸಂಪರ್ಕ` | Displayed to Hirer with copy button |
| **3. Arriving Soon**| `tracking` | `approaching` | `ಹತ್ತಿರದಲ್ಲಿದ್ದಾರೆ • Arriving at doorstep` | Displayed to Hirer |
| **4. Arrived** | `arrived` | `arrived` | `ತಲುಪಿದ್ದಾರೆ • Worker has arrived!` | Worker inputs OTP into `WorkerOtpVerificationSheet` |
| **5. Working** | `in_progress` | Disconnected | `ಕೆಲಸ ಪ್ರಗತಿಯಲ್ಲಿದೆ • Work in progress` | Verified atomically; telemetry service stops |

---

## 4. Key Invariants & Safeguards

1. **No Spoofed or Simulated Locations:** Neither client nor server fabricates fake GPS fixes. All positions derive from genuine Android location providers.
2. **Anti-Premature Arrival:** If worker telemetry has not started, worker position is never defaulted to destination coordinates, and distance is rendered honestly as `--` rather than `0 m`.
3. **Tile Autonomy:** Map tile availability is completely decoupled from GPS connectivity; network disruptions to tiles do not impact telemetry streaming, and vice versa.
4. **Attribution Integrity:** OpenStreetMap legal copyright notice is rendered via `RichAttributionWidget` with interactive external link.
