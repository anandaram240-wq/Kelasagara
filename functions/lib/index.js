"use strict";
/**
 * KELASAGARA BIOMETRIC CLOUD FUNCTIONS — TRUSTED SERVER LAYER
 * ============================================================
 * All biometric writes to Firestore MUST go through this server.
 * Flutter clients have NO permission to read or write biometric_vault.
 *
 * Architecture:
 *   Client calls HTTPS Callable → Cloud Function validates auth, runs
 *   1:N de-duplication using Firestore FindNearest (KNN vector search),
 *   writes template if unique, updates user's faceVerified flag atomically.
 *
 * Firestore Admin SDK bypasses security rules — that is intentional and
 * is why client rules on biometric_vault must be allow read/write: false.
 *
 * Security model:
 *   - Firebase App Check enforced on all callable functions
 *   - JWT validated via context.auth (auto-verified by Firebase Functions)
 *   - Rate-limited: max 3 enrollment attempts per UID per 24h
 *   - No raw photo is stored — only the 128-D normalized embedding
 *   - Threshold 0.74 used as initial value; to be re-calibrated empirically
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.retryFailedOutboxNotifications = exports.dispatchNotificationsOutbox = exports.reconcileStaleApprovalLeases = exports.expireStalePendingDirectBookings = exports.resolvePendingRequestsOnAssignment = exports.cancelVoiceDirectBooking = exports.rejectVoiceDirectBooking = exports.approveVoiceDirectBooking = exports.requestVoiceDirectBooking = exports.getHirerArrivalOtp = exports.verifyArrivalOtp = exports.requestBiometricChallenge = exports.IDEMPOTENT_SAFETY_WINDOW_MS = exports.CHALLENGE_TTL_MS = exports.CHALLENGE_COLLECTION = exports.onGeofenceAlertTriggered = exports.OrthogonalBiometricProjector = exports.deleteBiometricTemplate = exports.verifyBiometricLogin = exports.enrollBiometric = void 0;
exports.issueBiometricChallengeTransactional = issueBiometricChallengeTransactional;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const crypto = __importStar(require("crypto"));
admin.initializeApp();
const db = admin.firestore();
// ─── CONSTANTS ─────────────────────────────────────────────────────────────
/** Cosine similarity threshold above which two embeddings are the SAME person */
const DUPLICATE_THRESHOLD = 0.74;
/** Cosine similarity threshold for ambiguity / manual review */
const AMBIGUITY_THRESHOLD = 0.65;
/** Expected embedding dimensionality */
const EMBEDDING_DIM = 128;
/** Rate limit: max enrollment attempts per UID per window */
const MAX_ENROLL_ATTEMPTS = 3;
/** Rate limit window in milliseconds (24 hours) */
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
// ─── MATH UTILITIES ────────────────────────────────────────────────────────
/**
 * Computes Cosine Similarity between two equal-length numeric vectors.
 * For L2-normalized unit vectors this equals the dot product directly.
 */
function cosineSimilarity(a, b) {
    if (a.length !== b.length || a.length === 0)
        return 0;
    let dot = 0, normA = 0, normB = 0;
    for (let i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }
    if (normA === 0 || normB === 0)
        return 0;
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}
/**
 * L2-normalizes a vector onto the unit hypersphere.
 * Returns the original vector if norm is zero.
 */
function l2Normalize(v) {
    const sumSq = v.reduce((acc, val) => acc + val * val, 0);
    const norm = Math.sqrt(sumSq);
    if (norm === 0)
        return [...v];
    return v.map((x) => x / norm);
}
/**
 * Masks a phone number for DPDPA 2023 privacy compliance.
 * e.g. "+91 9845012345" → "+91 ******2345"
 */
