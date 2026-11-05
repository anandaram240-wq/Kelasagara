// backend/src/tests/biometric_backend.test.ts
import assert from "assert";
import path from "path";
import { cosineSimilarity, l2Normalize, maskPhoneNumber, evaluateMatch, similarityToDistance } from "../services/biometric_matching";
import { runFaceInference } from "../services/face_inference";
import { preprocessFaceBuffer } from "../services/face_preprocessing";
import { config } from "../config";

async function runTests() {
  console.log("====================================================");
  console.log("🧪 RUNNING STANDALONE BACKEND BIOMETRIC TEST SUITE");
  console.log("====================================================");

  // ── TEST 1: Vector Mathematics & L2 Normalization ──────────────────────
  const rawVector = new Float32Array(128).fill(0.25);
  const normalized = l2Normalize(rawVector);
  const norm = Math.sqrt(normalized.reduce((acc, x) => acc + x * x, 0));
  assert(Math.abs(norm - 1.0) < 1e-5, "Normalized vector must have L2 norm = 1.0");
  console.log("✔ Test 1: L2 Normalization yields unit length 1.000000 on S^127");

  // ── TEST 2: Cosine Similarity Primitives ───────────────────────────────
  const selfSim = cosineSimilarity(normalized, normalized);
  assert(Math.abs(selfSim - 1.0) < 1e-5, "Self similarity must equal 1.0");
  
  const opposite = normalized.map(x => -x);
  const oppSim = cosineSimilarity(normalized, opposite);
  assert(Math.abs(oppSim - (-1.0)) < 1e-5, "Opposite vectors must yield -1.0");
  console.log("✔ Test 2: Cosine similarity identity and orthogonality verified");

  // ── TEST 3: Distance Conversion ────────────────────────────────────────
  const dist = similarityToDistance(0.85);
  assert(Math.abs(dist - 0.15) < 1e-5, "Distance must equal 1.0 - similarity");
  console.log("✔ Test 3: Metric cosine distance conversion verified (dist = 1 - sim)");

  // ── TEST 4: DPDPA 2023 Phone Masking ───────────────────────────────────
  assert.strictEqual(maskPhoneNumber("+919845012345"), "+91 ******2345");
  assert.strictEqual(maskPhoneNumber("9845012345"), "******2345");
  assert.strictEqual(maskPhoneNumber("+91 98450 12345"), "+91 ******2345");
  console.log("✔ Test 4: Privacy-preserving DPDPA phone masking verified");

  // ── TEST 5: Threshold Decision Matrix ──────────────────────────────────
  const dupDecision = evaluateMatch(0.82);
  assert.strictEqual(dupDecision.isDuplicate, true, "Sim 0.82 >= 0.74 must be duplicate");
  assert.strictEqual(dupDecision.decision, "duplicate");

  const ambDecision = evaluateMatch(0.68);
  assert.strictEqual(ambDecision.isDuplicate, false, "Sim 0.68 must not block duplicate directly");
  assert.strictEqual(ambDecision.decision, "ambiguity");

  const uniqDecision = evaluateMatch(0.40);
  assert.strictEqual(uniqDecision.isDuplicate, false);
  assert.strictEqual(uniqDecision.decision, "unique");
  console.log("✔ Test 5: Tri-state threshold classification (Duplicate/Ambiguity/Unique) verified");

  // ── TEST 6: MobileFaceNet ONNX Neural Network Inference ────────────────
  console.log("... Running MobileFaceNet ONNX inference on test image buffer ...");
  // Create a synthetic 112x112 RGB buffer (37,632 bytes)
  const syntheticFaceBuffer = Buffer.alloc(112 * 112 * 3, 128);
  const embedding = await runFaceInference(syntheticFaceBuffer);

  assert.strictEqual(embedding.length, 128, "Embedding must have exactly 128 dimensions");
  const modelNorm = Math.sqrt(embedding.reduce((acc, x) => acc + x * x, 0));
  assert(Math.abs(modelNorm - 1.0) < 1e-4, "Model output embedding must be unit normalized");
  console.log(`✔ Test 6: MobileFaceNet forward pass succeeded! Output D=${embedding.length}, Norm=${modelNorm.toFixed(6)}`);

  console.log("\n====================================================");
  console.log("🎉 ALL 6 STANDALONE BACKEND TESTS PASSED CLEANLY!");
  console.log("====================================================");
}

runTests().catch(err => {
  console.error("Test failed with error:", err);
  process.exit(1);
});
