# V19 Presentation Attack Detection (PAD) Evaluation Protocol

## 1. Standards Context & Scope Limitation
- **ISO/IEC 30107-3:2023** defines testing and reporting methodologies for Presentation Attack Detection (PAD), measuring Attack Presentation Classification Error Rate (APCER) and Bona Fide Presentation Classification Error Rate (BPCER).
- The standard explicitly does **NOT** certify a single software algorithm or guarantee absolute protection against all physical attacks.
- Software unit tests that reject synthetic arrays or test fixtures do **NOT** constitute ISO 30107-3 certification.

## 2. Multi-Signal Defensive Architecture
The current implementation enforces a 5-layer heuristic PAD defense:

```
Camera Frame Burst (3 Frames over 300 - 600 ms)
       │
       ├── 1. Temporal Kinematic Blink:
       │      F1: Eye Open (EAR >= 0.58)
       │      F2: Eye Closed Apex (EAR <= 0.28)
       │      F3: Eye Reopened (EAR >= 0.58)
       │
       ├── 2. Micro-Texture Sharpness (Pech-Pacheco Laplacian):
       │      Kernel [0,1,0; 1,-4,1; 0,1,0] on 112x112 grayscale crop.
       │      Bona fide range: σ²L ∈ [110, 1200].
       │      Rejects blurred printouts (< 110) and high-frequency moiré (> 1200).
       │
       ├── 3. Inter-Frame Identity Consistency:
       │      Cosine(Embedding(F1), Embedding(F3)) >= 0.85.
       │      Prevents video-splice attacks where different faces are spliced.
       │
       ├── 4. Luminance Step-Jump Continuity:
       │      Max luma shift between consecutive frames < 15%.
       │      Blocks sudden tablet backlight illumination injection.
       │
       └── 5. Cryptographic Request Nonce Binding:
              buildPadBoundRequestHash() binds frame digest, Laplacian variance,
              blink verdict, and IPD into SHA-256 with 60-second server nonce.
```

## 3. Physical Evaluation Protocol (To Be Executed)
To measure true APCER and BPCER, the following physical test protocol is specified:
1. **Target Artifacts:**
   - 2D Matte Paper Printout ($A4$, 300 DPI, laser color).
   - 2D Glossy Photo Printout ($4 \times 6$ inch).
   - High-Resolution Screen Replay (iPad Pro Retina, 120Hz).
   - Budget Phone Screen Replay (Redmi 9A, 60Hz LCD).
2. **Environmental Conditions:**
   - Harsh direct outdoor sunlight (50,000 lux).
   - Indoor fluorescent office lighting (500 lux).
   - Dim evening / power-cut condition (< 50 lux).
3. **Current Execution Status:** **NOT PERFORMED**.
   Physical attacks have not been systematically executed against physical hardware in this session. Software-level regression tests pass, but empirical APCER/BPCER rates remain unmeasured.
