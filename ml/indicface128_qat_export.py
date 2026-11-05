#!/usr/bin/env python3
"""
KELASAGARA BIOMATCH (v17) - INDICFACE-128 QAT, CALIBRATION & ONNX INT8 PIPELINE
===============================================================================
Executes:
  1. QAT-ready MobileFaceNet-GDC (128-D) with fused Conv-BN-ReLU6 & FloatFunctional skips
  2. South-Asian field augmentation & ONNX CalibrationDataReader (112x112 aligned RGB)
  3. 2-Stage Quantization-Aware Training (QAT) with Sub-Center MagFace/ArcFace Loss
  4. ONNX Opset 18 Export + Graph Pre-processing + Static QDQ INT8 Quantization
  5. Angular Drift (radians/degrees) & FAR/FRR Verification at 0.74 Cosine Threshold
"""

import os
import math
import glob
import copy
import logging
from pathlib import Path
from typing import List, Tuple, Dict, Optional

import cv2
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torch.ao.quantization import (
    QuantStub,
    DeQuantStub,
    QConfig,
    MovingAverageMinMaxObserver,
    PerChannelMinMaxObserver,
    prepare_qat,
    disable_observer,
)
from torch.ao.nn.quantized import FloatFunctional

import onnx
import onnxruntime as ort
from onnxruntime.quantization import (
    CalibrationDataReader,
    CalibrationMethod,
    QuantFormat,
    QuantType,
    quantize_static,
)
from onnxruntime.quantization.shape_inference import quant_pre_process

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("IndicFace128-QAT")


# ============================================================================
# 1. QAT-COMPATIBLE INDICFACE-128 BACKBONE (FUSABLE CONV-BN-RELU6 + GDC)
# ============================================================================
class ConvBNReLU6(nn.Sequential):
    """Fusable Conv2d + BatchNorm2d + ReLU6 module for XNNPACK / NNAPI INT8."""
    def __init__(self, in_c: int, out_c: int, k: int = 3, s: int = 1, p: int = 1, g: int = 1):
        super().__init__(
            nn.Conv2d(in_c, out_c, kernel_size=k, stride=s, padding=p, groups=g, bias=False),
            nn.BatchNorm2d(out_c),
            nn.ReLU6(inplace=False),
        )


class ConvBNLinear(nn.Sequential):
    """Fusable Conv2d + BatchNorm2d without activation (used in linear bottlenecks & GDC)."""
    def __init__(self, in_c: int, out_c: int, k: int = 1, s: int = 1, p: int = 0, g: int = 1):
        super().__init__(
            nn.Conv2d(in_c, out_c, kernel_size=k, stride=s, padding=p, groups=g, bias=False),
            nn.BatchNorm2d(out_c),
        )


class QATDepthwiseSeparableBottleneck(nn.Module):
    """
    Inverted Residual Bottleneck with FloatFunctional skip-addition
    so QAT observers track the dynamic range of the residual sum.
    """
    def __init__(self, in_c: int, out_c: int, stride: int, expansion: int):
        super().__init__()
        self.use_residual = (stride == 1) and (in_c == out_c)
        hidden_dim = in_c * expansion

        self.pw_expand = ConvBNReLU6(in_c, hidden_dim, k=1, s=1, p=0, g=1)
        self.dw_conv = ConvBNReLU6(hidden_dim, hidden_dim, k=3, s=stride, p=1, g=hidden_dim)
        self.pw_linear = ConvBNLinear(hidden_dim, out_c, k=1, s=1, p=0, g=1)
        self.skip_add = FloatFunctional()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out = self.pw_expand(x)
        out = self.dw_conv(out)
        out = self.pw_linear(out)
        if self.use_residual:
            return self.skip_add.add(x, out)
        return out


