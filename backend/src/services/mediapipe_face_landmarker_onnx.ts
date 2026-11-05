import * as ort from 'onnxruntime-node';
import sharp from 'sharp';
import { createHash } from 'crypto';
import * as fs from 'fs';
import { FaceInferenceService, YuNetDetection } from './face_inference';

export interface Point2D {
  x: number;
  y: number;
}

export interface Point3D extends Point2D {
  z: number;
}

export interface SixPointEyeContour {
  p1: Point2D; // Horizontal corner 1
  p2: Point2D; // Upper lid 1 (paired vertically with p6)
  p3: Point2D; // Upper lid 2 (paired vertically with p5)
  p4: Point2D; // Horizontal corner 2
  p5: Point2D; // Lower lid 2 (paired vertically with p3)
  p6: Point2D; // Lower lid 1 (paired vertically with p2)
}

export interface FrameLandmarkAndQualityAnalysis {
  faceCount: number;
  facePresenceProbability: number;
  interocularDistancePx: number;
  yawDeg: number;
  pitchDeg: number;
  rollDeg: number;
  meanFaceLuma: number;
  laplacianSharpness: number;
  eyeContours: {
    viewerLeftEye: SixPointEyeContour;
    viewerRightEye: SixPointEyeContour;
  };
  earViewerLeft: number;
  earViewerRight: number;
  earBilateralMean: number;
  /** Extracted strictly by OpenCV SFace on the 5-point aligned 112x112 BGR crop */
  sfaceEmbedding128: Float32Array;
}

export interface MediaPipeLandmarkerServiceConfig {
  modelPath: string;
  expectedSha256: string;
  inputResolution?: 256;
  inputLayout?: 'NHWC' | 'NCHW';
  minFacePresenceProbability?: number;
  inferenceTimeoutMs?: number;
  roiExpansionFactor?: number;
}

export type MediaPipeLandmarkerConfig = MediaPipeLandmarkerServiceConfig;

/**
 * First 16 indices of MediaPipe's 71-point left-eye and right-eye attention refinement
 * tensors, mapping into the 468-point canonical mesh.
 */
const LEFT_EYE_REFINEMENT_MESH_INDICES: readonly number[] = [
  33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246,
];

const RIGHT_EYE_REFINEMENT_MESH_INDICES: readonly number[] = [
  362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398,
];

export const MEDIAPIPE_6PT_EAR_INDICES = {
  VIEWER_LEFT_EYE: { p1: 33, p2: 160, p3: 158, p4: 133, p5: 153, p6: 144 },
  VIEWER_RIGHT_EYE: { p1: 362, p2: 385, p3: 387, p4: 263, p5: 373, p6: 380 },
  POSE_ANCHORS: {
    NOSE_TIP: 1,
    GLABELLA: 10,
    CHIN_GNATHION: 152,
    LEFT_OUTER_CANTHUS: 33,
    RIGHT_OUTER_CANTHUS: 263,
    LEFT_IRIS_CENTER: 468,
    RIGHT_IRIS_CENTER: 473,
  },
} as const;

export const MEDIAPIPE_EAR_INDICES = {
  IMAGE_LEFT_EYE: MEDIAPIPE_6PT_EAR_INDICES.VIEWER_LEFT_EYE,
  IMAGE_RIGHT_EYE: MEDIAPIPE_6PT_EAR_INDICES.VIEWER_RIGHT_EYE,
  POSE_ANCHORS: MEDIAPIPE_6PT_EAR_INDICES.POSE_ANCHORS,
} as const;

export class MediaPipeFaceLandmarkerOnnx {
  private session: ort.InferenceSession | null = null;
  private initPromise: Promise<void> | null = null;
  private readonly resolution: number;
  private readonly layout: 'NHWC' | 'NCHW';
  private readonly minPresenceProb: number;
  private readonly inferenceTimeoutMs: number;

  constructor(
    private readonly config: MediaPipeLandmarkerServiceConfig,
    private readonly sfaceService: FaceInferenceService
  ) {
    this.resolution = config.inputResolution ?? 256;
    this.layout = config.inputLayout ?? 'NHWC';
    this.minPresenceProb = config.minFacePresenceProbability ?? 0.55;
    this.inferenceTimeoutMs = config.inferenceTimeoutMs ?? 2500;
  }

