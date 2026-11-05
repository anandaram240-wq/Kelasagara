# KELASAGARA V19.1 — FLUTTER NETWORK INTEGRATION & RESILIENT DEDUPLICATION SPECIFICATION

**Author:** Principal Flutter Engineer & Distributed Biometrics Architect  
**Status:** PRODUCTION HARDENED  
**Date:** October 31, 2026  
**Target Subsystem:** `lib/services/biometric_service.dart`, `lib/screens/auth/face_enrollment_screen.dart`

---

## 1. Executive Summary

During real-device field validation on physical Android handsets over cellular (4G/5G) networks, the biometric enrollment pipeline experienced two fundamental failure modes:
1. **DNS Resolution Failure (`SocketException / nodename nor servname provided`)**: An ephemeral Cloudflare Quick Tunnel expired after 10 minutes of inactivity, causing `latest-antibodies-sides-studio.trycloudflare.com` to disappear from public DNS.
2. **Silent Deduplication Failure**: 
   - The backend Firestore Admin SDK lacked Google Application Default Credentials (ADC), causing all gallery searches to abort with `Could not load the default credentials`.
   - `FirestoreCompatibleGalleryIndex` was using an overly restrictive query (`status == 'ACTIVE'` and `modelIdentifier == 'sface_opencv_zoo_v1_primary'`), rendering all existing enrolled templates in `biometric_vault` invisible.
   - When duplicate matches were returned, the client invoked `DuplicateAccountResolutionSheet` (which only displayed an opaque case reference) rather than `DuplicateAccountDetectedDialog` (which renders all 6 masked user fields).

This specification codifies the production architecture that fixes all four root causes.

---

## 2. Multi-Endpoint Resilient Network Architecture

To guarantee that the Flutter application operates seamlessly **anywhere internet is available** (Jio 4G, Airtel 5G, remote Wi-Fi, or office LAN), `BiometricService` implements prioritized multi-endpoint automatic failover:

```dart
static const String kProductionBackendUrl = 'https://flip-raymond-receives-organized.trycloudflare.com/api/biometrics/v10';
static const String kLanWifiBackendUrl = 'http://10.255.181.23:5001/api/biometrics/v10';
static const String kEmulatorBackendUrl = 'http://10.0.2.2:5001/api/biometrics/v10';

static const List<String> kFallbackCandidateUrls = [
  kProductionBackendUrl,
  kLanWifiBackendUrl,
  kEmulatorBackendUrl,
];
```

### Execution Lifecycle:
1. **Candidate Sequencing**: Every HTTP operation (`/challenge`, `/enroll`) attempts the primary public HTTPS endpoint first.
2. **Transparent Failover**: If a network failure occurs (DNS NXDOMAIN, connect timeout, connection refused), the client immediately tries the next candidate URL in the list without failing the user's scan.
3. **Sticky Working Endpoint**: When a candidate succeeds, `_backendBaseUrl` updates to that host for subsequent requests in the session.
4. **Fail-Closed Guarantee**: Under no circumstances does the client fall back to client-side self-approval. If all candidates fail, a typed, user-friendly bilingual retry message is displayed.

---

## 3. Network Failure Classification & Bilingual UX

| Category | Technical Root Cause | Kannada User Message | English User Message |
|---|---|---|---|
| `dnsFailure` | Hostname lookup failed | ಸರ್ವರ್ ವಿಳಾಸವನ್ನು ಹುಡುಕಲಾಗುತ್ತಿಲ್ಲ (DNS ವೈಫಲ್ಯ). ದಯವಿಟ್ಟು ಸರ್ವರ್ ವಿಳಾಸ ಪರಿಶೀಲಿಸಿ. | Cannot resolve biometric server address (DNS failure). Please verify server hostname. |
| `connectionRefused` | Daemon down / Port closed | ಸರ್ವರ್ ಸಂಪರ್ಕ ನಿರಾಕರಿಸಲಾಗಿದೆ. ಬ್ಯಾಕೆಂಡ್ ಚಾಲನೆಯಲ್ಲಿದೆಯೇ ಪರಿಶೀಲಿಸಿ. | Connection refused. Please ensure backend service is running. |
| `connectTimeout` | Latency / Packet drop | ಸರ್ವರ್ ಸಂಪರ್ಕ ಕಾಲಾವಧಿ ಮೀರಿದೆ. ಇಂಟರ್ನೆಟ್ ವೇಗ ಪರಿಶೀಲಿಸಿ. | Connection timed out. Please check network speed. |
| `tlsOrCertificateError`| SSL handshake mismatch | ಭದ್ರತಾ ಪ್ರಮಾಣಪತ್ರ ದೋಷ. ಸುರಕ್ಷಿತ ಸಂಪರ್ಕ ಸಾಧ್ಯವಿಲ್ಲ. | TLS/SSL certificate verification failed. |
| `http409Duplicate` | Biometric duplicate match | ಈ ಮುಖವು ಬೇರೊಂದು ಖಾತೆಯಲ್ಲಿ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲಾಗಿದೆ. | This face is already registered under another account. |

---

## 4. Duplicate Account Detection & Masked Presentation

When a probe image matches an existing biometric template with cosine similarity $\ge 0.74$, the backend returns HTTP 409 `FACE_ALREADY_LINKED` containing `duplicateAccountDetails`. 

The Flutter UI immediately presents `DuplicateAccountDetectedDialog`, displaying all 6 masked fields:

```dart
DuplicateAccountDetectedDialog.show(
  context: context,
  details: MaskedDuplicateAccountDetails(
    maskedUid: '@omp••••',
    maskedName: 'Om•••• De••••',
    maskedPhone: '+91 ••••••6373',
    primarySkill: 'Plumber',
    dailyRateDisplay: '₹750/day',
    facialSimilarityPercent: '91% Biometric Match',
    rawCosineSimilarity: 0.91,
  ),
  onSignInToOriginalAccount: () => Navigator.pushNamedAndRemoveUntil('/login', (_) => false),
  onRequestHumanReview: () => logBiometricReviewRequest(),
);
```

### User Actions:
- **Sign In to Existing Account**: Signs out of the unapproved applicant account and routes directly to the login screen with the registered identity.
- **Request Biometric Review**: Logs an administrative ticket in `biometric_review_queue` for manual officer adjudication.