class IndicFace128QAT(nn.Module):
    """
    Production 128-D Backbone for Kelasagara BioMatch (v17).
    Quantizes all convolutional & GDC stages to INT8 via QuantStub/DeQuantStub,
    while keeping the final BatchNorm1d + L2 hypersphere projection in FP32.
    """
    def __init__(self, embedding_dim: int = 128):
        super().__init__()
        self.quant = QuantStub()

        self.conv1 = ConvBNReLU6(3, 64, k=3, s=2, p=1, g=1)          # 56x56x64
        self.dw_conv2 = ConvBNReLU6(64, 64, k=3, s=1, p=1, g=64)     # 56x56x64

        stage_cfg = [
            (2, 64, 5, 2),   # 28x28x64
            (4, 128, 1, 2),  # 14x14x128
            (2, 128, 6, 1),  # 14x14x128
            (4, 128, 1, 2),  # 7x7x128
            (2, 128, 2, 1),  # 7x7x128
        ]

        blocks = []
        in_c = 64
        for t, c, n, s in stage_cfg:
            for i in range(n):
                stride = s if i == 0 else 1
                blocks.append(QATDepthwiseSeparableBottleneck(in_c, c, stride, t))
                in_c = c
        self.features = nn.Sequential(*blocks)

        self.conv_sep = ConvBNReLU6(128, 512, k=1, s=1, p=0, g=1)    # 7x7x512
        self.gdc = ConvBNLinear(512, 512, k=7, s=1, p=0, g=512)      # 1x1x512
        self.flatten = nn.Flatten()
        self.linear = nn.Linear(512, embedding_dim, bias=False)

        # Dequantize back to FP32 prior to 1D BatchNorm and L2 unit hypersphere division
        self.dequant = DeQuantStub()
        self.bn_out = nn.BatchNorm1d(embedding_dim, affine=True)

        self._init_weights()

    def _init_weights(self) -> None:
        for m in self.modules():
            if isinstance(m, nn.Conv2d):
                nn.init.kaiming_normal_(m.weight, mode="fan_out", nonlinearity="relu")
            elif isinstance(m, (nn.BatchNorm2d, nn.BatchNorm1d)):
                nn.init.constant_(m.weight, 1.0)
                nn.init.constant_(m.bias, 0.0)
            elif isinstance(m, nn.Linear):
                nn.init.xavier_normal_(m.weight)

    def fuse_model(self) -> None:
        """
        Fuses Conv2d + BatchNorm2d (+ ReLU6) across the entire backbone prior to QAT.
        """
        torch.ao.quantization.fuse_modules_qat(self.conv1, ["0", "1", "2"], inplace=True)
        torch.ao.quantization.fuse_modules_qat(self.dw_conv2, ["0", "1", "2"], inplace=True)
        for m in self.features:
            if isinstance(m, QATDepthwiseSeparableBottleneck):
                torch.ao.quantization.fuse_modules_qat(m.pw_expand, ["0", "1", "2"], inplace=True)
                torch.ao.quantization.fuse_modules_qat(m.dw_conv, ["0", "1", "2"], inplace=True)
                torch.ao.quantization.fuse_modules_qat(m.pw_linear, ["0", "1"], inplace=True)
        torch.ao.quantization.fuse_modules_qat(self.conv_sep, ["0", "1", "2"], inplace=True)
        torch.ao.quantization.fuse_modules_qat(self.gdc, ["0", "1"], inplace=True)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        x = self.quant(x)
        x = self.conv1(x)
        x = self.dw_conv2(x)
        x = self.features(x)
        x = self.conv_sep(x)
        x = self.gdc(x)
        x = self.flatten(x)
        x = self.linear(x)
        x = self.dequant(x)

        z = self.bn_out(x)
        # MagFace pre-normalized quality norm ||z||_2 (threshold >= 18.5 in production)
        quality_norm = torch.norm(z, p=2, dim=1, keepdim=True).clamp(min=1e-12)
        normalized_embedding = z / quality_norm
        return normalized_embedding, quality_norm


