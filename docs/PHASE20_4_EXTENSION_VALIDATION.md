# PHASE 20.4 ATTESTATION EXTENSION VALIDATION
## Structured ASN.1 DER Validation of Android Key Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17)

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Target Release:** Phase 20.4 (Independent Device Attestation & Trust-Chain Validation Engine)  
**Parent Phase 20.3 Commit:** `6f8a0c91e509d26ce7fab26bfe554cc902cc599f`  

---

## 1. ASN.1 DER SCHEMA DEFINITION (OID 1.3.6.1.4.1.11129.2.1.17)

According to the Android Key Attestation specification, the extension contains the `KeyDescription` sequence:

```asn1
KeyDescription ::= SEQUENCE {
    attestationVersion         INTEGER,
    attestationSecurityLevel   SecurityLevel,
    keymasterVersion           INTEGER,
    keymasterSecurityLevel     SecurityLevel,
    attestationChallenge       OCTET_STRING,
    uniqueId                   OCTET_STRING,
    softwareEnforced           AuthorizationList,
    hardwareEnforced           AuthorizationList,
}

SecurityLevel ::= ENUMERATED {
    Software                   (0),
    TrustedEnvironment         (1),
    StrongBox                  (2),
}

AuthorizationList ::= SEQUENCE {
    purpose                    [1] EXPLICIT SET OF INTEGER OPTIONAL,
    algorithm                  [2] EXPLICIT INTEGER OPTIONAL,
    keySize                    [3] EXPLICIT INTEGER OPTIONAL,
    digest                     [5] EXPLICIT SET OF INTEGER OPTIONAL,
    padding                    [6] EXPLICIT SET OF INTEGER OPTIONAL,
    ecCurve                    [10] EXPLICIT INTEGER OPTIONAL,
    rsaPublicExponent          [200] EXPLICIT INTEGER OPTIONAL,
    rollbackResistance         [303] EXPLICIT NULL OPTIONAL,
    activeDateTime             [400] EXPLICIT INTEGER OPTIONAL,
    originationExpireDateTime  [401] EXPLICIT INTEGER OPTIONAL,
    usageExpireDateTime        [402] EXPLICIT INTEGER OPTIONAL,
    noAuthRequired             [503] EXPLICIT NULL OPTIONAL,
    userAuthType               [504] EXPLICIT INTEGER OPTIONAL,
    authTimeout                [505] EXPLICIT INTEGER OPTIONAL,
    allowWhileOnBody           [506] EXPLICIT NULL OPTIONAL,
    trustedUserPresenceRequired [507] EXPLICIT NULL OPTIONAL,
    trustedConfirmationRequired [508] EXPLICIT NULL OPTIONAL,
    unlockedDeviceRequired     [509] EXPLICIT NULL OPTIONAL,
    allApplications            [600] EXPLICIT NULL OPTIONAL,
    applicationId              [601] EXPLICIT OCTET_STRING OPTIONAL,
    creationDateTime           [701] EXPLICIT INTEGER OPTIONAL,
    origin                     [702] EXPLICIT INTEGER OPTIONAL,
    rootOfTrust                [704] EXPLICIT RootOfTrust OPTIONAL,
    osVersion                  [705] EXPLICIT INTEGER OPTIONAL,
    osPatchLevel               [706] EXPLICIT INTEGER OPTIONAL,
    attestationApplicationId   [709] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdBrand         [710] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdDevice        [711] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdProduct       [712] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdSerial        [713] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdImei          [714] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdMeid          [715] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdManufacturer  [716] EXPLICIT OCTET_STRING OPTIONAL,
    attestationIdModel         [717] EXPLICIT OCTET_STRING OPTIONAL,
    vendorPatchLevel           [718] EXPLICIT INTEGER OPTIONAL,
    bootPatchLevel             [719] EXPLICIT INTEGER OPTIONAL,
}

RootOfTrust ::= SEQUENCE {
    verifiedBootKey            OCTET_STRING,
    deviceLocked               BOOLEAN,
    verifiedBootState          VerifiedBootState,
    verifiedBootHash           OCTET_STRING,
}

VerifiedBootState ::= ENUMERATED {
    Verified                   (0),
    SelfSigned                 (1),
    Unverified                 (2),
    Failed                     (3),
}
```

---

## 2. PARSING & POSITION VALIDATION INVARIANTS

### Multi-Byte ASN.1 Context-Specific Tags
Context tags $\ge 31$ in ASN.1 BER/DER are encoded with initial byte `0xBF` (`101 11111_2` = Context-Specific Constructed) followed by variable-length base-128 continuation octets:
- **Tag 702 (Origin)**: `0xBF 0x85 0x3E`
- **Tag 704 (RootOfTrust)**: `0xBF 0x85 0x40`
- **Tag 705 (OSVersion)**: `0xBF 0x85 0x41`
- **Tag 706 (OSPatchLevel)**: `0xBF 0x85 0x42`
- **Tag 709 (AttestationApplicationId)**: `0xBF 0x85 0x45`
- **Tag 718 (VendorPatchLevel)**: `0xBF 0x85 0x4E`
- **Tag 719 (BootPatchLevel)**: `0xBF 0x85 0x4F`

The upgraded verifier (`device_key_attestation.ts`) decodes multi-byte tag headers properly, resolving the critical parsing limitation present in legacy zero-dependency implementations.

### Certificate-Chain Position Validation
1. **Search for First Trusted Occurrence**: Does not assume the extension is strictly on index 0 (leaf). Scans the certificate chain sequentially from index 0 upwards.
2. **Untrusted Extension Rejection**: If an attestation extension appears in a root certificate or an untrusted self-signed stub, the certificate chain is rejected immediately.
3. **Challenge Match Verification**: The `attestationChallenge` extracted from `KeyDescription` is compared byte-for-byte against the expected registration challenge.
4. **Hardware vs Software Enforced Authorization**: Verifies whether security-critical authorizations (`purpose`, `algorithm`, `origin`, `rootOfTrust`) originate from the `hardwareEnforced` sequence rather than `softwareEnforced`.