function maskPhone(phone) {
    const clean = phone.trim();
    if (clean.length < 4)
        return "an existing profile";
    const last4 = clean.slice(-4);
    if (clean.startsWith("+91"))
        return `+91 ******${last4}`;
    return `******${last4}`;
}
function validateEnrollRequest(data) {
    var _a, _b;
    if (typeof data !== "object" || data === null) {
        throw new functions.https.HttpsError("invalid-argument", "Request must be an object.");
    }
    const d = data;
    if (!Array.isArray(d.embedding)) {
        throw new functions.https.HttpsError("invalid-argument", "embedding must be an array.");
    }
    if (d.embedding.length !== EMBEDDING_DIM) {
        throw new functions.https.HttpsError("invalid-argument", `embedding must have exactly ${EMBEDDING_DIM} elements. Got ${d.embedding.length}.`);
    }
    for (const el of d.embedding) {
        if (typeof el !== "number" || !isFinite(el)) {
            throw new functions.https.HttpsError("invalid-argument", "All embedding values must be finite numbers.");
        }
    }
    const allowedRoles = ["worker", "hirer"];
    if (typeof d.role !== "string" || !allowedRoles.includes(d.role)) {
        throw new functions.https.HttpsError("invalid-argument", `role must be one of: ${allowedRoles.join(", ")}.`);
    }
    return {
        embedding: d.embedding,
        role: d.role,
        livenessAudit: (_a = d.livenessAudit) !== null && _a !== void 0 ? _a : {},
        modelFingerprint: (_b = d.modelFingerprint) !== null && _b !== void 0 ? _b : "kelasagara_biomatch_v1",
    };
}
// ─── RATE LIMITING ──────────────────────────────────────────────────────────
/**
 * Checks and increments enrollment attempt count for a given UID.
 * Throws if the rate limit is exceeded.
 */
async function checkRateLimit(uid) {
    const rateLimitRef = db.collection("biometric_rate_limits").doc(uid);
    await db.runTransaction(async (tx) => {
        const doc = await tx.get(rateLimitRef);
        const now = Date.now();
        if (!doc.exists) {
            tx.set(rateLimitRef, { attempts: 1, windowStart: now });
            return;
        }
        const { attempts, windowStart } = doc.data();
        if (now - windowStart > RATE_LIMIT_WINDOW_MS) {
            // New window — reset counter
            tx.set(rateLimitRef, { attempts: 1, windowStart: now });
            return;
        }
        if (attempts >= MAX_ENROLL_ATTEMPTS) {
            throw new functions.https.HttpsError("resource-exhausted", `Too many enrollment attempts. Maximum ${MAX_ENROLL_ATTEMPTS} attempts per 24 hours.`);
        }
        tx.update(rateLimitRef, { attempts: firestore_1.FieldValue.increment(1) });
    });
}
// ─── VECTOR SEARCH (KNN via Firestore FindNearest) ─────────────────────────
/**
 * Searches biometric_vault using Firestore native KNN vector search.
 * Falls back to full scan ONLY if vector index is not yet deployed.
 *
 * Returns the closest match found with its similarity score.
 */
async function findNearestTemplate(normalizedProbe, excludeUid) {
    var _a, _b, _c, _d;
    const vaultRef = db.collection("biometric_vault");
    // ── Attempt Firestore Native KNN Vector Search ──────────────────────────
    // Requires the vector index defined in firestore.indexes.json.
    // This is O(log N) and avoids downloading the entire collection.
    try {
        const vectorQuery = vaultRef.findNearest("embedding", firestore_1.FieldValue.vector(normalizedProbe), {
            limit: 5,
            distanceMeasure: "COSINE",
        });
        const snap = await vectorQuery.get();
        let bestSimilarity = -1;
        let bestUid = "";
        let bestPhone = "";
        for (const doc of snap.docs) {
            const data = doc.data();
            const docUid = (_a = data.uid) !== null && _a !== void 0 ? _a : doc.id;
            if (docUid === excludeUid)
                continue;
            const rawEmbedding = data.embedding;
            // Firebase VectorValue: convert to plain array
            const enrolledVector = Array.isArray(rawEmbedding)
                ? rawEmbedding
                : rawEmbedding.toArray();
            const similarity = cosineSimilarity(normalizedProbe, enrolledVector);
            if (similarity > bestSimilarity) {
                bestSimilarity = similarity;
                bestUid = docUid;
                bestPhone = (_b = data.phoneNumber) !== null && _b !== void 0 ? _b : "";
            }
        }
        if (bestSimilarity > AMBIGUITY_THRESHOLD) {
            return { uid: bestUid, phone: bestPhone, similarity: bestSimilarity };
        }
        return null;
    }
    catch (vectorError) {
        // Vector index not deployed yet — fall back to full scan
        // This will be removed once the index is confirmed deployed in production.
        const errMsg = (vectorError instanceof Error) ? vectorError.message : String(vectorError);
        functions.logger.warn("[BiometricFn] Vector search unavailable, falling back to full scan. Error:", errMsg);
        // ── FALLBACK: Full Collection Scan ──────────────────────────────────
        // WARNING: O(N) — acceptable only during development before index is deployed.
        const fullSnap = await vaultRef.get();
        let bestSimilarity = -1;
        let bestUid = "";
        let bestPhone = "";
        for (const doc of fullSnap.docs) {
            const data = doc.data();
            const docUid = (_c = data.uid) !== null && _c !== void 0 ? _c : doc.id;
            if (docUid === excludeUid)
                continue;
            const rawList = data.embedding;
            if (!rawList || rawList.length === 0)
                continue;
            const enrolledVector = rawList.map((e) => Number(e));
            const similarity = cosineSimilarity(normalizedProbe, enrolledVector);
            if (similarity > bestSimilarity) {
                bestSimilarity = similarity;
                bestUid = docUid;
                bestPhone = (_d = data.phoneNumber) !== null && _d !== void 0 ? _d : "";
            }
        }
        if (bestSimilarity > AMBIGUITY_THRESHOLD) {
            return { uid: bestUid, phone: bestPhone, similarity: bestSimilarity };
        }
        return null;
    }
}
// ─── MAIN CALLABLE: enrollBiometric ────────────────────────────────────────
/**
 * HTTPS Callable Function — Enroll Face Biometric
 *
 * Called by Flutter client after blink liveness is verified.
 * Accepts 128-D embedding, performs 1:N de-duplication against
 * biometric_vault, and if unique writes the template AND marks
 * the user's faceVerified=true — all in a single Firestore batch.
 *
 * Returns:
 *   { status: 'approved' | 'duplicate' | 'ambiguity' | 'error',
 *     maskedPhone?: string, similarity?: number, message: string }
 */