# ============================================================================
# 2. SUB-CENTER MAGFACE / ARCFACE QUALITY-ADAPTIVE LOSS
# ============================================================================
class SubCenterMagArcLoss(nn.Module):
    def __init__(
        self,
        num_classes: int,
        embedding_dim: int = 128,
        sub_centers: int = 3,
        scale: float = 64.0,
        l_a: float = 10.0,
        u_a: float = 110.0,
        l_m: float = 0.40,
        u_m: float = 0.80,
        lambda_g: float = 20.0,
    ):
        super().__init__()
        self.num_classes = num_classes
        self.sub_centers = sub_centers
        self.scale = scale
        self.l_a = l_a
        self.u_a = u_a
        self.l_m = l_m
        self.u_m = u_m
        self.lambda_g = lambda_g

        self.weight = nn.Parameter(torch.FloatTensor(num_classes * sub_centers, embedding_dim))
        nn.init.xavier_uniform_(self.weight)

    def forward(
        self,
        normalized_embeddings: torch.Tensor,
        quality_norms: torch.Tensor,
        labels: torch.Tensor,
    ) -> torch.Tensor:
        a = torch.clamp(quality_norms, min=self.l_a, max=self.u_a)
        margin = ((self.u_m - self.l_m) / (self.u_a - self.l_a)) * (a - self.l_a) + self.l_m

        norm_weights = F.normalize(self.weight, p=2, dim=1)
        cos_theta_all = F.linear(normalized_embeddings, norm_weights)
        cos_theta_all = cos_theta_all.view(-1, self.num_classes, self.sub_centers)

        cos_theta, _ = torch.max(cos_theta_all, dim=2)
        cos_theta = cos_theta.clamp(-1.0 + 1e-7, 1.0 - 1e-7)

        sin_theta = torch.sqrt(1.0 - torch.pow(cos_theta, 2))
        cos_m = torch.cos(margin)
        sin_m = torch.sin(margin)
        phi = cos_theta * cos_m - sin_theta * sin_m

        th = torch.cos(math.pi - margin)
        mm = torch.sin(math.pi - margin) * margin
        phi = torch.where(cos_theta > th, phi, cos_theta - mm)

        one_hot = torch.zeros_like(cos_theta)
        one_hot.scatter_(1, labels.view(-1, 1).long(), 1.0)

        logits = self.scale * ((one_hot * phi) + ((1.0 - one_hot) * cos_theta))
        cls_loss = F.cross_entropy(logits, labels)
        reg_loss = torch.mean((a / (self.u_a ** 2)) + (1.0 / a))
        return cls_loss + self.lambda_g * reg_loss


