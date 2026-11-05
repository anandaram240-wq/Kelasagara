/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.2
 * File: backend/src/biometrics/hnsw_cluster_sync_v12.ts
 *
 * Sub-200ms Signed Binary HNSW Snapshot Serialization (`KS12` Format)
 * and Incremental Write-Ahead Log (WAL) Multi-Node Cluster Synchronization.
 */

import crypto from 'node:crypto';

export type WalOperationTypeV12 = 'UPSERT_NODE' | 'ROTATE_KEY_METADATA' | 'TOMBSTONE_NODE';

export interface HnswGraphNodeV12 {
  readonly uid: string;
  readonly faceId: string;
  readonly keyId: string;
  readonly modelVersion: 'v10_sface_128' | 'v11_adaface_512';
  readonly lockToken: string;
  readonly embedding: Float32Array;
  readonly neighborsByLayer: ReadonlyArray<readonly string[]>; // Layer 0..L neighbor UIDs
  readonly updatedAtMs: number;
}

export interface HnswWalEntryV12 {
  readonly walSeq: number; // Strictly monotonic integer sequence
  readonly opType: WalOperationTypeV12;
  readonly uid: string;
  readonly timestampMs: number;
  readonly nodePayload?: HnswGraphNodeV12;
  readonly rotatedKeyMetadata?: {
    readonly keyId: string;
    readonly lockToken: string;
    readonly updatedAtMs: number;
  };
}

export interface SnapshotHydrationTelemetryV12 {
  readonly restoredNodeCount: number;
  readonly watermarkWalSeq: number;
  readonly watermarkTimestampMs: number;
  readonly hydrationLatencyMs: number;
  readonly snapshotBytes: number;
}

export interface IncrementalSyncTelemetryV12 {
  readonly previousWalSeq: number;
  readonly currentWalSeq: number;
  readonly appliedEntries: number;
  readonly upsertedNodes: number;
  readonly rotatedMetadataNodes: number;
  readonly tombstonedNodes: number;
  readonly syncLatencyMs: number;
}

const SNAPSHOT_MAGIC = 'KS12';
const SNAPSHOT_FORMAT_VERSION = 1;
const HMAC_SIGNATURE_BYTES = 32;

/**
 * Coordinates sub-200ms binary snapshot serialization/hydration and incremental WAL
 * delta synchronization across horizontally scaled Kelasagara backend nodes.
 */
export class HnswClusterSyncCoordinatorV12 {
  private readonly nodes = new Map<string, HnswGraphNodeV12>();
  private watermarkWalSeq = 0;
  private watermarkTimestampMs = 0;
  private readonly maxConnectionsPerLayer: number;

  constructor(
    private readonly snapshotSigningSecret: Buffer,
    options: { maxConnectionsPerLayer?: number } = {}
  ) {
    if (snapshotSigningSecret.byteLength < 32) {
      throw new Error('BIOMETRIC_V12_SNAPSHOT_SECRET_TOO_SHORT: Requires at least 32 bytes');
    }
    this.maxConnectionsPerLayer = options.maxConnectionsPerLayer ?? 16;
  }

  public getNodeCount(): number {
    return this.nodes.size;
  }

  public getWatermarkWalSeq(): number {
    return this.watermarkWalSeq;
  }

  public getNode(uid: string): HnswGraphNodeV12 | undefined {
    return this.nodes.get(uid);
  }

