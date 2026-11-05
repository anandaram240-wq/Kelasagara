// backend/src/services/biometric_matching.ts
import { config } from "../config";

/**
 * Computes Cosine Similarity between two numeric vectors.
 * For unit-normalized vectors (||v|| = 1.0), this equals the dot product.
 */
export function cosineSimilarity(a: number[] | Float32Array, b: number[] | Float32Array): number {
  if (!a || !b || a.length !== b.length || a.length === 0) return 0.0;
  let dot = 0.0;
  let normA = 0.0;
  let normB = 0.0;

  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  if (normA === 0 || normB === 0) return 0.0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

/**
 * Converts cosine similarity into cosine distance.
 * distance = 1.0 - similarity
 */
export function similarityToDistance(similarity: number): number {
  return 1.0 - similarity;
}

/**
 * Converts cosine distance back to similarity.
 */
export function distanceToSimilarity(distance: number): number {
  return 1.0 - distance;
}

/**
 * Normalizes a vector onto the unit hypersphere (L2 norm = 1.0).
 */
export function l2Normalize(v: number[] | Float32Array): number[] {
  let sumSq = 0.0;
  for (let i = 0; i < v.length; i++) {
    sumSq += v[i] * v[i];
  }
  const norm = Math.sqrt(sumSq);
  if (norm === 0.0) return Array.from(v);
  const result = new Array(v.length);
  for (let i = 0; i < v.length; i++) {
    result[i] = v[i] / norm;
  }
  return result;
}

/**
 * Masks phone number for DPDPA 2023 compliance.
 * e.g. +91 98450 12345 -> +91 ******2345
 */
export function maskPhoneNumber(phone: string): string {
  const clean = (phone || "").trim();
  if (clean.length < 4) return "an existing profile";
  const last4 = clean.slice(-4);
  if (clean.startsWith("+91")) return `+91 ******${last4}`;
  return `******${last4}`;
}

/**
 * Masks user name for privacy-preserving duplicate account hints.
 * Shows first half of each name word visible, with remaining characters masked as '*'.
 * e.g. "Ananda Kumar" -> "Ana*** Kum**"
 * e.g. "Ramesh" -> "Ram***"
 */
export function maskName(fullName?: string | null): string {
  const clean = (fullName || "").trim();
  if (!clean || clean.length === 0) return "Registered User";
  const words = clean.split(/\s+/);
  return words
    .map((word) => {
      if (word.length <= 2) {
        return word.charAt(0) + "*";
      }
      const visibleLength = Math.ceil(word.length / 2);
      const maskedLength = word.length - visibleLength;
      return word.slice(0, visibleLength) + "*".repeat(maskedLength);
    })
    .join(" ");
}

export type MatchDecision = "duplicate" | "ambiguity" | "unique";

/**
 * Classifies 1:1 verification probe similarity against operating verificationThreshold.
 * OpenCV SFace reference threshold = 0.363.
 */
export function evaluateVerification(similarity: number, threshold = config.verificationThreshold): {
  isMatch: boolean;
  similarity: number;
  threshold: number;
} {
  return {
    isMatch: similarity >= threshold,
    similarity,
    threshold,
  };
}

/**
 * Classifies 1:N candidate matching score against calibrated deduplication thresholds.
 */
export function evaluateMatch(maxSimilarity: number): {
  decision: MatchDecision;
  isDuplicate: boolean;
  isHardBlock: boolean;
} {
  const hardBlockThresh = config.hardBlockThreshold || 0.90;
  if (maxSimilarity >= hardBlockThresh) {
    return { decision: "duplicate", isDuplicate: true, isHardBlock: true };
  }
  if (maxSimilarity >= config.duplicateThreshold) {
    return { decision: "duplicate", isDuplicate: true, isHardBlock: false };
  }
  if (maxSimilarity >= config.ambiguityThreshold) {
    return { decision: "ambiguity", isDuplicate: false, isHardBlock: false };
  }
  return { decision: "unique", isDuplicate: false, isHardBlock: false };
}

/**
 * Masks a Firebase UID for safe display to the duplicate claimant.
 * Shows first 3 chars + *** + last 4 chars.
 * Example: 'xK9mP2qRsT7uVwXy' → 'xK9***wXy'
 * DPDPA 2023 §8(3) compliant — no raw UID exposure.
 */
export function maskUid(uid: string): string {
  if (!uid || uid.length < 8) return '***';
  return `${uid.slice(0, 3)}***${uid.slice(-4)}`;
}

/**
 * Generates a Kelasagara-style masked display ID.
 * Format: KLS-{masked_uid_segment}-{last4_phone}
 * Example: 'KLS-xK9***wXy-7890'
 */
export function maskedDisplayId(uid: string, phoneNumber: string): string {
  const maskedU = maskUid(uid);
  const phoneSuffix = phoneNumber.replace(/\D/g, '').slice(-4);
  return phoneSuffix ? `KLS-${maskedU}-${phoneSuffix}` : `KLS-${maskedU}`;
}
