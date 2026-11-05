# KELASAGARA ROLLBACK PLAN
## HOTFIX CANONICAL SFACE PREPROCESSING, DEDUPLICATION & PRIVACY CORRECTION

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Parent Commit:** `56ea479` (on `security/phase20.10-capture-wire-verification`)  
**Protected Tag:** `v19.2.3-release`  
**Protected Tag Hash:** `8634a1813c84fccc73b8944803b6bd541f5e2326`  
**Protected Release APK SHA-256:** `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`  
**Date:** November 1, 2026

---

## 1. PURPOSE

This document defines the emergency rollback procedure in the unlikely event that unexpected regressions or operational anomalies arise following deployment of the canonical SFace preprocessing hotfix.

---

## 2. PRE-REQUISITES & SAFETY CHECKS

1. Verify that the current repository state is clean:
   ```bash
   cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"
   git status
   ```
2. Verify that the protected tag `v19.2.3-release` has not been altered:
   ```bash
   git rev-parse v19.2.3-release
   # Expected output: 8634a1813c84fccc73b8944803b6bd541f5e2326
   ```
3. Verify that the protected APK checksum remains unchanged:
   ```bash
   shasum -a 256 "/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk"
   # Expected output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce
   ```

---

## 3. ROLLBACK PROCEDURES

### Scenario A: Rollback Branch to Parent Commit
If an issue occurs before merging to main, reset the hotfix branch directly to parent commit `56ea479`:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"
git checkout security/hotfix-canonical-face-preprocessing
git reset --hard 56ea479
cd backend
npm run build
npm test
```

### Scenario B: Emergency Reversion of Merged Hotfix Commit
If the hotfix was already merged into a release branch, create a clean revert commit:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"
git revert <HOTFIX_COMMIT_HASH> -m 1 --no-edit
cd backend
npm run build
npm test
```

### Scenario C: Standalone Rollback of Specific Subsystems

#### 1. Reverting Backend Face Preprocessing Only
If server-side YuNet detection needs to be temporarily bypassed in a sandbox test:
- In `backend/src/routes/biometric_v10_routes.ts`:
  Restore the previous route delegate or pass a mock detector into `extractCanonicalEmbeddingFromOriginalImage`.
- Rebuild backend:
  ```bash
  cd backend && npm run build
  ```

#### 2. Reverting Flutter Client UI Only
If `DuplicateAccountResolutionSheet` needs adjustments:
- Inspect `lib/screens/auth/face_enrollment_screen.dart:1125`.
- Note: NEVER re-introduce PII leakage (`maskedPhone`, `maskedName`, `primarySkill`, `dailyRateDisplay`, `facialSimilarityPercent`) into client dialogs.

---

## 4. DATABASE INTEGRITY & DATA RECOVERY

1. **No Destructive Database Changes:** This hotfix did not perform database migrations or schema alterations. All biometric templates in `biometric_vault` and user records in `users` remain 100% compatible.
2. **Review Queue Integrity:** Any ambiguous review cases opened during the hotfix window remain intact in the `biometric_duplicate_cases` collection under their unique `CASE-XXXXXXXX` reference IDs for human review.

---

## 5. POST-ROLLBACK VERIFICATION CHECKLIST

- [ ] All 844 baseline backend tests pass: `cd backend && npm test`
- [ ] Flutter analysis passes: `flutter analyze`
- [ ] Protected tag `v19.2.3-release` remains intact
- [ ] Protected APK SHA-256 remains `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`
- [ ] ONNX model files and hashes remain verified
