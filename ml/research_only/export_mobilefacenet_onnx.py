#!/usr/bin/env python3
"""
Kelasagara-BioMatch: Export MobileFaceNet to ONNX
Pure PyTorch implementation (requires only torch and numpy).
Architecture: MobileFaceNet (112x112x3 RGB -> 128-D Unit Hypersphere Vector)
License: Apache 2.0 (Permissible for commercial use)
"""

import os
import torch
import torch.nn as nn

class ConvBlock(nn.Module):
    def __init__(self, in_c, out_c, kernel, stride, padding, groups=1):
        super().__init__()
        self.conv = nn.Conv2d(in_c, out_c, kernel, stride, padding, groups=groups, bias=False)
        self.bn = nn.BatchNorm2d(out_c)
        self.prelu = nn.PReLU()

    def forward(self, x):
        return self.prelu(self.bn(self.conv(x)))

class DepthwiseSeparable(nn.Module):
    def __init__(self, in_c, out_c, stride=1):
        super().__init__()
        self.dw = nn.Conv2d(in_c, in_c, 3, stride, 1, groups=in_c, bias=False)
        self.bn1 = nn.BatchNorm2d(in_c)
        self.prelu = nn.PReLU()
        self.pw = nn.Conv2d(in_c, out_c, 1, 1, 0, bias=False)
        self.bn2 = nn.BatchNorm2d(out_c)

    def forward(self, x):
        return self.bn2(self.pw(self.prelu(self.bn1(self.dw(x)))))

class MobileFaceNet(nn.Module):
    """
    MobileFaceNet lightweight facial recognition backbone.
    Input: [Batch, 3, 112, 112] (RGB, values in [-1.0, 1.0])
    Output: [Batch, 128] (L2-normalized unit vector on S^127)
    """
    def __init__(self, embedding_size=128):
        super().__init__()
        self.conv1 = ConvBlock(3, 64, 3, 2, 1)            # 112x112 -> 56x56
        self.dw1 = DepthwiseSeparable(64, 64, stride=1)
        self.dw2 = DepthwiseSeparable(64, 128, stride=2)   # 56x56 -> 28x28
        self.dw3 = DepthwiseSeparable(128, 128, stride=1)
        self.dw4 = DepthwiseSeparable(128, 256, stride=2)  # 28x28 -> 14x14
        self.dw5 = DepthwiseSeparable(256, 512, stride=2)  # 14x14 -> 7x7
        self.gdconv = nn.Conv2d(512, 512, 7, 1, 0, groups=512, bias=False)
        self.bn_gd = nn.BatchNorm2d(512)
        self.fc = nn.Linear(512, embedding_size, bias=False)
        self.bn_out = nn.BatchNorm1d(embedding_size)

    def forward(self, x):
        x = self.conv1(x)
        x = self.dw1(x)
        x = self.dw2(x)
        x = self.dw3(x)
        x = self.dw4(x)
        x = self.dw5(x)
        x = self.bn_gd(self.gdconv(x))
        x = x.view(x.size(0), -1)
        x = self.fc(x)
        x = self.bn_out(x)
        # Unit hypersphere normalization (||v||_2 = 1.0)
        return nn.functional.normalize(x, p=2, dim=1)

def export_onnx(output_path="ml/kelasagara_mobilefacenet.onnx"):
    print("=== EXPORTING MOBILEFACENET TO ONNX ===")
    model = MobileFaceNet(embedding_size=128)
    model.eval()

    # Total parameters
    total_params = sum(p.numel() for p in model.parameters())
    print(f"Total model parameters: {total_params:,} (< 1M params)")

    dummy_input = torch.randn(1, 3, 112, 112, dtype=torch.float32)

    with torch.no_grad():
        output = model(dummy_input)
        norm = torch.norm(output, p=2, dim=1).item()
        assert abs(norm - 1.0) < 1e-5, f"Expected norm 1.0, got {norm}"
        print(f"Inference output shape: {list(output.shape)}, L2 Norm: {norm:.6f}")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=14,
        do_constant_folding=True,
        input_names=["input_tensor"],
        output_names=["embedding"],
        dynamic_axes={"input_tensor": {0: "batch_size"}, "embedding": {0: "batch_size"}},
    )
    file_size_kb = os.path.getsize(output_path) / 1024
    print(f"Exported ONNX model to: {output_path} ({file_size_kb:.1f} KB)")
    print("Export complete!")

if __name__ == "__main__":
    export_onnx()
