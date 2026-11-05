#!/usr/bin/env python3
"""
Unpacks face_landmarks_detector.tflite from Google's official MediaPipe
face_landmarker.task bundle and converts it to ONNX opset 15 for onnxruntime-node.
"""
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

TASK_PATH = Path("backend/assets/models/face_landmarker.task")
OUT_DIR = Path("backend/assets/models")
TFLITE_EXTRACTED = OUT_DIR / "face_landmarks_detector.tflite"
ONNX_OUTPUT = OUT_DIR / "mediapipe_face_landmarks_detector.onnx"
MANIFEST_OUTPUT = OUT_DIR / "mediapipe_face_landmarks_detector.manifest.json"


def main() -> int:
    if not TASK_PATH.exists():
        print(f"ERROR: Official {TASK_PATH} not found.", file=sys.stderr)
        return 1

    with zipfile.ZipFile(TASK_PATH, "r") as zf:
        if "face_landmarks_detector.tflite" not in zf.namelist():
            print("ERROR: face_landmarks_detector.tflite missing from task bundle.", file=sys.stderr)
            return 1
        TFLITE_EXTRACTED.write_bytes(zf.read("face_landmarks_detector.tflite"))

    subprocess.run(
        [
            sys.executable,
            "-m",
            "tf2onnx.convert",
            "--tflite",
            str(TFLITE_EXTRACTED),
            "--output",
            str(ONNX_OUTPUT),
            "--opset",
            "15",
        ],
        check=True,
    )

    sha256_hex = hashlib.sha256(ONNX_OUTPUT.read_bytes()).hexdigest()
    MANIFEST_OUTPUT.write_text(
        json.dumps(
            {
                "modelId": "mediapipe_face_landmarks_detector_v2_opset15",
                "file": ONNX_OUTPUT.name,
                "sha256": sha256_hex,
                "inputShape": [1, 256, 256, 3],
                "inputLayout": "NHWC",
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Verified ONNX written: {ONNX_OUTPUT} (SHA-256: {sha256_hex})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
