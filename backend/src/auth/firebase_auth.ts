// backend/src/auth/firebase_auth.ts
import { Request, Response, NextFunction } from "express";
import admin from "firebase-admin";
import { config } from "../config";

// Initialize Firebase Admin SDK if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: config.projectId,
  });
}

export interface AuthenticatedRequest extends Request {
  user?: {
    uid: string;
    email?: string;
    phone?: string;
    isAdmin?: boolean;
  };
}

/**
 * Express middleware to verify Firebase Auth ID token from Authorization header.
 * Token must be passed as: Authorization: Bearer <token>
 */
export async function authenticateFirebaseToken(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const isProduction = process.env.NODE_ENV === "production";
  const devTokenAllowed = !isProduction && config.allowDevToken === true;

  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    // Check if test / dev token header is allowed ONLY in non-production testing mode
    if (devTokenAllowed && req.headers["x-dev-uid"]) {
      const rawUid = (req.headers["x-dev-uid"] as string).trim();
      if (/^[a-zA-Z0-9_\-\.]{1,128}$/.test(rawUid)) {
        req.user = {
          uid: rawUid,
          email: `${rawUid}@kelasagara.internal`,
        };
        return next();
      }
    }

    res.status(401).json({
      error: "unauthenticated",
      message: "Missing or invalid Authorization header. Expected 'Bearer <token>'.",
    });
    return;
  }

  const idToken = authHeader.split("Bearer ")[1].trim();

  // If in production, dev-mock-token or x-dev-uid is unconditionally rejected immediately
  if (isProduction && (idToken.startsWith("dev-mock-token-") || req.headers["x-dev-uid"])) {
    res.status(401).json({
      error: "unauthenticated",
      message: "Development authentication tokens are strictly forbidden in production mode.",
    });
    return;
  }

  // If in authorized dev/test mode with mock token, bypass remote network token verification immediately
  if (devTokenAllowed && idToken.startsWith("dev-mock-token-")) {
    const mockUid = idToken.replace("dev-mock-token-", "").trim();
    if (/^[a-zA-Z0-9_\-\.]{1,128}$/.test(mockUid)) {
      req.user = { uid: mockUid, email: `${mockUid}@kelasagara.internal` };
      return next();
    }
    res.status(401).json({
      error: "unauthenticated",
      message: "Malformed development mock token UID.",
    });
    return;
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    req.user = {
      uid: decodedToken.uid,
      email: decodedToken.email,
      phone: decodedToken.phone_number,
      isAdmin: decodedToken.admin === true,
    };
    next();
  } catch (error: any) {
    res.status(401).json({
      error: "unauthenticated",
      message: "Invalid or expired Firebase ID token.",
      details: error.message,
    });
  }
}
