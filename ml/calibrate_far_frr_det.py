#!/usr/bin/env python3
"""
UIDAI FaceRD 1:1 and 1:N Biometric Threshold Calibration Engine
Computes ROC, DET, EER, and optimal cosine thresholds for d=128 and d=512.
"""
import json
import math
from dataclasses import dataclass, asdict
from typing import List, Dict
import numpy as np


@dataclass
class CalibrationReport:
    embedding_dim: int
    gallery_size_n: int
    impostor_mean: float
    impostor_std: float
    genuine_mean: float
    genuine_std: float
    eer_rate: float
    eer_threshold: float
    threshold_far_1e_4: float
    threshold_far_1e_6: float
    recommended_1_to_n_threshold: float
    expected_frr_at_recommended: float
    expected_far_1_to_n_at_recommended: float


def l2_normalize(vectors: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    return vectors / np.clip(norms, 1e-12, None)


def evaluate_biometric_calibration(
    genuine_scores: np.ndarray,
    impostor_scores: np.ndarray,
    embedding_dim: int = 128,
    gallery_size_n: int = 100_000,
    target_far_1_to_n: float = 1e-3,
) -> CalibrationReport:
    thresholds = np.linspace(-0.20, 0.99, 12000)

    # Vectorized empirical CDF evaluation
    gen_sorted = np.sort(genuine_scores)
    imp_sorted = np.sort(impostor_scores)

    n_gen = len(gen_sorted)
    n_imp = len(imp_sorted)

    # FRR(tau) = P(s_gen < tau)
    frr = np.searchsorted(gen_sorted, thresholds, side="left") / float(n_gen)
    # FAR_1:1(tau) = P(s_imp >= tau)
    far_1_1 = (n_imp - np.searchsorted(imp_sorted, thresholds, side="left")) / float(n_imp)

    # Parametric Beta/Gaussian tail refinement for extreme quantiles (10^-6 to 10^-8)
    imp_mean = float(np.mean(impostor_scores))
    imp_std = float(np.std(impostor_scores))
    gen_mean = float(np.mean(genuine_scores))
    gen_std = float(np.std(genuine_scores))

    # Analytical Gaussian tail fallback where empirical samples < 10^7
    z_scores = (thresholds - imp_mean) / max(imp_std, 1e-8)
    far_analytic = 0.5 * np.vectorize(math.erfc)(z_scores / math.sqrt(2.0))
    far_blended = np.where(far_1_1 > (10.0 / n_imp), far_1_1, far_analytic)

    # Equal Error Rate (EER)
    eer_idx = int(np.argmin(np.abs(frr - far_blended)))
    eer_rate = float((frr[eer_idx] + far_blended[eer_idx]) * 0.5)
    eer_threshold = float(thresholds[eer_idx])

    # Thresholds at fixed 1:1 FAR targets
    idx_1e4 = int(np.argmin(np.abs(far_blended - 1e-4)))
    idx_1e6 = int(np.argmin(np.abs(far_blended - 1e-6)))

    # 1:N Family-Wise FAR across Karnataka District + Adjacency Graph
    far_1_n = 1.0 - np.power(1.0 - np.clip(far_blended, 0.0, 1.0), gallery_size_n)
    idx_1n = int(np.argmin(np.abs(far_1_n - target_far_1_to_n)))
    rec_tau = float(thresholds[idx_1n])

    return CalibrationReport(
        embedding_dim=embedding_dim,
        gallery_size_n=gallery_size_n,
        impostor_mean=round(imp_mean, 5),
        impostor_std=round(imp_std, 5),
        genuine_mean=round(gen_mean, 5),
        genuine_std=round(gen_std, 5),
        eer_rate=round(eer_rate, 6),
        eer_threshold=round(eer_threshold, 4),
        threshold_far_1e_4=round(float(thresholds[idx_1e4]), 4),
        threshold_far_1e_6=round(float(thresholds[idx_1e6]), 4),
        recommended_1_to_n_threshold=round(rec_tau, 4),
        expected_frr_at_recommended=round(float(frr[idx_1n]), 5),
        expected_far_1_to_n_at_recommended=round(float(far_1_n[idx_1n]), 6),
    )


if __name__ == "__main__":
    rng = np.random.default_rng(seed=42)
    # Simulate calibrated Sub-Center ArcFace 128-D hypersphere distributions
    imp_sim = rng.normal(loc=0.042, scale=1.0 / math.sqrt(128), size=500_000)
    gen_sim = np.clip(rng.normal(loc=0.845, scale=0.038, size=50_000), -1.0, 1.0)

    report = evaluate_biometric_calibration(
        genuine_scores=gen_sim,
        impostor_scores=imp_sim,
        embedding_dim=128,
        gallery_size_n=100_000,
        target_far_1_to_n=1e-3,
    )
    print(json.dumps(asdict(report), indent=2))
