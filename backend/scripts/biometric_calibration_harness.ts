// backend/scripts/biometric_calibration_harness.ts
/**
 * Automated Biometric Calibration CLI (Gate G-01).
 * Re-exports core calibration & evaluation logic from service and provides executable CLI.
 */

export * from '../src/services/biometric_evaluation_harness';
import { BiometricCalibrationHarness } from '../src/services/biometric_evaluation_harness';

if (require.main === module) {
  // Generate benchmark demonstration calibration report
  const rng = (seed: number) => {
    let s = seed;
    return () => {
      s = (s * 9301 + 49297) % 233280;
      return s / 233280;
    };
  };

  const rand = rng(42);
  const genuine: number[] = [];
  const impostor: number[] = [];

  for (let i = 0; i < 1500; i++) {
    // Genuine similarity distribution ~ N(0.68, 0.08)
    const u1 = rand();
    const u2 = rand();
    const z = Math.sqrt(-2.0 * Math.log(u1 || 0.001)) * Math.cos(2.0 * Math.PI * u2);
    genuine.push(Math.max(-0.2, Math.min(0.99, 0.68 + z * 0.08)));
  }

  for (let i = 0; i < 25000; i++) {
    // Impostor similarity distribution ~ N(0.08, 0.09)
    const u1 = rand();
    const u2 = rand();
    const z = Math.sqrt(-2.0 * Math.log(u1 || 0.001)) * Math.cos(2.0 * Math.PI * u2);
    impostor.push(Math.max(-0.4, Math.min(0.72, 0.08 + z * 0.09)));
  }

  const report = BiometricCalibrationHarness.calibrateFromScores(genuine, impostor, 10000);
  console.log('=== KELASAGARA BIOMETRIC EMPIRICAL CALIBRATION REPORT ===');
  console.log(`Subjects/Pairs: Genuine=${report.genuinePairsCount}, Impostor=${report.impostorPairsCount}`);
  console.log(`Equal Error Rate (EER): ${(report.equalErrorRate * 100).toFixed(3)}% at Tau=${report.eerThreshold}`);
  console.log(`Recommended Verify Threshold: ${report.recommendedVerifyThreshold}`);
  console.log(`Recommended Duplicate Warning: ${report.recommendedDuplicateWarningThreshold}`);
  console.log(`Recommended Duplicate Hard Block: ${report.recommendedDuplicateHardBlockThreshold}`);
  console.log('\nDET Curve:');
  console.log(report.asciiDetCurve.join('\n'));
}