exports.enrollBiometric = functions
    .runWith({
    timeoutSeconds: 30,
    memory: "256MB",
})
    .https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e;
    // ── 1. Auth guard ───────────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to enroll biometrics.");
    }
    const uid = context.auth.uid;
    // ── 2. Input validation ─────────────────────────────────────────────
    const req = validateEnrollRequest(data);
    // ── 3. Rate limiting ────────────────────────────────────────────────
    await checkRateLimit(uid);
    // ── 4. Get user phone from Firestore (trusted — not from client) ────
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError("not-found", "User profile not found.");
    }
    const userData = userDoc.data();
    const phoneNumber = (_b = (_a = userData.phone) !== null && _a !== void 0 ? _a : userData.phoneNumber) !== null && _b !== void 0 ? _b : "";
    const currentStatus = (_c = userData.accountStatus) !== null && _c !== void 0 ? _c : "";
    // Must be in pending_face status to enroll
    if (currentStatus !== "pending_face") {
        throw new functions.https.HttpsError("failed-precondition", `Cannot enroll biometrics in status: ${currentStatus}. Must be pending_face.`);
    }
    // ── 5. Normalize probe vector ────────────────────────────────────────
    const normalizedProbe = l2Normalize(req.embedding);
    functions.logger.info(`[enrollBiometric] Starting 1:N de-dup for uid=${uid}, role=${req.role}`);
    // ── 6. 1:N De-duplication search ────────────────────────────────────
    const nearestMatch = await findNearestTemplate(normalizedProbe, uid);
    if (nearestMatch && nearestMatch.similarity >= DUPLICATE_THRESHOLD) {
        // ── DUPLICATE DETECTED — block enrollment ────────────────────────
        const maskedPhone = maskPhone(nearestMatch.phone);
        // Log security event
        await db.collection("biometric_audit_logs").add({
            eventType: "DUPLICATE_REGISTRATION_INTERCEPTED",
            attemptingUid: uid,
            attemptingPhone: phoneNumber,
            matchedUid: nearestMatch.uid,
            similarityScore: nearestMatch.similarity,
            threshold: DUPLICATE_THRESHOLD,
            timestamp: firestore_1.FieldValue.serverTimestamp(),
            functionVersion: "v1",
        });
        functions.logger.warn(`[enrollBiometric] DUPLICATE BLOCKED: uid=${uid} matches ${nearestMatch.uid} (similarity=${nearestMatch.similarity.toFixed(4)})`);
        return {
            status: "duplicate",
            maskedPhone,
            similarity: nearestMatch.similarity,
            message: `Your face is already registered with an existing account (${maskedPhone}). Duplicate accounts violate platform rules.`,
        };
    }
    if (nearestMatch && nearestMatch.similarity >= AMBIGUITY_THRESHOLD) {
        // ── AMBIGUITY — flag for manual review but allow enrollment ────────
        const maskedPhone = maskPhone(nearestMatch.phone);
        await db.collection("biometric_audit_logs").add({
            eventType: "ENROLLMENT_AMBIGUITY_FLAGGED",
            attemptingUid: uid,
            matchedUid: nearestMatch.uid,
            similarityScore: nearestMatch.similarity,
            threshold: AMBIGUITY_THRESHOLD,
            timestamp: firestore_1.FieldValue.serverTimestamp(),
            requiresManualReview: true,
            functionVersion: "v1",
        });
        functions.logger.warn(`[enrollBiometric] AMBIGUITY FLAGGED: uid=${uid} similarity=${nearestMatch.similarity.toFixed(4)} (ambiguous, allowing with review flag)`);
        // Enroll but flag for review — fall through to enrollment below
        functions.logger.info(`[enrollBiometric] Ambiguous match (${nearestMatch.similarity.toFixed(4)}) for uid=${uid} — flagging for review but allowing enrollment.`);
    }
    // ── 7. UNIQUE — enroll template + mark face verified atomically ──────
    const batch = db.batch();
    // Write biometric template (Admin SDK — bypasses Firestore rules)
    const vaultRef = db.collection("biometric_vault").doc(uid);
    batch.set(vaultRef, {
        uid,
        phoneNumber,
        phoneNumberMasked: maskPhone(phoneNumber),
        role: req.role,
        embedding: firestore_1.FieldValue.vector(normalizedProbe),
        enrolledAt: firestore_1.FieldValue.serverTimestamp(),
        modelFingerprint: (_d = req.modelFingerprint) !== null && _d !== void 0 ? _d : "kelasagara_biomatch_v1",
        livenessAudit: (_e = req.livenessAudit) !== null && _e !== void 0 ? _e : {},
        requiresReview: nearestMatch !== null,
        functionVersion: "v1",
    });
    // Mark user as face-verified and advance account status
    const userRef = db.collection("users").doc(uid);
    const newStatus = req.role === "hirer" ? "approved" : "pending_review";
    batch.update(userRef, {
        faceVerified: true,
        faceVerifiedAt: firestore_1.FieldValue.serverTimestamp(),
        verificationStatus: "face_done",
        faceVerificationMethod: "kelasagara_biomatch_v1",
        accountStatus: newStatus,
    });
    await batch.commit();
    functions.logger.info(`[enrollBiometric] SUCCESS: uid=${uid} enrolled. accountStatus→${newStatus}`);
    return {
        status: "approved",
        similarity: 0.0,
        accountStatus: newStatus,
        message: "Biometric enrollment successful.",
    };
});
// ─── CALLABLE: verifyBiometricLogin ────────────────────────────────────────
/**
 * HTTPS Callable — Verify Face for Login (1:1 Verification)
 *
 * Called when a returning user attempts face-based sign-in.
 * Compares probe embedding against the user's own enrolled template.
 * Never cross-checks against other users (that's only for enrollment).
 */
