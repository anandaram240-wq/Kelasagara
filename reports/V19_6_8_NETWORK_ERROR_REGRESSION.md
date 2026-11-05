# KELASAGARA BIOMATCH V19.6.8: NETWORK ERROR REGRESSION & CLASSIFICATION SPECIFICATION

**Date:** 2026-10-24  
**Author:** Antigravity Senior Mobile Architecture & Biometric Security Engineer  
**Baseline Commit:** `ff2814e`  
**Milestone:** V19.6.8 Hotfix & Network Error Resilience  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  

---

## 1. Executive Summary

During physical device testing on Android cellular connections (5G/4G), network transport failures previously collapsed into a single generic, uninformative message:
`Biometric verification server unreachable. Please check connection and try again.`

This masked the true root causes, including:
1. Android OS blocking cleartext HTTP requests (`android:usesCleartextTraffic="false"`).
2. Unroutable private LAN IP addresses (`10.255.181.23`) on cellular carriers.
3. Strict 2-second connection timeouts failing under realistic cellular radio latencies.
4. Unresolvable DNS hostnames.

In V19.6.8, we introduced the `ClassifiedNetworkError` subsystem in [`lib/services/biometric_service.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart) with 16 distinct `NetworkFailureCategory` classifications, extended timeout tolerances, and bilingual (English/Kannada) diagnostic feedback.

---

## 2. Complete 16-Category Classification Taxonomy

Every `DioException` encountered during biometric challenge acquisition, verification, or enrollment is intercepted by `BiometricService.classifyDioException()` and mapped to one of the following 16 deterministic categories:

| Category Enum | Root Cause Trigger | HTTP / Socket Trigger | English Diagnostic Message | Kannada Actionable Guidance |
|:---|:---|:---|:---|:---|
| `cleartextProhibited` | Android `usesCleartextTraffic="false"` | `Cleartext HTTP traffic ... not permitted` | Insecure HTTP connection blocked by Android security policy. HTTPS or reverse proxy required. | ಭದ್ರತಾ ಕಾರಣಗಳಿಂದಾಗಿ ಅಸುರಕ್ಷಿತ ಸಂಪರ್ಕವನ್ನು ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ. ದಯವಿಟ್ಟು HTTPS ಬಳಸಿ. |
| `dnsResolutionFailed` | Hostname lookup failed | `SocketException` with `Failed host lookup` | Cannot resolve server address. Check DNS or mobile carrier connection. | ಸರ್ವರ್ ವಿಳಾಸವನ್ನು ಪತ್ತೆಹಚ್ಚಲು ಸಾಧ್ಯವಾಗುತ್ತಿಲ್ಲ. ಇಂಟರ್ನೆಟ್ ಸಂಪರ್ಕವನ್ನು ಪರಿಶೀಲಿಸಿ. |
| `connectionRefused` | Backend daemon down / port closed | `ECONNREFUSED` / `Connection refused` | Biometric verification server is not responding on port. Verify server daemon is running. | ಬಯೋಮೆಟ್ರಿಕ್ ಪರಿಶೀಲನಾ ಸರ್ವರ್ ಚಾಲನೆಯಲ್ಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಸರ್ವರ್ ಅನ್ನು ಪರಿಶೀಲಿಸಿ. |
| `connectionTimeout` | SYN handshake timed out | `DioExceptionType.connectionTimeout` | Connection to biometric server timed out. Cellular network may be slow or congested. | ಬಯೋಮೆಟ್ರಿಕ್ ಸರ್ವರ್ ಸಂಪರ್ಕದ ಸಮಯ ಮೀರಿದೆ. ನೆಟ್‌ವರ್ಕ್ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ. |
| `sendTimeout` | Request transmission stalled | `DioExceptionType.sendTimeout` | Request send timed out. Low network uplink bandwidth. | ವಿನಂತಿ ಕಳುಹಿಸುವಿಕೆ ವಿಫಲವಾಗಿದೆ. ನೆಟ್‌ವರ್ಕ್ ಅಪ್‌ಲಿಂಕ್ ವೇಗವನ್ನು ಪರಿಶೀಲಿಸಿ. |
| `receiveTimeout` | Server processing exceeded deadline | `DioExceptionType.receiveTimeout` | Server response timed out. Biometric pipeline under heavy load. | ಸರ್ವರ್ ಪ್ರತಿಕ್ರಿಯಿಸಲು ವಿಳಂಬವಾಗಿದೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಸಮಯದ ನಂತರ ಪ್ರಯತ್ನಿಸಿ. |
| `unauthorized` | Token invalid, revoked, or expired | `HTTP 401 Unauthorized` | Biometric authentication expired. Please sign in again. | ಬಯೋಮೆಟ್ರಿಕ್ ದೃಢೀಕರಣ ಅವಧಿ ಮುಗಿದಿದೆ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಲಾಗ್ ಇನ್ ಮಾಡಿ. |
| `forbidden` | Insufficient role or blocked device | `HTTP 403 Forbidden` | Access to biometric service denied. Check account permissions. | ಬಯೋಮೆಟ್ರಿಕ್ ಸೇವೆಗೆ ಪ್ರವೇಶ ನಿರಾಕರಿಸಲಾಗಿದೆ. ಅನುಮತಿಗಳನ್ನು ಪರಿಶೀಲಿಸಿ. |
| `notFound` | Route mismatch or unmounted path | `HTTP 404 Not Found` | Biometric API endpoint not found. Verify route configuration. | ಬಯೋಮೆಟ್ರಿಕ್ API ಮಾರ್ಗ ಕಂಡುಬಂದಿಲ್ಲ. ಆವೃತ್ತಿಯನ್ನು ಪರಿಶೀಲಿಸಿ. |
| `payloadTooLarge` | Burst image payload exceeds limits | `HTTP 413 Payload Too Large` | Face crop image payload is too large. Adjust compression quality. | ಫೋಟೋ ಡೇಟಾ ತುಂಬಾ ದೊಡ್ಡದಾಗಿದೆ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ. |
| `rateLimited` | Burst or verification throttling | `HTTP 429 Too Many Requests` | Too many biometric attempts. Please wait before retrying. | ಹಲವಾರು ಪ್ರಯತ್ನಗಳು ದಾಖಲಾಗಿವೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಸಮಯ ಕಾಯಿರಿ. |
| `serverError` | Internal pipeline fault (500) | `HTTP 500 Internal Server Error` | Biometric processing error on server. Please try again later. | ಸರ್ವರ್‌ನಲ್ಲಿ ಆಂತರಿಕ ತೊಂದರೆ ಉಂಟಾಗಿದೆ. ನಂತರ ಪ್ರಯತ್ನಿಸಿ. |
| `badGateway` | Ingress / reverse-proxy error | `HTTP 502 Bad Gateway` | Biometric gateway error. Upstream service unreachable. | ಬಯೋಮೆಟ್ರಿಕ್ ಗೇಟ್‌ವೇ ಸಂಪರ್ಕ ವಿಫಲವಾಗಿದೆ. |
| `serviceUnavailable` | System undergoing maintenance | `HTTP 503 Service Unavailable` | Biometric service temporarily unavailable for maintenance. | ಬಯೋಮೆಟ್ರಿಕ್ ಸೇವೆ ಸದ್ಯಕ್ಕೆ ಲಭ್ಯವಿಲ್ಲ. ನಿರ್ವಹಣೆಯಲ್ಲಿದೆ. |
| `offlineNoConnectivity` | Handset flight mode or no signal | `ENETUNREACH`, `EHOSTUNREACH`, network down | Device appears offline. Check Wi-Fi or mobile data toggle. | ಸಾಧನವು ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿದೆ. ವೈ-ಫೈ ಅಥವಾ ಮೊಬೈಲ್ ಡೇಟಾ ಪರಿಶೀಲಿಸಿ. |
| `unknownNetworkError` | Unclassified edge cases | Other socket / transport anomalies | Network communication error. Please check your connection. | ನೆಟ್‌ವರ್ಕ್ ಸಂವಹನ ದೋಷ. ದಯವಿಟ್ಟು ಸಂಪರ್ಕವನ್ನು ಪರಿಶೀಲಿಸಿ. |

---

## 3. Cellular Mobile Timeout Adjustments

Under mobile network conditions (2G, 3G, 4G LTE, and early 5G SA/NSA handoffs), radio resource control (RRC) state transitions from idle to active can introduce 1.5–3.0 seconds of latency jitter before TCP SYN packets reach the remote host.

The previous hardcoded timeouts in `BiometricService`:
```dart
// Pre-V19.6.8: Excessive sensitivity to mobile radio latency
connectTimeout: const Duration(seconds: 2),
receiveTimeout: const Duration(seconds: 3),
```

Caused spurious timeout failures even when the backend was fully operational.

In V19.6.8, timeouts were calibrated for production mobile network viability:
```dart
// V19.6.8: Resilient mobile timeouts
connectTimeout: const Duration(seconds: 10),
receiveTimeout: const Duration(seconds: 15),
```

---

## 4. Automated Regression Evidence

The test suite [`test/v19_6_8_network_error_regression_test.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/test/v19_6_8_network_error_regression_test.dart) exercises the classification logic against simulated error conditions:

```
00:00 +0: Biometric Network Error Classification Tests Android cleartext policy prohibition triggers cleartextProhibited category
00:00 +1: Biometric Network Error Classification Tests DNS resolution failure triggers dnsResolutionFailed category
00:00 +2: Biometric Network Error Classification Tests Connection refused triggers connectionRefused category
00:00 +3: Biometric Network Error Classification Tests Connection timeout triggers connectionTimeout category with 10s budget note
00:00 +4: Biometric Network Error Classification Tests Receive timeout triggers receiveTimeout category
00:00 +5: Biometric Network Error Classification Tests HTTP 401 Unauthorized triggers unauthorized category with Kannada message
00:00 +6: Biometric Network Error Classification Tests HTTP 403 Forbidden triggers forbidden category
00:00 +7: Biometric Network Error Classification Tests HTTP 404 triggers notFound category with sanitized route path
00:00 +8: Biometric Network Error Classification Tests HTTP 429 triggers rateLimited category
00:00 +9: Biometric Network Error Classification Tests HTTP 500 triggers serverError category with trace correlation ID
00:00 +10: Biometric Network Error Classification Tests Network unreachable triggers offlineNoConnectivity category
00:00 +11: Biometric Network Error Classification Tests resolveDefaultEndpoint prioritizes release mode over Android platform check
00:00 +12: All tests passed!
```

---

## 5. Security & Privacy Safeguards

1. **Path Sanitization:** The error classifier strips sensitive query parameters and authentication tokens before embedding route paths into diagnostic objects:
   ```dart
   final cleanRoute = routePath.split('?').first;
   ```
2. **Audit Correlation Tracking:** Server response headers (`x-correlation-id`, `x-request-id`) are extracted and exposed in `ClassifiedNetworkError.correlationId` to enable cross-system log correlation without exposing payload data.
3. **Fail-Closed Biometrics:** In all failure modes, `BiometricCheckResult.technicalFailureRetry()` is returned, ensuring that transport failures never accidentally bypass enrollment or authentication checks.
