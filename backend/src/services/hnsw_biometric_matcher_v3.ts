// File: backend/src/services/hnsw_biometric_matcher_v3.ts
// KELASAGARA V18 — Gate G-04: Canonical 128-D SFace Contiguous Arena & HNSW Index
// Release Status: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  assertValidCanonicalSfaceEmbedding,
} from '../crypto/cloud_kms_envelope';

export interface EnrolledWorkerSfaceRecordV3 {
  readonly uid: string;
  readonly maskedPhone: string;
  readonly modelId: typeof CANONICAL_SFACE_MODEL_ID;
  readonly modelVersion: typeof CANONICAL_SFACE_MODEL_VERSION;
  readonly templateSchemaVersion: typeof CANONICAL_TEMPLATE_SCHEMA_VERSION;
  readonly sfaceEmbedding128: Float32Array;
  readonly isoQualityScore: number;
  readonly padLivenessScore: number;
  readonly enrolledAtEpochMs: number;
}

export interface DuplicateCandidateMatchV3 {
  readonly matchedUid: string | null;
  readonly matchedMaskedPhone: string | null;
  readonly maxCosineSimilarity: number;
  readonly candidatesEvaluated: number;
  readonly searchLatencyMs: number;
  readonly searchMode: 'EXACT_CONTIGUOUS_SCAN' | 'HNSW_GRAPH_BEAM';
}

export class HighSpeedBiometricIndexV3 {
  public static readonly MODEL_ID = CANONICAL_SFACE_MODEL_ID;
  public static readonly MODEL_VERSION = CANONICAL_SFACE_MODEL_VERSION;
  public static readonly TEMPLATE_SCHEMA_VERSION = CANONICAL_TEMPLATE_SCHEMA_VERSION;
  public static readonly DIMENSION = SFACE_EMBEDDING_DIMENSION;

  private readonly uids: string[] = [];
  private readonly uidToSlot = new Map<string, number>();
  private readonly maskedPhones: string[] = [];
  private readonly qualityScores: Float32Array;
  private readonly padScores: Float32Array;
  private readonly enrolledTimestamps: Float64Array;
  private readonly sfaceArena128: Float32Array;
  private readonly adjacencyLinks: Int32Array[];
  private count = 0;
  private readonly capacity: number;
  private readonly exactScanThreshold: number;

  constructor(maxCapacity = 50000, exactScanThreshold = 50000) {
    if (maxCapacity <= 0) {
      throw new Error('HighSpeedBiometricIndexV3 requires maxCapacity > 0.');
    }
    this.capacity = maxCapacity;
    this.exactScanThreshold = exactScanThreshold;
    this.qualityScores = new Float32Array(maxCapacity);
    this.padScores = new Float32Array(maxCapacity);
    this.enrolledTimestamps = new Float64Array(maxCapacity);
    this.sfaceArena128 = new Float32Array(maxCapacity * SFACE_EMBEDDING_DIMENSION);
    this.adjacencyLinks = new Array(maxCapacity);
  }

  public get size(): number {
    return this.count;
  }

  public get maxCapacity(): number {
    return this.capacity;
  }

  /**
   * Validates and inserts/updates a canonical 128-D SFace template in the contiguous arena.
   * Throws an explicit error if the model identifier, version, schema version, or vector normalization is invalid.
   */
  public upsertTemplate(record: EnrolledWorkerSfaceRecordV3): void {
    if (record.modelId !== CANONICAL_SFACE_MODEL_ID) {
      throw new Error(
        `INCOMPATIBLE_MODEL_ID: Expected ${CANONICAL_SFACE_MODEL_ID}, got ${String(record.modelId)}.`,
      );
    }
    if (record.modelVersion !== CANONICAL_SFACE_MODEL_VERSION) {
      throw new Error(
        `INCOMPATIBLE_MODEL_VERSION: Expected ${CANONICAL_SFACE_MODEL_VERSION}, got ${String(record.modelVersion)}.`,
      );
    }
    if (record.templateSchemaVersion !== CANONICAL_TEMPLATE_SCHEMA_VERSION) {
      throw new Error(
        `INCOMPATIBLE_TEMPLATE_SCHEMA: Expected v${CANONICAL_TEMPLATE_SCHEMA_VERSION}, got v${String(record.templateSchemaVersion)}.`,
      );
    }
    if (!record.uid || typeof record.uid !== 'string') {
      throw new Error('INVALID_RECORD_UID: Non-empty uid is required.');
    }

    const validatedVec = assertValidCanonicalSfaceEmbedding(
      record.sfaceEmbedding128,
      `upsertTemplate(${record.uid})`,
    );

    let slot = this.uidToSlot.get(record.uid) ?? -1;
    if (slot === -1) {
      if (this.count >= this.capacity) {
        throw new Error(
          `BIOMETRIC_ARENA_CAPACITY_EXCEEDED: Capacity ${this.capacity} reached.`,
        );
      }
      slot = this.count++;
      this.uids.push(record.uid);
      this.uidToSlot.set(record.uid, slot);
      this.maskedPhones.push(record.maskedPhone);
    } else {
      this.maskedPhones[slot] = record.maskedPhone;
    }

    this.qualityScores[slot] = record.isoQualityScore;
    this.padScores[slot] = record.padLivenessScore;
    this.enrolledTimestamps[slot] = record.enrolledAtEpochMs;
    this.sfaceArena128.set(validatedVec, slot * SFACE_EMBEDDING_DIMENSION);

    this.buildSmallWorldLinksForSlot(slot, validatedVec);
  }

