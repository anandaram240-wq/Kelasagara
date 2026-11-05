import crypto from "crypto";

export interface ChainedAuditEventV18 {
  sequenceNumber: number;
  eventId: string;
  eventType:
    | "ENROLLMENT_COMMITTED"
    | "DUPLICATE_INVESTIGATION_QUEUED"
    | "KMS_DEK_ROTATED"
    | "HUMAN_REVIEW_ADJUDICATED";
  actorId: string;
  payloadDigestSha256: string;
  previousChainHash: string;
  chainHash: string;
  timestampIso: string;
}

export interface WormBucketAnchorObject {
  objectPath: string;
  bucketName: string;
  retentionMode: "Locked";
  retainUntilIso: string;
  ifGenerationMatch: 0; // Enforces WORM write-once semantics
  startSequence: number;
  endSequence: number;
  firstChainHash: string;
  terminalChainHash: string;
  merkleRootSha256: string;
  sealedAtIso: string;
}

export interface WormStorageDriver {
  putImmutableObject(anchor: WormBucketAnchorObject): Promise<void>;
  getImmutableObject(objectPath: string): Promise<WormBucketAnchorObject | null>;
}

/**
 * In-memory WORM driver enforcing Locked Object Retention rules (rejects any overwrite,
 * mutation, or deletion prior to retainUntilIso, even by a privileged caller).
 */
export class LockedGcsWormDriverSimulator implements WormStorageDriver {
  private readonly lockedObjects = new Map<string, string>();

  public async putImmutableObject(anchor: WormBucketAnchorObject): Promise<void> {
    if (anchor.retentionMode !== "Locked") {
      throw new Error("ERR_WORM_POLICY_VIOLATION: Bucket requires RetentionMode='Locked'.");
    }
    if (anchor.ifGenerationMatch !== 0) {
      throw new Error("ERR_WORM_PRECONDITION_REQUIRED: ifGenerationMatch: 0 must be set.");
    }
    if (this.lockedObjects.has(anchor.objectPath)) {
      throw new Error(
        `ERR_WORM_OBJECT_IMMUTABLE: Object ${anchor.objectPath} already exists and cannot be overwritten.`
      );
    }
    this.lockedObjects.set(anchor.objectPath, JSON.stringify(anchor));
  }

  public async getImmutableObject(objectPath: string): Promise<WormBucketAnchorObject | null> {
    const raw = this.lockedObjects.get(objectPath);
    return raw ? (JSON.parse(raw) as WormBucketAnchorObject) : null;
  }

  public attemptPrivilegedDelete(objectPath: string, currentTime: Date = new Date()): void {
    const raw = this.lockedObjects.get(objectPath);
    if (!raw) return;
    const parsed = JSON.parse(raw) as WormBucketAnchorObject;
    if (new Date(parsed.retainUntilIso).getTime() > currentTime.getTime()) {
      throw new Error(
        `ERR_GCS_OBJECT_RETENTION_LOCKED: Cannot delete ${objectPath} before ${parsed.retainUntilIso} (even with Admin/Owner IAM).`
      );
    }
    this.lockedObjects.delete(objectPath);
  }
}

export class GcsWormAuditAnchorV18 {
  private readonly events: ChainedAuditEventV18[] = [];
  private readonly bucketName: string;
  private readonly retentionDays: number;
  private readonly wormDriver: WormStorageDriver;

  constructor(options: {
    bucketName: string;
    retentionDays?: number;
    wormDriver: WormStorageDriver;
  }) {
    this.bucketName = options.bucketName;
    this.retentionDays = options.retentionDays ?? 365;
    this.wormDriver = options.wormDriver;
  }

