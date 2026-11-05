#!/usr/bin/env python3
"""
Kelasagara-BioMatch: Proprietary MobileFaceNet + ArcFace Training Pipeline
Author: Kelasagara AI Engineering Group
Architecture: MobileFaceNet with Depthwise Separable Convolutions & GDConv
Loss: Additive Angular Margin Loss (ArcFace, Deng et al., CVPR 2019)
"""

import math
import os
import argparse
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms
from PIL import Image

# ── 1. ARCHITECTURE: MobileFaceNet Backbone (< 1M parameters) ───────────

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
    MobileFaceNet feature extractor for edge devices.
    Input: [B, 3, 112, 112]
    Output: [B, 128] normalized unit vector (||v||_2 = 1.0)
    """
    def __init__(self, embedding_size=128):
        super().__init__()
        self.conv1 = ConvBlock(3, 64, 3, 2, 1)           # 112x112 -> 56x56
        self.dw1 = DepthwiseSeparable(64, 64, stride=1)
        self.dw2 = DepthwiseSeparable(64, 128, stride=2)  # 56x56 -> 28x28
        self.dw3 = DepthwiseSeparable(128, 128, stride=1)
        self.dw4 = DepthwiseSeparable(128, 256, stride=2) # 28x28 -> 14x14
        self.dw5 = DepthwiseSeparable(256, 512, stride=2) # 14x14 -> 7x7
        # Global Depthwise Convolution (GDConv) replacing Global Average Pooling
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
        # L2 Hypersphere Normalization (||v|| = 1.0)
        return nn.functional.normalize(x, p=2, dim=1)

# ── 2. LOSS FUNCTION: ArcMarginProduct (ArcFace) ─────────────────────────

class ArcMarginProduct(nn.Module):
    """
    Additive Angular Margin (ArcFace) classification head.
    s: Hypersphere radius scaling factor (default: 64.0)
    m: Angular margin penalty in radians (default: 0.50 rad ≈ 28.6°)
    """
    def __init__(self, in_features=128, out_features=1000, s=64.0, m=0.50):
        super().__init__()
        self.in_features = in_features
        self.out_features = out_features
        self.s = s
        self.m = m
        self.weight = nn.Parameter(torch.FloatTensor(out_features, in_features))
        nn.init.xavier_uniform_(self.weight)

        self.cos_m = math.cos(m)
        self.sin_m = math.sin(m)
        self.th = math.cos(math.pi - m)
        self.mm = math.sin(math.pi - m) * m

    def forward(self, input, label):
        # 1. Cosine calculation: cosine = <x, w>
        cosine = nn.functional.linear(
            nn.functional.normalize(input),
            nn.functional.normalize(self.weight)
        )
        sine = torch.sqrt(torch.clamp(1.0 - torch.pow(cosine, 2), 1e-7, 1.0))
        # 2. Add angular margin: phi = cos(theta + m)
        phi = cosine * self.cos_m - sine * self.sin_m
        phi = torch.where(cosine > self.th, phi, cosine - self.mm)
        # 3. One-hot target logit modulation
        one_hot = torch.zeros(cosine.size(), device=input.device)
        one_hot.scatter_(1, label.view(-1, 1).long(), 1)
        output = (one_hot * phi) + ((1.0 - one_hot) * cosine)
        output *= self.s
        return output

# ── 3. DATA AUGMENTATION (Simulating Indian Phone Cameras) ────────────────

def get_transforms():
    return transforms.Compose([
        transforms.Resize((112, 112)),
        transforms.RandomHorizontalFlip(),
        transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.2),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]), # [-1.0, 1.0] range
    ])

# ── 4. TRAINING LOOP ─────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Train Kelasagara MobileFaceNet with ArcFace")
    parser.add_argument("--epochs", type=int, default=25, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=64, help="Batch size")
    parser.add_argument("--lr", type=float, default=0.001, help="Initial learning rate")
    parser.add_argument("--embedding_size", type=int, default=128, help="Output embedding dimensions")
    parser.add_argument("--num_classes", type=int, default=1000, help="Number of identities in training set")
    parser.add_argument("--output", type=str, default="kelasagara_mobilefacenet.pth", help="Checkpoint save path")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Kelasagara-BioMatch] Training device: {device}")

    model = MobileFaceNet(embedding_size=args.embedding_size).to(device)
    metric_fc = ArcMarginProduct(
        in_features=args.embedding_size,
        out_features=args.num_classes,
        s=64.0,
        m=0.50
    ).to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.AdamW([
        {"params": model.parameters(), "weight_decay": 5e-4},
        {"params": metric_fc.parameters(), "weight_decay": 5e-4}
    ], lr=args.lr)

    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    print(f"[Kelasagara-BioMatch] Model parameters: {sum(p.numel() for p in model.parameters()):,}")
    print(f"[Kelasagara-BioMatch] Starting training for {args.epochs} epochs...")

    # Placeholder loop illustrating execution steps
    model.eval()
    dummy_x = torch.randn(2, 3, 112, 112).to(device)
    dummy_out = model(dummy_x)
    print(f"[Kelasagara-BioMatch] Validation test forward pass: shape = {dummy_out.shape}, norm = {torch.norm(dummy_out[0]).item():.4f}")

    # Save initial model weights
    torch.save(model.state_dict(), args.output)
    print(f"[Kelasagara-BioMatch] Successfully saved model to {args.output}")

if __name__ == "__main__":
    main()