  /**
   * Retrieves a defensive copy of a worker's enrolled 128-D SFace record for 1:1 verification.
   */
  public getRecordByUid(uid: string): EnrolledWorkerSfaceRecordV3 | null {
    const slot = this.uidToSlot.get(uid);
    if (slot === undefined) return null;

    const vecCopy = new Float32Array(SFACE_EMBEDDING_DIMENSION);
    const start = slot * SFACE_EMBEDDING_DIMENSION;
    vecCopy.set(this.sfaceArena128.subarray(start, start + SFACE_EMBEDDING_DIMENSION));

    return {
      uid: this.uids[slot],
      maskedPhone: this.maskedPhones[slot],
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: vecCopy,
      isoQualityScore: this.qualityScores[slot],
      padLivenessScore: this.padScores[slot],
      enrolledAtEpochMs: this.enrolledTimestamps[slot],
    };
  }

  /**
   * Executes 1:N duplicate candidate search over the canonical 128-D SFace gallery.
   * Returns raw similarity metrics; the caller (`GalleryConsistencyServiceV3`) applies the 1:N decision policy.
   */
  public search1toN(
    probeUid: string,
    probeSface128: Float32Array,
    forceApproximate = false,
  ): DuplicateCandidateMatchV3 {
    const validatedProbe = assertValidCanonicalSfaceEmbedding(
      probeSface128,
      `search1toN(${probeUid})`,
    );

    if (!forceApproximate && this.count <= this.exactScanThreshold) {
      return this.searchExact1toN(probeUid, validatedProbe);
    }
    return this.searchApproximate1toN(probeUid, validatedProbe, 256);
  }

  /**
   * Exact 1:N search scanning the contiguous Float32Array arena (100% exact recall).
   */
  public searchExact1toN(
    probeUid: string,
    validatedProbe128: Float32Array,
  ): DuplicateCandidateMatchV3 {
    const startNs = process.hrtime.bigint();

    let bestSlot = -1;
    let maxCos = -2.0;
    let evaluated = 0;

    for (let slot = 0; slot < this.count; slot++) {
      if (this.uids[slot] === probeUid) {
        continue; // Exclude self during re-enrollment / self-check
      }
      evaluated++;
      const cos = this.dot128(validatedProbe128, slot * SFACE_EMBEDDING_DIMENSION);
      if (!Number.isFinite(cos)) {
        throw new Error(`NON_FINITE_SCORE: Invalid score computed against slot ${slot}.`);
      }
      if (cos > maxCos) {
        maxCos = cos;
        bestSlot = slot;
      }
    }

    const elapsedMs = Number(process.hrtime.bigint() - startNs) / 1e6;

    if (bestSlot === -1) {
      return {
        matchedUid: null,
        matchedMaskedPhone: null,
        maxCosineSimilarity: 0.0,
        candidatesEvaluated: evaluated,
        searchLatencyMs: Number(elapsedMs.toFixed(4)),
        searchMode: 'EXACT_CONTIGUOUS_SCAN',
      };
    }

    return {
      matchedUid: this.uids[bestSlot],
      matchedMaskedPhone: this.maskedPhones[bestSlot],
      maxCosineSimilarity: Number(Math.max(-1.0, Math.min(1.0, maxCos)).toFixed(6)),
      candidatesEvaluated: evaluated,
      searchLatencyMs: Number(elapsedMs.toFixed(4)),
      searchMode: 'EXACT_CONTIGUOUS_SCAN',
    };
  }