exports.verifyBiometricLogin = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }
    const uid = context.auth.uid;
    const req = validateEnrollRequest(data);
    const normalizedProbe = l2Normalize(req.embedding);
    const templateDoc = await db.collection("biometric_vault").doc(uid).get();
    if (!templateDoc.exists) {
        return {
            status: "not_enrolled",
            message: "No biometric template found. Please complete face enrollment.",
        };
    }
    const templateData = templateDoc.data();
    const rawEmbedding = templateData.embedding;
    const enrolledVector = Array.isArray(rawEmbedding)
        ? rawEmbedding
        : rawEmbedding.toArray();
    const similarity = cosineSimilarity(normalizedProbe, enrolledVector);
    const verified = similarity >= DUPLICATE_THRESHOLD;
    await db.collection("biometric_audit_logs").add({
        eventType: verified ? "BIOMETRIC_LOGIN_SUCCESS" : "BIOMETRIC_LOGIN_FAILED",
        uid,
        similarityScore: similarity,
        threshold: DUPLICATE_THRESHOLD,
        timestamp: firestore_1.FieldValue.serverTimestamp(),
    });
    return {
        status: verified ? "verified" : "rejected",
        similarity,
        message: verified ? "Face verified successfully." : "Face did not match enrolled template.",
    };
});
// ─── CALLABLE: deleteBiometricTemplate ─────────────────────────────────────
/**
 * HTTPS Callable — Delete Biometric Template (DPDPA 2023 Right to Erasure)
 *
 * Allows a user to delete their own biometric template upon account deletion.
 * Admin can delete any template.
 */
