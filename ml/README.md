# 🧠 Kelasagara-BioMatch: AI Model Training & Export Guide

This directory contains the complete source code for training and exporting the **`Kelasagara-BioMatch`** proprietary edge face authentication model (MobileFaceNet with Additive Angular Margin ArcFace loss).

---

## Architecture Overview

```
Input: 112 x 112 x 3 RGB Face Crop
  │
  ├── ConvBlock (3 -> 64, stride 2) [56x56]
  ├── DepthwiseSeparable (64 -> 64)
  ├── DepthwiseSeparable (64 -> 128, stride 2) [28x28]
  ├── DepthwiseSeparable (128 -> 128)
  ├── DepthwiseSeparable (128 -> 256, stride 2) [14x14]
  ├── DepthwiseSeparable (256 -> 512, stride 2) [7x7]
  ├── Global Depthwise Conv (512 -> 512, 7x7 kernel) [1x1]
  ├── Linear Projection (512 -> 128)
  └── L2 Hypersphere Normalization (||v||_2 = 1.0)
Output: 128-D Unit Hypersphere Embedding Vector
```

---

## 1. Quick Training on Google Colab (Free T4 GPU)

1. Open [Google Colab](https://colab.research.google.com).
2. Set runtime type to **GPU** (`Runtime > Change runtime type > T4 GPU`).
3. Clone or upload this folder:
   ```bash
   pip install torch torchvision onnx tensorflow onnx-tf pillow
   ```
4. Run training:
   ```bash
   python train_mobilefacenet.py --epochs 25 --batch_size 64 --lr 0.001
   ```
5. Export to quantized Android TFLite:
   ```bash
   python export_tflite_int8.py
   ```
6. Download the resulting `kelasagara_facenet.tflite` (approx. 2.2 MB) and copy it to:
   `assets/models/kelasagara_facenet.tflite` in your Flutter app.

---

## 2. Mathematical Hyperparameters

* **Embedding Dimension ($d$)**: 128
* **ArcFace Scale Factor ($s$)**: 64.0
* **ArcFace Angular Margin ($m$)**: 0.50 radians ($\approx 28.6^\circ$)
* **Cosine Matching Threshold ($\tau$)**:
  * $\ge 0.74$: Duplicate / Match (Same Human)
  * $< 0.65$: Distinct Individual
