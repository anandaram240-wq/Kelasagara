// backend/src/services/in_memory_biometric_index.ts
/**
 * In-Memory Biometric Deduplication Index (Ticket T-20 / Finding F8).
 * Shields Firestore Spark free tier (50,000 reads/day) by executing 1:N gallery searches
 * entirely in RAM.
 *
 * Cost reduction:
 * Without index: N Firestore reads per enrollment attempt (500 users = 500 reads).
 * With index: 0 Firestore reads per enrollment attempt (in-memory cosine similarity search).
 *
 * Invariant I-31: RAM Gallery Search Bounded Quota.
 * In production Spark tier, 1:N candidate searches MUST query the in-memory gallery cache
 * before performing any Firestore collection scans.
 */

import { cosineSimilarity } from "./biometric_matching";

export interface IndexedBiometricRecord {
  uid: string;
  embedding: number[];
  modelId: string;
  preprocessVersion: string;
  phoneNumber: string;
  enrolledAtMs: number;
}

export interface CachedTopKResult {
  uid: string;
  similarity: number;
  modelId: string;
  preprocessVersion: string;
  phoneNumber: string;
}

export class InMemoryBiometricIndex {
  private static index: Map<string, IndexedBiometricRecord> = new Map();
  private static isInitialized = false;

  /**
   * Inserts or updates a template in the in-memory gallery.
   */
  static upsert(record: IndexedBiometricRecord): void {
    this.index.set(record.uid, record);
  }

  /**
   * Removes a template from the index (e.g., DPDPA erasure).
   */
  static delete(uid: string): boolean {
    return this.index.delete(uid);
  }

  /**
   * Queries top-K nearest neighbors in RAM using cosine similarity.
   * Filters out candidates from different models or preprocessing pipelines (Invariant I-06).
   */
  static findTopK(
    probeEmbedding: number[],
    excludeUid: string,
    k = 3,
    targetModelId = "sface_opencv_zoo_v1_primary",
    targetPreprocessVersion = "PREPROC_V1_UMEYAMA_112_RGB_RAW255"
  ): CachedTopKResult[] {
    const candidates: CachedTopKResult[] = [];

    for (const [uid, record] of this.index.entries()) {
      if (uid === excludeUid) continue;

      // Invariant I-06: Cross-model / cross-preprocessing protection
      if (record.modelId !== targetModelId || record.preprocessVersion !== targetPreprocessVersion) {
        continue;
      }

      const similarity = cosineSimilarity(probeEmbedding, record.embedding);
      candidates.push({
        uid,
        similarity,
        modelId: record.modelId,
        preprocessVersion: record.preprocessVersion,
        phoneNumber: record.phoneNumber,
      });
    }

    // Sort descending by similarity
    candidates.sort((a, b) => b.similarity - a.similarity);
    return candidates.slice(0, k);
  }

  /**
   * Returns current count of indexed subjects.
   */
  static size(): number {
    return this.index.size;
  }

  /**
   * Clears all indexed templates (testing only).
   */
  static clear(): void {
    this.index.clear();
    this.isInitialized = false;
  }

  /**
   * Populates the index from an array of records (e.g. at startup).
   */
  static populate(records: IndexedBiometricRecord[]): void {
    this.clear();
    for (const r of records) {
      this.index.set(r.uid, r);
    }
    this.isInitialized = true;
  }

  static isReady(): boolean {
    return this.isInitialized;
  }
}
