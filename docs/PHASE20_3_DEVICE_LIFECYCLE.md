# KELASAGARA V20.3: DEVICE LIFECYCLE MANAGEMENT
## State Machine, Rotation, Quotas, and Deletion Protocols

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-09  
**Classification:** Core Security Engineering Specification

---

## 1. DEVICE KEY STATE MACHINE

Every cryptographic key registered in `/biometric_devices/{deviceKeyId}` exists in one of three deterministic lifecycle states:

```
                      ┌──────────────────────┐
                      │    INITIAL STATE     │
                      └──────────────────────┘
                                  │
                                  │ registerDevice() (Attestation Verified)
                                  ▼
                      ┌──────────────────────┐
            ┌────────>│        ACTIVE        │<────────┐
            │         └──────────────────────┘         │
            │                     │                    │
            │                     │ adminSuspend()     │
            │                     ▼                    │
            │         ┌──────────────────────┐         │
            │         │      SUSPENDED       │─────────┘
            │         └──────────────────────┘  adminReactivate()
            │                     │
            │                     │ revokeDeviceKey() / userRevoke()
            │                     ▼
            │         ┌──────────────────────┐
            └─────────│       REVOKED        │
                      └──────────────────────┘
                         (Permanent Terminal)
```

### Transition Invariants:
1. **ACTIVE:** The device key is fully authorized. Can sign transaction challenges and execute biometric operations. `lastAuthenticatedAt` is updated on each success.
2. **SUSPENDED:** Temporarily locked due to suspicious anomaly (e.g. rapid geographic impossible travel or excessive consecutive failed biometric attempts). Rejects all transaction signing attempts with `DEVICE_KEY_SUSPENDED`. Can be returned to `ACTIVE` by an authorized compliance officer.
3. **REVOKED:** Permanently terminated due to device loss, theft, user replacement, or account de-registration. A revoked key **can never be re-activated** (`DEVICE_KEY_REVOKED`).

---

## 2. KEY ROTATION & DEVICE QUOTA ENFORCEMENT

- **Active Quota Limit:** A worker may have at most two active devices registered simultaneously (`MAX_ACTIVE_DEVICES_PER_WORKER = 2`).
- **Device Replacement Flow:**
  When a worker acquires a new phone:
  1. The worker authenticates with their primary credentials (Firebase Phone OTP + Password/MFA).
  2. The mobile app lists currently registered devices via `GET /api/biometrics/v10/devices`.
  3. The worker selects an older device to revoke via `POST /api/biometrics/v10/revoke-device`.
  4. The worker registers the new device hardware key via `POST /api/biometrics/v10/register-device`.
  5. The underlying worker biometric facial identity is **preserved** without requiring physical re-enrollment.
- **Biometric Identity Decoupling:**
  Revoking a device key **never** deletes the worker's facial biometric template from the vault. Device keys protect the transport and authorization channel; the biometric template represents the immutable physical human identity.
