# PHASE 20.11: GALLERY ISOLATION & DEDUPLICATION ARCHITECTURE
**Role:** Backend Security Engineer & Biometric Systems Architect  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. BACKGROUND & PROBLEM STATEMENT

Prior to Phase 20.11, when an applicant submitted a face capture for biometric registration, `FirestoreCompatibleGalleryIndex` iterated across existing documents in `biometric_vault`. For documents containing `biometricEnvelope`, `canonicalEmbedding`, or `sfaceEmbedding128`, it computed cosine similarity against the applicant's probe vector regardless of how that stored template had been preprocessed.

Because pre-hotfix enrollments squashed full camera scenes directly to 112x112 without facial alignment, their 128-D vectors captured background wall textures, lighting gradients, and clothing colors rather than invariant facial identity features. When compared against genuine applicant faces, the background vectors produced spurious similarity values in the range of 0.48 to 0.58, which exceeded the historical duplicate threshold (0.550) and falsely locked out innocent workers.

---

## 2. THE GALLERY ISOLATION ARCHITECTURE

Phase 20.11 implements strict gallery isolation at the candidate evaluation layer:

```
                  ┌──────────────────────────────────────────────┐
                  │ New Applicant Probe (Canonical V2 SFace 128) │
                  └──────────────────────┬───────────────────────┘
                                         │
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │     FirestoreCompatibleGalleryIndex Query    │
                  └──────────────────────┬───────────────────────┘
                                         │
               ┌─────────────────────────┴─────────────────────────┐
               │                                                   │
               ▼                                                   ▼
   [Template Classification]                           [Status Guard]
   Is embeddingSpaceId ==                              Is status == 'ACTIVE'?
   CANONICAL_EMBEDDING_SPACE_V2?                       If not, skip.
               │
       ┌───────┴───────┐
       │               │
      YES              NO
       │               │
       ▼               ▼
[Compare SFace]   [NEVER_COMPARE]
Cosine similarity Candidate skipped before
evaluated.        cosine calculation.
                  Zero cross-space pollution.
```

---

## 3. IMPLEMENTATION IN `FirestoreCompatibleGalleryIndex`

```typescript
// Workstream B & C: Strict Embedding Space Isolation
// INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE
const classification = classifyBiometricTemplate(data);

// Space 1: Canonical SFace Deep Neural Space (V2)
if (classification === 'CANONICAL_V2') {
  // Evaluated strictly against probeEmbedding128
  // Thresholds: Clean < 0.3630, Hard Duplicate >= 0.7200
  ...
}

// Space 2: Legacy Geometric Landmark Space
if (classification === 'LEGACY_LANDMARK_SPACE' && params.probeLandmarkVector128) {
  // Evaluated ONLY if probe specifically supplies landmark coordinates
  ...
}

// Space 3: DEFECTIVE_FULL_PHOTO_SFACE_V10 or LEGACY_TEMPLATE_UNKNOWN
// RULE: INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE
// Strictly skipped to prevent false duplicate collisions.
```

---

## 4. VERIFICATION EVIDENCE

This isolation mechanism was verified in test scenario `Scenario 4 & 5` of `phase20_11_legacy_template_isolation.test.ts`:
- A mixed gallery consisting of:
  1. `enr_legacy_landmark_1` (Legacy landmark)
  2. `enr_defective_sface_2` (Defective full-photo resize)
  3. `enr_unknown_3` (Unknown legacy record)
  4. `enr_canonical_v2_4` (Canonical V2 template)
- When queried with a Canonical V2 probe, the index filtered out candidates 1, 2, and 3 completely, evaluating ONLY candidate 4.
- Result: **0 false duplicates, 100% space isolation.**
