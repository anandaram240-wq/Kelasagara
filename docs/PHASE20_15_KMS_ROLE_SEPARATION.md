# KELASAGARA V20.15 — CLOUD KMS ROLE SEPARATION AUDIT
## Cryptographic Separation of Signing Authority from Verification Authority

**Author:** Principal Cryptographic Systems Engineer, IAM Security Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/kms.tf`, `infra/terraform/iam_bindings.tf`  
**Status:** ARCHITECTURALLY ENFORCED  

---

### 1. Defect Analysis: The Danger of `roles/cloudkms.signerVerifier`

In default Google Cloud KMS documentation, developers frequently assign `roles/cloudkms.signerVerifier` to any service interacting with asymmetric digital signature keys.

This violates the fundamental security property of public-key cryptography:
- **Signing Authority (`cloudkms.cryptoKeyVersions.useToSign`):** A strictly guarded secret capability. Only the authorized notary or attestation emitter should possess this capability.
- **Verification Authority (`cloudkms.cryptoKeyVersions.useToVerify` and `cloudkms.cryptoKeyVersions.viewPublicKey`):** A public or semi-public capability. Verifying clients must be able to download the public key and verify ECDSA signatures without the power to mint counterfeit signatures.

If `roles/cloudkms.signerVerifier` is assigned to a verifier service (e.g. `sa-biometrics-verifier`), any remote code execution (RCE) or logic vulnerability in the verification service allows an attacker to forge audit records, tamper with preprocessing manifests, and issue false attestation proofs.

---

### 2. Remediated Architecture

In Phase 20.15, `roles/cloudkms.signerVerifier` is strictly banned (enforced via Policy-as-Code rule **POL-12**).

Instead, distinct permissions are partitioned across separate asymmetric keys and principals:

```
                           +---------------------------+
                           |  Cloud KMS Keyring:       |
                           |  biometrics-keyring       |
                           +---------------------------+
                                         |
                +------------------------+------------------------+
                |                                                 |
                v                                                 v
   [manifest_signer_key]                             [audit_checkpoint_signer_key]
   Asymmetric ECDSA P-256                            Asymmetric ECDSA P-256
                |                                                 |
     +----------+----------+                                      |
     |                     |                                      |
     v                     v                                      v
roles/cloudkms.signer   roles/cloudkms.verifier          roles/cloudkms.signer
(sa-biometrics-notary)  roles/cloudkms.publicKeyViewer   (sa-biometrics-audit-notary)
                        (sa-biometrics-verifier)
```

---

### 3. Verification & IAM Comparison

| Principal | Role Assigned | Permitted Cloud KMS Methods | Prohibited Methods |
| :--- | :--- | :--- | :--- |
| **`sa-biometrics-audit-notary`** | `roles/cloudkms.signer` | `cloudkms.cryptoKeyVersions.useToSign`<br>`cloudkms.cryptoKeys.get` | ❌ `cloudkms.cryptoKeys.create`<br>❌ `cloudkms.cryptoKeys.destroy`<br>❌ `cloudkms.cryptoKeyVersions.destroy` |
| **`sa-biometrics-verifier`** | `roles/cloudkms.verifier` | `cloudkms.cryptoKeyVersions.useToVerify`<br>`cloudkms.cryptoKeys.get` | ❌ `cloudkms.cryptoKeyVersions.useToSign` (CANNOT SIGN!) |
| **`sa-biometrics-verifier`** | `roles/cloudkms.publicKeyViewer` | `cloudkms.cryptoKeyVersions.viewPublicKey`<br>`cloudkms.cryptoKeys.get` | ❌ `cloudkms.cryptoKeyVersions.useToSign` (CANNOT SIGN!) |
| **`sa-biometrics-reviewer`** | *None on KMS* | None | ❌ Zero access to KMS keys |
| **`sa-biometrics-inventory`** | `roles/cloudkms.publicKeyViewer` | `cloudkms.cryptoKeyVersions.viewPublicKey` | ❌ `cloudkms.cryptoKeyVersions.useToSign`<br>❌ `cloudkms.cryptoKeyVersions.useToDecrypt` |

---

### 4. Policy-as-Code & Adversarial Test Validation

Policy-as-Code rule **POL-12** inspects every IAM binding against Cloud KMS keys:
```typescript
// backend/src/services/terraform_policy_as_code_v15.ts (POL-12)
if (binding.role === 'roles/cloudkms.signerVerifier') {
  evaluations.push({
    policyId: 'POL-12',
    name: 'Cloud KMS Signer vs Verifier Role Separation',
    passed: false,
    severity: 'CRITICAL',
    message: `Violation: Combined role roles/cloudkms.signerVerifier assigned to ${binding.member}. Must be split into roles/cloudkms.signer and roles/cloudkms.verifier.`
  });
}
```

In `phase20_15_infrastructure_assurance.test.ts`:
- **Test 14** verifies that `sa-biometrics-audit-notary` has `roles/cloudkms.signer` and fails if `signerVerifier` is bound.
- **Test 31** verifies that `sa-biometrics-verifier` has `roles/cloudkms.verifier`, not `roles/cloudkms.signer`.

### 5. Conclusion

The separation of signing and verification roles eliminates privilege escalation paths between the biometric verifier and the audit notary. Public key verification remains fully operational while the private signing capability remains sealed in Cloud KMS HSM.
