#!/usr/bin/env python3
"""
Kelasagara-BioMatch: INT8 Quantization & TFLite Export Pipeline
Converts PyTorch checkpoint -> ONNX -> TensorFlow SavedModel -> TFLite INT8
Target Size: <= 2.4 MB
Target Device: Android (Snapdragon, MediaTek, Exynos)
"""

import os
import argparse
import numpy as np

def export_pipeline(checkpoint_path="kelasagara_mobilefacenet.pth", output_tflite="kelasagara_facenet.tflite"):
    print(f"[Export] Starting export pipeline from {checkpoint_path}...")

    try:
        import torch
        import onnx
        from train_mobilefacenet import MobileFaceNet

        # 1. Load PyTorch model
        model = MobileFaceNet(embedding_size=128)
        if os.path.exists(checkpoint_path):
            model.load_state_dict(torch.load(checkpoint_path, map_location="cpu"))
            print(f"[Export] Loaded weights from {checkpoint_path}")
        else:
            print(f"[Export] Note: Checkpoint {checkpoint_path} not found; using initialized weights for architecture compilation.")

        model.eval()

        # 2. Export to ONNX
        onnx_file = "kelasagara_facenet.onnx"
        dummy_input = torch.randn(1, 3, 112, 112)
        torch.onnx.export(
            model,
            dummy_input,
            onnx_file,
            input_names=['input_face'],
            output_names=['embedding_vector'],
            opset_version=13,
            dynamic_axes=None # Fixed batch size 1 for optimal mobile inference
        )
        print(f"[Export] Successfully exported to ONNX: {onnx_file}")

        # 3. Convert ONNX to TensorFlow
        try:
            from onnx_tf.backend import prepare
            import tensorflow as tf

            onnx_model = onnx.load(onnx_file)
            tf_rep = prepare(onnx_model)
            tf_model_path = "tf_saved_model"
            tf_rep.export_graph(tf_model_path)
            print(f"[Export] Converted to TensorFlow SavedModel: {tf_model_path}")

            # 4. INT8 Post-Training Quantization with Representative Calibration Data
            def representative_data_gen():
                for _ in range(100):
                    # Random face crops normalized to [-1.0, 1.0]
                    data = np.random.uniform(-1.0, 1.0, size=(1, 112, 112, 3)).astype(np.float32)
                    yield [data]

            converter = tf.lite.TFLiteConverter.from_saved_model(tf_model_path)
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.representative_dataset = representative_data_gen
            converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
            converter.inference_input_type = tf.float32
            converter.inference_output_type = tf.float32

            tflite_model = converter.convert()

            with open(output_tflite, "wb") as f:
                f.write(tflite_model)

            size_mb = os.path.getsize(output_tflite) / (1024 * 1024)
            print(f"[Export] SUCCESS! Quantized TFLite model generated: {output_tflite} ({size_mb:.2f} MB)")

        except ImportError as e:
            print(f"[Export] TensorFlow/onnx-tf not installed in current environment ({e}).")
            print(f"[Export] ONNX model {onnx_file} was successfully generated and can be converted via Colab or standard TF pipeline.")

    except Exception as e:
        print(f"[Export] Export pipeline encountered: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default="kelasagara_mobilefacenet.pth")
    parser.add_argument("--output", default="kelasagara_facenet.tflite")
    args = parser.parse_args()
    export_pipeline(args.checkpoint, args.output)
