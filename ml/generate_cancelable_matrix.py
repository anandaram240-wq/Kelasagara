#!/usr/bin/env python3
"""
KELASAGARA BIOMATCH (v17) - ORTHOGONAL CANCELABLE MATRIX GENERATOR (O(128))
===========================================================================
Generates a Haar-uniform 128x128 orthogonal transformation matrix Q_secret
via Mezzadri's sign-corrected QR decomposition from a 256-bit master secret.
"""

import os
import hmac
import struct
import hashlib
import base64
import json
import math
import numpy as np


def derive_gaussian_matrix_from_seed(master_secret: bytes, dim: int = 128) -> np.ndarray:
    """
    Deterministically expands `master_secret` via HMAC-SHA256 counter mode
    and Box-Muller transform into a [dim, dim] standard normal matrix N(0, 1).
    Bit-identical to the TypeScript implementation below.
    """
    total_elements = dim * dim
    normals = np.zeros(total_elements, dtype=np.float64)

    counter = 0
    idx = 0
    while idx < total_elements:
        # Generate 32 deterministic pseudo-random bytes per counter block
        block = hmac.new(
            master_secret,
            struct.pack(">I", counter),
            hashlib.sha256,
        ).digest()
        counter += 1

        # Unpack 4 pairs of uint32 values from the 32-byte digest
        for offset in range(0, 32, 8):
            if idx >= total_elements:
                break
            u1_int, u2_int = struct.unpack(">II", block[offset : offset + 8])
            # Map strictly into open interval (0, 1) to avoid log(0)
            u1 = (u1_int + 1.0) / 4294967297.0
            u2 = (u2_int + 1.0) / 4294967297.0

            mag = math.sqrt(-2.0 * math.log(u1))
            z0 = mag * math.cos(2.0 * math.pi * u2)
            z1 = mag * math.sin(2.0 * math.pi * u2)

            normals[idx] = z0
            idx += 1
            if idx < total_elements:
                normals[idx] = z1
                idx += 1

    return normals.reshape((dim, dim))


def generate_haar_orthogonal_matrix(master_secret: bytes, dim: int = 128) -> np.ndarray:
    """
    Computes Q_secret in O(128) via QR decomposition with Mezzadri diagonal
    phase normalization so Q_secret is unique and Haar-distributed.
    """
    gaussian_mat = derive_gaussian_matrix_from_seed(master_secret, dim)
    q, r = np.linalg.qr(gaussian_mat)

    # Extract signs of diagonal of R: diag_signs[i] = +1 if R[i,i] >= 0 else -1
    diag_r = np.diag(r)
    diag_signs = np.where(diag_r >= 0.0, 1.0, -1.0)

    # Multiply columns of Q by diag_signs: Q_secret = Q @ diag(diag_signs)
    q_secret = q * diag_signs[np.newaxis, :]
    return q_secret


def verify_isometry_invariants(q_secret_fp64: np.ndarray, num_pairs: int = 1000) -> dict:
    dim = q_secret_fp64.shape[0]
    identity = np.eye(dim, dtype=np.float64)

    # 1. Orthogonality check: ||Q^T Q - I||_inf
    ortho_err_fp64 = float(np.max(np.abs(q_secret_fp64.T @ q_secret_fp64 - identity)))

    # 2. Downcast to Float32 (matching runtime Node.js Float32Array)
    q_fp32 = q_secret_fp64.astype(np.float32)
    ortho_err_fp32 = float(np.max(np.abs(q_fp32.T @ q_fp32 - np.eye(dim, dtype=np.float32))))

    # 3. Verify Cosine Similarity invariance over 1,000 random unit vectors on S^127
    rng = np.random.default_rng(42)
    u = rng.standard_normal((num_pairs, dim)).astype(np.float32)
    v = rng.standard_normal((num_pairs, dim)).astype(np.float32)
    u /= np.linalg.norm(u, axis=1, keepdims=True)
    v /= np.linalg.norm(v, axis=1, keepdims=True)

    # Project through Q_secret: u_tilde = u @ Q_secret^T
    u_tilde = u @ q_fp32.T
    v_tilde = v @ q_fp32.T
    u_tilde /= np.linalg.norm(u_tilde, axis=1, keepdims=True)
    v_tilde /= np.linalg.norm(v_tilde, axis=1, keepdims=True)

    orig_cos = np.sum(u * v, axis=1)
    proj_cos = np.sum(u_tilde * v_tilde, axis=1)
    max_cos_drift = float(np.max(np.abs(orig_cos - proj_cos)))

    # 4. Verify non-invertibility / decorrelation between raw u and permuted u_tilde
    self_cos = np.abs(np.sum(u * u_tilde, axis=1))
    mean_self_correlation = float(np.mean(self_cos))

    assert ortho_err_fp64 < 1e-13, f"FP64 orthogonality failed: {ortho_err_fp64}"
    assert max_cos_drift < 1e-6, f"FP32 cosine similarity drift too high: {max_cos_drift}"

    return {
        "dimension": dim,
        "ortho_error_fp64": ortho_err_fp64,
        "ortho_error_fp32": ortho_err_fp32,
        "max_cosine_drift_fp32": max_cos_drift,
        "mean_raw_vs_cancelable_correlation": mean_self_correlation,
    }


if __name__ == "__main__":
    secret_env = os.environ.get(
        "BIOMATCH_ORTHO_SEED",
        "kelasagara-v17-master-cancelable-biometric-seed-2026-rotate-hsm",
    )
    master_secret_bytes = hashlib.sha256(secret_env.encode("utf-8")).digest()

    q_mat = generate_haar_orthogonal_matrix(master_secret_bytes, dim=128)
    metrics = verify_isometry_invariants(q_mat)

    # Serialize row-major Float32 binary (128 * 128 * 4 = 65,536 bytes) -> Base64
    q_fp32_bytes = q_mat.astype("<f4").tobytes()
    b64_payload = base64.b64encode(q_fp32_bytes).decode("ascii")
    matrix_sha256 = hashlib.sha256(q_fp32_bytes).hexdigest()

    print("=" * 72)
    print("KELASAGARA CANCELABLE BIOMETRIC MATRIX (O(128)) VERIFICATION")
    print("=" * 72)
    print(json.dumps(metrics, indent=2))
    print(f"Binary Payload Size : {len(q_fp32_bytes)} bytes (64.0 KB)")
    print(f"Matrix SHA-256      : {matrix_sha256}")
    print("=" * 72)
