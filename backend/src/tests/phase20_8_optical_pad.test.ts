/**
 * backend/src/tests/phase20_8_optical_pad.test.ts
 *
 * Phase 20.8: Deterministic Adversarial Optical PAD Test Suite
 *
 * All test fixtures are explicitly categorized under strict scientific provenance:
 * - SYNTHETIC_OPTICAL_FIXTURE: Synthesized 2D grayscale pixel grids & patterns.
 * - MOCKED_CAMERA_FRAME: Synthetic frame buffers with simulated sensor parameters.
 * - SOFTWARE_PROTOCOL_TEST: In-memory protocol state & challenge sequence verification.
 * - PHYSICAL_OPTICAL_FIXTURE: Laboratory physical charts (marked GATED if no hardware).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  OpticalDisplayFeatureExtractor,
  OpticalDisplayFeatures,
} from '../biometric-evaluation/optical_display_feature_extractor';
import {
  CandidatePadHardenedEngine,
  MultiSignalFusionInput,
} from '../biometric-evaluation/candidate_pad_hardened_engine';

describe('KELASAGARA V20.8 — OPTICAL PAD SIGNAL EXTRACTION & FUSION SUITE', () => {

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY 1: MOIRÉ & SPATIAL FREQUENCY EXTRACTION (SYNTHETIC_OPTICAL_FIXTURE)
  // ─────────────────────────────────────────────────────────────────────────
  describe('Category 1: Moiré & 2D Spatial Frequency Extraction [SYNTHETIC_OPTICAL_FIXTURE]', () => {
    
    it('1.1 [SYNTHETIC_OPTICAL_FIXTURE]: Detects periodic high-frequency grid pattern', () => {
      const W = 64;
      const H = 64;
      const pixels = new Uint8Array(W * H);

      // Synthesize periodic Nyquist subpixel grid: alternating high-frequency pattern
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const isGrid = (x % 2 === 0) && (y % 2 === 0);
          pixels[y * W + x] = isGrid ? 230 : 50;
        }
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.strictEqual(features.isLowQualityOrCorrupt, false);
      assert.ok(
        features.spatialHighFrequencyEnergy >= 0.35,
        `Expected high frequency energy >= 0.35, got ${features.spatialHighFrequencyEnergy}`
      );
      assert.ok(
        features.spectralPeakiness >= 3.0,
        `Expected spectral peakiness >= 3.0, got ${features.spectralPeakiness}`
      );
      assert.strictEqual(features.moirePatternDetected, true);
    });

    it('1.2 [SYNTHETIC_OPTICAL_FIXTURE]: Smooth natural skin gradient exhibits low high-frequency energy', () => {
      const W = 64;
      const H = 64;
      const pixels = new Uint8Array(W * H);

      // Synthesize smooth low-frequency facial skin gradient
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const luma = 120 + 25 * Math.sin((2 * Math.PI * x) / W) + 20 * Math.cos((2 * Math.PI * y) / H);
          pixels[y * W + x] = Math.round(luma);
        }
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.strictEqual(features.isLowQualityOrCorrupt, false);
      assert.ok(
        features.spatialHighFrequencyEnergy < 0.20,
        `Expected smooth skin HF energy < 0.20, got ${features.spatialHighFrequencyEnergy}`
      );
      assert.strictEqual(features.moirePatternDetected, false);
    });

    it('1.3 [SYNTHETIC_OPTICAL_FIXTURE]: Gracefully handles uniform flat image without division by zero', () => {
      const W = 32;
      const H = 32;
      const pixels = new Uint8Array(W * H).fill(128); // Completely flat

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.strictEqual(features.spatialHighFrequencyEnergy, 0.0);
      assert.strictEqual(features.moirePatternDetected, false);
      assert.strictEqual(features.isLowQualityOrCorrupt, true); // Zero AC energy flag
    });

    it('1.4 [SYNTHETIC_OPTICAL_FIXTURE]: Rejects invalid or sub-minimal image dimensions', () => {
      const pixels = new Uint8Array(8 * 8).fill(100);
      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, 8, 8);
      
      assert.strictEqual(features.isLowQualityOrCorrupt, true);
      assert.strictEqual(features.moirePatternDetected, false);
    });

    it('1.5 [SYNTHETIC_OPTICAL_FIXTURE]: Uncorrelated noise produces broadband energy without periodic peakiness', () => {
      const W = 64;
      const H = 64;
      const pixels = new Uint8Array(W * H);

      // Pseudo-random noise
      let seed = 123456;
      for (let i = 0; i < W * H; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        pixels[i] = 100 + (seed % 60);
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      // Even though broadband noise has energy across frequencies, it does NOT trigger Moiré pattern
      // because it lacks periodic spectral concentration (proves false-positive resistance)
      assert.strictEqual(features.moirePatternDetected, false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY 2: SPECULAR HIGHLIGHT EXTRACTION [MOCKED_CAMERA_FRAME]
  // ─────────────────────────────────────────────────────────────────────────
  describe('Category 2: Specular Highlight Profile Extraction [MOCKED_CAMERA_FRAME]', () => {
    
    it('2.1 [MOCKED_CAMERA_FRAME]: Compact specular highlight spot yields positive heuristic score', () => {
      const W = 64;
      const H = 64;
      const pixels = new Uint8Array(W * H).fill(100);

      // Inject small 3x3 specular reflection glint at (30, 30)
      for (let dy = 0; dy < 3; dy++) {
        for (let dx = 0; dx < 3; dx++) {
          pixels[(30 + dy) * W + (30 + dx)] = 255;
        }
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.ok(
        features.specularHighlightFeatureScore > 0.5,
        `Expected compact highlight score > 0.5, got ${features.specularHighlightFeatureScore}`
      );
      assert.strictEqual(features.rawMetrics.saturatedPixelCount, 9);
    });

    it('2.2 [MOCKED_CAMERA_FRAME]: Diffuse flat glare wash yields degraded specular score', () => {
      const W = 64;
      const H = 64;
      const pixels = new Uint8Array(W * H).fill(100);

      // Inject large washed out 25x25 white glare patch (typical of flat glass bounce)
      for (let dy = 0; dy < 25; dy++) {
        for (let dx = 0; dx < 25; dx++) {
          pixels[(15 + dy) * W + (15 + dx)] = 255;
        }
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.ok(
        features.specularHighlightFeatureScore <= 0.2,
        `Expected diffuse glare score <= 0.2, got ${features.specularHighlightFeatureScore}`
      );
      assert.strictEqual(features.rawMetrics.saturatedPixelCount, 625);
    });

    it('2.3 [MOCKED_CAMERA_FRAME]: Zero saturated highlights yields score of 0.0', () => {
      const W = 32;
      const H = 32;
      const pixels = new Uint8Array(W * H).fill(110); // All pixels strictly below saturation floor (250)

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(pixels, W, H);
      
      assert.strictEqual(features.specularHighlightFeatureScore, 0.0);
      assert.strictEqual(features.rawMetrics.saturatedPixelCount, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY 3: DYNAMIC CHALLENGE & SEQUENCE VALIDATION [SOFTWARE_PROTOCOL_TEST]
  // ─────────────────────────────────────────────────────────────────────────
  describe('Category 3: Dynamic Challenge & Sequence Validation [SOFTWARE_PROTOCOL_TEST]', () => {
    
    it('3.1 [SOFTWARE_PROTOCOL_TEST]: Valid monotonic burst sequence within interval bounds passes', () => {
      const timestampsMs: [number, number, number] = [1000, 1120, 1250];
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(
        timestampsMs,
        900,  // issuedAtMs
        4000  // expiresAtMs
      );

      assert.strictEqual(result.isValid, true);
    });

    it('3.2 [SOFTWARE_PROTOCOL_TEST]: Rejects non-monotonic frame sequence (replay / out-of-order)', () => {
      const nonMonotonic: [number, number, number] = [1000, 1200, 1100];
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(nonMonotonic);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.failureReason, 'NON_MONOTONIC_TIMESTAMPS');
    });

    it('3.3 [SOFTWARE_PROTOCOL_TEST]: Rejects duplicate identical timestamps (anti-freeze)', () => {
      const duplicateTimestamps: [number, number, number] = [1000, 1000, 1150];
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(duplicateTimestamps);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.failureReason, 'NON_MONOTONIC_TIMESTAMPS');
    });

    it('3.4 [SOFTWARE_PROTOCOL_TEST]: Rejects sub-minimal inter-frame interval (< 40ms injection)', () => {
      const tooFast: [number, number, number] = [1000, 1020, 1100]; // dt01 = 20ms < 40ms
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(tooFast);

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.failureReason, 'INVALID_INTER_FRAME_INTERVAL');
    });

    it('3.5 [SOFTWARE_PROTOCOL_TEST]: Rejects frame burst submitted after challenge expiration', () => {
      const timestampsMs: [number, number, number] = [5000, 5150, 5300];
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(
        timestampsMs,
        1000, // issuedAtMs
        4500  // expiresAtMs (expired at 4500, last frame is 5300)
      );

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.failureReason, 'CHALLENGE_EXPIRED');
    });

    it('3.6 [SOFTWARE_PROTOCOL_TEST]: Rejects pre-recorded frames predating challenge issuance', () => {
      const timestampsMs: [number, number, number] = [800, 950, 1100];
      const result = CandidatePadHardenedEngine.validateFrameSequenceContinuity(
        timestampsMs,
        1000, // issuedAtMs (frame 0 is 800 < 1000)
        4500
      );

      assert.strictEqual(result.isValid, false);
      assert.strictEqual(result.failureReason, 'FRAME_PREDATES_CHALLENGE');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY 4: MULTI-SIGNAL DECISION FUSION [SOFTWARE_PROTOCOL_TEST]
  // ─────────────────────────────────────────────────────────────────────────
  describe('Category 4: Seven-Signal Decision Fusion Pipeline [SOFTWARE_PROTOCOL_TEST]', () => {
    
    const mockBenignOpticalFeatures: OpticalDisplayFeatures = {
      spatialHighFrequencyEnergy: 0.12,
      spectralPeakiness: 1.8,
      moirePatternDetected: false,
      specularHighlightFeatureScore: 0.85,
      isLowQualityOrCorrupt: false,
      rawMetrics: {
        roiWidth: 64,
        roiHeight: 64,
        totalAcEnergy: 1000,
        highFreqEnergy: 120,
        peakHighFreqMagnitude: 20,
        meanHighFreqMagnitude: 11,
        saturatedPixelCount: 10,
        meanLuminance: 125,
      },
    };

    it('4.1 [SOFTWARE_PROTOCOL_TEST]: All benign signals fuse to BONA_FIDE_CANDIDATE', () => {
      const fusionInput: MultiSignalFusionInput = {
        fiqaQualityAcceptable: true,
        poseContinuityAcceptable: true,
        eyelidApertureClosureRatio: 0.45, // <= 0.60
        opticalFeatures: mockBenignOpticalFeatures,
        sequenceTimingsValid: true,
        dynamicChallengeCompliant: true,
        identitySimilarity: 0.92, // >= 0.85
      };

      const result = CandidatePadHardenedEngine.fusePadSignals(fusionInput);
      assert.strictEqual(result.outcome, 'BONA_FIDE_CANDIDATE');
    });

    it('4.2 [SOFTWARE_PROTOCOL_TEST]: Moiré display grid triggers PRESENTATION_ATTACK_SUSPECTED', () => {
      const attackOpticalFeatures: OpticalDisplayFeatures = {
        ...mockBenignOpticalFeatures,
        spatialHighFrequencyEnergy: 0.52,
        spectralPeakiness: 6.2,
        moirePatternDetected: true,
      };

      const fusionInput: MultiSignalFusionInput = {
        fiqaQualityAcceptable: true,
        poseContinuityAcceptable: true,
        eyelidApertureClosureRatio: 0.45,
        opticalFeatures: attackOpticalFeatures,
        sequenceTimingsValid: true,
        dynamicChallengeCompliant: true,
        identitySimilarity: 0.92,
      };

      const result = CandidatePadHardenedEngine.fusePadSignals(fusionInput);
      assert.strictEqual(result.outcome, 'PRESENTATION_ATTACK_SUSPECTED');
      assert.strictEqual(result.reason, 'ELECTRONIC_DISPLAY_PERIODIC_GRID_DETECTED');
    });

    it('4.3 [SOFTWARE_PROTOCOL_TEST]: Low FIQA quality triggers CAPTURE_QUALITY_INSUFFICIENT', () => {
      const fusionInput: MultiSignalFusionInput = {
        fiqaQualityAcceptable: false, // Motion blur / extreme darkness
        poseContinuityAcceptable: true,
        eyelidApertureClosureRatio: 0.45,
        opticalFeatures: mockBenignOpticalFeatures,
        sequenceTimingsValid: true,
        dynamicChallengeCompliant: true,
        identitySimilarity: 0.92,
      };

      const result = CandidatePadHardenedEngine.fusePadSignals(fusionInput);
      assert.strictEqual(result.outcome, 'CAPTURE_QUALITY_INSUFFICIENT');
    });

    it('4.4 [SOFTWARE_PROTOCOL_TEST]: Dynamic challenge failure triggers CHALLENGE_INVALID', () => {
      const fusionInput: MultiSignalFusionInput = {
        fiqaQualityAcceptable: true,
        poseContinuityAcceptable: true,
        eyelidApertureClosureRatio: 0.45,
        opticalFeatures: mockBenignOpticalFeatures,
        sequenceTimingsValid: true,
        dynamicChallengeCompliant: false, // User failed to perform requested micro-action
        identitySimilarity: 0.92,
      };

      const result = CandidatePadHardenedEngine.fusePadSignals(fusionInput);
      assert.strictEqual(result.outcome, 'CHALLENGE_INVALID');
    });

    it('4.5 [SOFTWARE_PROTOCOL_TEST]: Corrupt optical feature extraction triggers SIGNAL_UNAVAILABLE', () => {
      const corruptOpticalFeatures: OpticalDisplayFeatures = {
        ...mockBenignOpticalFeatures,
        isLowQualityOrCorrupt: true,
      };

      const fusionInput: MultiSignalFusionInput = {
        fiqaQualityAcceptable: true,
        poseContinuityAcceptable: true,
        eyelidApertureClosureRatio: 0.45,
        opticalFeatures: corruptOpticalFeatures,
        sequenceTimingsValid: true,
        dynamicChallengeCompliant: true,
        identitySimilarity: 0.92,
      };

      const result = CandidatePadHardenedEngine.fusePadSignals(fusionInput);
      assert.strictEqual(result.outcome, 'SIGNAL_UNAVAILABLE');
    });

    it('4.6 [SOFTWARE_PROTOCOL_TEST]: Isolated comparison mode returns comparative telemetry without side effects', () => {
      const comparison = CandidatePadHardenedEngine.comparePoliciesInIsolatedMode({
        f1Aperture: 12.0,
        f2Aperture: 5.0, // 5 / 12 = 0.417 <= 0.60
        f3Aperture: 11.8,
        dt12Ms: 120,
        dt23Ms: 130,
        mu1Luma: 120,
        mu2Luma: 121,
        mu3Luma: 122,
        laplacianVar: 350.0,
        identityCosine13: 0.94,
        periodicScreenGridEnergy: 0.58, // Elevated tablet screen grid
        specularHighlightFeatureScore: 0.01, // Flat glass
      });

      // Baseline falsely accepts because eye aperture closed and luma was stable
      assert.strictEqual(comparison.baseline.padDecision, 'PASS_LIVE_BONAFIDE');
      // Candidate correctly intercepts because periodicScreenGridEnergy >= 0.38
      assert.strictEqual(comparison.candidate.padDecision, 'REJECT_PRESENTATION_ATTACK');
      assert.strictEqual(comparison.policyAgreement, false);
      assert.strictEqual(comparison.isVulnerabilityIntercepted, true);
    });
  });
});
