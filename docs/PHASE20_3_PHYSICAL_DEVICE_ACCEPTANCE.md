# KELASAGARA V20.3: PHYSICAL DEVICE ACCEPTANCE & COMPATIBILITY MATRIX
## Android Hardware Keystore & Key Attestation Field Qualification

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-12  
**Classification:** Hardware Engineering & Mobile Device Qualification Report

---

## 1. DEVICE QUALIFICATION PROTOCOL & METHODOLOGY

To ensure that Kelasagara V20.3 operates reliably across the diverse Android device ecosystem prevalent among informal gig workers in India, the Android Keystore engine was evaluated across three distinct hardware tiers:
1. **Tier 1 (Dedicated Hardware Enclave):** Devices equipped with StrongBox KeyMint (e.g. Google Pixel Titan M2, Samsung Knox Vault, high-end Qualcomm Snapdragon 8 Gen 2/3).
2. **Tier 2 (Standard Hardware TEE):** Devices with ARM TrustZone / Trusted Execution Environment (e.g. Redmi Note 10/11/12, Realme, Vivo, Samsung Galaxy M/A-series, MediaTek Dimensity).
3. **Tier 3 (Development & Virtualized Environments):** Android Studio Emulators (x86_64, arm64) without physical hardware security modules.

---

## 2. HARDWARE ASSURANCE COMPATIBILITY MATRIX

| Device Tier | Hardware Model / Environment | Android OS Level | Keystore Security Level | Key Attestation Chain | Play Integrity Verdict | Production Behavior |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | Google Pixel 7 / 8 / 9 | Android 13 - 15 (API 33 - 35) | `DEVICE_KEY_STRONGBOX` | Full Chain (roots to Google Root CA) | `MEETS_STRONG_INTEGRITY` | **Full Production Authorization** |
| **Tier 1** | Samsung Galaxy S23 / S24 | Android 14 - 15 (API 34 - 35) | `DEVICE_KEY_STRONGBOX` | Full Chain (roots to Google Root CA) | `MEETS_STRONG_INTEGRITY` | **Full Production Authorization** |
| **Tier 2** | Redmi Note 11 / 12 (Snapdragon) | Android 11 - 14 (API 30 - 34) | `DEVICE_KEY_TEE` | Full Chain (roots to Google Root CA) | `MEETS_DEVICE_INTEGRITY` | **Full Production Authorization** |
| **Tier 2** | Vivo T2 / Realme Narzo 50 | Android 12 - 14 (API 31 - 34) | `DEVICE_KEY_TEE` | Full Chain (roots to Google Root CA) | `MEETS_DEVICE_INTEGRITY` | **Full Production Authorization** |
| **Tier 2** | Samsung Galaxy A14 / M14 | Android 13 - 14 (API 33 - 34) | `DEVICE_KEY_TEE` | Full Chain (roots to Google Root CA) | `MEETS_DEVICE_INTEGRITY` | **Full Production Authorization** |
| **Tier 3** | Android Studio Emulator | API 34 (x86_64) | `DEVICE_KEY_SOFTWARE` | Self-Attested / Dev Stub | `MEETS_BASIC_INTEGRITY` | Allowed in `APP_ENV=LOCAL/TEST`; **Blocked in PRODUCTION** |

---

## 3. KEY OBSERVATIONS & RESILIENCE

1. **Graceful StrongBox Fallback:**
   The Kotlin `DeviceKeyManager` successfully traps `StrongBoxUnavailableException` on Tier 2 devices and automatically completes key generation using the device TEE. Zero user-facing crashes occurred during fallback.
2. **Key Invalidation on Device Biometric Change:**
   Because the transport device key is configured with `setUserAuthenticationRequired(false)` (biometric matching is handled server-authoritatively by SFace), adding or removing a fingerprint in Android Settings does **not** corrupt or invalidate the worker's device key.
3. **App Updates & Reinstalls:**
   - App updates preserve Keystore entries within the shared UID.
   - App uninstallation deletes the app's Keystore entries (standard Android OS behavior). Upon re-installation, the worker executes the recovery protocol documented in `docs/PHASE20_3_REVOCATION_AND_RECOVERY.md`.
