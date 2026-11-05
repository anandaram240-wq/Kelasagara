/**
 * functions/src/tracking/geofence_notification_trigger.ts
 *
 * Production Cloud Function for Kelasagara Real-Time Tracking Alerts.
 * Dispatches bilingual (Kannada + English) FCM push notifications when
 * the worker crosses 150m (Approaching) or 35m (Arrived) geofences.
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

export const onGeofenceAlertTriggered = functions.firestore
  .document('bookings/{bookingId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const bookingId = context.params.bookingId;

    if (!afterData) return null;

    const beforeAlert = beforeData?.lastGeofenceAlert;
    const afterAlert = afterData?.lastGeofenceAlert;

    // Check if lastGeofenceAlert changed
    if (!afterAlert || beforeAlert?.milestone === afterAlert?.milestone) {
      return null;
    }

    const milestone: string = afterAlert.milestone || '';
    const titleEn: string = afterAlert.titleEn || 'Worker update';
    const titleKn: string = afterAlert.titleKn || 'ಕೆಲಸಗಾರರ ಅಪ್ಡೇಟ್';
    const bodyEn: string = afterAlert.bodyEn || '';
    const bodyKn: string = afterAlert.bodyKn || '';

    const hirerId: string | undefined = afterData.hirerId || afterData.userId;
    if (!hirerId) {
      console.warn(`[GeofenceAlert] Booking ${bookingId} has no hirerId`);
      return null;
    }

    // 1. Retrieve Hirer's active FCM device tokens
    const hirerDoc = await admin.firestore().collection('users').doc(hirerId).get();
    const hirerData = hirerDoc.data();
    const tokens: string[] = [];

    if (hirerData?.fcmToken && typeof hirerData.fcmToken === 'string') {
      tokens.push(hirerData.fcmToken);
    }
    if (Array.isArray(hirerData?.deviceTokens)) {
      for (const t of hirerData.deviceTokens) {
        if (typeof t === 'string' && !tokens.includes(t)) {
          tokens.push(t);
        }
      }
    }
    if (afterData.hirerFcmToken && !tokens.includes(afterData.hirerFcmToken)) {
      tokens.push(afterData.hirerFcmToken);
    }

    if (tokens.length === 0) {
      console.log(`[GeofenceAlert] No FCM tokens found for Hirer ${hirerId}`);
      return null;
    }

    // 2. Bilingual combined headline
    const combinedTitle = `${titleKn} • ${titleEn}`;
    const combinedBody = `${bodyKn}\n${bodyEn}`;

    // 3. Construct High-Priority Multicast Payload
    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: combinedTitle,
        body: combinedBody,
      },
      data: {
        bookingId: bookingId,
        milestone: milestone,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        route: '/tracking',
        status: afterData.status || '',
        arrivalOtp: (afterData.arrivalOtp || afterData.startOtp || '').toString(),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'tracking_alerts',
          priority: 'max',
          defaultSound: true,
          defaultVibrateTimings: true,
          visibility: 'public',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: combinedTitle,
              body: combinedBody,
            },
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `[GeofenceAlert] Sent ${milestone} alert for booking ${bookingId}: ` +
        `${response.successCount} succeeded, ${response.failureCount} failed.`
      );
      return { success: true, count: response.successCount };
    } catch (err) {
      console.error(`[GeofenceAlert] Failed to send multicast for ${bookingId}:`, err);
      return null;
    }
  });
