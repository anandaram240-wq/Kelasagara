// backend/src/services/account_lifecycle.ts
/**
 * Account Lifecycle & Rental Defense Engine (Ticket T-18 / Finding F4).
 * Mitigates account renting, credential leasing, and unvetted proxy labor by enforcing:
 * 1. Periodic shift-start 1:1 facial re-verification.
 * 2. Hardware device fingerprint binding.
 * 3. Geolocation plausibility and GPS-spoof detection.
 *
 * Invariant I-27: Mandatory Shift Re-Verification.
 * Gig workers MUST pass 1:1 biometric re-verification before commencing an active shift.
 * Shifts expire after SHIFT_TTL_HOURS (default 10h), requiring fresh re-authentication.
 *
 * Invariant I-28: Hardware Device Binding.
 * Accounts are bound to a verified hardware device fingerprint. Untrusted device logins
 * force biometric step-up before any bookings can be accepted.
 */

import admin from "firebase-admin";
import { cosineSimilarity } from "./biometric_matching";
import { FirestoreBiometricRepository } from "./firestore_biometric_repository";
import { AuditService } from "./audit_service";
import { config } from "../config";

export interface ShiftStatus {
  uid: string;
  isShiftActive: boolean;
  shiftStartedAt?: number;
  shiftExpiresAt?: number;
  lastVerifiedAt?: number;
  boundDeviceId?: string;
  requiresReverification: boolean;
  reason?: string;
}

export interface ReVerifyRequest {
  uid: string;
  probeEmbedding: number[];
  deviceId: string;
  latitude?: number;
  longitude?: number;
  isMockGps?: boolean;
}

export interface ReVerifyResult {
  success: boolean;
  isMatch: boolean;
  similarity: number;
  threshold: number;
  shiftActive: boolean;
  deviceBound: boolean;
  requiresDeviceChallenge: boolean;
  message: string;
}

export class AccountLifecycleService {
  private static readonly SHIFT_TTL_MS = 10 * 60 * 60 * 1000; // 10 hours
  private static readonly MAX_SPEED_KMH = 120.0; // Max plausible speed between checks

  private static get db() {
    return admin.firestore();
  }

  /**
   * Retrieves current worker shift status.
   */
  static async getShiftStatus(uid: string): Promise<ShiftStatus> {
    const userDoc = await this.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      throw new Error(`User not found: ${uid}`);
    }

    const data = userDoc.data() || {};
    const now = Date.now();
    const shiftStartedAt = data.shiftStartedAt ? Number(data.shiftStartedAt) : 0;
    const shiftExpiresAt = data.shiftExpiresAt ? Number(data.shiftExpiresAt) : 0;
    const boundDeviceId = data.boundDeviceId || "";
    const lastVerifiedAt = data.lastBiometricVerifiedAt ? Number(data.lastBiometricVerifiedAt) : 0;

    const isShiftActive = shiftExpiresAt > now;
    const requiresReverification = !isShiftActive;

