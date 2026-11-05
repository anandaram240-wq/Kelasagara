// backend/src/services/face_inference.ts
import * as ort from "onnxruntime-node";
import { config } from "../config";
import { l2Normalize } from "./biometric_matching";
import { preprocessFaceBuffer, preprocessFaceBufferAuthoritative, flipImageHorizontally } from "./face_preprocessing";
import { ModelRegistry } from "./model_registry";

let primarySession: ort.InferenceSession | null = null;
let fallbackSession: ort.InferenceSession | null = null;

/**
 * Initializes the primary ONNX inference session singleton.
 * Enforces Invariant I-18: Verifies SHA-256 artifact integrity before loading.
 */
export async function getPrimaryInferenceSession(): Promise<ort.InferenceSession> {
  if (!primarySession) {
    try {
      console.log(`[FaceInference] Verifying primary model artifact at: ${config.modelPath}`);
      ModelRegistry.verifyArtifactIntegrity(config.modelPath, config.modelVersion);

      console.log(`[FaceInference] Loading Primary ONNX model (${config.modelVersion})...`);
      primarySession = await ort.InferenceSession.create(config.modelPath, {
        executionProviders: ["cpu"],
        graphOptimizationLevel: "all",
      });
      console.log(`[FaceInference] Primary model loaded successfully! Inputs: ${primarySession.inputNames}, Outputs: ${primarySession.outputNames}`);
    } catch (error: any) {
      console.error(`[FaceInference] Failed to load Primary ONNX model: ${error.message}`);
      throw new Error(`Primary ONNX model initialization failed: ${error.message}`);
    }
  }
  return primarySession;
}

/**
 * Initializes the fallback ONNX inference session singleton.
 * Enforces Invariant I-18: Verifies SHA-256 artifact integrity before loading.
 */
export async function getFallbackInferenceSession(): Promise<ort.InferenceSession> {
  if (!fallbackSession) {
    try {
      console.log(`[FaceInference] Verifying fallback model artifact at: ${config.fallbackModelPath}`);
      ModelRegistry.verifyArtifactIntegrity(config.fallbackModelPath, config.fallbackModelVersion);

      console.log(`[FaceInference] Loading Fallback ONNX model (${config.fallbackModelVersion})...`);
      fallbackSession = await ort.InferenceSession.create(config.fallbackModelPath, {
        executionProviders: ["cpu"],
        graphOptimizationLevel: "all",
      });
      console.log(`[FaceInference] Fallback model loaded successfully! Inputs: ${fallbackSession.inputNames}, Outputs: ${fallbackSession.outputNames}`);
    } catch (error: any) {
      console.error(`[FaceInference] Failed to load Fallback ONNX model: ${error.message}`);
      throw new Error(`Fallback ONNX model initialization failed: ${error.message}`);
    }
  }
  return fallbackSession;
}

/**
 * Backward compatibility alias for primary session.
 */
export async function getInferenceSession(): Promise<ort.InferenceSession> {
  return getPrimaryInferenceSession();
}

/**
 * Runs facial recognition inference on a preprocessed face buffer.
 * Supports primary model with automatic fallback to secondary model on failure.
 * Returns a 128-D L2-normalized embedding vector on the unit hypersphere.
 */
export async function runFaceInference(
  imageBuffer: Buffer,
  options?: { useFallback?: boolean }
): Promise<number[]> {
  const isFallback = options?.useFallback ?? false;
  const session = isFallback
    ? await getFallbackInferenceSession()
    : await getPrimaryInferenceSession();

  // 1. Preprocess raw or compressed image buffer into [1, 3, 112, 112] float tensor
  const tensorData =
    imageBuffer.length === 112 * 112 * 3
      ? preprocessFaceBuffer(imageBuffer)
      : (await preprocessFaceBufferAuthoritative(imageBuffer)).nchwFloat32;
  const inputTensor = new ort.Tensor("float32", tensorData, [1, 3, 112, 112]);

  // 2. Execute forward inference pass
  const inputName = session.inputNames[0];
  const feeds: Record<string, ort.Tensor> = { [inputName]: inputTensor };
  const results = await session.run(feeds);

  // 3. Extract output embedding
  const outputName = session.outputNames[0];
  const outputTensor = results[outputName];
  const rawEmbedding = outputTensor.data as Float32Array;

  if (rawEmbedding.length !== config.embeddingDim) {
    throw new Error(
      `Unexpected embedding dimension: expected ${config.embeddingDim}, got ${rawEmbedding.length}`
    );
  }

  // 4. Ensure unit hypersphere normalization (||v||_2 = 1.0)
  return l2Normalize(rawEmbedding);
}

/**
 * Resets inference sessions (used by unit and failure injection tests).
 */
export function resetInferenceSessions(): void {
  primarySession = null;
  fallbackSession = null;
}

/**
 * Executes Test-Time Augmentation (Flip-TTA) (Ticket B-03).
 * Evaluates both the original image and horizontally mirrored image,
 * producing an ensemble L2-normalized embedding vector.
 */
export async function runFaceInferenceWithTTA(
  imageBuffer: Buffer,
  options?: { useFallback?: boolean }
): Promise<number[]> {
  const embOrig = await runFaceInference(imageBuffer, options);
  const flippedBuffer = flipImageHorizontally(imageBuffer);
  const embFlip = await runFaceInference(flippedBuffer, options);

  const combined = new Array(embOrig.length);
  for (let i = 0; i < embOrig.length; i++) {
    combined[i] = embOrig[i] + embFlip[i];
  }
  return l2Normalize(combined);
}

export interface YuNetDetection {
  box: { x: number; y: number; width: number; height: number };
  landmarks: {
    leftEye: { x: number; y: number };
    rightEye: { x: number; y: number };
    noseTip: { x: number; y: number };
    mouthLeft: { x: number; y: number };
    mouthRight: { x: number; y: number };
  };
  score: number;
}

export interface FaceInferenceService {
  detectFaceYuNet(imageBuffer: Buffer): Promise<YuNetDetection | null>;
  detectAllFacesYuNet?(imageBuffer: Buffer): Promise<YuNetDetection[]>;
  alignFace112(imageBuffer: Buffer, det?: YuNetDetection | null): Promise<Buffer>;
  extractEmbeddingFromAligned(alignedPngOrRaw: Buffer): Promise<Float32Array>;
}



