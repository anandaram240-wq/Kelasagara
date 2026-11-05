# PHASE 20.11: OPENCV REFERENCE PARITY AUDIT
**Role:** Senior Computer Vision Engineer & Biometric Systems Architect  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. OBJECTIVE

Audit the Node.js Sharp / ONNX Runtime implementation in `CanonicalSFaceEngineV10` against the official OpenCV Zoo reference implementation (`cv::FaceDetectorYN` and `cv::FaceRecognizerSF`).

---

## 2. STAGE-BY-STAGE PARITY ANALYSIS

### Stage 1: YuNet Face Detection
| Parameter | OpenCV Zoo Reference | Kelasagara Implementation | Parity Status |
| :--- | :--- | :--- | :--- |
| **Model Weights** | `face_detection_yunet_2023mar.onnx` | `backend/models/face_detection_yunet_2023mar.onnx` (`8f2383e...`) | **IDENTICAL (100%)** |
| **Input Shape** | $[1, 3, 640, 640]$ BGR float32 | $[1, 3, 640, 640]$ BGR float32 | **IDENTICAL** |
| **Aspect Preservation** | Letterbox with top-left anchor | Letterbox with top-left anchor | **IDENTICAL** |
| **Strides** | 8, 16, 32 | 8, 16, 32 | **IDENTICAL** |
| **Score Formulation** | $\sqrt{\text{cls} \times \text{obj}}$ | `Math.sqrt(clsScore * objScore)` | **IDENTICAL** |
| **Keypoint Order** | Right eye, Left eye, Nose, Right mouth, Left mouth | `[rightEye, leftEye, noseTip, rightMouth, leftMouth]` | **IDENTICAL** |
| **NMS IoU** | 0.4 | 0.4 greedy NMS | **IDENTICAL** |

### Stage 2: Umeyama Facial Alignment
| Parameter | OpenCV Zoo Reference (`cv::FaceRecognizerSF::alignCrop`) | Kelasagara Implementation (`alignFaceToCanonical112`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Target Geometry** | Standard 5-point coordinates in $112 \times 112$ | Standard 5-point coordinates in $112 \times 112$ | **IDENTICAL** |
| - Left Eye | $[38.2946, 51.6963]$ | $[38.2946, 51.6963]$ | **EXACT MATCH** |
| - Right Eye | $[73.5318, 51.6963]$ | $[73.5318, 51.6963]$ | **EXACT MATCH** |
| - Nose Tip | $[56.0252, 71.7366]$ | $[56.0252, 71.7366]$ | **EXACT MATCH** |
| - Left Mouth | $[41.5493, 92.3655]$ | $[41.5493, 92.3655]$ | **EXACT MATCH** |
| - Right Mouth | $[70.7299, 92.2041]$ | $[70.7299, 92.2041]$ | **EXACT MATCH** |
| **Alignment Math** | Umeyama 2D similarity transform ($s, R, t$) | Singular Value Decomposition / Umeyama similarity | **EXACT MATCH** |
| **Interpolation** | Bilinear sampling | Bilinear sampling with boundary clamp | **EXACT MATCH** |

### Stage 3: SFace Feature Extraction
| Parameter | OpenCV Zoo Reference (`cv::FaceRecognizerSF::feature`) | Kelasagara Implementation (`extractCanonicalEmbeddingFromAligned112`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Model Weights** | `face_recognition_sface_2021dec.onnx` | `backend/models/face_recognition_sface_2021dec.onnx` (`0ba9fbf...`) | **IDENTICAL (100%)** |
| **Input Shape** | $[1, 3, 112, 112]$ BGR float32 | $[1, 3, 112, 112]$ BGR float32 | **IDENTICAL** |
| **Channel Range** | $[0.0, 255.0]$ unnormalized pixel values | $[0.0, 255.0]$ unnormalized pixel values | **IDENTICAL** |
| **Output Vector** | 128-D float32 | 128-D float32 | **IDENTICAL** |
| **Normalization** | $L_2$ normalized to unit length ($\|\vec{v}\| = 1.0$) | $L_2$ normalized to unit length ($\|\vec{v}\| = 1.0$) | **EXACT MATCH** |

---

## 3. AUDIT CONCLUSION

The Node.js implementation exhibits mathematical and functional parity with the official OpenCV Zoo C++ reference implementation across all feature extraction steps.