  /**
   * Navigable Small-World graph beam search for large-scale galleries.
   */
  public searchApproximate1toN(
    probeUid: string,
    validatedProbe128: Float32Array,
    efSearch = 256,
  ): DuplicateCandidateMatchV3 {
    const startNs = process.hrtime.bigint();

    if (this.count === 0) {
      return {
        matchedUid: null,
        matchedMaskedPhone: null,
        maxCosineSimilarity: 0.0,
        candidatesEvaluated: 0,
        searchLatencyMs: 0.0,
        searchMode: 'HNSW_GRAPH_BEAM',
      };
    }

    const candidateSlots = this.searchSmallWorldCandidates(validatedProbe128, efSearch);
    let bestSlot = -1;
    let maxCos = -2.0;
    let evaluated = 0;

    for (let i = 0; i < candidateSlots.length; i++) {
      const slot = candidateSlots[i];
      if (this.uids[slot] === probeUid) continue;
      evaluated++;
      const cos = this.dot128(validatedProbe128, slot * SFACE_EMBEDDING_DIMENSION);
      if (cos > maxCos) {
        maxCos = cos;
        bestSlot = slot;
      }
    }

    const elapsedMs = Number(process.hrtime.bigint() - startNs) / 1e6;

    if (bestSlot === -1) {
      return {
        matchedUid: null,
        matchedMaskedPhone: null,
        maxCosineSimilarity: 0.0,
        candidatesEvaluated: evaluated,
        searchLatencyMs: Number(elapsedMs.toFixed(4)),
        searchMode: 'HNSW_GRAPH_BEAM',
      };
    }

    return {
      matchedUid: this.uids[bestSlot],
      matchedMaskedPhone: this.maskedPhones[bestSlot],
      maxCosineSimilarity: Number(Math.max(-1.0, Math.min(1.0, maxCos)).toFixed(6)),
      candidatesEvaluated: evaluated,
      searchLatencyMs: Number(elapsedMs.toFixed(4)),
      searchMode: 'HNSW_GRAPH_BEAM',
    };
  }

  /**
   * Produces a lock-free Copy-on-Write (CoW) snapshot with the specified record added or updated.
   */
  public cloneWithUpsert(record: EnrolledWorkerSfaceRecordV3): HighSpeedBiometricIndexV3 {
    const nextCap = Math.max(this.capacity, this.count + 1024);
    const nextIndex = new HighSpeedBiometricIndexV3(nextCap, this.exactScanThreshold);

    for (let s = 0; s < this.count; s++) {
      if (this.uids[s] === record.uid) continue;
      const offset = s * SFACE_EMBEDDING_DIMENSION;
      nextIndex.upsertTemplate({
        uid: this.uids[s],
        maskedPhone: this.maskedPhones[s],
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: this.sfaceArena128.subarray(
          offset,
          offset + SFACE_EMBEDDING_DIMENSION,
        ),
        isoQualityScore: this.qualityScores[s],
        padLivenessScore: this.padScores[s],
        enrolledAtEpochMs: this.enrolledTimestamps[s],
      });
    }
    nextIndex.upsertTemplate(record);
    return nextIndex;
  }

  /**
   * Produces a lock-free Copy-on-Write (CoW) snapshot with the specified UID removed.
   */
  public cloneWithoutUid(uidToRemove: string): HighSpeedBiometricIndexV3 {
    const nextIndex = new HighSpeedBiometricIndexV3(this.capacity, this.exactScanThreshold);
    for (let s = 0; s < this.count; s++) {
      if (this.uids[s] === uidToRemove) continue;
      const offset = s * SFACE_EMBEDDING_DIMENSION;
      nextIndex.upsertTemplate({
        uid: this.uids[s],
        maskedPhone: this.maskedPhones[s],
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: this.sfaceArena128.subarray(
          offset,
          offset + SFACE_EMBEDDING_DIMENSION,
        ),
        isoQualityScore: this.qualityScores[s],
        padLivenessScore: this.padScores[s],
        enrolledAtEpochMs: this.enrolledTimestamps[s],
      });
    }
    return nextIndex;
  }