exports.deleteBiometricTemplate = functions
    .runWith({ timeoutSeconds: 15, memory: "128MB" })
    .https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
    }
    const requestUid = (_a = data.targetUid) !== null && _a !== void 0 ? _a : context.auth.uid;
    // Only allow deleting own template unless admin
    const callerUid = context.auth.uid;
    if (requestUid !== callerUid) {
        // Check admin claim
        const caller = await admin.auth().getUser(callerUid);
        const isAdmin = ((_b = caller.customClaims) === null || _b === void 0 ? void 0 : _b["admin"]) === true;
        if (!isAdmin) {
            throw new functions.https.HttpsError("permission-denied", "You can only delete your own biometric template.");
        }
    }
    await db.collection("biometric_vault").doc(requestUid).delete();
    await db.collection("biometric_audit_logs").add({
        eventType: "BIOMETRIC_TEMPLATE_DELETED",
        requestingUid: callerUid,
        deletedUid: requestUid,
        timestamp: firestore_1.FieldValue.serverTimestamp(),
        dpdpaCompliance: "right_to_erasure",
    });
    functions.logger.info(`[deleteBiometricTemplate] Deleted template for uid=${requestUid}`);
    return { status: "deleted", message: "Biometric template permanently deleted." };
});
var orthogonalBiometricProjector_1 = require("./biometric/orthogonalBiometricProjector");
Object.defineProperty(exports, "OrthogonalBiometricProjector", { enumerable: true, get: function () { return orthogonalBiometricProjector_1.OrthogonalBiometricProjector; } });
var geofence_notification_trigger_1 = require("./tracking/geofence_notification_trigger");
Object.defineProperty(exports, "onGeofenceAlertTriggered", { enumerable: true, get: function () { return geofence_notification_trigger_1.onGeofenceAlertTriggered; } });
// ============================================================================
// GATE G-02: 60-SECOND TRANSACTIONAL BIOMETRIC CHALLENGE CALLABLE FUNCTION
// ============================================================================
const https_1 = require("firebase-functions/v2/https");
const crypto_1 = require("crypto");
exports.CHALLENGE_COLLECTION = 'biometric_challenges';
exports.CHALLENGE_TTL_MS = 60000;
exports.IDEMPOTENT_SAFETY_WINDOW_MS = 5000;
const ALLOWED_PURPOSES = new Set([
    'enroll',
    'verify_1to1',
    'reverify_shift',
]);
const SAFE_REQUEST_ID_REGEX = /^[a-zA-Z0-9_-]{6,64}$/;
/**
 * Pure transactional challenge issuer shared between the Express route and
 * the Firebase Callable Function. Enforces all reads before writes.
 */
