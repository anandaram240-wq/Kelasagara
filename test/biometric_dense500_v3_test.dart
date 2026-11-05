// File: test/biometric_dense500_v3_test.dart
// Standards Verified:
// - ISO/IEC 19794-5 & 39794-5: 3D Pose, Scale & Roll Alignment Invariance
// - ISO/IEC 19795-1: Demographic Occlusion Invariance (Beards, Turbans) & 1:N Stranger Separation
// - ISO/IEC 30107-3: 3D Perspective Parallax PAD (Live 3D Burst vs Coplanar 2D Spoof)
// - ISO/IEC 24745: Cancelable Biometric BioHash Salt Revocation & Unlinkability

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/dense_500_landmark_engine_v3.dart';

/// Parametric 3D Craniofacial Synthesizer for deterministic anthropometric testing.
class SyntheticCraniofacialGenerator {
  /// Generates a realistic 478-vertex 3D facial mesh parameterized by subject ID.
  /// Each subject ID produces a distinct biological morphology (inter-canthal ratio,
  /// nasal bridge prominence, zygomatic arch width, mandibular taper, cranial vault height).
  static List<Point3D> generateSubjectMesh478({
    required int subjectSeed,
    double cameraScale = 120.0,
    double rollDeg = 0.0,
    double pitchDeg = 0.0,
    double yawDeg = 0.0,
    double translateX = 240.0,
    double translateY = 320.0,
    double sensorNoiseStd = 0.0,
    int noiseSeed = 101,
  }) {
    final math.Random subjectRng = math.Random(subjectSeed * 7919 + 31);
    final math.Random noiseRng = math.Random(noiseSeed);

    // Subject-specific anatomical morphology parameters
    final double periocularSpread = 0.82 + (subjectRng.nextDouble() - 0.5) * 0.48;
    final double nasalBridgeHeight = 0.32 + (subjectRng.nextDouble() - 0.5) * 0.28;
    final double nasalLength = 0.58 + (subjectRng.nextDouble() - 0.5) * 0.36;
    final double zygomaticWidth = 1.35 + (subjectRng.nextDouble() - 0.5) * 0.55;
    final double mandibularTaper = 0.95 + (subjectRng.nextDouble() - 0.5) * 0.52;
    final double cranialHeight = 0.78 + (subjectRng.nextDouble() - 0.5) * 0.42;

    // Subject-specific harmonic morphological signature across facial surface
    final List<double> freqX = List<double>.generate(
      6,
      (_) => (subjectRng.nextDouble() - 0.5) * 0.42,
    );
    final List<double> freqY = List<double>.generate(
      6,
      (_) => (subjectRng.nextDouble() - 0.5) * 0.42,
    );
    final List<double> freqZ = List<double>.generate(
      6,
      (_) => (subjectRng.nextDouble() - 0.5) * 0.36,
    );

    final List<Point3D> canonical = List<Point3D>.filled(
      478,
      const Point3D(0, 0, 0),
    );

    for (int i = 0; i < 478; i++) {
      final double u = (i / 478.0) * 2.0 * math.pi;
      final double v = ((i * 13) % 478) / 478.0;

      // Base anatomical ellipsoid coordinates
      double x = zygomaticWidth * 0.5 * math.cos(u) * (0.65 + 0.35 * v);
      double y = (v - 0.42) * 1.65;
      double z = -0.22 * (x * x + y * y) + 0.12 * math.cos(u * 2.0);

      // Partition-specific morphological modulation
      if (i < 150) {
        // Upper cranial / forehead zone
        y -= 0.25 * cranialHeight;
        x *= periocularSpread;
      } else if (i >= 150 && i < 470) {
        // Lower mandibular / labial zone
        y += 0.22 * mandibularTaper;
        x *= mandibularTaper * 0.88;
      }

      // Apply subject-specific biological surface harmonics
      for (int h = 0; h < 6; h++) {
        final double phase = (h + 1) * u + (h + 2) * v * math.pi;
        x += freqX[h] * math.sin(phase) * 0.28;
        y += freqY[h] * math.cos(phase) * 0.28;
        z += freqZ[h] * math.sin(phase * 0.7) * 0.24;
      }

      canonical[i] = Point3D(x, y, z, confidence: 0.98);
    }

    // Pin canonical anatomical anchor indices required by Procrustes & PAD stages
    canonical[Dense500LandmarkEngineV3.kLeftPupilIdx] =
        const Point3D(-0.5, 0.0, 0.0, confidence: 0.99);
    canonical[Dense500LandmarkEngineV3.kRightPupilIdx] =
        const Point3D(0.5, 0.0, 0.0, confidence: 0.99);
    canonical[Dense500LandmarkEngineV3.kNasionBridgeIdx] = Point3D(
      0.0,
      -0.06 * periocularSpread,
      0.14 * nasalBridgeHeight,
      confidence: 0.99,
    );
    canonical[Dense500LandmarkEngineV3.kNoseTipIdx] = Point3D(
      0.0,
      0.34 * nasalLength,
      0.38 + 0.15 * nasalBridgeHeight,
      confidence: 0.99,
    );
    canonical[Dense500LandmarkEngineV3.kSubnasaleIdx] = Point3D(
      0.0,
      0.46 * nasalLength,
      0.18 * nasalBridgeHeight,
      confidence: 0.98,
    );
    canonical[Dense500LandmarkEngineV3.kForeheadGlabellaIdx] = Point3D(
      0.0,
      -0.52 * cranialHeight,
      0.06,
      confidence: 0.96,
    );
    canonical[Dense500LandmarkEngineV3.kChinGnathionIdx] = Point3D(
      0.0,
      1.12 * mandibularTaper,
      0.04,
      confidence: 0.96,
    );
    canonical[Dense500LandmarkEngineV3.kLeftCheekZygomaIdx] = Point3D(
      -0.68 * zygomaticWidth,
      0.24,
      -0.18,
      confidence: 0.97,
    );
    canonical[Dense500LandmarkEngineV3.kRightCheekZygomaIdx] = Point3D(
      0.68 * zygomaticWidth,
      0.24,
      -0.18,
      confidence: 0.97,
    );
    canonical[Dense500LandmarkEngineV3.kMouthLeftIdx] = Point3D(
      -0.32 * mandibularTaper,
      0.72 * nasalLength,
      0.08,
      confidence: 0.97,
    );
    canonical[Dense500LandmarkEngineV3.kMouthRightIdx] = Point3D(
      0.32 * mandibularTaper,
      0.72 * nasalLength,
      0.08,
      confidence: 0.97,
    );

    // Apply 3D Rigid Camera Transformation (Pitch -> Yaw -> Roll -> Scale -> Translate)
    final double rRad = rollDeg * math.pi / 180.0;
    final double pRad = pitchDeg * math.pi / 180.0;
    final double yRad = yawDeg * math.pi / 180.0;

    final double cosR = math.cos(rRad), sinR = math.sin(rRad);
    final double cosP = math.cos(pRad), sinP = math.sin(pRad);
    final double cosY = math.cos(yRad), sinY = math.sin(yRad);

    final List<Point3D> transformed = List<Point3D>.filled(
      478,
      const Point3D(0, 0, 0),
    );

    for (int i = 0; i < 478; i++) {
      final Point3D pt = canonical[i];

      // 1. Pitch around X-axis
      final double x1 = pt.x;
      final double y1 = pt.y * cosP - pt.z * sinP;
      final double z1 = pt.y * sinP + pt.z * cosP;

      // 2. Yaw around Y-axis
      final double x2 = x1 * cosY - z1 * sinY;
      final double y2 = y1;
      final double z2 = x1 * sinY + z1 * cosY;

      // 3. Roll around Z-axis
      final double x3 = x2 * cosR - y2 * sinR;
      final double y3 = x2 * sinR + y2 * cosR;
      final double z3 = z2;

      // 4. Add sensor landmark jitter & scale to screen pixels
      final double nx = sensorNoiseStd > 0
          ? (noiseRng.nextDouble() - 0.5) * 2.0 * sensorNoiseStd
          : 0.0;
      final double ny = sensorNoiseStd > 0
          ? (noiseRng.nextDouble() - 0.5) * 2.0 * sensorNoiseStd
          : 0.0;
      final double nz = sensorNoiseStd > 0
          ? (noiseRng.nextDouble() - 0.5) * 2.0 * sensorNoiseStd
          : 0.0;

      transformed[i] = Point3D(
        (x3 + nx) * cameraScale + translateX,
        (y3 + ny) * cameraScale + translateY,
        (z3 + nz) * cameraScale,
        confidence: pt.confidence,
      );
    }

    return transformed;
  }

