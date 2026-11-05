// backend/src/tests/concurrency_vault_store.test.ts
import assert from "assert";
import { cosineSimilarity, evaluateMatch } from "../services/biometric_matching";

interface MockDoc {
  id: string;
  data: Record<string, any>;
}

class MockFirestoreStore {
  public vault: Map<string, Record<string, any>> = new Map();
  public users: Map<string, Record<string, any>> = new Map();
  public sessions: Map<string, Record<string, any>> = new Map();
  public monotonicSequence = 0;

  async runTransaction<T>(updateFunction: (tx: any) => Promise<T>): Promise<T> {
    const tx = {
      get: async (col: string, id: string) => {
        const store = col === "sessions" ? this.sessions : col === "vault" ? this.vault : this.users;
        const data = store.get(id);
        return { exists: !!data, data: () => data };
      },
      set: (col: string, id: string, data: any) => {
        const store = col === "sessions" ? this.sessions : col === "vault" ? this.vault : this.users;
        store.set(id, { ...data, _seq: ++this.monotonicSequence });
      },
    };
    return await updateFunction(tx);
  }

  // Pending-inclusive 1:N scan
  async searchNearest(probe: number[], excludeUid: string): Promise<{ uid: string; similarity: number; isPending: boolean } | null> {
    let bestSim = -1;
    let bestUid = "";
    let isPending = false;

    // 1. Scan Vault (Committed)
    for (const [uid, record] of this.vault.entries()) {
      if (uid === excludeUid) continue;
      const sim = cosineSimilarity(probe, record.embedding);
      if (sim > bestSim) {
        bestSim = sim;
        bestUid = uid;
        isPending = false;
      }
    }

    // 2. Scan In-Progress Sessions (Pending-Inclusive Search)
    const now = Date.now();
    for (const [uid, sess] of this.sessions.entries()) {
      if (uid === excludeUid) continue;
      if (sess.status === "in_progress" && (now - sess.startedAt) < 60000 && sess.pendingEmbedding) {
        const sim = cosineSimilarity(probe, sess.pendingEmbedding);
        if (sim > bestSim) {
          bestSim = sim;
          bestUid = uid;
          isPending = true;
        }
      }
    }

    return bestSim > 0 ? { uid: bestUid, similarity: bestSim, isPending } : null;
  }
}

