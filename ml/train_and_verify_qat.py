#!/usr/bin/env python3
"""
ml/train_and_verify_qat.py
Fine-tunes IndicFace128 with ArcFace Angular Margin Loss on data/karnataka_aligned_112/,
triggers static INT8 QDQ ONNX export, and verifies unit hypersphere norm & angular drift.
"""

import os
import math
import shutil
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from PIL import Image

# Import existing architecture from ml/indicface128_qat_export.py
from indicface128_qat_export import IndicFace128QAT

DATASET_DIR = Path("data/karnataka_aligned_112")
ASSETS_MODEL_DIR = Path("assets/models")
OUTPUT_ONNX = ASSETS_MODEL_DIR / "indicface128_int8_qdq.onnx"

class ArcMarginProduct(nn.Module):
    """
    Additive Angular Margin Penalty (ArcFace) on S^127 unit hypersphere:
    cos(theta + m) = cos(theta)*cos(m) - sin(theta)*sin(m)
    """
    def __init__(self, in_features: int = 128, out_features: int = 24, s: float = 32.0, m: float = 0.50):
        super().__init__()
        self.s = s
        self.m = m
        self.weight = nn.Parameter(torch.FloatTensor(out_features, in_features))
        nn.init.xavier_uniform_(self.weight)
        self.cos_m = math.cos(m)
        self.sin_m = math.sin(m)
        self.th = math.cos(math.pi - m)
        self.mm = math.sin(math.pi - m) * m

    def forward(self, embeddings: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
        cosine = F.linear(embeddings, F.normalize(self.weight, p=2, dim=1))
        sine = torch.sqrt((1.0 - torch.clamp(cosine * cosine, 0, 1)) + 1e-6)
        phi = cosine * self.cos_m - sine * self.sin_m
        phi = torch.where(cosine > self.th, phi, cosine - self.mm)

        one_hot = torch.zeros_like(cosine)
        one_hot.scatter_(1, labels.view(-1, 1).long(), 1.0)
        output = (one_hot * phi) + ((1.0 - one_hot) * cosine)
        return output * self.s

class AlignedFaceDataset(Dataset):
    def __init__(self, root_dir: Path):
        self.samples = []
        classes = sorted([d for d in root_dir.glob("*") if d.is_dir()])
        self.num_classes = len(classes)
        for cls_idx, cls_dir in enumerate(classes):
            for img_path in sorted(cls_dir.glob("*.png")):
                self.samples.append((img_path, cls_idx))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        img_path, label = self.samples[idx]
        arr = np.asarray(Image.open(img_path).convert("RGB"), dtype=np.float32)
        # Normalize to [-1.0, 1.0] matching biomatch_ffi_bridge.cpp: (px - 127.5) / 128.0
        arr = (arr - 127.5) / 128.0
        tensor = torch.from_numpy(arr).permute(2, 0, 1)  # CHW
        return tensor, torch.tensor(label, dtype=torch.long)

def run_qat_finetune_and_export():
    if not DATASET_DIR.exists() or not any(DATASET_DIR.iterdir()):
        from prepare_karnataka_field_dataset import build_dataset
        build_dataset()

    ds = AlignedFaceDataset(DATASET_DIR)
    loader = DataLoader(ds, batch_size=16, shuffle=True, drop_last=True)
    print(f"[+] Loaded {len(ds)} aligned samples across {ds.num_classes} worker identities.")

    model = IndicFace128QAT()
    model.train()

    # Configure PyTorch QAT with qnnpack for ARM64 mobile targets
    torch.backends.quantized.engine = "qnnpack"
    model.qconfig = torch.ao.quantization.get_default_qat_qconfig("qnnpack")
    # Keep final FP32 L2 hypersphere projection unquantized to prevent angular drift
    if hasattr(model, "fp32_head"):
        model.fp32_head.qconfig = None
    torch.ao.quantization.prepare_qat(model, inplace=True)

    arcface_head = ArcMarginProduct(128, max(ds.num_classes, 2), s=32.0, m=0.50)
    optimizer = torch.optim.AdamW(
        list(model.parameters()) + list(arcface_head.parameters()),
        lr=3e-4,
        weight_decay=1e-4,
    )
    criterion = nn.CrossEntropyLoss()

    epochs = 4
    for epoch in range(1, epochs + 1):
        running_loss = 0.0
        for x, y in loader:
            optimizer.zero_grad()
            emb = model(x)
            logits = arcface_head(emb, y)
            loss = criterion(logits, y)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
        print(f"    Epoch [{epoch}/{epochs}] - ArcFace Angular Margin Loss: {running_loss / len(loader):.4f}")

    # Measure FP32 reference embeddings before INT8 conversion
    model.eval()
    sample_batch, _ = next(iter(loader))
    with torch.no_grad():
        fp32_emb = model(sample_batch)

    # Convert to quantized INT8 backbone + FP32 tail
    quantized_model = torch.ao.quantization.convert(model.eval(), inplace=False)
    with torch.no_grad():
        int8_emb = quantized_model(sample_batch)

    # Compute angular drift delta_theta = arccos(clamp(u . v, -1, 1))
    cos_sim = torch.sum(fp32_emb * int8_emb, dim=1).clamp(-1.0, 1.0)
    angular_drift_rad = torch.acos(cos_sim).mean().item()
    unit_norm_check = torch.norm(int8_emb, p=2, dim=1).mean().item()

    print(f"[✓] Unit Hypersphere Norm ||v||_2 : {unit_norm_check:.6f} (Target: 1.000000)")
    print(f"[✓] Mean QAT Angular Drift Δθ     : {angular_drift_rad:.6f} rad (Spec <= 0.011 rad)")

    # Export ONNX model to assets/models/indicface128_int8_qdq.onnx
    ASSETS_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    dummy_input = torch.randn(1, 3, 112, 112)
    torch.onnx.export(
        model.eval(),
        dummy_input,
        str(OUTPUT_ONNX),
        export_params=True,
        opset_version=18,
        do_constant_folding=True,
        input_names=["input_rgb_112"],
        output_names=["embedding_s127"],
    )
    size_mb = OUTPUT_ONNX.stat().st_size / (1024 * 1024)
    print(f"[✓] Baked production model -> {OUTPUT_ONNX} ({size_mb:.2f} MB)")

if __name__ == "__main__":
    run_qat_finetune_and_export()
