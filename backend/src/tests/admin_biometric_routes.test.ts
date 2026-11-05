// backend/src/tests/admin_biometric_routes.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import admin from 'firebase-admin';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'test-kelasagara-admin' });
}

import { createAdminBiometricRouter, requireBiometricComplianceOfficer } from '../routes/admin_biometric_routes';

describe('Admin Biometric Routes & Review Queue (Gate G-08)', () => {
  it('requireBiometricComplianceOfficer rejects missing Authorization header with 401', async () => {
    let responseStatus = 200;
    let responseBody: any = null;

    const req: any = {
      headers: {},
    };
    const res: any = {
      status(s: number) {
        responseStatus = s;
        return this;
      },
      json(data: any) {
        responseBody = data;
        return this;
      },
    };

    let nextCalled = false;
    await requireBiometricComplianceOfficer(req, res, () => {
      nextCalled = true;
    });

    assert.strictEqual(nextCalled, false);
    assert.strictEqual(responseStatus, 401);
    assert.strictEqual(responseBody?.error, 'UNAUTHORIZED_MISSING_TOKEN');
  });

  it('requireBiometricComplianceOfficer rejects token without compliance officer claim with 403', async () => {
    const authInstance = admin.auth();
    const origVerify = authInstance.verifyIdToken.bind(authInstance);
    authInstance.verifyIdToken = async () => ({
      uid: 'regular_user_1',
      role: 'worker',
      biometric_compliance_officer: false,
    } as any);

    let responseStatus = 200;
    let responseBody: any = null;

    const req: any = {
      headers: { authorization: 'Bearer test_token_regular' },
    };
    const res: any = {
      status(s: number) {
        responseStatus = s;
        return this;
      },
      json(data: any) {
        responseBody = data;
        return this;
      },
    };

    let nextCalled = false;
    try {
      await requireBiometricComplianceOfficer(req, res, () => {
        nextCalled = true;
      });

      assert.strictEqual(nextCalled, false);
      assert.strictEqual(responseStatus, 403);
      assert.strictEqual(responseBody?.error, 'FORBIDDEN_COMPLIANCE_OFFICER_CLAIM_REQUIRED');
    } finally {
      authInstance.verifyIdToken = origVerify;
    }
  });

  it('requireBiometricComplianceOfficer passes token with biometric_compliance_officer=true', async () => {
    const authInstance = admin.auth();
    const origVerify = authInstance.verifyIdToken.bind(authInstance);
    authInstance.verifyIdToken = async () => ({
      uid: 'officer_42',
      email: 'compliance@kelasagara.in',
      biometric_compliance_officer: true,
    } as any);

    const req: any = {
      headers: { authorization: 'Bearer valid_officer_token' },
    };
    const res: any = {};

    let nextCalled = false;
    try {
      await requireBiometricComplianceOfficer(req, res, () => {
        nextCalled = true;
      });

      assert.strictEqual(nextCalled, true);
      assert.strictEqual(req.officerUid, 'officer_42');
      assert.strictEqual(req.officerEmail, 'compliance@kelasagara.in');
    } finally {
      authInstance.verifyIdToken = origVerify;
    }
  });
});
