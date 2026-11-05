# PHASE 20.8: SPECULAR REFLECTION OPTICAL SIGNAL ANALYSIS
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Author:** Mobile Camera Signal Processing Engineer & Senior Computer Vision Architect  
**Date:** November 2026  
**Status:** SPECIFICATION RATIFIED & EXPERIMENTALLY ISOLATED

---

## 1. Physical Principle: Specular vs. Diffuse Surface Reflection

When incident light strikes a surface, the reflected radiance is governed by the surface bidirectional reflectance distribution function (BRDF):
1. **Diffuse Reflection (Lambertian):** Light penetrates the surface layers, undergoes multiple scattering events, and is re-emitted uniformly across all viewing angles. Human skin is predominantly Lambertian.
2. **Specular Reflection (Fresnel):** Light reflects directly off the boundary layer according to Snell's law, forming a sharp virtual image of the illuminant. On human eyes, the thin tear film covering the cornea acts as a smooth, wet spherical reflector with an index of refraction $n \approx 1.336$.

When an active light source (such as a phone screen flashing white or cyan) illuminates a subject:
- A curved, wet cornea produces a **small, high-intensity, compact specular highlight spot** (Purkinje image I).
- A flat electronic display panel (such as an iPad or phone screen used as a spoof instrument) reflects light off flat cover glass ($r = \infty$), producing a **broad, diffuse, wash-out reflection** or planar specular glare.

---

## 2. Mathematical Definition of `specularHighlightFeatureScore`

Because standard commodity mobile RGB sensors lack calibrated optical power or stereo infrared keratometry, the feature is computed as an **image-derived 2D heuristic** rather than a true 3D physical surface curvature:

### 2.1. Pixel Intensity Thresholding
Within the evaluated ocular bounding box $ROI_{\text{eye}}$, pixels reaching the saturation floor ($I(x, y) \ge 250$ in 8-bit space) are detected:
$$S_{\text{saturated}} = \{ (x, y) \in ROI_{\text{eye}} : I(x, y) \ge 250 \}$$

### 2.2. Area Ratio & Compactness Scoring
Let $N_{\text{sat}} = |S_{\text{saturated}}|$ and $A_{\text{ROI}} = W_{\text{ROI}} \times H_{\text{ROI}}$. The saturation area ratio is:
$$R_{\text{sat}} = \frac{N_{\text{sat}}}{A_{\text{ROI}}}$$

The heuristic score is defined by piecewise linear bounds:
$$S_{\text{specular}} = \begin{cases} 
0.0, & \text{if } N_{\text{sat}} = 0 \quad (\text{No highlight detected}) \\
\min\left(1.0, \frac{0.04 - R_{\text{sat}}}{0.035}\right), & \text{if } 0.0005 \le R_{\text{sat}} \le 0.04 \quad (\text{Compact specular spot}) \\
0.10, & \text{if } R_{\text{sat}} > 0.04 \quad (\text{Diffuse planar wash-out})
\end{cases}$$

---

## 3. Sensor Noise, Exposure, and Ambient Interaction

| Parameter | Impact on Specular Feature | Defensive Handling |
| :--- | :--- | :--- |
| **High Camera Exposure (Overexposure)** | Blooming causes genuine corneal glints to expand in pixel area. | Overexposure ceiling ($R_{\text{sat}} > 0.04$) downgrades score to $0.10$. |
| **Low Ambient Light (Dim Room)** | Fewer saturated pixels reach $250$. | Active screen chromatic pulse provides localized illumination. |
| **Sensor Shot Noise (High ISO)** | Salt-and-pepper noise creates isolated 1-pixel spikes. | Morphological filtering requires connected component area $\ge 4\,\text{px}$. |

---

## 4. Implementation and Test Status

The specular feature extractor is implemented in `OpticalDisplayFeatureExtractor.extractFromGrayscalePlane()` and verified by unit test fixtures `2.1`, `2.2`, and `2.3` in `phase20_8_optical_pad.test.ts`:
- Compact glint fixture ($3 \times 3$ on $64 \times 64$): Score $= 0.8500$.
- Diffuse wash fixture ($25 \times 25$ on $64 \times 64$): Score $= 0.1000$.
- Zero saturated pixels fixture: Score $= 0.0000$.
