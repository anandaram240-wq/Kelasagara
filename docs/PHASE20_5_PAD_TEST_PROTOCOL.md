# PHASE 20.5 PAD TEST PROTOCOL
## Presentation Attack Detection Evaluation Protocol (Conforming to ISO/IEC 30107-3:2023)

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. SCOPE AND STANDARDS DELINEATION

This protocol specifies the methodology for evaluating the Kelasagara Presentation Attack Detection (PAD) subsystems in accordance with **ISO/IEC 30107-3:2023** (Biometric presentation attack detection - Testing and reporting):
- **Bona Fide Presentations**: Genuine living human subjects presenting their physical faces to the camera.
- **Attack Presentations**: Physical Presentation Attack Instruments (PAIs) presented to the camera lens.
- **Distinction from Software Replay**: Digital video injection via virtual cameras or modified Android binaries is tested as an application security threat, distinct from optical PAD.

---

## 2. TEST EXECUTION ENVIRONMENT & FIXTURES

### Attack Presentation Categories
1. **Printed Photographs (2D Paper)**:
   - Species A: 300 DPI color print on standard matte paper.
   - Species B: 600 DPI photo-quality print on glossy paper.
   - Species C: High-res print with eye holes cut out (partial facial cutout).
2. **Electronic Screen Displays (2D Video / Photo)**:
   - Species D: 6.5" OLED smartphone screen displaying static photo at 100% brightness.
   - Species E: 10.9" IPS LCD tablet screen displaying high-res video loop.
   - Species F: 27" 4K UHD desktop monitor displaying looped head movement video.
3. **Motion / Trajectory Replays**:
   - Species G: Replay of natural blinking recorded from previous genuine session.
   - Species H: Replay of lateral head nod motion.

---

## 3. DECISION CRITERIA & METRIC DEFINITIONS

- **APCER (Attack Presentation Classification Error Rate)**:
  $$\text{APCER} = \frac{\text{Number of Presentation Attacks Accepted as Live}}{\text{Total Presentation Attack Attempts}}$$
- **BPCER (Bona Fide Presentation Classification Error Rate)**:
  $$\text{BPCER} = \frac{\text{Number of Bona Fide Presentations Rejected as Spoof}}{\text{Total Bona Fide Attempts}}$$

### Disclaimers on Standards
- **No ISO Certification Claim**: This internal academic evaluation is conducted according to the principles of ISO/IEC 30107-3:2023, but does NOT constitute accredited laboratory third-party certification.
