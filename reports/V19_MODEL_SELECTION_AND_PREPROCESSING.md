# V19 Model Selection and Preprocessing Report

## 1. Primary Model Specification & Provenance
- **Model Name:** `face_recognition_sface_2021dec.onnx`
- **Source:** OpenCV Zoo (`models/face_recognition_sface/face_recognition_sface_2021dec.onnx`)
- **License:** Apache 2.0 (Code + Model Weights cleared for commercial deployment)
- **Architecture:** MobileFaceNet backbone with Sigmoid-Constrained Hypersphere Loss (Zhong et al., IEEE T-BIOM 2021)
- **Input Tensor:** Shape `[1, 3, 112, 112]`, BGR channel order, Float32
- **Output Tensor:** 128-dimensional Float32 vector on $\mathbb{S}^{127}$
- **Runtime:** ONNX Runtime Node.js (`onnxruntime-node@1.20.1`)

## 2. Canonical Preprocessing Pipeline
To guarantee zero drift between enrollment and verification, the pipeline executes these exact deterministic steps:
1. **Raw Frame Ingestion:** JPEG byte stream decoded via `sharp` buffer.
2. **Face Detection & 5-Point Landmarks:** OpenCV YuNet detects bounding box and 5 canonical facial anchors:
   $$\{ \text{Left Eye}, \text{Right Eye}, \text{Nose Tip}, \text{Left Mouth Corner}, \text{Right Mouth Corner} \}$$
3. **Similarity Transform:** Computes 2D affine transformation mapping detected landmarks to canonical SFace anchor points in $112 \times 112$ space.
4. **Channel Order & Normalization:**
   - Resized to $112 \times 112 \times 3$ BGR.
   - Per-pixel normalization: $(p - 127.5) / 128.0$.
   - Tensor transposed to NCHW: `[1, 3, 112, 112]`.
5. **Inference & L2 Hypersphere Projection:**
   $$\hat{v} = \frac{v}{\|v\|_2 + \epsilon}, \quad \|\hat{v}\|_2 = 1.0 \pm 10^{-6}$$

## 3. Candidate Model Research & Comparative Evaluation
| Model Architecture | License | Dimension | Published Benchmark | Inference Latency | Kelasagara Viability |
|:---|:---:|:---:|:---:|:---:|:---|
| **SFace (Current)** | Apache 2.0 | 128-D | LFW 99.60%, IJB-C TAR@FAR=1e-4: 92.8% | 11.1 ms (CPU) | **Cleared for Controlled Test** |
| **ArcFace (ResNet-50)** | Non-commercial / MIT (varies) | 512-D | LFW 99.82%, IJB-C TAR@FAR=1e-4: 95.6% | 68.0 ms (Heavy) | High memory footprint for budget server |
| **AdaFace (CVPR 2022)** | Research Only | 512-D | LFW 99.82%, Quality-adaptive margin | 45.0 ms (GPU needed) | License restricted; requires custom training |
| **MagFace (CVPR 2021)** | Apache 2.0 | 512-D | LFW 99.83%, Magnitude encodes quality | 42.0 ms | Feature magnitude cannot be back-ported to SFace |

> [!WARNING]
> **Proprietary Claims Boundary:** Pretrained SFace deployed inside Kelasagara is an **inference pipeline integration**, NOT a proprietary trained model. True proprietary ownership requires training custom weights on an ethically sourced, consented Indian demographic dataset with independent benchmark validation.

> [!NOTE]
> **Norm vs Quality Correction:** In MagFace and AdaFace, feature norm $||\mathbf{z}||$ correlates with image quality because of their loss function formulation. In SFace, outputs are strictly normalized to unit length on $\mathbb{S}^{127}$; raw unnormalized logit norm must NOT be treated as a calibrated ISO quality score.