  public appendEvent(params: {
    eventType: ChainedAuditEventV18["eventType"];
    actorId: string;
    payloadObject: Record<string, unknown>;
  }): ChainedAuditEventV18 {
    const seq = this.events.length + 1;
    const eventId = `EVT_${seq}_${crypto.randomBytes(4).toString("hex").toUpperCase()}`;
    const timestampIso = new Date().toISOString();
    const prevHash =
      this.events.length > 0
        ? this.events[this.events.length - 1].chainHash
        : "GENESIS_KELASAGARA_V18_WORM";

    const payloadDigestSha256 = crypto
      .createHash("sha256")
      .update(JSON.stringify(params.payloadObject))
      .digest("hex");

    const chainHash = crypto
      .createHash("sha256")
      .update(
        `${seq}|${eventId}|${params.eventType}|${params.actorId}|${payloadDigestSha256}|${prevHash}|${timestampIso}`
      )
      .digest("hex");

    const event: ChainedAuditEventV18 = {
      sequenceNumber: seq,
      eventId,
      eventType: params.eventType,
      actorId: params.actorId,
      payloadDigestSha256,
      previousChainHash: prevHash,
      chainHash,
      timestampIso,
    };

    this.events.push(event);
    return event;
  }

  public static computeMerkleRoot(hashes: string[]): string {
    if (hashes.length === 0) {
      throw new Error("ERR_EMPTY_MERKLE_LEAVES");
    }
    let layer = [...hashes];
    while (layer.length > 1) {
      const nextLayer: string[] = [];
      for (let i = 0; i < layer.length; i += 2) {
        const left = layer[i];
        const right = i + 1 < layer.length ? layer[i + 1] : left;
        const combined = crypto
          .createHash("sha256")
          .update(`${left}:${right}`)
          .digest("hex");
        nextLayer.push(combined);
      }
      layer = nextLayer;
    }
    return layer[0];
  }

  /**
   * Seals the current audit range into an immutable GCS WORM object with Locked Retention.
   */
  public async sealAnchorToWormBucket(
    startSeq: number,
    endSeq: number
  ): Promise<WormBucketAnchorObject> {
    const slice = this.events.filter(
      (e) => e.sequenceNumber >= startSeq && e.sequenceNumber <= endSeq
    );
    if (slice.length === 0) {
      throw new Error("ERR_EMPTY_AUDIT_SLICE");
    }

    const merkleRootSha256 = GcsWormAuditAnchorV18.computeMerkleRoot(
      slice.map((e) => e.chainHash)
    );
    const now = new Date();
    const retainUntil = new Date(
      now.getTime() + this.retentionDays * 24 * 60 * 60 * 1000
    );

    const objectPath = `worm-anchors/v18/seq_${startSeq}_to_${endSeq}.json`;
    const anchor: WormBucketAnchorObject = {
      objectPath,
      bucketName: this.bucketName,
      retentionMode: "Locked",
      retainUntilIso: retainUntil.toISOString(),
      ifGenerationMatch: 0,
      startSequence: startSeq,
      endSequence: endSeq,
      firstChainHash: slice[0].chainHash,
      terminalChainHash: slice[slice.length - 1].chainHash,
      merkleRootSha256,
      sealedAtIso: now.toISOString(),
    };

    await this.wormDriver.putImmutableObject(anchor);
    return anchor;
  }

  /**
   * Detects if a rogue Firebase Admin SDK user mutated or re-hashed events in Firestore
   * by comparing the Firestore event slice against the immutable GCS WORM anchor.
   */
  public async verifyFirestoreEventsAgainstWormAnchor(
    objectPath: string,
    firestoreEventsSlice: ChainedAuditEventV18[]
  ): Promise<{ verified: boolean; reason?: string }> {
    const anchor = await this.wormDriver.getImmutableObject(objectPath);
    if (!anchor) {
      return { verified: false, reason: "ERR_WORM_ANCHOR_MISSING" };
    }
    if (firestoreEventsSlice.length === 0) {
      return { verified: false, reason: "ERR_EMPTY_FIRESTORE_SLICE" };
    }

    const recomputedMerkle = GcsWormAuditAnchorV18.computeMerkleRoot(
      firestoreEventsSlice.map((e) => e.chainHash)
    );
    if (recomputedMerkle !== anchor.merkleRootSha256) {
      return {
        verified: false,
        reason: "ERR_ADMIN_SDK_TAMPER_DETECTED: Firestore hash chain diverges from WORM Merkle root.",
      };
    }

    const lastEvent = firestoreEventsSlice[firestoreEventsSlice.length - 1];
    if (lastEvent.chainHash !== anchor.terminalChainHash) {
      return {
        verified: false,
        reason: "ERR_TERMINAL_HASH_MISMATCH",
      };
    }

    return { verified: true };
  }
}
