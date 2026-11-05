# KELASAGARA V20.9: FRAME TIMESTAMP SECURITY
## Monotonicity, Sequence Continuity, and Anti-Freeze Verification

**Document Ref:** `docs/PHASE20_9_FRAME_TIMESTAMP_SECURITY.md`  
**Phase:** 20.9  
**Auditor:** Senior Android Security Architect  
**Date:** November 1, 2026

---

### 1. Threat Model: Temporal Manipulation & Replay

Adversaries attempting to bypass biometric liveness or presentation attack detection often employ temporal manipulation:
1. **Camera Freeze Attack:** Feeding identical static frames or stalling the video buffer to simulate a perfectly still subject.
2. **Out-of-Order Injection:** Splicing pre-recorded frames from different sessions into an active burst capture.
3. **Clock Manipulation:** Altering system time or presenting fabricated frame timestamps to forge challenge response latency.

---

### 2. Invariant Rules Implemented in `CameraCaptureIntegrity.ts`

To neutralize these attack vectors, the following invariant assertions are enforced:

#### Invariant T1: Strict Monotonicity
Every frame $i$ in a capture burst must possess a monotonic hardware timestamp:
$$t_i - t_{i-1} > 0$$
Any non-positive delta ($dt \le 0$) immediately trips a security violation.

#### Invariant T2: Hardware Frame Interval Bounding
For a 15–30 fps camera feed, inter-frame intervals must fall within physical boundaries:
$$10\text{ ms} \le (t_i - t_{i-1}) \le 2000\text{ ms}$$
Deltas $< 10\text{ ms}$ indicate software synthetic frame injection; deltas $> 2000\text{ ms}$ indicate camera stall or session stalling.

#### Invariant T3: Sequence Continuity
Every frame's sequence index must strictly increment:
$$\text{seq}_i = \text{seq}_{i-1} + 1$$
Sequence gaps or index reuse fail closed.

#### Invariant T4: Anti-Freeze Pixel Variance (MSE)
Natural camera sensors under active optical exposure exhibit photon shot noise and subtle micro-motions. The mean squared error between consecutive grayscale frames must exceed the minimum physical noise floor:
$$\text{MSE}(F_i, F_{i-1}) = \frac{1}{N} \sum_{k=1}^N (F_i[k] - F_{i-1}[k])^2 \ge \tau_{\text{freeze}} \quad (\tau_{\text{freeze}} = 1.0\text{ LSB}^2)$$
Identical duplicate frames ($\text{MSE} = 0.0$) are flagged as frozen camera attacks.

---

### 3. Empirical Test Results

In `backend/src/tests/phase20_9_capture_pipeline.test.ts` Suite 4:
- Valid continuous sequence ($3\text{ frames}, \Delta t \approx 66\text{ ms}, \text{MSE} = 25.0$): **PASSED**.
- Reversed timestamp ($t_1 < t_0$): **REJECTED** (`Timestamp non-monotonic`).
- Sequence index gap ($\text{seq}_0=0 \rightarrow \text{seq}_1=2$): **REJECTED** (`Sequence index discontinuity`).
- Frozen video ($\text{MSE} = 0.0$): **REJECTED** (`Camera freeze detected`).
