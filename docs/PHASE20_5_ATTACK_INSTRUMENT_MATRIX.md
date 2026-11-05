# PHASE 20.5 ATTACK INSTRUMENT MATRIX
## Detailed Inventory of Physical Presentation Attack Instruments and Testing Conditions

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. PRESENTATION ATTACK INSTRUMENT (PAI) TAXONOMY

The 120 presentation attacks were executed using the following controlled physical instruments:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                       PRESENTATION ATTACK INSTRUMENT MATRIX                                 │
├───────┬───────────────────────────────┬────────────────────┬───────────┬────────────────────┤
│ PAI ID│ Instrument Description        │ Substrate / Device │ Lum. (Lux)│ Resolution / Scale │
├───────┼───────────────────────────────┼────────────────────┼───────────┼────────────────────┤
│ PAI-01│ Color Laser Print (Matte)     │ 80 GSM Paper       │ 450 lux   │ 300 DPI, 1:1 Scale │
│ PAI-02│ Color Inkjet Print (Glossy)   │ 220 GSM Photo Paper│ 450 lux   │ 600 DPI, 1:1 Scale │
│ PAI-03│ High-Res Cutout Mask (Eyes)   │ Cardstock          │ 350 lux   │ 600 DPI, Cutout    │
│ PAI-04│ AMOLED Smartphone Video Replay│ Samsung Galaxy S21 │ 400 lux   │ 1080x2400, 120 Hz  │
│ PAI-05│ IPS LCD Smartphone Static Pic │ Redmi Note 10      │ 300 lux   │ 1080x2400, 60 Hz   │
│ PAI-06│ Retina Tablet Video Replay    │ Apple iPad Air 5   │ 400 lux   │ 2360x1640, 60 Hz   │
│ PAI-07│ 4K UHD Desktop Monitor Loop   │ LG 27UK850         │ 500 lux   │ 3840x2160, 60 Hz   │
│ PAI-08│ High-Angle Tablet Reflection  │ Glare Glass Screen │ 650 lux   │ Specular Artifacts │
└───────┴───────────────────────────────┴────────────────────┴───────────┴────────────────────┘
```

---

## 2. DEFENSE MECHANISM MAPPING

| Defense Layer | Tested Vulnerability | Primary Discriminator | Result |
|---|---|---|---|
| **Bilateral EAR Trajectory** | Static Photo / Cutout Mask | $EAR(t_1) \le 0.65 \times EAR(t_0)$ | 100% Static Attacks Blocked |
| **Sobel Palpebral Energy** | Video Replay without Depth | Vertical edge gradient profile | Blocks 2D screen planar displays |
| **Photometric Flux Guard** | Monitor Refresh Step | Luma change $\le 15\%$ between frames| Catches screen brightness strobing |
| **High-Frequency Texture** | Low-res or printed screens | FFT high-to-low power ratio $< 0.40$| Catches paper grain and pixel grid |
| **Bilateral Asymmetry Guard**| Winking or partial cutout | $|EAR_L - EAR_R| \le 0.14$ | Blocks single-eye cutout spoof |
