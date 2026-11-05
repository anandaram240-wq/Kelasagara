# KELASAGARA V18: Gate G-01 De-Identified Dataset Manifest Validation Report

- **Document ID:** `KLS-V18-G01-MANIFEST-VALIDATION`
- **Schema Identifier:** `https://kelasagaara.in/schemas/biometric-calibration-manifest-v18.json`
- **Schema Version:** `18.1.0`
- **Production Biometric Calibration Approved:** `false`
- **Deployment Gate Mode:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. Manifest Schema & Strict Field Allowlist

The Gate G-01 manifest validator enforces a recursive closed-schema allowlist across four structural levels. Any unexpected property at any level immediately aborts validation with `DISALLOWED_MANIFEST_FIELD`.

| Object Level | Allowed Keys | Validation Rules |
| :--- | :--- | :--- |
| **Root (`$`)** | `schemaId`, `schemaVersion`, `provenance`, `records` | `schemaId` and `schemaVersion` must match exact constants; `records` must be a non-empty array. |
| **Provenance (`$.provenance`)** | `datasetId`, `collectionProtocolId`, `lawfulUseReference`, `ethicsApprovalId`, `deIdentificationMethod`, `authorizedByRole`, `createdAtIso` | All fields required, non-empty alphanumeric/token syntax (`^[A-Za-z0-9_./:\-]{4,128}$`), valid ISO-8601 `createdAtIso`. |
| **Record (`$.records[i]`)** | `imageId`, `subjectId`, `sessionId`, `partition`, `relativePath`, `sha256`, `captureMetadata` | `imageId` (`^IMG_[A-Z0-9_]{4,64}$`), `subjectId` (`^SUBJ_[A-Z0-9]{6,32}$`), `sessionId` (`^SESS_[A-Z0-9]{6,32}$`), `partition` in `calibration`, `validation`, `evaluation`. |
| **Capture Metadata (`$.records[i].captureMetadata`)** | `poseYawDeg`, `posePitchDeg`, `poseRollDeg`, `occlusionRatio`, `isoQualityScore`, `illuminationLux` | Optional finite numbers; `occlusionRatio` in `[0.0, 1.0]`, `isoQualityScore` in `[0.0, 100.0]`, `poseYawDeg` in `[-90, 90]`. |

---

## 2. Security, Path Confinement & Privacy Guarantees

### 2.1 Path Confinement & Symlink Escape Prevention
- **No Traversal or Absolute Paths:** Rejects Windows backslashes, null bytes, leading slashes, drive letters, and any path segment containing `..` or `...`.
- **Component-by-Component Symlink Inspection:** `resolveAndVerifyConfinedImagePath()` verifies that `datasetRoot` itself is a real directory and calls `fs.lstatSync()` on every directory and file hop from `realpathSync(datasetRoot)` down to the image file, rejecting any symbolic link (`SYMLINK_ESCAPE_REJECTED`) or resolved path escaping the root (`PATH_CONFINEMENT_VIOLATION`).
- **Magic-Byte Header Verification:** `verifyImageFileAndComputeSha256()` checks that each image is a regular file within size limits (`128 B` to `15 MB`) and verifies binary magic headers (`FF D8 FF` for JPEG, `89 50 4E 47 0D 0A 1A 0A` for PNG, and `RIFF....WEBP` for WebP) against the file extension.

### 2.2 Recursive PII Denylist & Redacted Error Reporting
- `scanForForbiddenPiiKeysRecursive()` walks the entire parsed JSON tree prior to schema evaluation and rejects prohibited personal-information keys (`name`, `fullName`, `phone`, `phoneNumber`, `email`, `aadhaar`, `pan`, `ssn`, `rrn`, `myNumber`, `passport`, `firebaseUid`, `uid`, `address`, `notes`, `comments`, `freeText`, `biometricRaw`) at any nesting depth.
- String values are also screened against email, phone number, and production `KLS-` UID patterns.
- **Zero-Echo Redaction:** Error messages report only the JSON path and key name, never echoing raw field values or image bytes into logs or test outputs.

### 2.3 Subject & Session Split Integrity
- **Partition Disjointness:** No `subjectId` or `sessionId` may appear in more than one partition (`calibration`, `validation`, `evaluation`).
- **Session Ownership Consistency:** A `sessionId` cannot be associated with more than one `subjectId`.
- **Single-Session Warning:** Emits a `SESSION_PROTOCOL_WARNING` if any subject has captures from only a single session, alerting evaluators to potential optimistic intra-session FNMR bias.

---

## 3. Deterministic Integrity Digest Specification

`validateAndLoadCalibrationManifest()` produces a reproducible `DatasetIntegrityDigest` containing:
1. **`provenanceSha256`:** SHA-256 over canonical JSON (sorted keys) of `schemaId`, `schemaVersion`, and `provenance`.
2. **`metadataSha256` (per record):** SHA-256 over canonical JSON of `imageId`, `subjectId`, `sessionId`, `partition`, `canonicalRelativePath`, and `captureMetadata`.
3. **`imageSha256` (per record):** SHA-256 over the raw binary bytes of the verified image file on disk.
4. **`recordsMerkleRootSha256`:** SHA-256 over all record entries sorted lexicographically by `imageId`, formatted as:
   `imageId|subjectId|sessionId|partition|canonicalRelativePath|byteSize|imageSha256|metadataSha256\n`
5. **`masterIntegritySha256`:** `SHA256(provenanceSha256 + ":" + recordsMerkleRootSha256)`. Any modification to a single pixel, path, subject assignment, partition label, or provenance field alters `masterIntegritySha256`.

---

## 4. Legal & Technical Limitations

1. **Pseudonymity Is Not Anonymity:** Replacing worker names and phone numbers with `SUBJ_*` tokens does not make a facial image dataset anonymous. Facial images and derived biometric templates remain sensitive personal data under the India Digital Personal Data Protection Act (DPDPA) 2023 and ISO/IEC 24745.
2. **Provenance String Is Not Legal Proof:** Recording `lawfulUseReference` and `ethicsApprovalId` provides audit traceability (`RECORDED_PROVENANCE_REFERENCE_ONLY_NOT_LEGAL_PROOF`) but does not substitute for human legal and ethics verification of informed consent records.
3. **Validator Tests vs. Biometric Calibration Validation:** Passing the 23 software unit tests verifies the mathematical harness and manifest security rules only. Population-level biometric accuracy remains `NOT VALIDATED` until executed on an authorized, de-identified multi-session human dataset.
