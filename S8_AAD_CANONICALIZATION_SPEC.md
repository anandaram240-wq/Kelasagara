# S8 AAD CANONICALIZATION SPECIFICATION

**Protocol:** Kelasagara BioMatch Canonical Authenticated Data Format  
**Version:** `BIOMATCH_AAD_V1`  
**Standard Compliance:** NIST SP 800-38D (AES-GCM), ISO/IEC 24745 (Biometric Template Protection)  
**Remediation Target:** Vulnerability GAP-03 (Field-shifting delimiter collisions)  

---

## 1. Vulnerability Analysis of Legacy Format
Under Stage S7 (`v2_aad_gcm`), Additional Authenticated Data was encoded as:
$$\text{AAD}_{\text{v2}} = \texttt{\$\{envelopeVersion\}|\$\{tenantId\}|\$\{uid\}|\$\{keyVersion\}}$$
Because the pipe character `|` was not escaped, an adversary controlling tenant names or user handles could construct collision pairs:
- Candidate A: `tenantId = "tenant1|user"`, `uid = "123"` $\to \texttt{v2_aad_gcm|tenant1|user|123|k1}$
- Candidate B: `tenantId = "tenant1"`, `uid = "user|123"` $\to \texttt{v2_aad_gcm|tenant1|user|123|k1}$

Because the byte representations were identical, a ciphertext generated for Candidate A could be accepted as a valid biometric template for Candidate B in a cross-tenant / cross-user attack.

---

## 2. Canonical Binary Length-Prefixed Specification
In Stage S8, canonical AAD uses an unambiguous, length-prefixed binary structure with explicit domain separation.

### Wire Layout:
```
+---------------------------------------+
| Magic Domain Header: "BIOMATCH_AAD_V1"| (15 bytes, ASCII)
+---------------------------------------+
| Field Count: 0x05                     | (1 byte, UInt8)
+---------------------------------------+
| Tag: 0x01 (ENVELOPE_VERSION)          | (1 byte, UInt8)
| Length: N1                            | (2 bytes, UInt16BE)
| Value: UTF-8 Bytes                    | (N1 bytes)
+---------------------------------------+
| Tag: 0x02 (TENANT_ID)                 | (1 byte, UInt8)
| Length: N2                            | (2 bytes, UInt16BE)
| Value: UTF-8 Bytes                    | (N2 bytes)
+---------------------------------------+
| Tag: 0x03 (UID)                       | (1 byte, UInt8)
| Length: N3                            | (2 bytes, UInt16BE)
| Value: UTF-8 Bytes                    | (N3 bytes)
+---------------------------------------+
| Tag: 0x04 (KEY_VERSION)               | (1 byte, UInt8)
| Length: N4                            | (2 bytes, UInt16BE)
| Value: UTF-8 Bytes                    | (N4 bytes)
+---------------------------------------+
| Tag: 0x05 (PURPOSE)                   | (1 byte, UInt8)
| Length: N5                            | (2 bytes, UInt16BE)
| Value: UTF-8 Bytes                    | (N5 bytes)
+---------------------------------------+
```

### Invariants Guaranteed:
1. **Uniqueness:** Field length prefixing ensures that no combination of field values can shift across boundaries.
2. **Domain Separation:** Leading magic string `"BIOMATCH_AAD_V1"` prevents cross-protocol reuse of ciphertexts.
3. **Bound Purpose:** Explicit inclusion of `TAG_PURPOSE` (e.g. `BIOMETRIC_AUTH_V1` vs `BIOMETRIC_RECOVERY_V1`) prevents cross-action ciphertext substitution.