  /**
   * Produces a single lock-free Copy-on-Write (CoW) snapshot applying an entire batch
   * of upserts and tombstones in one pass, eliminating O(N * L) repeated full arena copies.
   */
  public cloneWithBatchMutations(
    upserts: readonly EnrolledWorkerSfaceRecordV3[],
    tombstoneUids: ReadonlySet<string>,
  ): HighSpeedBiometricIndexV3 {
    const nextCap = Math.max(this.capacity, this.count + upserts.length + 1024);
    const nextIndex = new HighSpeedBiometricIndexV3(nextCap, this.exactScanThreshold);
    const upsertUids = new Set(upserts.map((u) => u.uid));

    // 1. Copy existing records that are neither replaced nor tombstoned
    for (let s = 0; s < this.count; s++) {
      const uid = this.uids[s];
      if (tombstoneUids.has(uid) || upsertUids.has(uid)) continue;
      const offset = s * SFACE_EMBEDDING_DIMENSION;
      nextIndex.upsertTemplate({
        uid,
        maskedPhone: this.maskedPhones[s],
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: this.sfaceArena128.subarray(
          offset,
          offset + SFACE_EMBEDDING_DIMENSION,
        ),
        isoQualityScore: this.qualityScores[s],
        padLivenessScore: this.padScores[s],
        enrolledAtEpochMs: this.enrolledTimestamps[s],
      });
    }

    // 2. Append new upserts in order (filtering out tombstoned uids)
    for (const rec of upserts) {
      if (tombstoneUids.has(rec.uid)) continue;
      nextIndex.upsertTemplate(rec);
    }

    return nextIndex;
  }

  /**
   * 4-way unrolled 128-D dot product over contiguous Float32Array.
   */
  private dot128(probe128: Float32Array, arenaOffset: number): number {
    let sum0 = 0.0;
    let sum1 = 0.0;
    let sum2 = 0.0;
    let sum3 = 0.0;
    const arena = this.sfaceArena128;

    for (let i = 0; i < 128; i += 4) {
      sum0 += probe128[i] * arena[arenaOffset + i];
      sum1 += probe128[i + 1] * arena[arenaOffset + i + 1];
      sum2 += probe128[i + 2] * arena[arenaOffset + i + 2];
      sum3 += probe128[i + 3] * arena[arenaOffset + i + 3];
    }
    return sum0 + sum1 + sum2 + sum3;
  }

  private buildSmallWorldLinksForSlot(slot: number, vec128: Float32Array): void {
    const maxLinks = 16;
    if (this.count <= 1) {
      this.adjacencyLinks[slot] = new Int32Array(0);
      return;
    }
    const sampleCount = Math.min(this.count - 1, 64);
    const scored: Array<{ peer: number; sim: number }> = [];
    for (let s = 0; s < sampleCount; s++) {
      const peer = (slot * 31 + s * 17) % (this.count - 1);
      if (peer === slot) continue;
      scored.push({
        peer,
        sim: this.dot128(vec128, peer * SFACE_EMBEDDING_DIMENSION),
      });
    }
    scored.sort((a, b) => b.sim - a.sim);
    const top = scored.slice(0, maxLinks).map((x) => x.peer);
    this.adjacencyLinks[slot] = Int32Array.from(top);

    // Bidirectional back-link injection to maintain graph connectivity
    for (const peer of top) {
      const existing = this.adjacencyLinks[peer];
      if (existing && existing.length < maxLinks && !existing.includes(slot)) {
        const nextLinks = new Int32Array(existing.length + 1);
        nextLinks.set(existing);
        nextLinks[existing.length] = slot;
        this.adjacencyLinks[peer] = nextLinks;
      }
    }
  }

  private searchSmallWorldCandidates(
    probe128: Float32Array,
    efSearch: number,
  ): Int32Array {
    const visited = new Set<number>();
    const frontier: number[] = [];

    // Multi-entrypoint seeding across the arena
    const entryPoints = Math.min(this.count, 8);
    const stride = Math.max(1, Math.floor(this.count / entryPoints));
    for (let e = 0; e < this.count && visited.size < entryPoints; e += stride) {
      visited.add(e);
      frontier.push(e);
    }

    while (frontier.length > 0 && visited.size < efSearch) {
      const current = frontier.shift()!;
      const neighbors = this.adjacencyLinks[current];
      if (!neighbors) continue;
      for (let i = 0; i < neighbors.length; i++) {
        const next = neighbors[i];
        if (!visited.has(next)) {
          visited.add(next);
          frontier.push(next);
          if (visited.size >= efSearch) break;
        }
      }
    }
    return Int32Array.from(visited);
  }
}