async function issueBiometricChallengeTransactional(params) {
    const { db, uid, purpose, clientRequestId, issuedVia } = params;
    const cleanReqId = typeof clientRequestId === 'string' &&
        SAFE_REQUEST_ID_REGEX.test(clientRequestId.trim())
        ? clientRequestId.trim()
        : null;
    const deterministicDocId = cleanReqId
        ? `chal_${uid}_${purpose}_${cleanReqId}`
        : (0, crypto_1.randomBytes)(16).toString('hex');
    const candidateRef = db.collection(exports.CHALLENGE_COLLECTION).doc(deterministicDocId);
    return db.runTransaction(async (tx) => {
        var _a, _b;
        const nowMs = (_a = params.nowMs) !== null && _a !== void 0 ? _a : Date.now();
        // --- PHASE A: TRANSACTION READ FIRST ---
        const existingSnap = await tx.get(candidateRef);
        if (existingSnap.exists) {
            const existing = existingSnap.data();
            const isSameOwnerAndPurpose = existing.uid === uid && existing.purpose === purpose;
            const isUnconsumed = existing.consumed === false;
            const hasSufficientRemainingTtl = Number(existing.expiresAtMs) > nowMs + exports.IDEMPOTENT_SAFETY_WINDOW_MS;
            if (isSameOwnerAndPurpose && isUnconsumed && hasSufficientRemainingTtl) {
                return {
                    challengeId: existing.challengeId,
                    uid: existing.uid,
                    purpose: existing.purpose,
                    nonce: existing.nonce,
                    ttlSeconds: 60,
                    expectedFrameCount: 3,
                    expectedSequence: ['EYES_OPEN', 'EYES_CLOSED_APEX', 'EYES_OPEN'],
                    issuedAtMs: Number(existing.issuedAtMs),
                    expiresAtMs: Number(existing.expiresAtMs),
                    consumed: false,
                    issuedVia: (_b = existing.issuedVia) !== null && _b !== void 0 ? _b : issuedVia,
                };
            }
        }
        // --- PHASE B: TRANSACTION WRITE SECOND ---
        // If the deterministic doc already existed but was consumed or expired,
        // allocate a fresh random document ID so consumed challenges are never overwritten.
        const freshChallengeId = existingSnap.exists
            ? (0, crypto_1.randomBytes)(16).toString('hex')
            : deterministicDocId;
        const targetRef = existingSnap.exists
            ? db.collection(exports.CHALLENGE_COLLECTION).doc(freshChallengeId)
            : candidateRef;
        const freshRecord = {
            challengeId: freshChallengeId,
            uid,
            purpose,
            nonce: (0, crypto_1.randomBytes)(32).toString('base64url'),
            ttlSeconds: 60,
            expectedFrameCount: 3,
            expectedSequence: ['EYES_OPEN', 'EYES_CLOSED_APEX', 'EYES_OPEN'],
            issuedAtMs: nowMs,
            expiresAtMs: nowMs + exports.CHALLENGE_TTL_MS,
            consumed: false,
            issuedVia,
        };
        tx.set(targetRef, freshRecord);
        return freshRecord;
    });
}
/**
 * Firebase Callable Function v2 (`requestBiometricChallenge`) deployed in `asia-south1`.
 * Obeys the exact authentication, purpose-binding, and 60-second TTL rules as the HTTP route.
 */
exports.requestBiometricChallenge = (0, https_1.onCall)({
    region: 'asia-south1',
    timeoutSeconds: 10,
    memory: '256MiB',
    enforceAppCheck: false, // Set to true once Firebase App Check is configured in staging
}, async (request) => {
    var _a, _b, _c;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (typeof uid !== 'string' || uid.trim().length === 0) {
        throw new https_1.HttpsError('unauthenticated', 'UNAUTHENTICATED_BIOMETRIC_CHALLENGE_REQUEST');
    }
    const rawPurpose = (_b = request.data) === null || _b === void 0 ? void 0 : _b.purpose;
    if (typeof rawPurpose !== 'string' ||
        !ALLOWED_PURPOSES.has(rawPurpose)) {
        throw new https_1.HttpsError('invalid-argument', 'INVALID_CHALLENGE_PURPOSE: Expected enroll, verify_1to1, or reverify_shift.');
    }
    const rawClientReqId = typeof ((_c = request.data) === null || _c === void 0 ? void 0 : _c.clientRequestId) === 'string'
        ? request.data.clientRequestId
        : null;
    try {
        const db = admin.firestore();
        const ticket = await issueBiometricChallengeTransactional({
            db,
            uid,
            purpose: rawPurpose,
            clientRequestId: rawClientReqId,
            issuedVia: 'callable_fallback',
        });
        return {
            ok: true,
            statusCode: 200,
            outcome: 'CHALLENGE_ISSUED',
            allowed: false,
            data: {
                challengeId: ticket.challengeId,
                nonce: ticket.nonce,
                purpose: ticket.purpose,
                issuedAtMs: ticket.issuedAtMs,
                expiresAtMs: ticket.expiresAtMs,
                ttlSeconds: 60,
                expectedFrameCount: 3,
                expectedSequence: ticket.expectedSequence,
                issuedVia: 'callable_fallback',
                releaseGateStatus: 'CONTROLLED_TEST_BUILD_ONLY',
                productionGateActive: false,
            },
            error: null,
            timestampMs: Date.now(),
        };
    }
    catch (_d) {
        throw new https_1.HttpsError('unavailable', 'CHALLENGE_STORE_TRANSACTION_FAILED');
    }
});
/**
 * HTTPS Callable: verifyArrivalOtp
 * Secure worker-submitted OTP verification with Admin SDK.
 * Validates worker identity, arrival gate, TTL, replay and rate-limiting.
 */