  public async init(): Promise<void> {
    return this.ensureInitialized();
  }

  public async ensureInitialized(): Promise<void> {
    if (this.session) return;
    if (this.initPromise) return this.initPromise;

    this.initPromise = (async () => {
      if (!fs.existsSync(this.config.modelPath)) {
        throw new Error(`MEDIAPIPE_MODEL_FILE_MISSING: ${this.config.modelPath}`);
      }
      const bytes = fs.readFileSync(this.config.modelPath);
      const actualSha = createHash('sha256').update(bytes).digest('hex');
      if (actualSha !== this.config.expectedSha256) {
        throw new Error(
          `MEDIAPIPE_MODEL_SHA256_MISMATCH: expected=${this.config.expectedSha256} actual=${actualSha}`
        );
      }
      this.session = await ort.InferenceSession.create(this.config.modelPath, {
        executionProviders: ['cpu'],
        graphOptimizationLevel: 'all',
      });
    })();

    try {
      await this.initPromise;
    } catch (err) {
      this.initPromise = null;
      throw err;
    }
  }

  /**
   * Analyzes a single frame: decodes image, verifies face count via YuNet, extracts
   * 478 MediaPipe landmarks with timeout protection, computes bilateral EAR, and
   * extracts the canonical 128-D SFace identity embedding.
   */
  public async analyzeFrame(
    rawImageBuffer: Buffer,
    options?: { isMirroredFrontCamera?: boolean }
  ): Promise<FrameLandmarkAndQualityAnalysis> {
    await this.ensureInitialized();

    return this.withTimeout(this.inferenceTimeoutMs, async () => {
      // 1. Decode & normalize EXIF orientation; if front camera was mirrored, normalize to upright unmirrored
      let pipeline = sharp(rawImageBuffer, { failOn: 'error' }).rotate();
      if (options?.isMirroredFrontCamera === true) {
        pipeline = pipeline.flop();
      }
      const orientedBuffer = await pipeline.toBuffer();
      const meta = await sharp(orientedBuffer).metadata();
      const width = meta.width ?? 0;
      const height = meta.height ?? 0;

      if (width < 80 || height < 80) {
        throw new Error('IMAGE_DIMENSIONS_TOO_SMALL');
      }

      // 2. Detect all faces via YuNet
      const faces: YuNetDetection[] = this.sfaceService.detectAllFacesYuNet
        ? await this.sfaceService.detectAllFacesYuNet(orientedBuffer)
        : (await this.sfaceService.detectFaceYuNet(orientedBuffer)
            ? [(await this.sfaceService.detectFaceYuNet(orientedBuffer))!]
            : []);

      if (faces.length !== 1) {
        return {
          faceCount: faces.length,
          facePresenceProbability: 0,
          interocularDistancePx: 0,
          yawDeg: 0,
          pitchDeg: 0,
          rollDeg: 0,
          meanFaceLuma: 0,
          laplacianSharpness: 0,
          eyeContours: {
            viewerLeftEye: this.emptyContour(),
            viewerRightEye: this.emptyContour(),
          },
          earViewerLeft: 0,
          earViewerRight: 0,
          earBilateralMean: 0,
          sfaceEmbedding128: new Float32Array(128),
        };
      }

      const primaryFace = faces[0];

      // 3. Crop square ROI around primary face box and run MediaPipe 256x256 ONNX
      const roi = this.computeSquareRoi(primaryFace.box, width, height, 1.25);
      const { data: rgbCropBytes } = await sharp(orientedBuffer)
        .extract({ left: roi.left, top: roi.top, width: roi.size, height: roi.size })
        .resize(this.resolution, this.resolution, { fit: 'fill', kernel: 'lanczos3' })
        .removeAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });

      const inputTensor = this.buildInputTensor(rgbCropBytes);
      const inputName = this.session!.inputNames[0];
      const outputMap = await this.session!.run({ [inputName]: inputTensor });

      const { landmarks478, presenceProbability } = this.decodeAndRefineLandmarks(
        outputMap,
        roi
      );

      if (presenceProbability < this.minPresenceProb) {
        throw new Error(
          `MEDIAPIPE_PRESENCE_BELOW_THRESHOLD: ${presenceProbability.toFixed(4)}`
        );
      }

      // 4. Extract and validate the 12 eyelid contour points
      const eyeContours = this.extractValidatedEyeContours(landmarks478, width, height);
      const earViewerLeft = MediaPipeFaceLandmarkerOnnx.computeSingleEyeEar(
        eyeContours.viewerLeftEye
      );
      const earViewerRight = MediaPipeFaceLandmarkerOnnx.computeSingleEyeEar(
        eyeContours.viewerRightEye
      );
      const earBilateralMean = 0.5 * (earViewerLeft + earViewerRight);

      // 5. Compute pose angles & interocular distance
      const pose = this.compute3DPoseAngles(landmarks478);
      const ipdPx = this.computeInterocularDistance(landmarks478);

      // 6. Authoritative identity embedding via OpenCV SFace on 5-point aligned 112x112 BGR crop
      const aligned112 = await this.sfaceService.alignFace112(orientedBuffer, primaryFace);
      const [qualityStats, sfaceEmbedding128] = await Promise.all([
        this.computeLumaAndLaplacian(aligned112),
        this.sfaceService.extractEmbeddingFromAligned(aligned112),
      ]);

      return {
        faceCount: 1,
        facePresenceProbability: presenceProbability,
        interocularDistancePx: ipdPx,
        yawDeg: pose.yawDeg,
        pitchDeg: pose.pitchDeg,
        rollDeg: pose.rollDeg,
        meanFaceLuma: qualityStats.meanLuma,
        laplacianSharpness: qualityStats.laplacianVariance,
        eyeContours,
        earViewerLeft,
        earViewerRight,
        earBilateralMean,
        sfaceEmbedding128,
      };
    });
  }

  /**
   * Merges the base 468-point mesh tensor with the attention refinement sub-tensors
   * (left eye 71x2, right eye 71x2, left iris 5x3, right iris 5x3) if present in the ONNX graph,
   * matching MediaPipe's LandmarksRefinementCalculator.
   */
  private decodeAndRefineLandmarks(
    outputs: ort.InferenceSession.OnnxValueMapType,
    roi: { left: number; top: number; size: number }
  ): { landmarks478: Point3D[]; presenceProbability: number } {
    let baseMesh1404: Float32Array | null = null;
    let combined1434: Float32Array | null = null;
    let leftEye142: Float32Array | null = null;
    let rightEye142: Float32Array | null = null;
    let irisLeft15: Float32Array | null = null;
    let irisRight15: Float32Array | null = null;
    let presenceProbability = 1.0;

    const irisTensors15: Float32Array[] = [];
    const eyeTensors142: Float32Array[] = [];

    for (const tensor of Object.values(outputs)) {
      const arr = tensor.data as Float32Array;
      switch (arr.length) {
        case 1434:
          combined1434 = arr;
          break;
        case 1404:
          baseMesh1404 = arr;
          break;
        case 142:
          eyeTensors142.push(arr);
          break;
        case 15:
          irisTensors15.push(arr);
          break;
        case 1: {
          const v = arr[0];
          if (!Number.isFinite(v)) {
            throw new Error('NON_FINITE_PRESENCE_SCORE');
          }
          presenceProbability = v < 0.0 || v > 1.0 ? 1.0 / (1.0 + Math.exp(-v)) : v;
          break;
        }
        default:
          break;
      }
    }

    if (eyeTensors142.length === 2) {
      // Order eye refinement tensors by mean X coordinate (viewer-left vs viewer-right)
      if (eyeTensors142[0][0] <= eyeTensors142[1][0]) {
        leftEye142 = eyeTensors142[0];
        rightEye142 = eyeTensors142[1];
      } else {
        leftEye142 = eyeTensors142[1];
        rightEye142 = eyeTensors142[0];
      }
    }

    if (irisTensors15.length === 2) {
      if (irisTensors15[0][0] <= irisTensors15[1][0]) {
        irisLeft15 = irisTensors15[0];
        irisRight15 = irisTensors15[1];
      } else {
        irisLeft15 = irisTensors15[1];
        irisRight15 = irisTensors15[0];
      }
    }

    const sourceCoords = combined1434 ?? baseMesh1404;
    if (!sourceCoords) {
      throw new Error('MEDIAPIPE_LANDMARK_TENSOR_NOT_FOUND');
    }

    // Determine coordinate normalization: [0, 256] crop pixels vs [0.0, 1.0] normalized
    const scaleDivisor = this.detectScaleDivisor(sourceCoords);
    const points: Point3D[] = new Array(478);

    const baseCount = Math.min(478, Math.floor(sourceCoords.length / 3));
    for (let i = 0; i < baseCount; i++) {
      const x = sourceCoords[i * 3];
      const y = sourceCoords[i * 3 + 1];
      const z = sourceCoords[i * 3 + 2];
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) {
        throw new Error(`NON_FINITE_LANDMARK_COORDINATE at index ${i}`);
      }
      points[i] = {
        x: roi.left + (x / scaleDivisor) * roi.size,
        y: roi.top + (y / scaleDivisor) * roi.size,
        z: (z / scaleDivisor) * roi.size,
      };
    }

    // Overlay refined 2D eye contour coordinates (x, y) from the attention sub-tensors
    if (leftEye142 && rightEye142) {
      const eyeScale = this.detectScaleDivisor(leftEye142);
      for (let k = 0; k < LEFT_EYE_REFINEMENT_MESH_INDICES.length; k++) {
        const meshIdx = LEFT_EYE_REFINEMENT_MESH_INDICES[k];
        points[meshIdx].x = roi.left + (leftEye142[k * 2] / eyeScale) * roi.size;
        points[meshIdx].y = roi.top + (leftEye142[k * 2 + 1] / eyeScale) * roi.size;
      }
      for (let k = 0; k < RIGHT_EYE_REFINEMENT_MESH_INDICES.length; k++) {
        const meshIdx = RIGHT_EYE_REFINEMENT_MESH_INDICES[k];
        points[meshIdx].x = roi.left + (rightEye142[k * 2] / eyeScale) * roi.size;
        points[meshIdx].y = roi.top + (rightEye142[k * 2 + 1] / eyeScale) * roi.size;
      }
    }

    // Populate or overlay indices 468..477 (left and right iris 5-point 3D tensors)
    if (irisLeft15 && irisRight15) {
      const irisScale = this.detectScaleDivisor(irisLeft15);
      for (let k = 0; k < 5; k++) {
        points[468 + k] = {
          x: roi.left + (irisLeft15[k * 3] / irisScale) * roi.size,
          y: roi.top + (irisLeft15[k * 3 + 1] / irisScale) * roi.size,
          z: (irisLeft15[k * 3 + 2] / irisScale) * roi.size,
        };
        points[473 + k] = {
          x: roi.left + (irisRight15[k * 3] / irisScale) * roi.size,
          y: roi.top + (irisRight15[k * 3 + 1] / irisScale) * roi.size,
          z: (irisRight15[k * 3 + 2] / irisScale) * roi.size,
        };
      }
    } else if (baseCount < 478) {
      // Fallback iris centers from eye corner midpoints if a 468-pt single tensor was loaded
      const lCenter = {
        x: 0.5 * (points[33].x + points[133].x),
        y: 0.5 * (points[33].y + points[133].y),
        z: 0.5 * (points[33].z + points[133].z),
      };
      const rCenter = {
        x: 0.5 * (points[362].x + points[263].x),
        y: 0.5 * (points[362].y + points[263].y),
        z: 0.5 * (points[362].z + points[263].z),
      };
      for (let k = 0; k < 5; k++) {
        points[468 + k] = { ...lCenter };
        points[473 + k] = { ...rCenter };
      }
    }

    return { landmarks478: points, presenceProbability };
  }

  /**
   * Extracts the 12 eyelid contour points and verifies anatomical topology:
   * - Horizontal palpebral fissure width ||p1 - p4|| >= 4.0 px
   * - Viewer-left eye outer corner (33) is to the left of viewer-right eye outer corner (263)
   */
  public extractValidatedEyeContours(
    landmarks: Point3D[],
    imgWidth: number,
    imgHeight: number
  ): {
    viewerLeftEye: SixPointEyeContour;
    viewerRightEye: SixPointEyeContour;
  } {
    if (!landmarks || landmarks.length < 468) {
      throw new Error('INVALID_LANDMARK_ARRAY_LENGTH');
    }

    const L = MEDIAPIPE_6PT_EAR_INDICES.VIEWER_LEFT_EYE;
    const R = MEDIAPIPE_6PT_EAR_INDICES.VIEWER_RIGHT_EYE;

    const pick = (idx: number): Point2D => {
      const pt = landmarks[idx];
      if (
        !pt ||
        !Number.isFinite(pt.x) ||
        !Number.isFinite(pt.y) ||
        pt.x < -imgWidth * 0.1 ||
        pt.x > imgWidth * 1.1 ||
        pt.y < -imgHeight * 0.1 ||
        pt.y > imgHeight * 1.1
      ) {
        throw new Error(`OUT_OF_BOUNDS_LANDMARK at index ${idx}`);
      }
      return { x: pt.x, y: pt.y };
    };

    const viewerLeftEye: SixPointEyeContour = {
      p1: pick(L.p1),
      p2: pick(L.p2),
      p3: pick(L.p3),
      p4: pick(L.p4),
      p5: pick(L.p5),
      p6: pick(L.p6),
    };

    const viewerRightEye: SixPointEyeContour = {
      p1: pick(R.p1),
      p2: pick(R.p2),
      p3: pick(R.p3),
      p4: pick(R.p4),
      p5: pick(R.p5),
      p6: pick(R.p6),
    };

    const leftWidth = Math.hypot(
      viewerLeftEye.p4.x - viewerLeftEye.p1.x,
      viewerLeftEye.p4.y - viewerLeftEye.p1.y
    );
    const rightWidth = Math.hypot(
      viewerRightEye.p4.x - viewerRightEye.p1.x,
      viewerRightEye.p4.y - viewerRightEye.p1.y
    );

    if (leftWidth < 4.0 || rightWidth < 4.0) {
      throw new Error('DEGENERATE_EYE_CONTOUR_WIDTH');
    }

    if (viewerLeftEye.p1.x >= viewerRightEye.p4.x) {
      throw new Error('INVERTED_EYE_TOPOLOGY_DETECTED');
    }

    return { viewerLeftEye, viewerRightEye };
  }

  public extract12EyelidPoints(landmarks: Point3D[]): {
    left: SixPointEyeContour;
    right: SixPointEyeContour;
  } {
    const res = this.extractValidatedEyeContours(landmarks, 256, 256);
    return {
      left: res.viewerLeftEye,
      right: res.viewerRightEye,
    };
  }

  public static computeSingleEyeEar(c: SixPointEyeContour): number {
    const v1 = Math.hypot(c.p2.x - c.p6.x, c.p2.y - c.p6.y);
    const v2 = Math.hypot(c.p3.x - c.p5.x, c.p3.y - c.p5.y);
    const horiz = Math.hypot(c.p1.x - c.p4.x, c.p1.y - c.p4.y);
    if (horiz < 1e-4) {
      throw new Error('ZERO_HORIZONTAL_EYE_SPAN');
    }
    const ear = (v1 + v2) / (2.0 * horiz);
    if (!Number.isFinite(ear) || ear < 0.0 || ear > 1.2) {
      throw new Error(`IMPLAUSIBLE_EAR_VALUE: ${ear}`);
    }
    return ear;
  }

  private buildInputTensor(rgbBytes: Buffer): ort.Tensor {
    const res = this.resolution;
    const plane = res * res;
    const floats = new Float32Array(3 * plane);
    const inv255 = 1.0 / 255.0;

    if (this.layout === 'NHWC') {
      for (let i = 0; i < 3 * plane; i++) {
        floats[i] = rgbBytes[i] * inv255;
      }
      return new ort.Tensor('float32', floats, [1, res, res, 3]);
    }

    for (let i = 0; i < plane; i++) {
      floats[i] = rgbBytes[i] * inv255;
      floats[plane + i] = rgbBytes[i * 3 + 1] * inv255;
      floats[2 * plane + i] = rgbBytes[i * 3 + 2] * inv255;
    }
    return new ort.Tensor('float32', floats, [1, 3, res, res]);
  }

  private detectScaleDivisor(coords: Float32Array): number {
    for (let i = 0; i < Math.min(coords.length, 30); i += 2) {
      if (Math.abs(coords[i]) > 2.0) {
        return this.resolution;
      }
    }
    return 1.0;
  }

  private computeSquareRoi(
    box: { x: number; y: number; width: number; height: number },
    imgW: number,
    imgH: number,
    expansion: number
  ): { left: number; top: number; size: number } {
    const cx = box.x + box.width * 0.5;
    const cy = box.y + box.height * 0.5;
    const rawSize = Math.round(Math.max(box.width, box.height) * expansion);
    const size = Math.max(32, Math.min(Math.min(imgW, imgH), rawSize));
    const left = Math.max(0, Math.min(imgW - size, Math.round(cx - size * 0.5)));
    const top = Math.max(0, Math.min(imgH - size, Math.round(cy - size * 0.5)));
    return { left, top, size };
  }

  private computeInterocularDistance(landmarks: Point3D[]): number {
    const P = MEDIAPIPE_6PT_EAR_INDICES.POSE_ANCHORS;
    const leftIris = landmarks[P.LEFT_IRIS_CENTER];
    const rightIris = landmarks[P.RIGHT_IRIS_CENTER];
    return Math.hypot(rightIris.x - leftIris.x, rightIris.y - leftIris.y);
  }

  private compute3DPoseAngles(landmarks: Point3D[]): {
    yawDeg: number;
    pitchDeg: number;
    rollDeg: number;
  } {
    const P = MEDIAPIPE_6PT_EAR_INDICES.POSE_ANCHORS;
    const lEye = landmarks[P.LEFT_OUTER_CANTHUS];
    const rEye = landmarks[P.RIGHT_OUTER_CANTHUS];
    const glabella = landmarks[P.GLABELLA];
    const chin = landmarks[P.CHIN_GNATHION];
    const radToDeg = 180.0 / Math.PI;

    const dxEye = rEye.x - lEye.x;
    const dyEye = rEye.y - lEye.y;
    const dzEye = rEye.z - lEye.z;
    const eyeSpan2D = Math.max(1e-3, Math.hypot(dxEye, dyEye));

    const rollDeg = Math.atan2(dyEye, Math.max(1e-3, dxEye)) * radToDeg;
    const yawDeg = Math.atan2(dzEye, eyeSpan2D) * radToDeg;
    const pitchDeg =
      Math.atan2(chin.z - glabella.z, Math.max(1e-3, chin.y - glabella.y)) * radToDeg;

    return { yawDeg, pitchDeg, rollDeg };
  }

  private async computeLumaAndLaplacian(aligned112: Buffer): Promise<{
    meanLuma: number;
    laplacianVariance: number;
  }> {
    const { data, info } = await sharp(aligned112)
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const w = info.width;
    const h = info.height;
    let sumLuma = 0;
    for (let i = 0; i < data.length; i++) sumLuma += data[i];
    const meanLuma = data.length > 0 ? sumLuma / data.length : 0;

    let lapSum = 0;
    let lapSqSum = 0;
    let n = 0;
    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const idx = y * w + x;
        const v =
          data[idx - w] + data[idx + w] + data[idx - 1] + data[idx + 1] - 4 * data[idx];
        lapSum += v;
        lapSqSum += v * v;
        n++;
      }
    }
    const lapMean = n > 0 ? lapSum / n : 0;
    const laplacianVariance = n > 0 ? Math.max(0, lapSqSum / n - lapMean * lapMean) : 0;

    return { meanLuma, laplacianVariance };
  }

  private emptyContour(): SixPointEyeContour {
    const z = { x: 0, y: 0 };
    return { p1: z, p2: z, p3: z, p4: z, p5: z, p6: z };
  }

  private async withTimeout<T>(ms: number, task: () => Promise<T>): Promise<T> {
    let timer: NodeJS.Timeout | undefined;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        reject(new Error(`MEDIAPIPE_INFERENCE_TIMEOUT_EXCEEDED_${ms}MS`));
      }, ms);
    });
    try {
      return await Promise.race([task(), timeoutPromise]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}