# ============================================================================
# 3. DATASET & ONNX RUNTIME CALIBRATION READER (112x112 ALIGNED FACES)
# ============================================================================
class KarnatakaFieldFaceDataset(Dataset):
    """
    Loads Umeyama-aligned 112x112 RGB images arranged in class folders:
        root_dir/worker_0001/img_01.jpg
    If `root_dir` does not exist, synthesizes structured calibration/training tensors
    so this script can be smoke-tested immediately in CI/CD.
    """
    def __init__(
        self,
        root_dir: Optional[str] = None,
        is_train: bool = True,
        synthetic_samples: int = 512,
        num_classes: int = 64,
    ):
        self.is_train = is_train
        self.samples: List[Tuple[str, int]] = []
        self.num_classes = num_classes

        if root_dir and os.path.isdir(root_dir):
            class_folders = sorted([
                d for d in os.listdir(root_dir)
                if os.path.isdir(os.path.join(root_dir, d))
            ])
            self.num_classes = max(len(class_folders), 1)
            for label_idx, folder in enumerate(class_folders):
                for img_path in glob.glob(os.path.join(root_dir, folder, "*.jpg")) + \
                                glob.glob(os.path.join(root_dir, folder, "*.png")):
                    self.samples.append((img_path, label_idx))

        self.use_synthetic = len(self.samples) == 0
        self.synthetic_samples = synthetic_samples

    def __len__(self) -> int:
        return self.synthetic_samples if self.use_synthetic else len(self.samples)

    @staticmethod
    def _apply_field_augmentations(rgb_img: np.ndarray) -> np.ndarray:
        """
        Simulates rural Karnataka mobile capture conditions:
        harsh overhead sunlight gamma shifts, low-end CMOS sensor ISO noise,
        and mild motion blur.
        """
        img = rgb_img.astype(np.float32)

        # 1. Random harsh sunlight / shadow gamma adjustment (Fitzpatrick III-VI invariance)
        if np.random.rand() < 0.5:
            gamma = np.random.uniform(0.75, 1.35)
            img = 255.0 * np.power(np.clip(img / 255.0, 0.0, 1.0), gamma)

        # 2. Simulated CMOS sensor ISO grain on budget Android front cameras
        if np.random.rand() < 0.4:
            sigma = np.random.uniform(2.0, 7.5)
            noise = np.random.normal(0.0, sigma, img.shape).astype(np.float32)
            img = np.clip(img + noise, 0.0, 255.0)

        # 3. Random horizontal flip
        if np.random.rand() < 0.5:
            img = np.ascontiguousarray(img[:, ::-1, :])

        return img

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, int]:
        if self.use_synthetic:
            rng = np.random.default_rng(seed=idx + 1000)
            label = idx % self.num_classes
            # Deterministic class prototype + perturbation to simulate structured faces
            class_rng = np.random.default_rng(seed=label + 42)
            base_face = class_rng.uniform(40.0, 215.0, size=(112, 112, 3)).astype(np.float32)
            jitter = rng.normal(0.0, 12.0, size=(112, 112, 3)).astype(np.float32)
            rgb = np.clip(base_face + jitter, 0.0, 255.0)
        else:
            img_path, label = self.samples[idx]
            bgr = cv2.imread(img_path)
            if bgr is None:
                raise RuntimeError(f"Corrupted image file: {img_path}")
            bgr = cv2.resize(bgr, (112, 112), interpolation=cv2.INTER_LINEAR)
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float32)

        if self.is_train:
            rgb = self._apply_field_augmentations(rgb)

        # Normalize to [-1.0, 1.0] matching biomatch_native.cpp: (I - 127.5) / 128.0
        normalized = (rgb - 127.5) / 128.0
        chw_tensor = torch.from_numpy(normalized.transpose(2, 0, 1)).float()
        return chw_tensor, label


class IndicFaceONNXCalibrationReader(CalibrationDataReader):
    """
    Feeds representative 112x112 NCHW batches into ONNX Runtime's static
    quantizer to calibrate activation clipping thresholds.
    """
    def __init__(self, dataset: Dataset, input_name: str = "input_rgb", max_samples: int = 256):
        self.dataset = dataset
        self.input_name = input_name
        self.max_samples = min(len(dataset), max_samples)
        self.current_idx = 0

    def get_next(self) -> Optional[Dict[str, np.ndarray]]:
        if self.current_idx >= self.max_samples:
            return None
        tensor_chw, _ = self.dataset[self.current_idx]
        self.current_idx += 1
        batch_nchw = tensor_chw.unsqueeze(0).cpu().numpy().astype(np.float32)
        return {self.input_name: batch_nchw}

    def rewind(self) -> None:
        self.current_idx = 0


# ============================================================================
# 4. QUANTIZATION-AWARE TRAINING (QAT) LOOP WITH BN & OBSERVER FREEZING
# ============================================================================
def freeze_bn_stats(module: nn.Module) -> None:
    """Freezes BatchNorm running mean/variance during final QAT epochs."""
    if isinstance(module, (nn.BatchNorm2d, nn.BatchNorm1d, nn.intrinsic.qat.ConvBnReLU2d, nn.intrinsic.qat.ConvBn2d)):
        if hasattr(module, "freeze_bn_stats"):
            module.freeze_bn_stats()
        else:
            module.eval()