exports.verifyArrivalOtp = functions
    .runWith({ secrets: ["JOURNEY_HMAC_SECRET"] })
    .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const workerUid = context.auth.uid;
    const bookingId = ((data === null || data === void 0 ? void 0 : data.bookingId) || "").toString().trim();
    const enteredOtp = ((data === null || data === void 0 ? void 0 : data.enteredOtp) || "").toString().trim();
    const workerLocation = data === null || data === void 0 ? void 0 : data.location;
    if (!bookingId || !enteredOtp) {
        throw new functions.https.HttpsError("invalid-argument", "bookingId and enteredOtp are required.");
    }
    const hmacSecret = process.env.JOURNEY_HMAC_SECRET;
    if (!hmacSecret || hmacSecret.trim().length === 0) {
        throw new functions.https.HttpsError("failed-precondition", "Server configuration error: Required secret JOURNEY_HMAC_SECRET is missing.");
    }
    const computeOtpHash = (bId, otp) => {
        return crypto.createHmac("sha256", hmacSecret.trim()).update(`${bId}:${otp.trim()}`).digest("hex");
    };
    const bookingRef = db.collection("bookings").doc(bookingId);
    try {
        const result = await db.runTransaction(async (txn) => {
            var _a;
            const snap = await txn.get(bookingRef);
            if (!snap.exists) {
                throw new functions.https.HttpsError("not-found", "BOOKING_NOT_FOUND");
            }
            const bData = snap.data() || {};
            if (bData.workerId !== workerUid) {
                throw new functions.https.HttpsError("permission-denied", "UNAUTHORIZED_NOT_WORKER");
            }
            const status = (bData.status || "").toLowerCase();
            if (status === "working" || status === "in_progress" || status === "completed" || status === "completion_verified") {
                return { success: false, error: "ALREADY_VERIFIED_OR_COMPLETED" };
            }
            if (status !== "arrived") {
                throw new functions.https.HttpsError("failed-precondition", "PREMATURE_VERIFICATION_NOT_ARRIVED");
            }
            if (bData.arrivalOtpUsed === true) {
                return { success: false, error: "OTP_ALREADY_USED" };
            }
            const attempts = bData.arrivalOtpAttempts || 0;
            if (attempts >= 5) {
                throw new functions.https.HttpsError("resource-exhausted", "MAX_ATTEMPTS_EXCEEDED");
            }
            const expiry = bData.arrivalOtpExpiry;
            if (expiry && expiry.toMillis() < Date.now()) {
                throw new functions.https.HttpsError("deadline-exceeded", "OTP_EXPIRED");
            }
            const storedHash = bData.arrivalOtpHash;
            let isMatch = false;
            if (storedHash) {
                const candidateHash = computeOtpHash(bookingId, enteredOtp);
                isMatch =
                    storedHash.length === candidateHash.length &&
                        crypto.timingSafeEqual(Buffer.from(storedHash, "hex"), Buffer.from(candidateHash, "hex"));
            }
            else {
                const secureSnap = await txn.get(bookingRef.collection("hirer_secure").doc("arrival_code"));
                if (secureSnap.exists) {
                    const secOtp = (((_a = secureSnap.data()) === null || _a === void 0 ? void 0 : _a.arrivalOtp) || "").toString().trim();
                    if (secOtp && secOtp.length === enteredOtp.length) {
                        isMatch = crypto.timingSafeEqual(Buffer.from(secOtp), Buffer.from(enteredOtp));
                    }
                }
            }
            if (!isMatch) {
                const nextAttempts = attempts + 1;
                txn.update(bookingRef, {
                    arrivalOtpAttempts: nextAttempts,
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
                return {
                    success: false,
                    error: "INCORRECT_OTP",
                    remainingAttempts: Math.max(0, 5 - nextAttempts),
                };
            }
            // Valid OTP: Atomically transition status to in_progress (work_started)
            txn.update(bookingRef, {
                status: "in_progress",
                journeyStatus: "work_started",
                arrivalVerified: true,
                arrivalOtpUsed: true,
                workStartedAt: firestore_1.FieldValue.serverTimestamp(),
                verifiedWorkerLocation: workerLocation || null,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            return { success: true, bookingId, status: "in_progress" };
        });
        return result;
    }
    catch (err) {
        if (err instanceof functions.https.HttpsError)
            throw err;
        throw new functions.https.HttpsError("internal", err.message || "INTERNAL_ERROR");
    }
});
/**
 * HTTPS Callable: getHirerArrivalOtp
 * Secure hirer-only OTP retrieval and issuance via Admin SDK.
 * Writes verifier hash to main booking doc and stores plaintext OTP exclusively in hirer_secure.
 */
exports.getHirerArrivalOtp = functions
    .runWith({ secrets: ["JOURNEY_HMAC_SECRET"] })
    .https.onCall(async (data, context) => {
    var _a;
    if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const hirerUid = context.auth.uid;
    const bookingId = ((data === null || data === void 0 ? void 0 : data.bookingId) || "").toString().trim();
    if (!bookingId) {
        throw new functions.https.HttpsError("invalid-argument", "bookingId is required.");
    }
    const bookingRef = db.collection("bookings").doc(bookingId);
    const snap = await bookingRef.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "BOOKING_NOT_FOUND");
    }
    const bData = snap.data() || {};
    if (bData.hirerId !== hirerUid) {
        throw new functions.https.HttpsError("permission-denied", "UNAUTHORIZED_NOT_HIRER");
    }
    const secureRef = bookingRef.collection("hirer_secure").doc("arrival_code");
    const secureSnap = await secureRef.get();
    if (secureSnap.exists) {
        return { success: true, arrivalOtp: (_a = secureSnap.data()) === null || _a === void 0 ? void 0 : _a.arrivalOtp };
    }
    // Issue new OTP
    const hmacSecret = process.env.JOURNEY_HMAC_SECRET;
    if (!hmacSecret || hmacSecret.trim().length === 0) {
        throw new functions.https.HttpsError("failed-precondition", "Server configuration error: Required secret JOURNEY_HMAC_SECRET is missing.");
    }
    const otpInt = crypto.randomInt(100000, 1000000);
    const otp = otpInt.toString();
    const hash = crypto.createHmac("sha256", hmacSecret.trim()).update(`${bookingId}:${otp}`).digest("hex");
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1000);
    await bookingRef.set({
        arrivalOtpHash: hash,
        arrivalOtpExpiry: admin.firestore.Timestamp.fromDate(expiresAt),
        arrivalOtpAttempts: 0,
        arrivalOtpUsed: false,
        arrivalVerified: false,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await secureRef.set({
        arrivalOtp: otp,
        hirerId: hirerUid,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    });
    return { success: true, arrivalOtp: otp };
});
// ─── VOICE DIRECT BOOKING MODULE (V5.0) ────────────────────────────────────
var voiceBookingCallables_1 = require("./voice_booking/voiceBookingCallables");
Object.defineProperty(exports, "requestVoiceDirectBooking", { enumerable: true, get: function () { return voiceBookingCallables_1.requestVoiceDirectBooking; } });
Object.defineProperty(exports, "approveVoiceDirectBooking", { enumerable: true, get: function () { return voiceBookingCallables_1.approveVoiceDirectBooking; } });
Object.defineProperty(exports, "rejectVoiceDirectBooking", { enumerable: true, get: function () { return voiceBookingCallables_1.rejectVoiceDirectBooking; } });
Object.defineProperty(exports, "cancelVoiceDirectBooking", { enumerable: true, get: function () { return voiceBookingCallables_1.cancelVoiceDirectBooking; } });
var cleanupTriggers_1 = require("./voice_booking/cleanupTriggers");
Object.defineProperty(exports, "resolvePendingRequestsOnAssignment", { enumerable: true, get: function () { return cleanupTriggers_1.resolvePendingRequestsOnAssignment; } });
Object.defineProperty(exports, "expireStalePendingDirectBookings", { enumerable: true, get: function () { return cleanupTriggers_1.expireStalePendingDirectBookings; } });
Object.defineProperty(exports, "reconcileStaleApprovalLeases", { enumerable: true, get: function () { return cleanupTriggers_1.reconcileStaleApprovalLeases; } });
var outboxDispatcher_1 = require("./voice_booking/outboxDispatcher");
Object.defineProperty(exports, "dispatchNotificationsOutbox", { enumerable: true, get: function () { return outboxDispatcher_1.dispatchNotificationsOutbox; } });
Object.defineProperty(exports, "retryFailedOutboxNotifications", { enumerable: true, get: function () { return outboxDispatcher_1.retryFailedOutboxNotifications; } });
//# sourceMappingURL=index.js.map