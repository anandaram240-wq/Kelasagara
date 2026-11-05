# PHASE 20.5 CAPTURE PROTOCOL
## Standard Operating Procedure for Controlled Mobile Biometric Capture

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. CAPTURE SESSION PROTOCOL

Each consented participant completes 3 distinct capture sessions separated by at least 24 hours:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          3-SESSION CAPTURE LIFECYCLE                            │
├────────────────────┬────────────────────┬───────────────────────────────────────┤
│ Session            │ Time Offset        │ Environmental & Sensor Target         │
├────────────────────┼────────────────────┼───────────────────────────────────────┤
│ Session 0 (Enroll) │ Day 0              │ Indoor uniform lighting, Mid-1080p    │
│ Session 1 (Verify) │ Day 1 (+24 hours)  │ Outdoor direct sun or Backlit, Flagsh │
│ Session 2 (Verify) │ Day 3 (+72 hours)  │ Low illumination or Fluorescent, Entry│
└────────────────────┴────────────────────┴───────────────────────────────────────┘
```

---

## 2. BURST CAPTURE MECHANISM

In each session, the application records a 3-frame burst sequence at 100ms intervals ($t_0, t_1, t_2$):
- **Frame 0 ($t_0$)**: Neutral frontal expression, open eyes baseline.
- **Frame 1 ($t_1$)**: Natural blink apex (bilateral palpebral compression $\le 0.65\times$ baseline).
- **Frame 2 ($t_2$)**: Re-opened eyes, neutral pose.

### Quality Invariants Enforced During Capture
- **Face Count**: Exactly 1 face in bounding box.
- **Inter-Pupillary Distance (IPD)**: $\ge 75$ pixels.
- **Head Pose Tolerance**: $\text{Yaw} \le 18^\circ$, $\text{Pitch} \le 15^\circ$, $\text{Roll} \le 12^\circ$.
- **Luminance Range**: Mean pixel intensity $35 \le \mu \le 220$.
- **Sharpness**: Laplacian variance $\ge 110.0$.

---

## 3. PRESENTATION ATTACK RECORDING PROTOCOL

For PAD evaluation, volunteers permitted the recording of controlled presentation attacks:
1. High-resolution print of Frame 0 on matte photo paper.
2. High-resolution print of Frame 0 on glossy photo paper.
3. Replay of 3-frame burst video on an AMOLED smartphone screen (6.5", 120Hz).
4. Replay on an IPS LCD tablet screen (10.9", 60Hz).
5. Replay on a 4K UHD external monitor.
6. Static photo displayed on smartphone screen with screen glare.
