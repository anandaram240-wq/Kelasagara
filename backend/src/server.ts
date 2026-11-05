// backend/src/server.ts
import express from "express";
import cors from "cors";
import path from "path";
import fs from "fs";
import admin from "firebase-admin";

// Ensure Google Application Default Credentials are set for Firestore Admin SDK
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  const defaultAdcPath = path.join(process.env.HOME || "", ".config/gcloud/application_default_credentials.json");
  if (fs.existsSync(defaultAdcPath)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = defaultAdcPath;
  }
}

import { config } from "./config";

// Initialize Firebase Admin if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: config.projectId,
  });
}
import { faceRouter } from "./routes/face_routes";
import { createBiometricV10Router } from "./routes/biometric_v10_routes";
import { FaceV10PilotController } from "./routes/face_v10_pilot_routes";
import { FaceV11ProductionController } from "./routes/face_v11_routes";
import { createFaceV12Router } from "./routes/face_v12_routes";
import { createFaceV18Router } from "./routes/face_v18_routes";
import { FaceV18UnifiedController } from "./routes/face_v18_unified_routes";
import { CanonicalSFaceEngineV10 } from "./biometrics/canonical_sface_engine_v10";
import { BiometricOperationReceiptService } from "./biometrics/identity_contract_v10";
import { BiometricLifecycleCoordinatorV10 } from "./services/biometric_lifecycle_coordinator_v10";
import { FirestoreCompatibleGalleryIndex } from "./services/firestore_compatible_gallery_index";
import { createAdminBiometricRouter } from "./routes/admin_biometric_routes";
import { createIdentityRouter } from "./routes/identity_routes";
import { createJourneyRouter } from "./routes/journey_routes";
import { getInferenceSession } from "./services/face_inference";

import { warmUpBiometricIndex } from "./services/biometric_enrollment";

const app = express();

// Security Headers Middleware
app.use((_req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  res.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
  res.setHeader("X-XSS-Protection", "0");
  res.setHeader("Referrer-Policy", "no-referrer");
  next();
});

