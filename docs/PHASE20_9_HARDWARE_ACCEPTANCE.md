# KELASAGARA V20.9: HARDWARE ACCEPTANCE CRITERIA
## Device Compatibility Matrix and Sensor Calibration Thresholds

**Document Ref:** `docs/PHASE20_9_HARDWARE_ACCEPTANCE.md`  
**Phase:** 20.9  
**Auditor:** Principal Android Camera & Systems Architect  
**Date:** November 1, 2026

---

### 1. Hardware Qualification Requirements

Before a physical Android handset model is certified for live biometric capture in future unblocked phases, it must satisfy the following hardware acceptance gates:

| Hardware Criterion | Specification Requirement | Verification Method |
| :--- | :--- | :--- |
| **Camera2 Hardware Level** | `INFO_SUPPORTED_HARDWARE_LEVEL_FULL` or `LIMITED` | `CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL` |
| **Output Image Format** | `ImageFormat.YUV_420_888` at $640 \times 480$ minimum | `StreamConfigurationMap.getOutputSizes()` |
| **Exposure Control** | Manual/Auto Exposure lock and readout | `CONTROL_AE_MODE`, `SENSOR_EXPOSURE_TIME` |
| **Frame Rate Stability** | Minimum $15\text{ fps}$, target $30\text{ fps}$ without frame drops | Inter-frame timestamp jitter $\sigma < 10\text{ ms}$ |
| **Keystore Hardware Backing** | `KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT` or `STRONGBOX` | Android KeyStore KeyInfo attestation certificate |
| **Optical Resolution** | MTF50 $\ge 0.35\text{ cycles/pixel}$ at $35\text{ cm}$ distance | Slanted edge analysis on physical chart |

---

### 2. Supported Vendor SoC Architecture Handling

The `Yuv420PlaneReader.kt` engine provides verified support across all major mobile SoC architectures:
- **Qualcomm Snapdragon (QCOM HAL):** Supports 64-byte padded row strides (`rowStride = 704` for $640\text{w}$) with semi-planar NV12/NV21.
- **MediaTek (MTK HAL):** Supports 16-byte aligned planar I420 and NV12.
- **Samsung Exynos:** Handles dynamic stride alignment and crop offsets.
- **ARM Mali / PowerVR / Adreno GPU pipelines:** Normalizes texture byte arrays to standard CPU/GPU shared memory layouts.