def configure_qat_model(fp32_model: IndicFace128QAT) -> IndicFace128QAT:
    """
    Fuses Conv+BN+ReLU6 layers and attaches symmetric per-channel INT8 weight
    observers and moving-average asymmetric activation observers.
    """
    qat_model = copy.deepcopy(fp32_model)
    qat_model.train()
    qat_model.fuse_model()

    qat_qconfig = QConfig(
        activation=MovingAverageMinMaxObserver.with_args(
            qscheme=torch.per_tensor_affine,
            dtype=torch.quint8,
            averaging_constant=0.01,
        ),
        weight=PerChannelMinMaxObserver.with_args(
            qscheme=torch.per_channel_symmetric,
            dtype=torch.qint8,
            ch_axis=0,
        ),
    )

    qat_model.qconfig = qat_qconfig
    # Keep the final 1D BatchNorm in FP32 to protect unit-hypersphere precision
    qat_model.bn_out.qconfig = None

    prepare_qat(qat_model, inplace=True)
    return qat_model


def run_qat_finetuning(
    fp32_model: IndicFace128QAT,
    train_loader: DataLoader,
    num_classes: int,
    device: torch.device,
    total_epochs: int = 6,
    freeze_bn_epoch: int = 4,
    freeze_obs_epoch: int = 5,
) -> IndicFace128QAT:
    logger.info("Initializing QAT model fusion and FakeQuantize observers...")
    qat_model = configure_qat_model(fp32_model).to(device)
    criterion = SubCenterMagArcLoss(num_classes=num_classes, embedding_dim=128).to(device)

    optimizer = torch.optim.SGD(
        list(qat_model.parameters()) + list(criterion.parameters()),
        lr=1e-3,
        momentum=0.9,
        weight_decay=5e-4,
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=total_epochs, eta_min=1e-5)

    for epoch in range(1, total_epochs + 1):
        qat_model.train()

        if epoch >= freeze_bn_epoch:
            qat_model.apply(freeze_bn_stats)
            logger.info(f"Epoch {epoch}/{total_epochs}: BatchNorm running statistics FROZEN.")

        if epoch >= freeze_obs_epoch:
            qat_model.apply(disable_observer)
            logger.info(f"Epoch {epoch}/{total_epochs}: Quantization range observers FROZEN.")

        running_loss = 0.0
        running_norm = 0.0
        batches = 0

        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)

            optimizer.zero_grad()
            embeddings, quality_norms = qat_model(images)
            loss = criterion(embeddings, quality_norms, labels)
            loss.backward()

            torch.nn.utils.clip_grad_norm_(qat_model.parameters(), max_norm=5.0)
            optimizer.step()

            running_loss += loss.item()
            running_norm += quality_norms.mean().item()
            batches += 1

        scheduler.step()
        logger.info(
            f"Epoch [{epoch:02d}/{total_epochs:02d}] | "
            f"QAT Loss: {running_loss / max(batches, 1):.4f} | "
            f"Mean MagFace Quality Norm ||z||_2: {running_norm / max(batches, 1):.2f}"
        )

    return qat_model