  /// Simulates thick beard and mustache growth by perturbing lower mandibular/labial
  /// vertices [150..469] and dropping detector landmark confidence in Zone D.
  static List<Point3D> applyThickBeardOcclusion(List<Point3D> cleanMesh) {
    final List<Point3D> occluded = List<Point3D>.from(cleanMesh);
    final math.Random beardRng = math.Random(9001);

    for (int i = 150; i < 468; i++) {
      // Preserve rigid eye pupils and nasal bridge
      if (i == Dense500LandmarkEngineV3.kLeftPupilIdx ||
          i == Dense500LandmarkEngineV3.kRightPupilIdx ||
          i == Dense500LandmarkEngineV3.kNasionBridgeIdx ||
          i == Dense500LandmarkEngineV3.kNoseTipIdx ||
          i == Dense500LandmarkEngineV3.kLeftCheekZygomaIdx ||
          i == Dense500LandmarkEngineV3.kRightCheekZygomaIdx) {
        continue;
      }
      // Only perturb lower-face vertices (below subnasale) or indices mapped to Zone D
      final Point3D p = occluded[i];
      occluded[i] = Point3D(
        p.x + (beardRng.nextDouble() - 0.5) * 18.0,
        p.y + 14.0 + beardRng.nextDouble() * 16.0,
        p.z + (beardRng.nextDouble() - 0.5) * 12.0,
        confidence: 0.18, // Low landmark visibility due to heavy facial hair
      );
    }

    // Expand chin gnathion downward to simulate a heavy beard profile
    final Point3D chin = occluded[Dense500LandmarkEngineV3.kChinGnathionIdx];
    occluded[Dense500LandmarkEngineV3.kChinGnathionIdx] = Point3D(
      chin.x,
      chin.y + 38.0,
      chin.z + 10.0,
      confidence: 0.20,
    );

    return occluded;
  }

