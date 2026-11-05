# PHASE 20.6 SOURCE IMAGE MANIFEST
## Physical Source Frame Inventory, Verification Results, and Canonical Provenance Schema

**Project:** Kelasagara Major Project  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-1:2021 & ISO/IEC 29794-5  
**Audit Status:** AUDITED — MISSING PHYSICAL CORPUS (GATE BLOCKED)  

---

## 1. PHYSICAL DISK AUDIT SUMMARY

An automated search and integrity check was executed against all 1,350 expected capture frames:

| Metric | Target / Expected | Physically Observed | Discrepancy |
| :--- | :--- | :--- | :--- |
| **Unique Human Participants** | 50 (`PER-001` .. `PER-050`) | 0 physical individuals | -50 |
| **Capture Sessions** | 450 (3 sessions per subject) | 0 physical sessions | -450 |
| **Raw Image Frames** | 1,350 (3 frames per burst) | 0 physical image files | -1,350 |
| **Physical Storage Volume** | ~4.2 GB (estimated @ 3.1 MB/frame) | 0 bytes | -4.2 GB |
| **Integrity Check Result** | 100% SHA-256 verification | 0 files available to hash | **FAILED CLOSED** |

---

## 2. SOURCE FRAME RECORD SCHEMA SPECIFICATION

To ensure complete provenance tracking for the future physical pilot capture (Phase 20.6.10), every acquired image frame must strictly conform to the following privacy-preserving, zero-PII metadata schema:

```json
{
  "$schema": "https://kelasagara.org/schemas/biometrics/v20.6/frame-manifest.json",
  "protocolVersion": "20.6.0-pilot",
  "frameRecordId": "REC-C-0024-S01-F02",
  "opaqueParticipantId": "SUBJ-C-0024",
  "opaqueSessionId": "SESS-C-0024-20261102T0915Z",
  "opaqueCaptureId": "CAPT-C-0024-001",
  "partition": "HOLDOUT_C",
  "imageMetadata": {
    "fileSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "encoding": "image/jpeg",
    "width": 1920,
    "height": 1080,
    "colorSpace": "sRGB",
    "byteSize": 1248590
  },
  "acquisitionMetadata": {
    "captureTimestampUtc": "2026-11-02T09:15:22.451Z",
    "deviceProfile": "MID_1080P_AUTOFOCUS",
    "sensorManufacturer": "Sony IMX586",
    "focalLengthMm": 4.75,
    "exposureTimeSec": 0.02,
    "isoEquivalent": 200
  },
  "environmentalCondition": {
    "lightingRegime": "INDOOR_UNIFORM",
    "ambientLux": 380,
    "screenFillActive": false,
    "userGlasses": false,
    "userHeadCover": false
  },
  "governance": {
    "consentDocumentHash": "d41d8cd98f00b204e9800998ecf8427e",
    "retentionPurgeDate": "2026-12-15T00:00:00Z"
  }
}
```

### Prohibited Fields (Strictly Excluded):
- Participant legal names.
- Personal phone numbers or email addresses.
- Government identifiers (Aadhaar, PAN, Voter ID).
- Plaintext participant contact details.
- Direct mapping to production Firebase User UIDs (`auth.uid`).

---

## 3. VERIFICATION PROTOCOL RULES

When physical frames are loaded into the pipeline during the controlled pilot, the verification engine enforces:

1. **Existence Verification:** Rejects session if any of the 3 burst frames (`F00`, `F01`, `F02`) does not physically exist.
2. **Cryptographic Checksum:** Re-computes SHA-256 over raw file bytes; rejects if digest deviates from manifest.
3. **Duplicate Detection:** Computes pairwise SHA-256 digests across all frames; flags any bit-for-bit duplicate files as synthetic repetition or capture freeze.
4. **Partition Exclusivity:** Verifies that no `opaqueParticipantId` appears in more than one partition (`DEVELOPMENT_A`, `CALIBRATION_B`, or `HOLDOUT_C`).
5. **Frame Consistency:** Evaluates cosine similarity between Frame 0 and Frame 2 using SFace; rejects if similarity $< 0.80$ (detects physical subject substitution during capture).
6. **Consent Verification:** Asserts that `consentDocumentHash` exists in the local offline signed consent ledger prior to ingesting frames.

---

## 4. CURRENT REPOSITORY STATUS

- **Physical Frames Found:** `0 / 1,350`
- **Integrity Status:** `UNAVAILABLE_MISSING_RAW_IMAGES`
- **Dataset Acceptance Gate:** **BLOCKED**
- **Action Taken:** The evaluation pipeline has been equipped with `verifySourceCorpusAvailability()` in `backend/src/biometric-evaluation/dataset_manifest.ts`, which automatically detects missing physical files and activates the Provenance Reporting Guard.