# ============================================================================
# 5. CLEAN FOLDED FP32 EXTRACTION & ONNX OPSET 18 STATIC QDQ INT8 EXPORT
# ============================================================================
def transfer_qat_weights_to_clean_fp32(qat_model: IndicFace128QAT) -> IndicFace128QAT:
    """
    Extracts QAT-adapted weights from `nn.intrinsic.qat.ConvBnReLU2d` / `ConvBn2d`
    into a clean, standard `IndicFace128QAT` graph so `torch.onnx.export` emits
    standard ONNX Opset 18 operators ready for XNNPACK/NNAPI QDQ compilation.
    """
    qat_cpu = copy.deepcopy(qat_model).cpu().eval()
    clean_model = IndicFace128QAT(embedding_dim=128).cpu().eval()

    def _copy_conv_bn(qat_seq: nn.Sequential, clean_seq: nn.Sequential) -> None:
        qat_fused = qat_seq[0]  # ConvBnReLU2d or ConvBn2d
        clean_conv: nn.Conv2d = clean_seq[0]
        clean_bn: nn.BatchNorm2d = clean_seq[1]

        clean_conv.weight.data.copy_(qat_fused.weight.detach())
        clean_bn.weight.data.copy_(qat_fused.bn.weight.detach())
        clean_bn.bias.data.copy_(qat_fused.bn.bias.detach())
        clean_bn.running_mean.data.copy_(qat_fused.bn.running_mean.detach())
        clean_bn.running_var.data.copy_(qat_fused.bn.running_var.detach())
        clean_bn.num_batches_tracked.data.copy_(qat_fused.bn.num_batches_tracked.detach())

    _copy_conv_bn(qat_cpu.conv1, clean_model.conv1)
    _copy_conv_bn(qat_cpu.dw_conv2, clean_model.dw_conv2)

    for qat_blk, clean_blk in zip(qat_cpu.features, clean_model.features):
        _copy_conv_bn(qat_blk.pw_expand, clean_blk.pw_expand)
        _copy_conv_bn(qat_blk.dw_conv, clean_blk.dw_conv)
        _copy_conv_bn(qat_blk.pw_linear, clean_blk.pw_linear)

    _copy_conv_bn(qat_cpu.conv_sep, clean_model.conv_sep)
    _copy_conv_bn(qat_cpu.gdc, clean_model.gdc)

    clean_model.linear.weight.data.copy_(qat_cpu.linear.weight.detach())
    clean_model.bn_out.weight.data.copy_(qat_cpu.bn_out.weight.detach())
    clean_model.bn_out.bias.data.copy_(qat_cpu.bn_out.bias.detach())
    clean_model.bn_out.running_mean.data.copy_(qat_cpu.bn_out.running_mean.detach())
    clean_model.bn_out.running_var.data.copy_(qat_cpu.bn_out.running_var.detach())

    return clean_model


def export_and_quantize_onnx(
    qat_model: IndicFace128QAT,
    calibration_dataset: Dataset,
    output_dir: str = "./artifacts_v17",
) -> Tuple[str, str]:
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    fp32_onnx_path = os.path.join(output_dir, "indicface128_fp32_raw.onnx")
    preproc_onnx_path = os.path.join(output_dir, "indicface128_fp32_folded.onnx")
    int8_onnx_path = os.path.join(output_dir, "indicface128_int8_qdq.onnx")

    clean_fp32_model = transfer_qat_weights_to_clean_fp32(qat_model)
    dummy_input = torch.randn(1, 3, 112, 112, dtype=torch.float32)

    logger.info(f"Exporting QAT-tuned model to ONNX Opset 18: {fp32_onnx_path}")
    torch.onnx.export(
        clean_fp32_model,
        dummy_input,
        fp32_onnx_path,
        export_params=True,
        opset_version=18,
        do_constant_folding=True,
        input_names=["input_rgb"],
        output_names=["embedding", "quality_norm"],
        # Static shape [1, 3, 112, 112] is required for mobile NNAPI / XNNPACK hardware delegates
    )

    logger.info("Running ONNX shape inference & Conv+BN graph folding...")
    quant_pre_process(
        input_model_path=fp32_onnx_path,
        output_model_path=preproc_onnx_path,
        skip_symbolic_shape=False,
    )

    # Identify final L2-normalization tail nodes so they stay in FP32
    onnx_model = onnx.load(preproc_onnx_path)
    tail_nodes_to_exclude: List[str] = []
    for node in onnx_model.graph.node:
        if node.op_type in {"ReduceL2", "Div", "Sqrt", "Pow", "ReduceSum", "Clip", "Max"}:
            tail_nodes_to_exclude.append(node.name)

    logger.info(f"Preserving FP32 precision on hypersphere normalization nodes: {tail_nodes_to_exclude}")

    calib_reader = IndicFaceONNXCalibrationReader(
        dataset=calibration_dataset,
        input_name="input_rgb",
        max_samples=128,
    )

    logger.info("Executing Static QDQ INT8 Quantization (Per-Channel QInt8 Weights, QUInt8 Activations)...")
    quantize_static(
        model_input=preproc_onnx_path,
        model_output=int8_onnx_path,
        calibration_data_reader=calib_reader,
        quant_format=QuantFormat.QDQ,
        activation_type=QuantType.QUInt8,
        weight_type=QuantType.QInt8,
        per_channel=True,
        reduce_range=False,
        calibrate_method=CalibrationMethod.MinMax,
        nodes_to_exclude=tail_nodes_to_exclude,
        extra_options={
            "ActivationSymmetric": False,
            "WeightSymmetric": True,
            "DedicateDQNode": True,
        },
    )

    fp32_size_mb = os.path.getsize(preproc_onnx_path) / (1024 * 1024)
    int8_size_mb = os.path.getsize(int8_onnx_path) / (1024 * 1024)
    logger.info(f"Model Footprint | FP32 Folded: {fp32_size_mb:.2f} MB -> INT8 QDQ: {int8_size_mb:.2f} MB")
    return preproc_onnx_path, int8_onnx_path


