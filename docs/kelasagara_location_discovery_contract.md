# Kelasagara Location Discovery Contract

## The Four Location Concepts
1. **Profile Location**: The district/taluk selected by the user during onboarding. Static until explicitly changed. Used for billing, generic filtering, and manual area search.
2. **Service Area**: The geographical boundary (radius) around the worker within which they are willing to accept jobs. Stored as `serviceRadiusKm`.
3. **Discovery Location**: The exact GPS coordinates of the worker when they set themselves to "available". Stored as `discoveryLat` and `discoveryLng`.
4. **Active Job Location**: The live tracking coordinates sent directly to RTDB when a job is accepted. Separate from discovery fields.

## Discovery Location Spec
- Fields in `UserProfile`:
  - `discoveryLat` (double?)
  - `discoveryLng` (double?)
  - `discoveryUpdatedAt` (DateTime?)
  - `discoverySessionId` (String)
  - `discoveryAccuracy` (double)
  - `serviceRadiusKm` (int, default 15)
- All fields are null/empty by default until the worker explicitly goes online.

## Freshness Thresholds
- **FRESH (< 10min)**: The worker's device has actively updated its location very recently. Highly reliable.
- **RECENT (< 30min)**: The worker's location is a bit older but still considered viable.
- **STALE (>= 30min)**: The location has not been updated for a long time. The worker will be hidden from search results.
*Rationale*: This protects the system from showing ghost workers who closed the app without properly logging off.

## GPS Policy
- **distanceFilter**: 50 meters. Prevents spamming Firestore with tiny fluctuations.
- **heartbeat**: 10 minutes. Ensures the location stays FRESH even if the worker is stationary.
- **accuracy**: Rejections for >100m accuracy. 
- **No per-tick writes**: We batch and only write if movement or time thresholds are met.

## Privacy
The `discoveryLocation` is purely based on the active device GPS. It is **NOT** derived from or fallback to the `Profile Location` or `registration address` to ensure safety and precision.

## Multi-Device Session
Uses `discoverySessionId`. When a worker goes online on Device B, Device A detects a session ID mismatch and stops updating location.

## Firestore Write Costs
Max writes estimated at ~6 writes/hour per worker (assuming 10min heartbeat + occasional movement > 50m).
