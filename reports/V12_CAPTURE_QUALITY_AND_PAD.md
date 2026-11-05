# KELASAGARA BIOMETRIC ENGINE V12.0
## Capture Quality Control & Presentation Attack Detection (PAD)

**Date:** October 23, 2026  
**Status:** VALIDATED & COMPLIANT  
**Standard Compliance:** ISO/IEC 29794-5:2025 (OFIQ), ISO/IEC 39794-5:2024, ISO/IEC 30107-3:2023  
**Architecture Inspiration:** UIDAI Face RD Liveness Capture & WADH Cryptographic Binding  

---

## 1. ISO/IEC 29794-5 Quality Assessment Gate

Before any captured video frame is submitted for feature extraction, it must satisfy rigorous pre-inference quality checks implemented in `AdvancedLandmarkAnalyzer` and `FaceQualityMetrics`:

```
               [ INCOMING CAMERA FRAME (30 FPS) ]
                               │
                               ▼
        [ ML Kit High-Fidelity Detector (~133 Landmarks) ]
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
 [ Interpupillary Dist ]  [ Head Pose Euler ]   [ 2D Laplacian ]
    IPD ≥ 90 pixels        |yaw| ≤ 5°            Sharpness σ² ≥ 110
    (ISO 39794-5)          |pitch| ≤ 5°          Moiré ceiling ≤ 1850
                           |roll| ≤ 8°
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                               ▼
              { ALL METRICS PASS QUALITY GATE? }
                     ├── NO  ──► Display localized guidance in Kannada & English
                     │           ("ಮುಖ ತುಂಬಾ ದೂರ — Move closer", etc.)
                     └── YES ──► Advance to Kinematic PAD Stage
```

### 1.1 Specification of Quality Criteria

| Quality Parameter | Standard Source | Threshold Value | Enforcement Action |
| :--- | :--- | :---: | :--- |
| **Interpupillary Distance (IPD)** | ISO/IEC 39794-5:2024 | $\ge 90\text{ px}$ | Frame rejected; prompt: *"ಮುಖ ತುಂಬಾ ದೂರ — Move closer"* |
| **Head Yaw Angle** | ISO/IEC 29794-5 §6.2 | $|\text{yaw}| \le 5.0^\circ$ | Frame rejected; prompt: *"ತಲೆ ತಿರುಗಿಸಬೇಡಿ — Face straight"* |
| **Head Pitch Angle** | ISO/IEC 29794-5 §6.2 | $|\text{pitch}| \le 5.0^\circ$ | Frame rejected; prompt: *"ತಲೆ ನೇರವಾಗಿಡಿ — Level head"* |
| **Head Roll Angle** | ISO/IEC 29794-5 §6.2 | $|\text{roll}| \le 8.0^\circ$ | Frame rejected; prompt: *"ತಲೆ ಓರೆ ಮಾಡಬೇಡಿ — No tilt"* |
| **Illumination Symmetry** | ISO/IEC 29794-5 §6.4 | $\ge 0.70$ | Rejection if half-face shadow detected |
| **Sharpness Metric ($\sigma^2_L$)** | Pech-Pacheco (2000) | $\sigma^2_L \ge 110$ | Rejection for motion or out-of-focus blur |
| **Screen Moiré Ceiling** | ISO/IEC 30107-3 | $\sigma^2_L \le 1850$ | Rejection for high-frequency screen pixel raster |

---

## 2. Multi-Stage Presentation Attack Detection (PAD)

Presentation attack detection combines passive texture analysis with interactive kinematic blink verification to prevent photo, video, and screen presentation spoofing.

### 2.1 Stage 1: Passive Texture & Sharpness Analysis
- **Operator:** Discrete 2D Laplacian convolution kernel on $112 \times 112$ grayscale face crop:
  $$K = \begin{bmatrix} 0 & 1 & 0 \\ 1 & -4 & 1 \\ 0 & 1 & 0 \end{bmatrix}, \quad \sigma^2_L = \text{Var}(I * K)$$
- **Print Attack Defense:** Paper printouts lack fine micro-texture and pore structure, yielding $\sigma^2_L < 110$.
- **Digital Screen Defense:** High-resolution smartphone/tablet screens emit artificial high-frequency grid interference (moiré pattern), yielding $\sigma^2_L > 1850$.

### 2.2 Stage 2: Kinematic Blink Validation
- **Mathematical Model:** Soukupová & Čech (2016) Eye Aspect Ratio (EAR) combined with ML Kit eye-open classification:
  $$EAR = \frac{\|p_2 - p_6\| + \|p_3 - p_5\|}{2 \|p_1 - p_4\|}$$
- **Threshold Calibration:**
  - $\text{Open Eye Threshold} \ge 0.58$ (supports deep-set eyes, glasses, and diverse melanin tones).
  - $\text{Closed Eye Threshold} \le 0.28$.
  - Minimum consecutive open frames before blink: $5$ frames (~167 ms at 30 FPS).
  - Minimum consecutive closed frames: $2$ frames (~67 ms at 30 FPS) — prevents artificial single-frame camera dropout spoofing.

---

## 3. Cryptographic Binding: Aadhaar-Inspired WADH

A critical requirement of UIDAI Face RD Registered Device specification is that the captured biometric data and liveness parameters must be cryptographically bound together so that neither can be swapped or injected independently.

In Kelasagara V12.0, this is implemented as the **PAD-Bound Request Hash (WADH)**:

$$\text{WADH} = \text{SHA-256}\Big(\text{UID} \,\|\, \text{Nonce} \,\|\, \text{FrameDigest} \,\|\, \sigma^2_L \,\|\, \text{BlinkVerdict} \,\|\, \text{IPD}\Big)$$

```dart
final String requestHash = buildPadBoundRequestHash(
  uid: currentUserUid,
  serverNonce: nonce,
  frameDigestHex: captureDigestHex,
  laplacianVariance: nativeResult.laplacianVariance,
  blinkDetected: _stage == _FaceStage.blinkClose || _burstComplete,
  ipdPixels: qualityReport.ipdPixels.toDouble(),
);
```

### 3.1 Server-Side Enforcement
The backend receives both the image payload and the signed request hash:
1. Recomputes $\text{SHA-256}(\text{ImageBuffer})$ to verify integrity against network tampering.
2. Validates that the request hash matches the active single-use challenge nonce.
3. Consumes the nonce immediately in memory to defeat replay attacks (Invariant I-05).
