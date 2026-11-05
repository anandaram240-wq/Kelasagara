import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  MediaPipeFaceLandmarkerOnnx,
  MEDIAPIPE_EAR_INDICES,
  Point3D,
} from '../services/mediapipe_face_landmarker_onnx';
import { ChallengeBurstPadService } from '../services/challenge_burst_pad_service';
import { FaceInferenceService } from '../services/face_inference';

function expect(actual: number) {
  return {
    toBeCloseTo(expected: number, numDigits: number = 2) {
      const precision = Math.pow(10, -numDigits) / 2;
      assert.ok(
        Math.abs(actual - expected) < precision,
        `Expected ${actual} to be close to ${expected} (precision ${precision})`
      );
    },
    toBeGreaterThanOrEqual(expected: number) {
      assert.ok(
        actual >= expected,
        `Expected ${actual} >= ${expected}`
      );
    },
    toBeLessThanOrEqual(expected: number) {
      assert.ok(
        actual <= expected,
        `Expected ${actual} <= ${expected}`
      );
    },
  };
}

function buildSynthetic478Mesh(options: {
  leftEyeAperturePx: number;
  rightEyeAperturePx: number;
}): Point3D[] {
  const mesh: Point3D[] = Array.from({ length: 478 }, () => ({ x: 100, y: 100, z: 0 }));

  const L = MEDIAPIPE_EAR_INDICES.IMAGE_LEFT_EYE;
  const R = MEDIAPIPE_EAR_INDICES.IMAGE_RIGHT_EYE;

  // Image-Left Eye: horizontal width = 30px (from x=50 to x=80, centered at y=70)
  const halfL = options.leftEyeAperturePx * 0.5;
  mesh[L.p1] = { x: 50, y: 70, z: 0 };           // 33: outer corner
  mesh[L.p4] = { x: 80, y: 70, z: 0 };           // 133: inner corner
  mesh[L.p2] = { x: 60, y: 70 - halfL, z: 0 };   // 160: upper-outer
  mesh[L.p6] = { x: 60, y: 70 + halfL, z: 0 };   // 144: lower-outer
  mesh[L.p3] = { x: 70, y: 70 - halfL, z: 0 };   // 158: upper-inner
  mesh[L.p5] = { x: 70, y: 70 + halfL, z: 0 };   // 153: lower-inner

  // Image-Right Eye: horizontal width = 30px (from x=120 to x=150, centered at y=70)
  const halfR = options.rightEyeAperturePx * 0.5;
  mesh[R.p1] = { x: 120, y: 70, z: 0 };          // 362: inner corner
  mesh[R.p4] = { x: 150, y: 70, z: 0 };          // 263: outer corner
  mesh[R.p2] = { x: 130, y: 70 - halfR, z: 0 };  // 385: upper-inner
  mesh[R.p6] = { x: 130, y: 70 + halfR, z: 0 };  // 380: lower-inner
  mesh[R.p3] = { x: 140, y: 70 - halfR, z: 0 };  // 387: upper-outer
  mesh[R.p5] = { x: 140, y: 70 + halfR, z: 0 };  // 373: lower-outer

  // Iris centers
  mesh[468] = { x: 65, y: 70, z: 0 };
  mesh[473] = { x: 135, y: 70, z: 0 };

  return mesh;
}

describe('MediaPipeFaceLandmarkerOnnx 12-Point Eyelid Extraction', () => {
  const dummyInference = {} as FaceInferenceService;
  const adapter = new MediaPipeFaceLandmarkerOnnx(
    {
      modelPath: 'assets/models/face_landmarker_256x256.onnx',
      expectedSha256: '0000000000000000000000000000000000000000000000000000000000000000',
    },
    dummyInference
  );

  it('extracts the exact 12 eyelid points and computes EAR = 0.30 for open eyes (9px height / 30px width)', () => {
    const openMesh = buildSynthetic478Mesh({
      leftEyeAperturePx: 9.0,
      rightEyeAperturePx: 9.0,
    });

    const contours = adapter.extract12EyelidPoints(openMesh);
    const meanEar = ChallengeBurstPadService.computeMeanEar(contours);

    // EAR = (9 + 9) / (2 * 30) = 18 / 60 = 0.30
    expect(meanEar).toBeCloseTo(0.30, 5);
  });

  it('computes EAR = 0.08 for blink apex (2.4px height / 30px width), passing the <= 0.62x closure gate', () => {
    const openContours = adapter.extract12EyelidPoints(
      buildSynthetic478Mesh({ leftEyeAperturePx: 9.0, rightEyeAperturePx: 9.0 })
    );
    const closedApexContours = adapter.extract12EyelidPoints(
      buildSynthetic478Mesh({ leftEyeAperturePx: 2.4, rightEyeAperturePx: 2.4 })
    );

    const earOpen = ChallengeBurstPadService.computeMeanEar(openContours);
    const earApex = ChallengeBurstPadService.computeMeanEar(closedApexContours);

    expect(earOpen).toBeGreaterThanOrEqual(0.24);
    expect(earApex).toBeCloseTo(0.08, 5);
    expect(earApex).toBeLessThanOrEqual(earOpen * 0.62);
  });
});