    return {
      uid,
      isShiftActive,
      shiftStartedAt: shiftStartedAt || undefined,
      shiftExpiresAt: shiftExpiresAt || undefined,
      lastVerifiedAt: lastVerifiedAt || undefined,
      boundDeviceId: boundDeviceId || undefined,
      requiresReverification,
      reason: requiresReverification ? "Shift expired or not started. Biometric re-verification required." : undefined,
    };
  }

  /**
   * Executes 1:1 facial re-verification for shift start or step-up authentication.
   * Compares probe embedding against enrolled template in biometric_vault.
   */
  static async reVerifyWorker(req: ReVerifyRequest): Promise<ReVerifyResult> {
    const { uid, probeEmbedding, deviceId, latitude, longitude, isMockGps } = req;

    // 1. Anti-Mock GPS check
    if (isMockGps === true) {
      await AuditService.logEvent({
        eventType: "STATE_RECONCILIATION_FLAGGED",
        uid,
        metadata: {
          flag: "MOCK_GPS_DETECTED",
          deviceId,
          latitude,
          longitude,
        },
      });
      return {
        success: false,
        isMatch: false,
        similarity: 0,
        threshold: config.verificationThreshold,
        shiftActive: false,
        deviceBound: false,
        requiresDeviceChallenge: false,
        message: "Mock GPS location provider detected. Please disable location spoofing apps to start shift.",
      };
    }

    // 2. Fetch enrolled biometric template
    const enrolledTemplate = await FirestoreBiometricRepository.getEnrolledTemplate(uid);
    if (!enrolledTemplate) {
      return {
        success: false,
        isMatch: false,
        similarity: 0,
        threshold: config.verificationThreshold,
        shiftActive: false,
        deviceBound: false,
        requiresDeviceChallenge: false,
        message: "No biometric template enrolled for this user. Full enrollment required.",
      };
    }

    // 3. Compute 1:1 similarity
    const similarity = cosineSimilarity(probeEmbedding, enrolledTemplate);
    const isMatch = similarity >= config.verificationThreshold;

    if (!isMatch) {
      await AuditService.logEvent({
        eventType: "BIOMETRIC_LOGIN_FAILED",
        uid,
        similarityScore: similarity,
        threshold: config.verificationThreshold,
        metadata: { action: "SHIFT_REVERIFY_FAILED", deviceId },
      });

      return {
        success: false,
        isMatch: false,
        similarity,
        threshold: config.verificationThreshold,
        shiftActive: false,
        deviceBound: false,
        requiresDeviceChallenge: false,
        message: "Facial re-verification failed. Identity does not match enrolled account owner.",
      };
    }

    // 4. Device Binding & Anomaly Evaluation (Account Rental Defense)
    const userDocRef = this.db.collection("users").doc(uid);
    const userSnap = await userDocRef.get();
    const userData = userSnap.data() || {};
    const boundDeviceId = userData.boundDeviceId;
    let requiresDeviceChallenge = false;

    if (boundDeviceId && boundDeviceId !== deviceId) {
      // Login attempted from a different device — account sharing / renting risk!
      console.warn(`[AccountLifecycle] Untrusted device login for ${uid}: bound=${boundDeviceId}, current=${deviceId}`);
      requiresDeviceChallenge = true;

      await AuditService.logEvent({
        eventType: "STATE_RECONCILIATION_FLAGGED",
        uid,
        metadata: {
          flag: "UNTRUSTED_DEVICE_SWITCH",
          boundDeviceId,
          newDeviceId: deviceId,
        },
      });
    }

    // 5. Geolocation Teleportation Plausibility Check
    if (latitude !== undefined && longitude !== undefined && userData.lastLocation) {
      const prev = userData.lastLocation;
      const prevTime = userData.lastLocationTimestamp ? Number(userData.lastLocationTimestamp) : 0;
      const now = Date.now();
      const elapsedHours = Math.max(0.001, (now - prevTime) / (1000 * 60 * 60));

      const distKm = this.haversineDistanceKm(prev.latitude, prev.longitude, latitude, longitude);
      const speedKmh = distKm / elapsedHours;

      if (speedKmh > this.MAX_SPEED_KMH) {
        console.warn(`[AccountLifecycle] Implausible speed detected for ${uid}: ${speedKmh.toFixed(1)} km/h across ${distKm.toFixed(1)} km`);
        await AuditService.logEvent({
          eventType: "STATE_RECONCILIATION_FLAGGED",
          uid,
          metadata: {
            flag: "IMPLAUSIBLE_TELEPORTATION",
            speedKmh,
            distanceKm: distKm,
            elapsedHours,
          },
        });
      }
    }

    // 6. Activate Shift & Bind Device
    const now = Date.now();
    const shiftExpiresAt = now + this.SHIFT_TTL_MS;

    const updatePayload: Record<string, any> = {
      isAvailable: true,
      shiftStartedAt: now,
      shiftExpiresAt,
      lastBiometricVerifiedAt: now,
      lastBiometricVerificationMethod: "1to1_sface_reverify",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Bind device if not yet bound
    if (!boundDeviceId && deviceId) {
      updatePayload.boundDeviceId = deviceId;
      updatePayload.deviceBoundAt = now;
    }

    if (latitude !== undefined && longitude !== undefined) {
      updatePayload.lastLocation = { latitude, longitude };
      updatePayload.lastLocationTimestamp = now;
    }

    await userDocRef.update(updatePayload);

    await AuditService.logEvent({
      eventType: "BIOMETRIC_LOGIN_SUCCESS",
      uid,
      similarityScore: similarity,
      threshold: config.verificationThreshold,
      metadata: {
        action: "SHIFT_REVERIFY_SUCCESS",
        deviceId,
        shiftExpiresAt,
      },
    });

    return {
      success: true,
      isMatch: true,
      similarity,
      threshold: config.verificationThreshold,
      shiftActive: true,
      deviceBound: Boolean(boundDeviceId || deviceId),
      requiresDeviceChallenge,
      message: "Biometric re-verification successful. Shift activated for 10 hours.",
    };
  }

  /**
   * Calculates Haversine distance in kilometers between two GPS coordinates.
   */
  private static haversineDistanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371; // Earth radius in km
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