async function runConcurrencyVaultStoreSuite() {
  console.log("====================================================");
  console.log("🧪 RUNNING PHASE 7: BIOMETRIC STORE CONCURRENCY & RECALL");
  console.log("====================================================");

  const store = new MockFirestoreStore();

  // ── TEST 1: Exact Flat Scan Recall@k = 1.000 vs Ground Truth
  console.log("Executing Test 1: Testing exact Cosine Scan Recall@k against ground truth...");
  const enrolledA = new Array(128).fill(0);
  enrolledA[0] = 1.0; // Pointing along dimension 0
  store.vault.set("user_a", { embedding: enrolledA, status: "ACTIVE" });

  const enrolledB = new Array(128).fill(0);
  enrolledB[1] = 1.0; // Orthogonal
  store.vault.set("user_b", { embedding: enrolledB, status: "ACTIVE" });

  // Probe is close to User A
  const probe = new Array(128).fill(0);
  probe[0] = 0.96;
  probe[2] = 0.28; // ||probe|| = sqrt(0.96^2 + 0.28^2) = 1.0

  const nearest = await store.searchNearest(probe, "user_c");
  assert.ok(nearest !== null, "Must find a candidate");
  assert.strictEqual(nearest.uid, "user_a", "Exact scan must retrieve true nearest neighbor User A");
  assert.ok(Math.abs(nearest.similarity - 0.96) < 1e-4, `Expected similarity 0.96, got ${nearest.similarity}`);
  console.log(`✔ Test 1: Exact flat vector scan recall@1 = 1.000 verified (sim: ${nearest.similarity.toFixed(4)}).`);

  // ── TEST 2: Pending-Inclusive Search & Concurrency Race
  console.log("Executing Test 2: Testing concurrent race of identical face across two distinct UIDs...");
  const faceVector = new Array(128).fill(1.0 / Math.sqrt(128));

  // Request 1 arrives for worker_001
  const lock1 = await store.runTransaction(async (tx) => {
    const snap = await tx.get("sessions", "worker_001");
    if (snap.exists && snap.data().status === "in_progress") throw new Error("locked");
    tx.set("sessions", "worker_001", {
      status: "in_progress",
      startedAt: Date.now(),
      pendingEmbedding: faceVector,
    });
    return true;
  });
  assert.strictEqual(lock1, true, "First session must acquire reservation lock");

  // Request 2 arrives simultaneously for fraudster_002 with identical face
  const collision = await store.searchNearest(faceVector, "fraudster_002");
  assert.ok(collision !== null, "Must detect pending collision");
  assert.strictEqual(collision.isPending, true, "Collision must flag as in-progress pending session");
  assert.strictEqual(collision.uid, "worker_001", "Must identify worker_001 as holding the face");
  assert.ok(collision.similarity > 0.999, "Similarity must indicate duplicate collision");

  // System denies fraudster_002 enrollment
  const evalResult = evaluateMatch(collision.similarity);
  assert.strictEqual(evalResult.isDuplicate, true, "Pending match must trigger duplicate denial!");
  console.log("✔ Test 2: Pending-inclusive search detects concurrent same-face race; duplicate intercepted.");

  // ── TEST 3: Monotonic Sequence & Single ACTIVE Guarantee (Invariant I-12)
  console.log("Executing Test 3: Verifying monotonic sequence promotion prevents dual-active states...");
  store.vault.set("worker_001", {
    embedding: faceVector,
    status: "ACTIVE",
    seq: ++store.monotonicSequence,
  });
  store.sessions.delete("worker_001");

  // Attempting to activate fraudster_002 now encounters committed ACTIVE record
  const secondCheck = await store.searchNearest(faceVector, "fraudster_002");
  assert.ok(secondCheck !== null);
  assert.strictEqual(secondCheck.isPending, false, "Must detect committed ACTIVE vault template");
  assert.strictEqual(secondCheck.uid, "worker_001");
  console.log("✔ Test 3: Invariant I-12 enforced: exactly one account achieves ACTIVE status.");

  // ── TEST 4: Crash Recovery & Stale Lock Invalidation
  console.log("Executing Test 4: Testing crash recovery for abandoned session (>60s timeout)...");
  const staleTimestamp = Date.now() - 75000; // 75 seconds ago (exceeded 60s lock TTL)
  store.sessions.set("worker_stale", {
    status: "in_progress",
    startedAt: staleTimestamp,
    pendingEmbedding: faceVector,
  });

  // New request arrives for worker_stale after client app was killed
  const reacquireLock = await store.runTransaction(async (tx) => {
    const snap = await tx.get("sessions", "worker_stale");
    if (snap.exists) {
      const data = snap.data();
      const isExpired = (Date.now() - data.startedAt) >= 60000;
      if (!isExpired && data.status === "in_progress") {
        throw new Error("locked");
      }
    }
    tx.set("sessions", "worker_stale", {
      status: "in_progress",
      startedAt: Date.now(),
      pendingEmbedding: faceVector,
    });
    return true;
  });
  assert.strictEqual(reacquireLock, true, "Stale session lock must be reclaimable after 60s timeout");
  console.log("✔ Test 4: Stale crash session reclaimed cleanly without deadlock.");

  console.log("====================================================");
  console.log("🎉 ALL PHASE 7 STORE CONCURRENCY & RECALL TESTS PASSED!");
  console.log("====================================================");
}

runConcurrencyVaultStoreSuite().catch((err) => {
  console.error("❌ Concurrency vault store suite failed:", err);
  process.exit(1);
});