# ============================================================================
# 6. ANGULAR DRIFT & BIOMETRIC THRESHOLD (0.74) VERIFICATION SUITE
# ============================================================================
def verify_angular_drift_and_far(
    fp32_onnx_path: str,
    int8_onnx_path: str,
    eval_dataset: Dataset,
    num_samples: int = 200,
    max_allowed_mean_rad: float = 0.015,
) -> Dict[str, float]:
    """
    Validates:
      1. Angular drift Delta_theta = arccos(e_FP32 . e_INT8) across evaluation samples
      2. Pairwise Cosine Similarity shift |s_FP32 - s_INT8|
      3. False Acceptance Rate (FAR) stability at the Kelasagara 0.74 duplicate threshold
    """
    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = 2

    fp32_sess = ort.InferenceSession(fp32_onnx_path, sess_options=sess_opts, providers=["CPUExecutionProvider"])
    int8_sess = ort.InferenceSession(int8_onnx_path, sess_options=sess_opts, providers=["CPUExecutionProvider"])

    n = min(len(eval_dataset), num_samples)
    fp32_embeddings = np.zeros((n, 128), dtype=np.float32)
    int8_embeddings = np.zeros((n, 128), dtype=np.float32)
    labels = np.zeros(n, dtype=np.int64)
    angular_drifts_rad = np.zeros(n, dtype=np.float32)

    for i in range(n):
        tensor_chw, label = eval_dataset[i]
        inp = {"input_rgb": tensor_chw.unsqueeze(0).numpy().astype(np.float32)}

        emb_fp32, _ = fp32_sess.run(["embedding", "quality_norm"], inp)
        emb_int8, _ = int8_sess.run(["embedding", "quality_norm"], inp)

        v_fp32 = emb_fp32[0] / max(np.linalg.norm(emb_fp32[0]), 1e-12)
        v_int8 = emb_int8[0] / max(np.linalg.norm(emb_int8[0]), 1e-12)

        fp32_embeddings[i] = v_fp32
        int8_embeddings[i] = v_int8
        labels[i] = label

        cos_sim = float(np.clip(np.dot(v_fp32, v_int8), -1.0, 1.0))
        angular_drifts_rad[i] = math.acos(cos_sim)

    mean_drift_rad = float(np.mean(angular_drifts_rad))
    p99_drift_rad = float(np.percentile(angular_drifts_rad, 99))
    max_drift_rad = float(np.max(angular_drifts_rad))
    mean_cos_retention = float(np.mean(np.cos(angular_drifts_rad)))

    # Compute all N*(N-1)/2 pairwise similarities for FAR/FRR shift check
    sim_matrix_fp32 = fp32_embeddings @ fp32_embeddings.T
    sim_matrix_int8 = int8_embeddings @ int8_embeddings.T

    triu_idx = np.triu_indices(n, k=1)
    pair_sims_fp32 = sim_matrix_fp32[triu_idx]
    pair_sims_int8 = sim_matrix_int8[triu_idx]
    pair_is_same = (labels[triu_idx[0]] == labels[triu_idx[1]])

    mean_abs_sim_diff = float(np.mean(np.abs(pair_sims_fp32 - pair_sims_int8)))
    impostor_sims_int8 = pair_sims_int8[~pair_is_same]
    far_at_074 = float(np.mean(impostor_sims_int8 >= 0.74)) if len(impostor_sims_int8) > 0 else 0.0

    logger.info("=" * 72)
    logger.info("INDICFACE-128 INT8 QUANTIZATION VERIFICATION REPORT")
    logger.info("=" * 72)
    logger.info(f"Mean Angular Drift        : {mean_drift_rad:.5f} rad ({math.degrees(mean_drift_rad):.3f} deg)")
    logger.info(f"P99 Angular Drift         : {p99_drift_rad:.5f} rad ({math.degrees(p99_drift_rad):.3f} deg)")
    logger.info(f"Max Angular Drift         : {max_drift_rad:.5f} rad ({math.degrees(max_drift_rad):.3f} deg)")
    logger.info(f"Mean Cosine Self-Fidelity : {mean_cos_retention:.6f}")
    logger.info(f"Mean Pairwise |Delta s|   : {mean_abs_sim_diff:.5f}")
    logger.info(f"Impostor FAR @ s >= 0.74  : {far_at_074 * 100:.4f}%")
    logger.info("=" * 72)

    if mean_drift_rad > max_allowed_mean_rad:
        raise AssertionError(
            f"QAT Verification FAILED: Mean angular drift {mean_drift_rad:.4f} rad "
            f"exceeded invariant threshold {max_allowed_mean_rad:.4f} rad."
        )

    return {
        "mean_drift_rad": mean_drift_rad,
        "p99_drift_rad": p99_drift_rad,
        "max_drift_rad": max_drift_rad,
        "mean_cos_retention": mean_cos_retention,
        "mean_abs_sim_diff": mean_abs_sim_diff,
        "far_at_074": far_at_074,
    }


