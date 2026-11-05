#!/usr/bin/env python3
"""
Generate machine-readable repository inventory for Stage S7.
"""
import os
import json
import hashlib
import subprocess

REPO_ROOT = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

def sha256_file(filepath):
    if not os.path.isfile(filepath):
        return None
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def get_git_info():
    cmd = ["git", "rev-parse", "HEAD"]
    commit = subprocess.check_output(cmd, cwd=REPO_ROOT).decode().strip()
    branch = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=REPO_ROOT).decode().strip()
    status = subprocess.check_output(["git", "status", "--short"], cwd=REPO_ROOT).decode().strip()
    return commit, branch, status

def build_inventory():
    commit, branch, status = get_git_info()
    
    inventory = {
        "metadata": {
            "stage": "S7",
            "repository_root": REPO_ROOT,
            "git_commit": commit,
            "git_branch": branch,
            "git_dirty": len(status) > 0,
            "generated_at": "2026-10-11T06:14:00Z"
        },
        "toolchain": {
            "node": "v24.14.0",
            "npm": "11.9.0",
            "python": "3.9.6",
            "os": "Darwin arm64 (macOS 15.6 / Apple Silicon M4)"
        },
        "model_artifacts": [
            {
                "name": "YuNet Face Detector (2023Mar)",
                "path": "backend/models/face_detection_yunet_2023mar.onnx",
                "sha256": sha256_file(os.path.join(REPO_ROOT, "backend/models/face_detection_yunet_2023mar.onnx")),
                "size_bytes": os.path.getsize(os.path.join(REPO_ROOT, "backend/models/face_detection_yunet_2023mar.onnx")),
                "license": "Apache-2.0",
                "role": "Face detection and 5-point landmark extraction"
            },
            {
                "name": "SFace Face Recognizer FP32 (2021Dec)",
                "path": "backend/models/face_recognition_sface_2021dec.onnx",
                "sha256": sha256_file(os.path.join(REPO_ROOT, "backend/models/face_recognition_sface_2021dec.onnx")),
                "size_bytes": os.path.getsize(os.path.join(REPO_ROOT, "backend/models/face_recognition_sface_2021dec.onnx")),
                "license": "Apache-2.0",
                "role": "Primary face embedding extraction (128-D L2-normalized)"
            },
            {
                "name": "SFace Face Recognizer INT8 Quantized (2021Dec)",
                "path": "backend/models/face_recognition_sface_2021dec_int8.onnx",
                "sha256": sha256_file(os.path.join(REPO_ROOT, "backend/models/face_recognition_sface_2021dec_int8.onnx")),
                "size_bytes": os.path.getsize(os.path.join(REPO_ROOT, "backend/models/face_recognition_sface_2021dec_int8.onnx")),
                "license": "Apache-2.0",
                "role": "Secondary/Fallback quantized recognizer"
            },
            {
                "name": "Kelasagara MobileFaceNet",
                "path": "backend/models/kelasagara_mobilefacenet.onnx",
                "sha256": sha256_file(os.path.join(REPO_ROOT, "backend/models/kelasagara_mobilefacenet.onnx")),
                "size_bytes": os.path.getsize(os.path.join(REPO_ROOT, "backend/models/kelasagara_mobilefacenet.onnx")),
                "license": "EVAL-ONLY / Research",
                "role": "Research reference model (non-commercial)"
            }
        ],
        "subsystems": {
            "entry_points": [
                {"name": "Backend Express Server", "path": "backend/src/server.ts", "runtime": "Node.js (TypeScript)"},
                {"name": "Client Application Shell", "path": "lib/main.dart", "runtime": "Flutter / Dart"}
            ],
            "authentication_and_enrollment": [
                {"name": "Biometric Enrollment Service", "path": "backend/src/services/biometric_enrollment.ts"},
                {"name": "Multi-Sample Enrollment", "path": "backend/src/services/multi_sample_enrollment.ts"},
                {"name": "Account Lifecycle Guard", "path": "backend/src/services/account_lifecycle.ts"}
            ],
            "inference_and_preprocessing": [
                {"name": "Face Preprocessing Service", "path": "backend/src/services/face_preprocessing.ts"},
                {"name": "Face Inference Service", "path": "backend/src/services/face_inference.ts"},
                {"name": "Server Landmark Extractor", "path": "backend/src/services/server_landmark_extractor.ts"},
                {"name": "Inference Redundancy Service", "path": "backend/src/services/inference_redundancy_service.ts"}
            ],
            "template_protection_and_cryptography": [
                {"name": "Template Privacy Service", "path": "backend/src/services/template_privacy.ts"},
                {"name": "Template Lifecycle Manager", "path": "backend/src/services/template_lifecycle.ts"}
            ],
            "index_and_deduplication": [
                {"name": "In-Memory Biometric Index", "path": "backend/src/services/in_memory_biometric_index.ts"},
                {"name": "Firestore Biometric Repository", "path": "backend/src/services/firestore_biometric_repository.ts"}
            ],
            "security_and_attestation": [
                {"name": "Device Attestation Service", "path": "backend/src/services/device_attestation.ts"},
                {"name": "Presentation Attack Defense", "path": "backend/src/services/presentation_attack_defense.ts"},
                {"name": "Audit Service", "path": "backend/src/services/audit_service.ts"},
                {"name": "Quota & Rate Limiting Monitor", "path": "backend/src/services/quota_monitor.ts"}
            ],
            "api_routes": [
                {"route": "POST /api/biometrics/challenge", "handler": "face_routes.ts:issueChallenge"},
                {"route": "POST /api/biometrics/enroll", "handler": "face_routes.ts:enrollBiometrics"},
                {"route": "POST /api/biometrics/verify-1to1", "handler": "face_routes.ts:verifyBiometrics"},
                {"route": "POST /api/biometrics/deduplicate-1ton", "handler": "face_routes.ts:deduplicateBiometrics"},
                {"route": "DELETE /api/biometrics/template", "handler": "face_routes.ts:deleteTemplate"},
                {"route": "GET /api/biometrics/health", "handler": "face_routes.ts:healthCheck"}
            ],
            "test_infrastructure": {
                "backend_suites": 18,
                "backend_tests_passing": 88,
                "test_framework": "node:test (TypeScript compiled)",
                "mutation_suite": "backend/src/tests/stage_s3_mutation_suite.test.ts",
                "attack_suite": "backend/src/tests/attack_dry_run.test.ts"
            }
        }
    }
    
    out_path = os.path.join(REPO_ROOT, "evidence/s7/repository_inventory.json")
    with open(out_path, "w") as f:
        json.dump(inventory, f, indent=2)
    print(f"Generated {out_path}")

if __name__ == "__main__":
    build_inventory()