  /**
   * Computes cosine similarity between two unit-normalized vectors.
   */
  private cosineSimilarity(a: Float32Array, b: Float32Array): number {
    if (a.length !== b.length) return -1;
    let dot = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /**
   * Inserts or updates a node in the in-memory HNSW graph and wires bidirectional edges.
   */
  public upsertNodeLocal(node: HnswGraphNodeV12): void {
    const existingUids: string[] = [];
    for (const [candidateUid, candidateNode] of this.nodes.entries()) {
      if (candidateUid !== node.uid && candidateNode.embedding.length === node.embedding.length) {
        existingUids.push(candidateUid);
      }
    }

    // Score top-M nearest neighbors for Layer 0
    const scored = existingUids
      .map((candidateUid) => {
        const candidate = this.nodes.get(candidateUid)!;
        return {
          uid: candidateUid,
          sim: this.cosineSimilarity(node.embedding, candidate.embedding),
        };
      })
      .sort((a, b) => b.sim - a.sim)
      .slice(0, this.maxConnectionsPerLayer);

    const layer0Neighbors = scored.map((s) => s.uid);
    const layers =
      node.neighborsByLayer.length > 0 ? node.neighborsByLayer : [layer0Neighbors];

    this.nodes.set(node.uid, {
      ...node,
      neighborsByLayer: layers,
    });

    // Maintain bidirectional Layer-0 links for fast greedy graph traversal
    for (const neighborUid of layer0Neighbors) {
      const neighbor = this.nodes.get(neighborUid);
      if (!neighbor) continue;
      const neighborL0 = neighbor.neighborsByLayer[0] ?? [];
      if (!neighborL0.includes(node.uid)) {
        const updatedL0 = [node.uid, ...neighborL0].slice(0, this.maxConnectionsPerLayer);
        this.nodes.set(neighborUid, {
          ...neighbor,
          neighborsByLayer: [updatedL0, ...neighbor.neighborsByLayer.slice(1)],
        });
      }
    }
  }

  /**
   * Sub-linear HNSW greedy graph traversal for 1:N duplicate detection.
   * Automatically skips `excludeUid` during `AUTHORIZED_RE_REGISTRATION`.
   */
  public searchNearestDuplicate(
    queryEmbedding: Float32Array,
    excludeUid?: string
  ): { bestUid: string | null; bestSimilarity: number; visitedCount: number } {
    if (this.nodes.size === 0) {
      return { bestUid: null, bestSimilarity: -1, visitedCount: 0 };
    }

    const visited = new Set<string>();
    let currentUid: string | null = null;
    let currentBestSim = -2.0;

    // Pick entry point
    for (const [uid, node] of this.nodes.entries()) {
      if (uid === excludeUid || node.embedding.length !== queryEmbedding.length) continue;
      currentUid = uid;
      currentBestSim = this.cosineSimilarity(queryEmbedding, node.embedding);
      visited.add(uid);
      break;
    }

    if (!currentUid) {
      return { bestUid: null, bestSimilarity: -1, visitedCount: 0 };
    }

    // Greedy walk across Layer 0 neighborhood with frontier expansion
    const candidateQueue: string[] = [currentUid];
    while (candidateQueue.length > 0) {
      const pivotUid = candidateQueue.shift()!;
      const pivotNode = this.nodes.get(pivotUid);
      if (!pivotNode) continue;

      const neighbors = pivotNode.neighborsByLayer[0] ?? [];
      for (const nUid of neighbors) {
        if (visited.has(nUid)) continue;
        visited.add(nUid);

        const nNode = this.nodes.get(nUid);
        if (!nNode || nNode.embedding.length !== queryEmbedding.length) continue;

        const sim = this.cosineSimilarity(queryEmbedding, nNode.embedding);
        if (nUid !== excludeUid && sim > currentBestSim) {
          currentBestSim = sim;
          currentUid = nUid;
          candidateQueue.push(nUid);
        }
      }
    }

    return {
      bestUid: currentUid === excludeUid ? null : currentUid,
      bestSimilarity: Number(currentBestSim.toFixed(6)),
      visitedCount: visited.size,
    };
  }

  /**
   * Serializes the entire HNSW index into a compact, HMAC-SHA256 signed `KS12` binary buffer.
   *
   * Binary Layout:
   * - [0..3]   Magic "KS12" (4 bytes)
   * - [4..5]   Format Version uint16BE (2 bytes)
   * - [6..9]   Node Count uint32BE (4 bytes)
   * - [10..17] Watermark WAL Sequence BigUInt64BE (8 bytes)
   * - [18..25] Watermark Timestamp ms BigUInt64BE (8 bytes)
   * - [26..N]  Packed Node Records (Metadata JSON length + Metadata UTF8 + Raw Float32Array bytes)
   * - [Last 32 bytes] HMAC-SHA256 Integrity Signature over all preceding bytes
   */
  public exportSignedBinarySnapshot(): Buffer {
    const chunks: Buffer[] = [];
    const header = Buffer.alloc(26);

    header.write(SNAPSHOT_MAGIC, 0, 4, 'ascii');
    header.writeUInt16BE(SNAPSHOT_FORMAT_VERSION, 4);
    header.writeUInt32BE(this.nodes.size, 6);
    header.writeBigUInt64BE(BigInt(this.watermarkWalSeq), 10);
    header.writeBigUInt64BE(BigInt(this.watermarkTimestampMs), 18);
    chunks.push(header);

    for (const node of this.nodes.values()) {
      const metaJson = JSON.stringify({
        u: node.uid,
        f: node.faceId,
        k: node.keyId,
        m: node.modelVersion,
        l: node.lockToken,
        n: node.neighborsByLayer,
        t: node.updatedAtMs,
        d: node.embedding.length,
      });
      const metaBytes = Buffer.from(metaJson, 'utf8');
      const embeddingBytes = Buffer.from(
        node.embedding.buffer,
        node.embedding.byteOffset,
        node.embedding.byteLength
      );

      const recordHeader = Buffer.alloc(8);
      recordHeader.writeUInt32BE(metaBytes.byteLength, 0);
      recordHeader.writeUInt32BE(embeddingBytes.byteLength, 4);

      chunks.push(recordHeader, metaBytes, embeddingBytes);
    }

    const payloadBuffer = Buffer.concat(chunks);
    const signature = crypto
      .createHmac('sha256', this.snapshotSigningSecret)
      .update(payloadBuffer)
      .digest();

    return Buffer.concat([payloadBuffer, signature]);
  }

  /**
   * Verifies the HMAC-SHA256 signature and hydrates the HNSW index in sub-200ms.
   */
  public hydrateFromBinarySnapshot(snapshotBuffer: Buffer): SnapshotHydrationTelemetryV12 {
    const start = performance.now();

    if (snapshotBuffer.byteLength < 26 + HMAC_SIGNATURE_BYTES) {
      throw new Error('BIOMETRIC_V12_SNAPSHOT_CORRUPTED: Buffer smaller than header + signature');
    }

    const payloadEnd = snapshotBuffer.byteLength - HMAC_SIGNATURE_BYTES;
    const payloadSlice = snapshotBuffer.subarray(0, payloadEnd);
    const providedSignature = snapshotBuffer.subarray(payloadEnd);

    const expectedSignature = crypto
      .createHmac('sha256', this.snapshotSigningSecret)
      .update(payloadSlice)
      .digest();

    if (!crypto.timingSafeEqual(providedSignature, expectedSignature)) {
      throw new Error('BIOMETRIC_V12_SNAPSHOT_SIGNATURE_MISMATCH: Tampered or untrusted snapshot');
    }

    const magic = payloadSlice.toString('ascii', 0, 4);
    if (magic !== SNAPSHOT_MAGIC) {
      throw new Error(`BIOMETRIC_V12_SNAPSHOT_INVALID_MAGIC:${magic}`);
    }

    const version = payloadSlice.readUInt16BE(4);
    if (version !== SNAPSHOT_FORMAT_VERSION) {
      throw new Error(`BIOMETRIC_V12_SNAPSHOT_UNSUPPORTED_VERSION:${version}`);
    }

    const nodeCount = payloadSlice.readUInt32BE(6);
    const watermarkWalSeq = Number(payloadSlice.readBigUInt64BE(10));
    const watermarkTimestampMs = Number(payloadSlice.readBigUInt64BE(18));

    this.nodes.clear();
    let offset = 26;

    for (let i = 0; i < nodeCount; i++) {
      const metaByteLen = payloadSlice.readUInt32BE(offset);
      const embByteLen = payloadSlice.readUInt32BE(offset + 4);
      offset += 8;

      const metaJson = payloadSlice.toString('utf8', offset, offset + metaByteLen);
      offset += metaByteLen;

      const meta = JSON.parse(metaJson) as {
        u: string;
        f: string;
        k: string;
        m: 'v10_sface_128' | 'v11_adaface_512';
        l: string;
        n: string[][];
        t: number;
        d: number;
      };

      const rawEmbSlice = payloadSlice.subarray(offset, offset + embByteLen);
      offset += embByteLen;

      const alignedEmbBytes = new Uint8Array(embByteLen);
      alignedEmbBytes.set(rawEmbSlice);
      const embedding = new Float32Array(alignedEmbBytes.buffer, 0, meta.d);

      this.nodes.set(meta.u, {
        uid: meta.u,
        faceId: meta.f,
        keyId: meta.k,
        modelVersion: meta.m,
        lockToken: meta.l,
        embedding,
        neighborsByLayer: meta.n,
        updatedAtMs: meta.t,
      });
    }

    this.watermarkWalSeq = watermarkWalSeq;
    this.watermarkTimestampMs = watermarkTimestampMs;

    return {
      restoredNodeCount: this.nodes.size,
      watermarkWalSeq,
      watermarkTimestampMs,
      hydrationLatencyMs: Number((performance.now() - start).toFixed(3)),
      snapshotBytes: snapshotBuffer.byteLength,
    };
  }

  /**
   * Applies incremental Write-Ahead Log (WAL) entries with `walSeq > watermarkWalSeq`.
   * Guarantees idempotency if duplicate or already-applied WAL sequences arrive over pub/sub.
   */
  public applyIncrementalWalDelta(
    entries: readonly HnswWalEntryV12[]
  ): IncrementalSyncTelemetryV12 {
    const start = performance.now();
    const previousWalSeq = this.watermarkWalSeq;

    const sorted = [...entries].sort((a, b) => a.walSeq - b.walSeq);

    let appliedEntries = 0;
    let upsertedNodes = 0;
    let rotatedMetadataNodes = 0;
    let tombstonedNodes = 0;

    for (const entry of sorted) {
      if (entry.walSeq <= this.watermarkWalSeq) {
        continue; // Idempotent skip for already-applied WAL entries
      }

      if (entry.opType === 'UPSERT_NODE' && entry.nodePayload) {
        this.upsertNodeLocal(entry.nodePayload);
        upsertedNodes++;
      } else if (entry.opType === 'ROTATE_KEY_METADATA' && entry.rotatedKeyMetadata) {
        const existing = this.nodes.get(entry.uid);
        if (existing) {
          this.nodes.set(entry.uid, {
            ...existing,
            keyId: entry.rotatedKeyMetadata.keyId,
            lockToken: entry.rotatedKeyMetadata.lockToken,
            updatedAtMs: entry.rotatedKeyMetadata.updatedAtMs,
          });
          rotatedMetadataNodes++;
        }
      } else if (entry.opType === 'TOMBSTONE_NODE') {
        if (this.nodes.delete(entry.uid)) {
          tombstonedNodes++;
        }
      }

      this.watermarkWalSeq = entry.walSeq;
      if (entry.timestampMs > this.watermarkTimestampMs) {
        this.watermarkTimestampMs = entry.timestampMs;
      }
      appliedEntries++;
    }

    return {
      previousWalSeq,
      currentWalSeq: this.watermarkWalSeq,
      appliedEntries,
      upsertedNodes,
      rotatedMetadataNodes,
      tombstonedNodes,
      syncLatencyMs: Number((performance.now() - start).toFixed(3)),
    };
  }
}