  /// Simulates a worker wearing a turban, headscarf, or safety helmet by obscuring
  /// upper cranial/forehead vertices [0..149] and dropping confidence in Zone C.
  static List<Point3D> applyTurbanHeadgearOcclusion(List<Point3D> cleanMesh) {
    final List<Point3D> occluded = List<Point3D>.from(cleanMesh);
    final math.Random turbanRng = math.Random(4004);

    for (int i = 0; i < 150; i++) {
      if (i == Dense500LandmarkEngineV3.kNoseTipIdx ||
          i == Dense500LandmarkEngineV3.kSubnasaleIdx) {
        continue;
      }
      final Point3D p = occluded[i];
      occluded[i] = Point3D(
        p.x + (turbanRng.nextDouble() - 0.5) * 14.0,
        p.y + 22.0 + turbanRng.nextDouble() * 12.0,
        p.z + 15.0,
        confidence: 0.14, // Obscured by turban fabric fold
      );
    }

    final Point3D glabella =
        occluded[Dense500LandmarkEngineV3.kForeheadGlabellaIdx];
    occluded[Dense500LandmarkEngineV3.kForeheadGlabellaIdx] = Point3D(
      glabella.x,
      glabella.y + 32.0,
      glabella.z + 14.0,
      confidence: 0.15,
    );

    return occluded;
  }
}

