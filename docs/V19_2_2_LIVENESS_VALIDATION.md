# KELASAGARA BIOMETRIC ENGINE V19.2.2: ACTIVE LIVENESS & PRESENTATION ATTACK DETECTION (PAD)

## 1. Compliance Standards
The presentation attack detection architecture complies with:
- **ISO/IEC 30107-3:** Biometric presentation attack detection — Testing and reporting.
- **UIDAI Aadhaar FaceRD v2.0:** Dynamic challenge-response and WADH binding specifications.

---

## 2. Dynamic Challenge-Response Protocol
1. **Authoritative Ticket Acquisition:** Prior to capture, client requests a single-use ticket from `/api/biometrics/v10/challenge`.
2. **Freshness Guarantee:** Nonces expire after 60 seconds (`TTL = 60s`). Replaying a consumed nonce triggers immediate `HTTP 401 EXPIRED_OR_REPLAYED_CHALLENGE`.
3. **Randomized Liveness Actions:** The server dynamically assigns one of several micro-interactions:
   - `BLINK`: Verification of continuous eye-opening and closing kinematics.
   - `TURN_HEAD_LEFT` / `TURN_HEAD_RIGHT`: In-plane yaw rotation verification.
   - `SMILE`: Mouth aspect ratio deflection.

---

## 3. Multi-Frame Kinematics & Sharpness Verification
- **Eye Aspect Ratio (EAR) Thresholds:**
  $$\text{EAR} = \frac{\|p_2 - p_6\| + \|p_3 - p_5\|}{2 \|p_1 - p_4\|}$$
  - Open state: $\text{EAR} \ge 0.28$
  - Closed blink state: $\text{EAR} \le 0.18$
- **Focus & Laplacian Variance:** Frames must exhibit $\sigma_{\text{Laplacian}}^2 \ge 80.0$, rejecting blurred frames, out-of-focus captures, and printed photographs held against the lens.
- **3-Frame Temporal Burst:** Captures $(t_0, t_0+120\text{ms}, t_0+240\text{ms})$ to detect 2D screen replays via photometric reflection inconsistencies.
