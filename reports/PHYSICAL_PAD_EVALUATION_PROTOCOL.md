# Gate G-02: Physical Presentation-Attack Evaluation Protocol (ISO/IEC 30107-3 Level 1)

- **Target Repository:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`
- **Target Subsystem:** `ChallengeBurstPadService` + `MediaPipeFaceLandmarkerOnnx` (478-point Attention Mesh)
- **Current Physical Execution Status:** `PROTOCOL_LOCKED_PENDING_LAB_EXECUTION` (Software adversarial suite passing; physical lab metrics below must only be populated from real human/PAI test bench runs).

---

## 1. MediaPipe 478-Point Ocular Landmark Mapping (Soukupová & Čech EAR)

The backend ONNX runtime adapter (`backend/src/services/mediapipe_face_landmarker_onnx.ts`) extracts the following 12 canonical eyelid vertices from the 478-point MediaPipe Attention Mesh:

| EAR Point | Anatomical Location | Left Eye Mesh Index | Right Eye Mesh Index |
| :--- | :--- | :---: | :---: |
| $p_1$ | Lateral Canthus (Outer Corner) | `33` | `263` |
| $p_2$ | Superior Lateral Eyelid | `160` | `387` |
| $p_3$ | Superior Medial Eyelid | `158` | `385` |
| $p_4$ | Medial Canthus (Inner Corner) | `133` | `362` |
| $p_5$ | Inferior Medial Eyelid | `153` | `380` |
| $p_6$ | Inferior Lateral Eyelid | `144` | `373` |

$$\text{EAR} = \frac{\|p_2 - p_6\|_2 + \|p_3 - p_5\|_2}{2 \|p_1 - p_4\|_2}$$

- **Open State Gate (`Frame 1` & `Frame 3`):** $\text{EAR} \ge 0.24$
- **Closed Apex Gate (`Frame 2`):** $\text{EAR} \le 0.18$ and $\Delta\text{EAR} \ge 0.08$

---

## 2. Physical PAI Test Bench Matrix (Level 1)

All physical trials must be executed across two extreme Indian field lighting regimes:
1. **Regime A — Direct Indian Outdoor Sunlight ($\approx 60,000\text{ lux}$):** Unshaded midday sun measured via calibrated lux meter at the subject's cheek plane.
2. **Regime B — Dim Rural/Indoor Ambient Light ($< 50\text{ lux}$):** Single low-wattage warm LED source without direct flash.

| PAI ID | Attack Instrument / Bona Fide Category | Physical Setup Specification | Lighting Regimes | Required Trials ($N$) |
| :--- | :--- | :--- | :--- | :---: |
| `BF-01` | Bona Fide Live Subject | Authorized test subjects across Fitzpatrick III–VI skin tones | $60,000\text{ lux}$ & $< 50\text{ lux}$ | $100$ per regime |
| `PAI-01` | 2D Matte Paper Cutout | $600\text{ DPI}$ A4 matte colour print on $250\text{ gsm}$ cardstock; tested flat, curved, and with scissors-cut eye apertures | $60,000\text{ lux}$ & $< 50\text{ lux}$ | $100$ per regime |
| `PAI-02` | iPad Pro 120Hz OLED Static & Toggle Replay | 12.9-inch iPad Pro (ProMotion $120\text{ Hz}$) alternating open-eye and closed-eye photos manually/scripted within $40\text{–}600\text{ ms}$ | $60,000\text{ lux}$ & $< 50\text{ lux}$ | $100$ per regime |
| `PAI-03` | High-FPS Video Re-Projection | $1080\text{p}$ $60\text{ fps}$ video of a genuine blink replayed on an OLED display mounted on an anti-tremor tripod at $35\text{ cm}$ | $60,000\text{ lux}$ & $< 50\text{ lux}$ | $100$ per regime |

---

## 3. ISO/IEC 30107-3 Evaluation Metrics & Acceptance Criteria

1. **Attack Presentation Classification Error Rate ($\text{APCER}_{\text{PAI}}$):**
   $$\text{APCER}_{\text{PAI}} = \frac{1}{N_{\text{PAI}}} \sum_{i=1}^{N_{\text{PAI}}} \mathbb{I}(\text{Verdict}_i = \texttt{PASS})$$
   - **Canary Clearance Gate:** $\text{APCER}_{\max} = \max_{\text{PAI}} \text{APCER}_{\text{PAI}} \le 2.0\%$.
2. **Bona Fide Presentation Classification Error Rate ($\text{BPCER}$):**
   $$\text{BPCER} = \frac{1}{N_{\text{BF}}} \sum_{j=1}^{N_{\text{BF}}} \mathbb{I}(\text{Verdict}_j \ne \texttt{PASS})$$
   - **Canary Clearance Gate:** $\text{BPCER} \le 5.0\%$ under indoor standard light and $\le 8.0\%$ under $60,000\text{ lux}$ / $< 50\text{ lux}$.