void main() {
  group('Dense500LandmarkEngineV3 — Mathematical & Hypersphere Properties', () {
    test(
      '1. Emits unit-normalized 512-D full and 256-D periocular embeddings centered across all orthants',
      () {
        final List<Point3D> mesh =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 1,
            );
        final BiometricTemplateV3 tpl =
            Dense500LandmarkEngineV3.extractTemplate(rawLandmarks: mesh);

        expect(
          BiometricTemplateV3.kModelVersion,
          equals('kelasagara_biomatch_v3_dense512'),
        );
        expect(tpl.fullEmbedding512.length, equals(512));
        expect(tpl.periocularEmbedding256.length, equals(256));

        // Verify L2 norm == 1.0 on S^511 and S^255
        double norm512 = 0.0;
        int positiveCount = 0;
        int negativeCount = 0;
        for (final double v in tpl.fullEmbedding512) {
          norm512 += v * v;
          if (v >= 0) {
            positiveCount++;
          } else {
            negativeCount++;
          }
        }
        expect(math.sqrt(norm512), closeTo(1.0, 1e-5));

        double norm256 = 0.0;
        for (final double v in tpl.periocularEmbedding256) {
          norm256 += v * v;
        }
        expect(math.sqrt(norm256), closeTo(1.0, 1e-5));

        // Verify First-Orthant Trap is eliminated (balanced positive & negative dimensions)
        expect(positiveCount, greaterThan(180));
        expect(negativeCount, greaterThan(180));
      },
    );

    test(
      '2. Gracefully upsamples legacy 133-point ML Kit contours to 500 canonical topological marks',
      () {
        final List<Point3D> mesh478 =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 7,
            );
        final List<Point3D> legacy133 = mesh478.sublist(0, 133);

        final BiometricTemplateV3 tpl =
            Dense500LandmarkEngineV3.extractTemplate(rawLandmarks: legacy133);

        expect(tpl.fullEmbedding512.length, equals(512));
        expect(tpl.periocularEmbedding256.length, equals(256));
        expect(tpl.isoQualityScore, greaterThan(50.0));
      },
    );
  });

  group('Dense500LandmarkEngineV3 — 3D Pose, Scale & Sensor Jitter Invariance', () {
    test(
      '3. Maintains >= 0.88 similarity across camera distance (40cm-90cm), roll (+-15 deg), and sensor noise',
      () {
        final List<Point3D> enrollmentScan =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 42,
              cameraScale: 100.0,
              rollDeg: 0.0,
              translateX: 200.0,
              translateY: 250.0,
            );

        final List<Point3D> fieldLoginScan =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 42,
              cameraScale: 185.0, // Closer to phone camera
              rollDeg: 14.5, // Tilted head
              translateX: 340.0,
              translateY: 410.0,
              sensorNoiseStd: 0.004, // Realistic landmark detector jitter
              noiseSeed: 555,
            );

        final BiometricTemplateV3 tplEnroll =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: enrollmentScan,
            );
        final BiometricTemplateV3 tplLogin =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: fieldLoginScan,
            );

        final BiometricMatchDecision decision =
            Dense500LandmarkEngineV3.compareTemplates(tplLogin, tplEnroll);

        expect(decision.fusedSimilarity, greaterThanOrEqualTo(0.88));
        expect(decision.isVerified1to1, isTrue);
        expect(decision.tier, equals(MatchTier.tier3HardDuplicateBlock));
      },
    );
  });

  group('Dense500LandmarkEngineV3 — Demographic Occlusion Invariance (Q1)', () {
    test(
      '4. Maintains >= 0.80 similarity when a clean-shaven worker grows a thick beard & mustache',
      () {
        final List<Point3D> cleanShavenMesh =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 108,
            );
        final List<Point3D> thickBeardMesh =
            SyntheticCraniofacialGenerator.applyThickBeardOcclusion(
              cleanShavenMesh,
            );

        final BiometricTemplateV3 tplClean =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: cleanShavenMesh,
            );
        final BiometricTemplateV3 tplBeard =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: thickBeardMesh,
            );

        // Verify engine detects lower-jaw occlusion
        expect(tplBeard.occlusionRatio, greaterThan(0.35));

        final BiometricMatchDecision decision =
            Dense500LandmarkEngineV3.compareTemplates(tplBeard, tplClean);

        // Rigid periocular core remains virtually unchanged despite heavy jaw perturbation
        expect(decision.periocularCosine, greaterThanOrEqualTo(0.85));
        expect(decision.fusedSimilarity, greaterThanOrEqualTo(0.80));
        expect(decision.isVerified1to1, isTrue);
      },
    );

    test(
      '5. Maintains >= 0.80 similarity when a worker wears a turban or headscarf obscuring the forehead',
      () {
        final List<Point3D> bareHeadMesh =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 215,
            );
        final List<Point3D> turbanMesh =
            SyntheticCraniofacialGenerator.applyTurbanHeadgearOcclusion(
              bareHeadMesh,
            );

        final BiometricTemplateV3 tplBare =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: bareHeadMesh,
            );
        final BiometricTemplateV3 tplTurban =
            Dense500LandmarkEngineV3.extractTemplate(rawLandmarks: turbanMesh);

        expect(tplTurban.occlusionRatio, greaterThan(0.30));

        final BiometricMatchDecision decision =
            Dense500LandmarkEngineV3.compareTemplates(tplTurban, tplBare);

        expect(decision.periocularCosine, greaterThanOrEqualTo(0.85));
        expect(decision.fusedSimilarity, greaterThanOrEqualTo(0.80));
        expect(decision.isVerified1to1, isTrue);
      },
    );

    test(
      '6. Verifies 1:1 login under simultaneous Turban + Thick Beard occlusion via Periocular Subspace Fusion',
      () {
        final List<Point3D> baselineMesh =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 309,
            );
        final List<Point3D> dualOccludedMesh =
            SyntheticCraniofacialGenerator.applyTurbanHeadgearOcclusion(
              SyntheticCraniofacialGenerator.applyThickBeardOcclusion(
                baselineMesh,
              ),
            );

        final BiometricTemplateV3 tplBase =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: baselineMesh,
            );
        final BiometricTemplateV3 tplDual =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: dualOccludedMesh,
            );

        expect(tplDual.occlusionRatio, greaterThan(0.65));

        final BiometricMatchDecision decision =
            Dense500LandmarkEngineV3.compareTemplates(tplDual, tplBase);

        expect(decision.periocularCosine, greaterThanOrEqualTo(0.82));
        expect(decision.fusedSimilarity, greaterThanOrEqualTo(0.80));
        expect(decision.isVerified1to1, isTrue);
      },
    );
  });

  group('Dense500LandmarkEngineV3 — 1:N Stranger Separation & Zero False Collisions', () {
    test(
      '7. Keeps 190 pairwise stranger comparisons centered near 0.0 with 0% False Match Rate (< 0.74)',
      () {
        const int numDistinctWorkers = 20;
        final List<BiometricTemplateV3> gallery = <BiometricTemplateV3>[];

        for (int s = 1; s <= numDistinctWorkers; s++) {
          final List<Point3D> mesh =
              SyntheticCraniofacialGenerator.generateSubjectMesh478(
                subjectSeed: s * 17 + 3,
              );
          gallery.add(
            Dense500LandmarkEngineV3.extractTemplate(rawLandmarks: mesh),
          );
        }

        double sumSimilarity = 0.0;
        double maxStrangerSimilarity = -1.0;
        int totalPairs = 0;
        int falseDuplicateBlocks = 0;

        for (int i = 0; i < numDistinctWorkers; i++) {
          for (int j = i + 1; j < numDistinctWorkers; j++) {
            final BiometricMatchDecision cmp =
                Dense500LandmarkEngineV3.compareTemplates(
                  gallery[i],
                  gallery[j],
                );
            sumSimilarity += cmp.fusedSimilarity;
            if (cmp.fusedSimilarity > maxStrangerSimilarity) {
              maxStrangerSimilarity = cmp.fusedSimilarity;
            }
            if (cmp.tier == MatchTier.tier3HardDuplicateBlock) {
              falseDuplicateBlocks++;
            }
            totalPairs++;
          }
        }

        final double meanStrangerSimilarity = sumSimilarity / totalPairs;

        // Mean similarity across unrelated people must center near 0.0 (not 0.84!)
        expect(meanStrangerSimilarity.abs(), lessThan(0.15));
        // Zero false duplicate blocks across all 190 pairs
        expect(falseDuplicateBlocks, equals(0));
        expect(
          maxStrangerSimilarity,
          lessThan(Dense500LandmarkEngineV3.kTier3DuplicateHardThreshold),
        );
      },
    );
  });

  group('Dense500LandmarkEngineV3 — ISO/IEC 24745 & ISO/IEC 30107-3 Security', () {
    test(
      '8. ISO/IEC 24745 Cancelable BioHash: rotating applicationBioHashSalt revokes & unlinks template',
      () {
        final List<Point3D> mesh =
            SyntheticCraniofacialGenerator.generateSubjectMesh478(
              subjectSeed: 77,
            );

        final BiometricTemplateV3 tplSaltA =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: mesh,
              applicationBioHashSalt: 0x4B4C535F, // Salt A
            );
        final BiometricTemplateV3 tplSaltB =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: mesh,
              applicationBioHashSalt: 0x9F2A88C1, // Rotated Salt B
            );

        final double crossSaltCosine =
            Dense500LandmarkEngineV3.cosineSimilarity(
              tplSaltA.fullEmbedding512,
              tplSaltB.fullEmbedding512,
            );

        // Same face under rotated BioHash salt must be quasi-orthogonal (unlinkable)
        expect(crossSaltCosine.abs(), lessThan(0.25));
      },
    );

    test(
      '9. ISO/IEC 30107-3 3D Parallax PAD: distinguishes live 3D burst from flat 2D printed photo spoof',
      () {
        // 1. Live 3D burst with natural micro-yaw head movement (-4 deg to +4 deg)
        final List<List<Point3D>> live3DBurst = <List<Point3D>>[
          SyntheticCraniofacialGenerator.generateSubjectMesh478(
            subjectSeed: 88,
            yawDeg: -4.0,
          ),
          SyntheticCraniofacialGenerator.generateSubjectMesh478(
            subjectSeed: 88,
            yawDeg: 0.0,
          ),
          SyntheticCraniofacialGenerator.generateSubjectMesh478(
            subjectSeed: 88,
            yawDeg: 4.5,
          ),
        ];

        final BiometricTemplateV3 liveTpl =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: live3DBurst[1],
              burstFramesForPad: live3DBurst,
            );

        // 2. Flat 2D Printed Photo Spoof (all Z depth coordinates flattened to 0.0, static parallax)
        final List<Point3D> flat2DMesh = live3DBurst[1]
            .map((Point3D p) => Point3D(p.x, p.y, 0.0, confidence: p.confidence))
            .toList();
        final List<List<Point3D>> flat2DBurst = <List<Point3D>>[
          flat2DMesh,
          flat2DMesh,
          flat2DMesh,
        ];

        final BiometricTemplateV3 spoofTpl =
            Dense500LandmarkEngineV3.extractTemplate(
              rawLandmarks: flat2DMesh,
              burstFramesForPad: flat2DBurst,
            );

        expect(liveTpl.padLivenessScore, greaterThanOrEqualTo(0.65));
        expect(spoofTpl.padLivenessScore, lessThan(0.05));
      },
    );
  });
}
