# Kelasagara Worker Availability Contract

## API
The `WorkerAvailabilityService` provides:
- `setAvailable()`: Turns on GPS tracking and marks the worker as discoverable.
- `setUnavailable()`: Stops GPS tracking and clears discovery location fields.
- `resumeIfAvailable()`: Checks if the user was marked available in a previous run and resumes the session if valid.
- `checkFreshness()`: Evaluates the age of the `discoveryUpdatedAt` timestamp against thresholds.

## Session Lifecycle
1. **Enable**: Worker clicks "Go Online". Location permission checked. Session ID generated.
2. **GPS Stream**: App starts listening to Geolocation updates.
3. **Writes**: Updates Firestore (`discoveryLat`, `discoveryLng`, etc.) based on 50m movement.
4. **Heartbeat**: A 10min timer forces an update even if stationary to keep the worker FRESH.
5. **Disable**: Worker clicks "Go Offline" or session is revoked. Stream stopped.

## Multi-Device Session Theft Protection
Each time a worker goes online, a unique `discoverySessionId` is written to their document. The local service checks if the Firestore `discoverySessionId` matches the local session. If not, another device has taken over, and the local stream is halted.

## Error Handling
- **Permission Denied**: `setAvailable()` throws an error caught by the UI.
- **GPS Unavailable**: Reverts to unavailable state or prompts user to enable GPS.
- **Low Accuracy**: Coordinates with accuracy > 100m are discarded.

## How to call from WorkerDashboard
```dart
try {
  await WorkerAvailabilityService.instance.setAvailable(userUid);
} catch (e) {
  // Show error snackbar
}
```

## Firestore Fields Written
- `isAvailable` (boolean)
- `discoveryLat` (double)
- `discoveryLng` (double)
- `discoveryUpdatedAt` (timestamp)
- `discoverySessionId` (string)
- `discoveryAccuracy` (double)
- `serviceRadiusKm` (int)