# ============================================================================
# 7. MAIN EXECUTION ENTRYPOINT
# ============================================================================
if __name__ == "__main__":
    torch.manual_seed(42)
    np.random.seed(42)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # Point `DATA_ROOT` to your aligned 112x112 dataset folder in production
    DATA_ROOT = os.environ.get("INDICFACE_DATA_DIR", "./data/karnataka_aligned_112")

    train_dataset = KarnatakaFieldFaceDataset(root_dir=DATA_ROOT, is_train=True, synthetic_samples=256, num_classes=32)
    calib_dataset = KarnatakaFieldFaceDataset(root_dir=DATA_ROOT, is_train=False, synthetic_samples=128, num_classes=32)
    eval_dataset = KarnatakaFieldFaceDataset(root_dir=DATA_ROOT, is_train=False, synthetic_samples=200, num_classes=32)

    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True, num_workers=0, drop_last=True)

    # 1. Initialize baseline FP32 model (or load pre-trained Stage-1 checkpoint)
    base_model = IndicFace128QAT(embedding_dim=128)
    ckpt_path = os.environ.get("INDICFACE_FP32_CKPT", "")
    if ckpt_path and os.path.isfile(ckpt_path):
        logger.info(f"Loading Stage-1 pre-trained FP32 weights from {ckpt_path}")
        base_model.load_state_dict(torch.load(ckpt_path, map_location="cpu"), strict=True)

    # 2. Execute Stage-2 Quantization-Aware Training (QAT)
    qat_trained_model = run_qat_finetuning(
        fp32_model=base_model,
        train_loader=train_loader,
        num_classes=train_dataset.num_classes,
        device=device,
        total_epochs=6,
        freeze_bn_epoch=4,
        freeze_obs_epoch=5,
    )

    # 3. Export to ONNX Opset 18 & Compile Static QDQ INT8 Graph
    fp32_onnx, int8_onnx = export_and_quantize_onnx(
        qat_model=qat_trained_model,
        calibration_dataset=calib_dataset,
        output_dir="./artifacts_v17",
    )

    # 4. Run Angular Drift & Biometric Invariant Verification
    verify_angular_drift_and_far(
        fp32_onnx_path=fp32_onnx,
        int8_onnx_path=int8_onnx,
        eval_dataset=eval_dataset,
        num_samples=200,
        max_allowed_mean_rad=0.015,
    )
