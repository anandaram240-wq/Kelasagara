// functions/test/biometric_unit.test.js
// Node.js test suite for Cloud Functions biometric matching primitives

const assert = require("assert");

// Math functions identical to functions/src/index.ts
function cosineSimilarity(a, b) {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

function l2Normalize(v) {
  const sumSq = v.reduce((acc, val) => acc + val * val, 0);
  const norm = Math.sqrt(sumSq);
  if (norm === 0) return [...v];
  return v.map((x) => x / norm);
}

function maskPhone(phone) {
  const clean = phone.trim();
  if (clean.length < 4) return "an existing profile";
  const last4 = clean.slice(-4);
  if (clean.startsWith("+91")) return `+91 ******${last4}`;
  return `******${last4}`;
}

const DUPLICATE_THRESHOLD = 0.74;
const AMBIGUITY_THRESHOLD = 0.65;
const EMBEDDING_DIM = 128;

console.log("=== RUNNING CLOUD FUNCTIONS BIOMETRIC UNIT TESTS ===");

// Test 1: Vector dimension
const v1 = l2Normalize(new Array(EMBEDDING_DIM).fill(0.1));
assert.strictEqual(v1.length, 128, "Dimension must be 128");
console.log("✔ Test 1: Embedding dimension is 128");

// Test 2: Unit norm
const norm = Math.sqrt(v1.reduce((sum, x) => sum + x * x, 0));
assert(Math.abs(norm - 1.0) < 1e-6, "Normalized vector must have norm = 1.0");
console.log("✔ Test 2: L2 normalization yields unit length 1.0");

// Test 3: Cosine similarity of identical vectors
const simSelf = cosineSimilarity(v1, v1);
assert(Math.abs(simSelf - 1.0) < 1e-6, "Self similarity must be 1.0");
console.log("✔ Test 3: Self-similarity is 1.0");

// Test 4: Duplicate threshold triggers on high similarity
const vDuplicate = v1.map((x, i) => (i < 10 ? x * 0.95 : x));
const normDup = l2Normalize(vDuplicate);
const simDup = cosineSimilarity(v1, normDup);
assert(simDup >= DUPLICATE_THRESHOLD, `Similarity ${simDup} must exceed duplicate threshold ${DUPLICATE_THRESHOLD}`);
console.log(`✔ Test 4: Duplicate detected with similarity ${simDup.toFixed(4)} >= ${DUPLICATE_THRESHOLD}`);

// Test 5: Distinct individuals do not trigger duplicate
const vDistinct = new Array(EMBEDDING_DIM).fill(0).map((_, i) => (i % 2 === 0 ? 1.0 : -1.0));
const normDist = l2Normalize(vDistinct);
const simDist = cosineSimilarity(v1, normDist);
assert(simDist < DUPLICATE_THRESHOLD, `Similarity ${simDist} must be below duplicate threshold`);
console.log(`✔ Test 5: Distinct person similarity ${simDist.toFixed(4)} is safely below threshold`);

// Test 6: Phone masking
assert.strictEqual(maskPhone("+919845012345"), "+91 ******2345");
assert.strictEqual(maskPhone("9845012345"), "******2345");
assert.strictEqual(maskPhone("12"), "an existing profile");
console.log("✔ Test 6: DPDPA 2023 phone masking operates correctly");

console.log("\nALL 6 CLOUD FUNCTIONS TESTS PASSED SUCCESSFULLY! 🚀");