// Hardened CORS Configuration
const corsOptions: cors.CorsOptions = {
  origin: (origin, callback) => {
    // Mobile apps, curl, and server-to-server requests have no Origin header
    if (!origin) return callback(null, true);
    if (config.allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error(`CORS origin '${origin}' is not permitted by BioMatch security policy.`));
  },
  methods: ["GET", "POST", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Dev-Uid"],
  credentials: true,
  maxAge: 86400, // 24 hours preflight cache
};

app.use(cors(corsOptions));
app.use(express.json({ limit: config.maxPayloadSize })); // Cap request size to 5MB
app.use(express.urlencoded({ extended: true, limit: config.maxPayloadSize }));

// Request logging middleware
app.use((req, _res, next) => {
  console.log(`[HTTP] ${req.method} ${req.path} - ${new Date().toISOString()}`);
  next();
});

// Mount biometric API routes
app.use("/api/biometrics", faceRouter);
app.use(createAdminBiometricRouter());
app.use("/api/identity", createIdentityRouter());
app.use("/api/journey", createJourneyRouter());

// Initialize Canonical V10 Biometric Subsystem
const db = admin.firestore();
const sfaceModelPath = path.resolve(__dirname, "../models/face_recognition_sface_2021dec.onnx");
const canonicalEngineV10 = new CanonicalSFaceEngineV10(sfaceModelPath);
const receiptSecret = Buffer.from(
  process.env.BIOMETRIC_RECEIPT_SECRET || "kelasagara_biometric_receipt_secret_key_32_bytes_min_length",
  "utf8"
);
const receiptServiceV10 = new BiometricOperationReceiptService(receiptSecret);
const galleryIndexV10 = new FirestoreCompatibleGalleryIndex(db);
const coordinatorV10 = new BiometricLifecycleCoordinatorV10(
  db,
  galleryIndexV10,
  receiptServiceV10
);

// Mount Canonical V10 Biometric API routes
app.use(
  "/api/biometrics/v10",
  createBiometricV10Router({
    db,
    coordinator: coordinatorV10,
    engine: canonicalEngineV10,
    receiptService: receiptServiceV10,
  })
);

// Mount Phase 9 V10 End-to-End Pilot Controller
const pilotControllerV10 = new FaceV10PilotController({ db });
app.use("/api/v10/biometrics", pilotControllerV10.router);

// Mount Phase 11 V11.0 Production Controller (512-D, FIQA, PAD, AES-256-GCM, HNSW)
const productionControllerV11 = new FaceV11ProductionController({ db });
app.use("/api/v11/biometrics", productionControllerV11.router);

// Mount Phase 12 V12.0 Hyperscale & Edge Router
app.use("/api/v12/biometrics", createFaceV12Router());

// Mount Phase 19 V18.0 Unified Biometric Controller (Group Commit, WORM Audit, Gate H Calibration Bridge)
const faceV18UnifiedController = new FaceV18UnifiedController();
app.use("/api/v18/biometrics", faceV18UnifiedController.router);

// Mount Phase 13 V18.0 Hyperscale Pipeline Router (Stage 1 PAD/FIQA -> Stage 2 ONNX -> Stage 3 CAS)
app.use("/api/v18/biometrics", createFaceV18Router({ db }));


// Root health and readiness checks (Section 8: Liveness & Readiness Probes)
app.get("/", (_req, res) => {
  res.status(200).json({
    status: "ok",
    name: "Kelasagara BioMatch Standalone Backend",
    version: "1.0.0",
    database: "Cloud Firestore Only",
    model: config.modelVersion,
  });
});

app.get("/health", (_req, res) => {
  res.status(200).json({
    status: "ok",
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

app.get("/ready", (_req, res) => {
  const isReady = Boolean(db && config.modelVersion);
  if (isReady) {
    res.status(200).json({
      ready: true,
      status: "ready",
      service: "kelasagara-biomatch-backend",
      modelVersion: config.modelVersion,
      timestamp: new Date().toISOString(),
    });
  } else {
    res.status(503).json({
      ready: false,
      status: "unready",
      timestamp: new Date().toISOString(),
    });
  }
});

// Error handling middleware (including 413 Payload Too Large and CORS rejections)
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err.type === "entity.too.large" || err.status === 413) {
    return res.status(413).json({
      success: false,
      status: "payload_too_large",
      error: {
        code: "PAYLOAD_TOO_LARGE",
        message: `Request payload exceeds allowed limit of ${config.maxPayloadSize}.`,
      },
      serverTimestamp: new Date().toISOString(),
    });
  }

  if (err.message && err.message.includes("BioMatch security policy")) {
    return res.status(403).json({
      success: false,
      status: "cors_rejected",
      error: {
        code: "CORS_FORBIDDEN",
        message: err.message,
      },
      serverTimestamp: new Date().toISOString(),
    });
  }

  console.error("[ServerError]", err);
  res.status(500).json({
    success: false,
    status: "internal_error",
    error: {
      code: "INTERNAL_ERROR",
      message: err.message || "An unexpected internal server error occurred.",
    },
    serverTimestamp: new Date().toISOString(),
  });
});

// Start server
export async function startServer() {
  try {
    // Preload ONNX model to avoid cold-start delay on first request
    await getInferenceSession();
  } catch (err: any) {
    console.warn(`[Server] Warning: Failed to preload ONNX model on start: ${err.message}`);
  }

  const server = app.listen(config.port, () => {
    console.log(`====================================================`);
    console.log(`🚀 KELASAGARA BIOMATCH STANDALONE BACKEND RUNNING`);
    console.log(`   Port: ${config.port}`);
    console.log(`   Firebase Project: ${config.projectId}`);
    console.log(`   Model: ${config.modelVersion} (OpenCV Zoo Apache-2.0, 128-D)`);
    console.log(`   Advisory Floor Threshold: ${config.advisoryFloorThreshold}`);
    console.log(`====================================================`);
  });

  // After server starts:
  warmUpBiometricIndex().then(() => {
    console.log('[BiometricIndex] Warm-up complete');
  }).catch(err => {
    console.error('[BiometricIndex] Warm-up failed (non-fatal):', err);
  });

  return server;
}

if (require.main === module) {
  startServer();
}

export default app;
