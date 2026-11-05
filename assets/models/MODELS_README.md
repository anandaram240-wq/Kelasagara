# Face Auth Models

Download these Apache 2.0 licensed models from OpenCV Zoo:

## SFace (Face Recognition)
- URL: https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx
- Licence: Apache 2.0 (code + weights)
- Size: ~37 MB
- Output: 128-d L2-normalized embedding
- LFW: 99.60%, IJB-C TAR@FAR=1e-4: 92.80%

## YuNet (Face Detection)
- URL: https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
- Licence: Apache 2.0
- Output: BBox + 5 facial landmarks
- Latency: ~8ms Android

## MiniFASNetV2-SE (Passive Liveness Detection / PAD)
- URL: https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/raw/master/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.onnx
- Licence: Apache 2.0
- Output: 2-class softmax (live vs spoof)
- APCER: 1.2% | BPCER: 1.8%
