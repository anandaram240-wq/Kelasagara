// File: backend/src/scripts/calibration_harness.ts
// KELASAGARA V18 — GATE G-01: De-Identified Dataset Manifest Validator & Dual-Subspace Calibration Harness
// Standards: ISO/IEC 19795-1 (Biometric Performance Testing), ISO/IEC 24745 & India DPDPA 2023

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';

export const PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED = false as const;
export const DEPLOYMENT_GATE_MODE = 'CONTROLLED_TEST_BUILD_ONLY' as const;

export const SFACE_DIMENSION = 128 as const;
export const LANDMARK_V3_FULL_DIMENSION = 512 as const;
export const LANDMARK_V3_PERI_DIMENSION = 256 as const;

export const CANONICAL_SFACE_THRESHOLDS = {
  verify1to1: 0.363,
  duplicateWarning: 0.74,
  hardBlock: 0.90,
} as const;

export const MANIFEST_SCHEMA_ID =
  'https://kelasagaara.in/schemas/biometric-calibration-manifest-v18.json' as const;
export const MANIFEST_SCHEMA_VERSION = '18.1.0' as const;

export const MIN_IMAGE_BYTES = 128 as const;
export const MAX_IMAGE_BYTES = 15 * 1024 * 1024; // 15 MB ceiling

export type ManifestPartitionLabel = 'calibration' | 'validation' | 'evaluation';
export type DatasetPartition = 'CALIBRATION' | 'VALIDATION' | 'HELD_OUT_EVAL';

export type EvaluationTrackId =
  | 'TRACK_A_SFACE_BASELINE'
  | 'TRACK_B_LANDMARK_V3_EXPERIMENTAL'
  | 'TRACK_C_CALIBRATED_LLR_FUSION';

export type ValidationStatus =
  | 'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED'
  | 'INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR'
  | 'EMPIRICALLY_VALIDATED';

// ============================================================================
// PART 1: MANIFEST SCHEMA, ALLOWLISTS & PRIVACY / INTEGRITY INTERFACES
// ============================================================================

export interface DatasetProvenanceMetadata {
  readonly datasetId: string;
  readonly collectionProtocolId: string;
  readonly lawfulUseReference: string;
  readonly ethicsApprovalId: string;
  readonly deIdentificationMethod: string;
  readonly authorizedByRole: string;
  readonly createdAtIso: string;
}

export interface ManifestCaptureMetadata {
  readonly poseYawDeg?: number;
  readonly posePitchDeg?: number;
  readonly poseRollDeg?: number;
  readonly occlusionRatio?: number;
  readonly isoQualityScore?: number;
  readonly illuminationLux?: number;
}

export interface ManifestImageRecord {
  readonly imageId: string;
  readonly subjectId: string;
  readonly sessionId: string;
  readonly partition: ManifestPartitionLabel;
  readonly relativePath: string;
  readonly sha256?: string;
  readonly captureMetadata?: ManifestCaptureMetadata;
}

export interface CalibrationDatasetManifestV18 {
  readonly schemaId: typeof MANIFEST_SCHEMA_ID;
  readonly schemaVersion: typeof MANIFEST_SCHEMA_VERSION;
  readonly provenance: DatasetProvenanceMetadata;
  readonly records: readonly ManifestImageRecord[];
}

export interface VerifiedImageIntegrityEntry {
  readonly imageId: string;
  readonly subjectId: string;
  readonly sessionId: string;
  readonly partition: ManifestPartitionLabel;
  readonly canonicalRelativePath: string;
  readonly format: 'JPEG' | 'PNG' | 'WEBP';
  readonly byteSize: number;
  readonly imageSha256: string;
  readonly metadataSha256: string;
}

export interface DatasetIntegrityDigest {
  readonly schemaId: typeof MANIFEST_SCHEMA_ID;
  readonly schemaVersion: typeof MANIFEST_SCHEMA_VERSION;
  readonly datasetId: string;
  readonly lawfulUseReference: string;
  readonly provenanceNote: 'RECORDED_PROVENANCE_REFERENCE_ONLY_NOT_LEGAL_PROOF';
  readonly deIdentificationNote: 'PSEUDONYMOUS_BIOMETRIC_DATA_REMAINS_PERSONAL_DATA_UNDER_DPDPA';
  readonly totalRecords: number;
  readonly partitionSubjectCounts: Record<ManifestPartitionLabel, number>;
  readonly partitionImageCounts: Record<ManifestPartitionLabel, number>;
  readonly provenanceSha256: string;
  readonly recordsMerkleRootSha256: string;
  readonly masterIntegritySha256: string;
  readonly entries: readonly VerifiedImageIntegrityEntry[];
  readonly warnings: readonly string[];
}

export interface ValidatedManifestLoadResult {
  readonly manifest: CalibrationDatasetManifestV18;
  readonly integrityDigest: DatasetIntegrityDigest;
  readonly resolvedRecords: ReadonlyArray<{
    readonly record: ManifestImageRecord;
    readonly mappedPartition: DatasetPartition;
    readonly resolvedRealPath: string;
    readonly imageSha256: string;
  }>;
}

const TOP_LEVEL_ALLOWLIST = new Set<string>([
  'schemaId',
  'schemaVersion',
  'provenance',
  'records',
]);

const PROVENANCE_ALLOWLIST = new Set<string>([
  'datasetId',
  'collectionProtocolId',
  'lawfulUseReference',
  'ethicsApprovalId',
  'deIdentificationMethod',
  'authorizedByRole',
  'createdAtIso',
]);

const RECORD_ALLOWLIST = new Set<string>([
  'imageId',
  'subjectId',
  'sessionId',
  'partition',
  'relativePath',
  'sha256',
  'captureMetadata',
]);

const CAPTURE_METADATA_ALLOWLIST = new Set<string>([
  'poseYawDeg',
  'posePitchDeg',
  'poseRollDeg',
  'occlusionRatio',
  'isoQualityScore',
  'illuminationLux',
]);

/**
 * Explicit denylist of PII and sensitive identifier property names at any nesting level.
 * Values are NEVER echoed in error messages to prevent leaking PII into logs.
 */
const FORBIDDEN_PII_KEY_NAMES = new Set<string>([
  'name',
  'fullname',
  'firstname',
  'lastname',
  'givenname',
  'surname',
  'phone',
  'phonenumber',
  'mobile',
  'mobilenumber',
  'contact',
  'email',
  'emailaddress',
  'aadhaar',
  'aadhar',
  'uidai',
  'pan',
  'pannumber',
  'ssn',
  'rrn',
  'mynumber',
  'passport',
  'passportnumber',
  'voterid',
  'drivinglicense',
  'dlnumber',
  'firebaseuid',
  'uid',
  'userid',
  'accountuid',
  'workeruid',
  'address',
  'street',
  'pincode',
  'dob',
  'dateofbirth',
  'notes',
  'comment',
  'comments',
  'freetext',
  'rawtext',
  'description',
  'biometricraw',
]);

const PSEUDONYMOUS_IMAGE_ID_REGEX = /^IMG_[A-Z0-9_]{4,64}$/;
const PSEUDONYMOUS_SUBJECT_ID_REGEX = /^SUBJ_[A-Z0-9]{6,32}$/;
const PSEUDONYMOUS_SESSION_ID_REGEX = /^SESS_[A-Z0-9]{6,32}$/;
const SHA256_HEX_REGEX = /^[a-fA-F0-9]{64}$/;
const SAFE_PROVENANCE_TOKEN_REGEX = /^[A-Za-z0-9_./:\-]{4,128}$/;

// Value-level PII patterns (checked without ever logging the matched substring)
const EMAIL_VALUE_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_VALUE_REGEX = /^(?:\+?\d{1,3}[\s-]?)?[6-9]\d{9}$/;
const PROD_KLS_UID_REGEX = /^KLS-[A-Za-z0-9*_-]{4,}$/i;

/**
 * Maps manifest partition labels ('calibration' | 'validation' | 'evaluation')
 * to the internal evaluation harness partition enum.
 */
export function mapManifestPartitionToInternal(
  partition: ManifestPartitionLabel,
): DatasetPartition {
  switch (partition) {
    case 'calibration':
      return 'CALIBRATION';
    case 'validation':
      return 'VALIDATION';
    case 'evaluation':
      return 'HELD_OUT_EVAL';
    default: {
      const exhaustive: never = partition;
      throw new Error(`Unsupported partition label: ${String(exhaustive)}`);
    }
  }
}

/**
 * Recursively scans an arbitrary parsed JSON value for prohibited PII keys at every nesting level.
 * Never logs or echoes any field values.
 */
export function scanForForbiddenPiiKeysRecursive(
  node: unknown,
  jsonPath = '$',
  depth = 0,
): void {
  if (depth > 16) {
    throw new Error(`Manifest JSON nesting depth exceeds maximum limit at ${jsonPath}`);
  }
  if (node === null || typeof node !== 'object') {
    return;
  }
  if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i++) {
      scanForForbiddenPiiKeysRecursive(node[i], `${jsonPath}[${i}]`, depth + 1);
    }
    return;
  }

  const obj = node as Record<string, unknown>;
  for (const rawKey of Object.keys(obj)) {
    const normalizedKey = rawKey.replace(/[\s_-]/g, '').toLowerCase();
    const childPath = `${jsonPath}.${rawKey}`;

    if (FORBIDDEN_PII_KEY_NAMES.has(normalizedKey)) {
      throw new Error(
        `PROHIBITED_PII_KEY: Forbidden personal-information key "${rawKey}" detected at ${childPath}. Raw value redacted.`,
      );
    }

    scanForForbiddenPiiKeysRecursive(obj[rawKey], childPath, depth + 1);
  }
}

/**
 * Enforces an explicit key allowlist on a JSON object.
 */
function enforceKeyAllowlist(
  obj: Record<string, unknown>,
  allowlist: ReadonlySet<string>,
  contextPath: string,
): void {
  for (const key of Object.keys(obj)) {
    if (!allowlist.has(key)) {
      throw new Error(
        `DISALLOWED_MANIFEST_FIELD: Unexpected field "${key}" at ${contextPath} is not in the schema allowlist.`,
      );
    }
  }
}

/**
 * Checks string values for prohibited PII patterns (emails, phone numbers, production KLS UIDs)
 * without echoing the sensitive value in error messages.
 */
function assertNotPiiValue(val: string, fieldPath: string): void {
  const trimmed = val.trim();
  if (EMAIL_VALUE_REGEX.test(trimmed)) {
    throw new Error(
      `PROHIBITED_PII_VALUE: Value at ${fieldPath} matches an email address pattern. Value redacted.`,
    );
  }
  if (PHONE_VALUE_REGEX.test(trimmed)) {
    throw new Error(
      `PROHIBITED_PII_VALUE: Value at ${fieldPath} matches a phone number pattern. Value redacted.`,
    );
  }
  if (PROD_KLS_UID_REGEX.test(trimmed)) {
    throw new Error(
      `PROHIBITED_PII_VALUE: Value at ${fieldPath} matches a production Kelasagaara account UID pattern. Value redacted.`,
    );
  }
}

/**
 * Confines a relative image path strictly within datasetRoot, rejecting absolute paths,
 * '..' or '...' traversal segments, backslashes, and symbolic links at any path component.
 */
export function resolveAndVerifyConfinedImagePath(
  datasetRoot: string,
  relativePath: string,
  recordIndex: number,
): { resolvedRealPath: string; canonicalRelativePath: string } {
  const fieldPath = `records[${recordIndex}].relativePath`;

  if (typeof relativePath !== 'string' || relativePath.trim().length === 0) {
    throw new Error(`INVALID_IMAGE_PATH: Empty relativePath at ${fieldPath}.`);
  }
  if (relativePath.includes('\0')) {
    throw new Error(`INVALID_IMAGE_PATH: Null byte in relativePath at ${fieldPath}.`);
  }
  if (relativePath.includes('\\')) {
    throw new Error(
      `INVALID_IMAGE_PATH: Backslash separator not permitted in ${fieldPath}. Use POSIX forward slashes.`,
    );
  }
  if (
    path.isAbsolute(relativePath) ||
    relativePath.startsWith('/') ||
    /^[a-zA-Z]:/.test(relativePath)
  ) {
    throw new Error(
      `PATH_TRAVERSAL_REJECTED: Absolute path is forbidden at ${fieldPath}.`,
    );
  }

  const segments = relativePath.split('/');
  for (const seg of segments) {
    if (seg === '' || seg === '.' || seg === '..' || seg.includes('..')) {
      throw new Error(
        `PATH_TRAVERSAL_REJECTED: Disallowed path traversal segment "${seg}" in ${fieldPath}.`,
      );
    }
  }

  if (!fs.existsSync(datasetRoot)) {
    throw new Error('DATASET_ROOT_MISSING: Configured datasetRoot does not exist.');
  }
  const rootStat = fs.lstatSync(datasetRoot);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    throw new Error(
      'DATASET_ROOT_INVALID: Configured datasetRoot must be a real directory and not a symbolic link.',
    );
  }
  const canonicalRoot = fs.realpathSync(datasetRoot);

  // Walk every component from canonicalRoot down to the target file and reject symlinks at every hop
  let currentPath = canonicalRoot;
  for (let i = 0; i < segments.length; i++) {
    currentPath = path.join(currentPath, segments[i]);
    if (!fs.existsSync(currentPath)) {
      throw new Error(
        `IMAGE_FILE_MISSING: Referenced image file does not exist at ${fieldPath}.`,
      );
    }
    const stat = fs.lstatSync(currentPath);
    if (stat.isSymbolicLink()) {
      throw new Error(
        `SYMLINK_ESCAPE_REJECTED: Symbolic link detected along path at ${fieldPath}.`,
      );
    }
  }

  const resolvedRealPath = fs.realpathSync(currentPath);
  const relFromRoot = path.relative(canonicalRoot, resolvedRealPath);
  if (
    relFromRoot.startsWith('..') ||
    path.isAbsolute(relFromRoot) ||
    relFromRoot === ''
  ) {
    throw new Error(
      `PATH_CONFINEMENT_VIOLATION: Resolved path escapes authorized datasetRoot at ${fieldPath}.`,
    );
  }

  return {
    resolvedRealPath,
    canonicalRelativePath: segments.join('/'),
  };
}

/**
 * Inspects file size, extension, and magic-byte header signatures (JPEG, PNG, WEBP),
 * and computes the file's SHA-256 hex digest.
 */
export function verifyImageFileAndComputeSha256(
  resolvedRealPath: string,
  canonicalRelativePath: string,
  recordIndex: number,
  options?: { minBytes?: number; maxBytes?: number },
): { format: 'JPEG' | 'PNG' | 'WEBP'; byteSize: number; sha256: string } {
  const fieldPath = `records[${recordIndex}].relativePath`;
  const stat = fs.statSync(resolvedRealPath);
  if (!stat.isFile()) {
    throw new Error(
      `INVALID_IMAGE_FILE: Target at ${fieldPath} is not a regular file.`,
    );
  }

  const minBytes = options?.minBytes ?? MIN_IMAGE_BYTES;
  const maxBytes = options?.maxBytes ?? MAX_IMAGE_BYTES;
  if (stat.size < minBytes || stat.size > maxBytes) {
    throw new Error(
      `IMAGE_SIZE_OUT_OF_BOUNDS: File at ${fieldPath} has size ${stat.size} bytes (allowed range: ${minBytes}..${maxBytes} bytes).`,
    );
  }

  const ext = path.extname(canonicalRelativePath).toLowerCase();
  if (ext !== '.jpg' && ext !== '.jpeg' && ext !== '.png' && ext !== '.webp') {
    throw new Error(
      `INVALID_IMAGE_FORMAT: Unsupported file extension "${ext}" at ${fieldPath}. Allowed: .jpg, .jpeg, .png, .webp.`,
    );
  }

  const buf = fs.readFileSync(resolvedRealPath);
  let detectedFormat: 'JPEG' | 'PNG' | 'WEBP' | null = null;

  // JPEG magic bytes: FF D8 FF
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    detectedFormat = 'JPEG';
  }
  // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
  else if (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47 &&
    buf[4] === 0x0d &&
    buf[5] === 0x0a &&
    buf[6] === 0x1a &&
    buf[7] === 0x0a
  ) {
    detectedFormat = 'PNG';
  }
  // WEBP magic bytes: "RIFF" [4-byte size] "WEBP"
  else if (
    buf.length >= 12 &&
    buf[0] === 0x52 &&
    buf[1] === 0x49 &&
    buf[2] === 0x46 &&
    buf[3] === 0x46 &&
    buf[8] === 0x57 &&
    buf[9] === 0x45 &&
    buf[10] === 0x42 &&
    buf[11] === 0x50
  ) {
    detectedFormat = 'WEBP';
  }

  if (detectedFormat === null) {
    throw new Error(
      `INVALID_IMAGE_MAGIC_BYTES: File header at ${fieldPath} does not match valid JPEG, PNG, or WEBP magic bytes.`,
    );
  }

  if (
    (ext === '.jpg' || ext === '.jpeg') &&
    detectedFormat !== 'JPEG'
  ) {
    throw new Error(
      `IMAGE_FORMAT_MISMATCH: Extension "${ext}" does not match magic header "${detectedFormat}" at ${fieldPath}.`,
    );
  }
  if (ext === '.png' && detectedFormat !== 'PNG') {
    throw new Error(
      `IMAGE_FORMAT_MISMATCH: Extension ".png" does not match magic header "${detectedFormat}" at ${fieldPath}.`,
    );
  }
  if (ext === '.webp' && detectedFormat !== 'WEBP') {
    throw new Error(
      `IMAGE_FORMAT_MISMATCH: Extension ".webp" does not match magic header "${detectedFormat}" at ${fieldPath}.`,
    );
  }

  const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
  return {
    format: detectedFormat,
    byteSize: stat.size,
    sha256,
  };
}

/**
 * Computes a deterministic SHA-256 hex digest of a canonical JSON structure with sorted keys.
 */
function sha256CanonicalJson(obj: Record<string, unknown>): string {
  const sortedKeys = Object.keys(obj).sort();
  const canonical: Record<string, unknown> = {};
  for (const k of sortedKeys) {
    canonical[k] = obj[k];
  }
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(canonical), 'utf8')
    .digest('hex');
}

/**
 * Validates a raw JSON manifest string or parsed object against the Gate G-01 v18 specification,
 * verifies all referenced image files inside datasetRoot, checks subject/session split integrity,
 * and returns a deterministic DatasetIntegrityDigest.
 */
export function validateAndLoadCalibrationManifest(
  rawJsonOrObject: string | unknown,
  datasetRoot: string,
  options?: { minImageBytes?: number; maxImageBytes?: number },
): ValidatedManifestLoadResult {
  let parsed: unknown;
  if (typeof rawJsonOrObject === 'string') {
    if (rawJsonOrObject.trim().length === 0) {
      throw new Error('MALFORMED_MANIFEST_JSON: Manifest JSON string is empty.');
    }
    try {
      parsed = JSON.parse(rawJsonOrObject);
    } catch {
      throw new Error('MALFORMED_MANIFEST_JSON: Failed to parse manifest JSON.');
    }
  } else {
    parsed = rawJsonOrObject;
  }

  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('INVALID_MANIFEST_ROOT: Manifest root must be a JSON object.');
  }

  // 1. Scan entire JSON tree for prohibited PII keys at every nesting level first
  scanForForbiddenPiiKeysRecursive(parsed, '$', 0);

  const rootObj = parsed as Record<string, unknown>;
  enforceKeyAllowlist(rootObj, TOP_LEVEL_ALLOWLIST, '$');

  // 2. Validate Schema ID & Version
  if (rootObj.schemaId !== MANIFEST_SCHEMA_ID) {
    throw new Error(
      `INVALID_SCHEMA_ID: Expected schemaId "${MANIFEST_SCHEMA_ID}", got "${String(rootObj.schemaId)}".`,
    );
  }
  if (rootObj.schemaVersion !== MANIFEST_SCHEMA_VERSION) {
    throw new Error(
      `INVALID_SCHEMA_VERSION: Expected schemaVersion "${MANIFEST_SCHEMA_VERSION}", got "${String(rootObj.schemaVersion)}".`,
    );
  }

  // 3. Validate Provenance & Lawful-Use Reference
  if (
    rootObj.provenance === null ||
    typeof rootObj.provenance !== 'object' ||
    Array.isArray(rootObj.provenance)
  ) {
    throw new Error('MISSING_PROVENANCE: Manifest requires a valid "provenance" object.');
  }
  const provObj = rootObj.provenance as Record<string, unknown>;
  enforceKeyAllowlist(provObj, PROVENANCE_ALLOWLIST, '$.provenance');

  for (const reqKey of PROVENANCE_ALLOWLIST) {
    const val = provObj[reqKey];
    if (typeof val !== 'string' || val.trim().length < 4) {
      throw new Error(
        `INVALID_PROVENANCE_FIELD: Field "provenance.${reqKey}" must be a non-empty string.`,
      );
    }
    assertNotPiiValue(val, `$.provenance.${reqKey}`);
    if (reqKey !== 'createdAtIso' && !SAFE_PROVENANCE_TOKEN_REGEX.test(val)) {
      throw new Error(
        `INVALID_PROVENANCE_TOKEN: Field "provenance.${reqKey}" contains disallowed free-text characters.`,
      );
    }
  }

  const createdDate = Date.parse(String(provObj.createdAtIso));
  if (!Number.isFinite(createdDate)) {
    throw new Error(
      'INVALID_PROVENANCE_DATE: Field "provenance.createdAtIso" must be a valid ISO-8601 timestamp.',
    );
  }

  const provenance: DatasetProvenanceMetadata = {
    datasetId: String(provObj.datasetId),
    collectionProtocolId: String(provObj.collectionProtocolId),
    lawfulUseReference: String(provObj.lawfulUseReference),
    ethicsApprovalId: String(provObj.ethicsApprovalId),
    deIdentificationMethod: String(provObj.deIdentificationMethod),
    authorizedByRole: String(provObj.authorizedByRole),
    createdAtIso: String(provObj.createdAtIso),
  };

  // 4. Validate Records Array
  if (!Array.isArray(rootObj.records) || rootObj.records.length === 0) {
    throw new Error('EMPTY_MANIFEST_RECORDS: Manifest "records" must be a non-empty array.');
  }

  const seenImageIds = new Set<string>();
  const seenRelativePaths = new Set<string>();
  const subjectToPartition = new Map<string, ManifestPartitionLabel>();
  const sessionToPartition = new Map<string, ManifestPartitionLabel>();
  const sessionToSubject = new Map<string, string>();
  const subjectSessions = new Map<string, Set<string>>();

  const partitionSubjSets: Record<ManifestPartitionLabel, Set<string>> = {
    calibration: new Set<string>(),
    validation: new Set<string>(),
    evaluation: new Set<string>(),
  };
  const partitionImageCounts: Record<ManifestPartitionLabel, number> = {
    calibration: 0,
    validation: 0,
    evaluation: 0,
  };

  const validatedRecords: ManifestImageRecord[] = [];
  const integrityEntries: VerifiedImageIntegrityEntry[] = [];
  const resolvedRecords: Array<{
    readonly record: ManifestImageRecord;
    readonly mappedPartition: DatasetPartition;
    readonly resolvedRealPath: string;
    readonly imageSha256: string;
  }> = [];

  for (let i = 0; i < rootObj.records.length; i++) {
    const rawRec = rootObj.records[i];
    const recPath = `$.records[${i}]`;
    if (rawRec === null || typeof rawRec !== 'object' || Array.isArray(rawRec)) {
      throw new Error(`INVALID_RECORD: Record at ${recPath} must be an object.`);
    }

    const recObj = rawRec as Record<string, unknown>;
    enforceKeyAllowlist(recObj, RECORD_ALLOWLIST, recPath);

    const imageId = recObj.imageId;
    const subjectId = recObj.subjectId;
    const sessionId = recObj.sessionId;
    const partition = recObj.partition;
    const relativePath = recObj.relativePath;

    if (typeof imageId !== 'string' || !PSEUDONYMOUS_IMAGE_ID_REGEX.test(imageId)) {
      throw new Error(
        `INVALID_IMAGE_ID: ${recPath}.imageId must match pseudonymous format ^IMG_[A-Z0-9_]{4,64}$.`,
      );
    }
    assertNotPiiValue(imageId, `${recPath}.imageId`);
    if (seenImageIds.has(imageId)) {
      throw new Error(`DUPLICATE_IMAGE_ID: Duplicate imageId "${imageId}" at ${recPath}.`);
    }
    seenImageIds.add(imageId);

    if (
      typeof subjectId !== 'string' ||
      !PSEUDONYMOUS_SUBJECT_ID_REGEX.test(subjectId)
    ) {
      throw new Error(
        `INVALID_SUBJECT_ID: ${recPath}.subjectId must match pseudonymous format ^SUBJ_[A-Z0-9]{6,32}$.`,
      );
    }
    assertNotPiiValue(subjectId, `${recPath}.subjectId`);

    if (
      typeof sessionId !== 'string' ||
      !PSEUDONYMOUS_SESSION_ID_REGEX.test(sessionId)
    ) {
      throw new Error(
        `INVALID_SESSION_ID: ${recPath}.sessionId must match pseudonymous format ^SESS_[A-Z0-9]{6,32}$.`,
      );
    }
    assertNotPiiValue(sessionId, `${recPath}.sessionId`);

    if (
      partition !== 'calibration' &&
      partition !== 'validation' &&
      partition !== 'evaluation'
    ) {
      throw new Error(
        `INVALID_PARTITION: ${recPath}.partition must be one of "calibration", "validation", or "evaluation".`,
      );
    }

    // Subject separation across partitions
    const priorSubjPart = subjectToPartition.get(subjectId);
    if (priorSubjPart && priorSubjPart !== partition) {
      throw new Error(
        `SUBJECT_PARTITION_LEAKAGE: subjectId "${subjectId}" appears in both "${priorSubjPart}" and "${partition}" at ${recPath}.`,
      );
    }
    subjectToPartition.set(subjectId, partition);

    // Session separation across partitions and single-subject ownership per session
    const priorSessPart = sessionToPartition.get(sessionId);
    if (priorSessPart && priorSessPart !== partition) {
      throw new Error(
        `SESSION_PARTITION_LEAKAGE: sessionId "${sessionId}" appears in both "${priorSessPart}" and "${partition}" at ${recPath}.`,
      );
    }
    sessionToPartition.set(sessionId, partition);

    const priorSessSubj = sessionToSubject.get(sessionId);
    if (priorSessSubj && priorSessSubj !== subjectId) {
      throw new Error(
        `CONTRADICTORY_SESSION_SUBJECT: sessionId "${sessionId}" is assigned to both "${priorSessSubj}" and "${subjectId}" at ${recPath}.`,
      );
    }
    sessionToSubject.set(sessionId, subjectId);

    if (!subjectSessions.has(subjectId)) {
      subjectSessions.set(subjectId, new Set<string>());
    }
    subjectSessions.get(subjectId)!.add(sessionId);

    // Validate optional captureMetadata
    let captureMetadata: ManifestCaptureMetadata | undefined;
    if (recObj.captureMetadata !== undefined) {
      if (
        recObj.captureMetadata === null ||
        typeof recObj.captureMetadata !== 'object' ||
        Array.isArray(recObj.captureMetadata)
      ) {
        throw new Error(`INVALID_CAPTURE_METADATA: ${recPath}.captureMetadata must be an object.`);
      }
      const metaObj = recObj.captureMetadata as Record<string, unknown>;
      enforceKeyAllowlist(
        metaObj,
        CAPTURE_METADATA_ALLOWLIST,
        `${recPath}.captureMetadata`,
      );

      for (const mKey of Object.keys(metaObj)) {
        const mVal = metaObj[mKey];
        if (typeof mVal !== 'number' || !Number.isFinite(mVal)) {
          throw new Error(
            `INVALID_CAPTURE_METADATA_VALUE: ${recPath}.captureMetadata.${mKey} must be a finite number.`,
          );
        }
      }

      if (
        metaObj.occlusionRatio !== undefined &&
        ((metaObj.occlusionRatio as number) < 0.0 ||
          (metaObj.occlusionRatio as number) > 1.0)
      ) {
        throw new Error(
          `CONTRADICTORY_METADATA: ${recPath}.captureMetadata.occlusionRatio must be in [0.0, 1.0].`,
        );
      }
      if (
        metaObj.isoQualityScore !== undefined &&
        ((metaObj.isoQualityScore as number) < 0.0 ||
          (metaObj.isoQualityScore as number) > 100.0)
      ) {
        throw new Error(
          `CONTRADICTORY_METADATA: ${recPath}.captureMetadata.isoQualityScore must be in [0.0, 100.0].`,
        );
      }
      if (
        metaObj.poseYawDeg !== undefined &&
        Math.abs(metaObj.poseYawDeg as number) > 90.0
      ) {
        throw new Error(
          `CONTRADICTORY_METADATA: ${recPath}.captureMetadata.poseYawDeg exceeds [-90, 90] degrees.`,
        );
      }

      captureMetadata = {
        poseYawDeg: metaObj.poseYawDeg as number | undefined,
        posePitchDeg: metaObj.posePitchDeg as number | undefined,
        poseRollDeg: metaObj.poseRollDeg as number | undefined,
        occlusionRatio: metaObj.occlusionRatio as number | undefined,
        isoQualityScore: metaObj.isoQualityScore as number | undefined,
        illuminationLux: metaObj.illuminationLux as number | undefined,
      };
    }

    // Resolve and verify confined image path & symlink safety
    const { resolvedRealPath, canonicalRelativePath } =
      resolveAndVerifyConfinedImagePath(datasetRoot, String(relativePath), i);

    if (seenRelativePaths.has(canonicalRelativePath)) {
      throw new Error(
        `DUPLICATE_IMAGE_PATH: Duplicate relativePath "${canonicalRelativePath}" referenced at ${recPath}.`,
      );
    }
    seenRelativePaths.add(canonicalRelativePath);

    // Verify image existence, format, size, magic bytes, and compute actual SHA-256
    const fileVerification = verifyImageFileAndComputeSha256(
      resolvedRealPath,
      canonicalRelativePath,
      i,
      {
        minBytes: options?.minImageBytes,
        maxBytes: options?.maxImageBytes,
      },
    );

    if (recObj.sha256 !== undefined) {
      if (typeof recObj.sha256 !== 'string' || !SHA256_HEX_REGEX.test(recObj.sha256)) {
        throw new Error(
          `INVALID_SHA256_FORMAT: ${recPath}.sha256 must be a 64-character hexadecimal string.`,
        );
      }
      if (recObj.sha256.toLowerCase() !== fileVerification.sha256.toLowerCase()) {
        throw new Error(
          `IMAGE_SHA256_MISMATCH: Checksum mismatch for ${imageId} at ${recPath}. Expected ${recObj.sha256.toLowerCase()}, computed ${fileVerification.sha256}.`,
        );
      }
    }

    const cleanRecord: ManifestImageRecord = {
      imageId,
      subjectId,
      sessionId,
      partition,
      relativePath: canonicalRelativePath,
      sha256: fileVerification.sha256,
      captureMetadata,
    };
    validatedRecords.push(cleanRecord);

    partitionSubjSets[partition].add(subjectId);
    partitionImageCounts[partition] += 1;

    const metadataSha256 = sha256CanonicalJson({
      imageId,
      subjectId,
      sessionId,
      partition,
      canonicalRelativePath,
      captureMetadata: captureMetadata ?? null,
    });

    integrityEntries.push({
      imageId,
      subjectId,
      sessionId,
      partition,
      canonicalRelativePath,
      format: fileVerification.format,
      byteSize: fileVerification.byteSize,
      imageSha256: fileVerification.sha256,
      metadataSha256,
    });

    resolvedRecords.push({
      record: cleanRecord,
      mappedPartition: mapManifestPartitionToInternal(partition),
      resolvedRealPath,
      imageSha256: fileVerification.sha256,
    });
  }

  // Sort integrity entries deterministically by imageId so identical dataset contents
  // always produce bit-identical Merkle & Master hashes regardless of record ordering
  const sortedEntries = [...integrityEntries].sort((a, b) =>
    a.imageId.localeCompare(b.imageId),
  );

  const provenanceSha256 = sha256CanonicalJson({
    schemaId: MANIFEST_SCHEMA_ID,
    schemaVersion: MANIFEST_SCHEMA_VERSION,
    ...provenance,
  });

  const merkleHasher = crypto.createHash('sha256');
  for (const entry of sortedEntries) {
    merkleHasher.update(
      `${entry.imageId}|${entry.subjectId}|${entry.sessionId}|${entry.partition}|${entry.canonicalRelativePath}|${entry.byteSize}|${entry.imageSha256}|${entry.metadataSha256}\n`,
      'utf8',
    );
  }
  const recordsMerkleRootSha256 = merkleHasher.digest('hex');

  const masterIntegritySha256 = crypto
    .createHash('sha256')
    .update(`${provenanceSha256}:${recordsMerkleRootSha256}`, 'utf8')
    .digest('hex');

  const warnings: string[] = [
    'PRIVACY_NOTICE: Pseudonymous subject/session IDs do not render facial biometric data anonymous. Handle all manifest artifacts under DPDPA 2023 and ISO/IEC 24745 access controls.',
    'PROVENANCE_NOTICE: lawfulUseReference is recorded as provenance metadata only and does not constitute independent legal verification.',
  ];

  let singleSessionSubjects = 0;
  for (const [, sessSet] of subjectSessions) {
    if (sessSet.size < 2) {
      singleSessionSubjects++;
    }
  }
  if (singleSessionSubjects > 0) {
    warnings.push(
      `SESSION_PROTOCOL_WARNING: ${singleSessionSubjects} subject(s) have captures from only a single sessionId. Cross-session genuine trials are recommended to avoid optimistic FNMR bias.`,
    );
  }

  const integrityDigest: DatasetIntegrityDigest = {
    schemaId: MANIFEST_SCHEMA_ID,
    schemaVersion: MANIFEST_SCHEMA_VERSION,
    datasetId: provenance.datasetId,
    lawfulUseReference: provenance.lawfulUseReference,
    provenanceNote: 'RECORDED_PROVENANCE_REFERENCE_ONLY_NOT_LEGAL_PROOF',
    deIdentificationNote:
      'PSEUDONYMOUS_BIOMETRIC_DATA_REMAINS_PERSONAL_DATA_UNDER_DPDPA',
    totalRecords: validatedRecords.length,
    partitionSubjectCounts: {
      calibration: partitionSubjSets.calibration.size,
      validation: partitionSubjSets.validation.size,
      evaluation: partitionSubjSets.evaluation.size,
    },
    partitionImageCounts,
    provenanceSha256,
    recordsMerkleRootSha256,
    masterIntegritySha256,
    entries: sortedEntries,
    warnings,
  };

  return {
    manifest: {
      schemaId: MANIFEST_SCHEMA_ID,
      schemaVersion: MANIFEST_SCHEMA_VERSION,
      provenance,
      records: validatedRecords,
    },
    integrityDigest,
    resolvedRecords,
  };
}

/**
 * CLI-level gate that validates the manifest file on disk BEFORE invoking feature extraction
 * or ROC/DET calibration. Any manifest or file error halts before `extractEmbeddingsForRecord` is called.
 */
export async function runCalibrationCliWithManifestValidation(params: {
  readonly manifestFilePath: string;
  readonly datasetRoot: string;
  readonly extractEmbeddingsForRecord: (resolved: {
    readonly record: ManifestImageRecord;
    readonly resolvedRealPath: string;
    readonly imageSha256: string;
  }) => Promise<{
    readonly isSyntheticData: boolean;
    readonly sfaceEmbedding128?: Float32Array;
    readonly landmarkFull512?: Float32Array;
    readonly landmarkPeri256?: Float32Array;
  }>;
  readonly enableFusionTrack?: boolean;
  readonly bootstrapIterations?: number;
  readonly randomSeed?: number;
}): Promise<{
  readonly integrityDigest: DatasetIntegrityDigest;
  readonly calibrationReport: V18CalibrationSuiteReport;
}> {
  if (!fs.existsSync(params.manifestFilePath)) {
    throw new Error('MANIFEST_FILE_MISSING: Specified manifestFilePath does not exist.');
  }
  const rawManifestText = fs.readFileSync(params.manifestFilePath, 'utf8');

  // Gate 1: Strict manifest, path confinement, magic-byte, PII, and SHA-256 validation
  // Fails immediately before any model inference if invalid.
  const validated = validateAndLoadCalibrationManifest(
    rawManifestText,
    params.datasetRoot,
  );

  // Gate 2: Extract embeddings only for verified, confined records
  const sampleRecords: BiometricSampleRecord[] = [];
  for (const item of validated.resolvedRecords) {
    const extracted = await params.extractEmbeddingsForRecord({
      record: item.record,
      resolvedRealPath: item.resolvedRealPath,
      imageSha256: item.imageSha256,
    });

    sampleRecords.push({
      sampleId: item.record.imageId,
      subjectId: item.record.subjectId,
      sessionId: item.record.sessionId,
      partition: item.mappedPartition,
      isSyntheticData: extracted.isSyntheticData,
      sfaceEmbedding128: extracted.sfaceEmbedding128,
      landmarkFull512: extracted.landmarkFull512,
      landmarkPeri256: extracted.landmarkPeri256,
      occlusionRatio: item.record.captureMetadata?.occlusionRatio,
      isoQualityScore: item.record.captureMetadata?.isoQualityScore,
    });
  }

  // Gate 3: Run multi-track ROC/DET evaluation
  const calibrationReport = runV18DualSubspaceCalibrationSuite(sampleRecords, {
    enableFusionTrack: params.enableFusionTrack,
    bootstrapIterations: params.bootstrapIterations,
    randomSeed: params.randomSeed,
  });

  return {
    integrityDigest: validated.integrityDigest,
    calibrationReport,
  };
}

// ============================================================================
// PART 2: EXISTING V18 DUAL-SUBSPACE CALIBRATION HARNESS
// ============================================================================

export interface BiometricSampleRecord {
  readonly sampleId: string;
  readonly subjectId: string;
  readonly sessionId: string;
  readonly partition: DatasetPartition;
  readonly isSyntheticData: boolean;
  readonly sfaceEmbedding128?: Float32Array | readonly number[];
  readonly landmarkFull512?: Float32Array | readonly number[];
  readonly landmarkPeri256?: Float32Array | readonly number[];
  readonly occlusionRatio?: number;
  readonly isoQualityScore?: number;
}

export interface ConfidenceInterval95 {
  readonly pointEstimate: number;
  readonly lower95: number;
  readonly upper95: number;
}

export interface RocDetOperatingPoint {
  readonly threshold: number;
  readonly fmr: number;
  readonly fnmr: number;
  readonly fmrWilson95: ConfidenceInterval95;
  readonly fnmrWilson95: ConfidenceInterval95;
  readonly fmrClusterBootstrap95: ConfidenceInterval95;
  readonly fnmrClusterBootstrap95: ConfidenceInterval95;
  readonly falseMatches: number;
  readonly falseNonMatches: number;
}

export interface ScoreDistributionSummary {
  readonly count: number;
  readonly mean: number;
  readonly stdDev: number;
  readonly min: number;
  readonly p05: number;
  readonly p50: number;
  readonly p95: number;
  readonly max: number;
}

export interface SelectedThresholds {
  readonly verify1to1: number;
  readonly duplicateWarning: number;
  readonly hardBlock: number;
  readonly monotonicValid: boolean;
}

export interface CalibratedFusionParameters {
  readonly intercept: number;
  readonly weightSface: number;
  readonly weightLandmarkFull: number;
  readonly weightLandmarkPeri: number;
  readonly weightQualityInteraction: number;
  readonly fittedOnGenuinePairs: number;
  readonly fittedOnImpostorPairs: number;
}

export interface TrackEvaluationReport {
  readonly trackId: EvaluationTrackId;
  readonly enabled: boolean;
  readonly disabledReason?: string;
  readonly validationStatus: ValidationStatus;
  readonly warnings: readonly string[];
  readonly subjectCount: number;
  readonly sampleCount: number;
  readonly genuineTrialCount: number;
  readonly impostorTrialCount: number;
  readonly genuineDistribution: ScoreDistributionSummary | null;
  readonly impostorDistribution: ScoreDistributionSummary | null;
  readonly eerEstimate: number | null;
  readonly selectedThresholds: SelectedThresholds | null;
  readonly operatingPointsAtSelected: {
    readonly verify1to1: RocDetOperatingPoint;
    readonly duplicateWarning: RocDetOperatingPoint;
    readonly hardBlock: RocDetOperatingPoint;
  } | null;
  readonly rocSweep: readonly RocDetOperatingPoint[];
  readonly fusionParameters?: CalibratedFusionParameters;
}

export interface V18CalibrationSuiteReport {
  readonly schemaVersion: 'v18.1.0';
  readonly productionBiometricCalibrationApproved: false;
  readonly deploymentGateMode: typeof DEPLOYMENT_GATE_MODE;
  readonly datasetContainsSyntheticVectors: boolean;
  readonly overallValidationStatus: ValidationStatus;
  readonly partitionCounts: Record<
    DatasetPartition,
    { subjects: number; samples: number }
  >;
  readonly tracks: {
    readonly trackA_SFace: TrackEvaluationReport;
    readonly trackB_LandmarkV3: TrackEvaluationReport;
    readonly trackC_DualFusion: TrackEvaluationReport;
  };
}

interface PairTrial {
  readonly sampleA: string;
  readonly sampleB: string;
  readonly subjectA: string;
  readonly subjectB: string;
  readonly sessionA: string;
  readonly sessionB: string;
  readonly isGenuine: boolean;
  readonly score: number;
}

interface RawPairFeatures {
  readonly subjectA: string;
  readonly subjectB: string;
  readonly sessionA: string;
  readonly sessionB: string;
  readonly isGenuine: boolean;
  readonly sfaceCos: number;
  readonly landmarkFullCos: number;
  readonly landmarkPeriCos: number;
  readonly maxOcclusion: number;
  readonly minQuality: number;
}

export function createDeterministicPrng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function computeWilsonScoreInterval95(
  k: number,
  n: number,
): ConfidenceInterval95 {
  if (!Number.isFinite(k) || !Number.isFinite(n) || n <= 0 || k < 0 || k > n) {
    throw new Error(`Invalid Wilson counts: k=${k}, n=${n}`);
  }

  const z = 1.959963984540054;
  const z2 = z * z;
  const pHat = k / n;
  const denom = 1.0 + z2 / n;
  const center = (pHat + z2 / (2.0 * n)) / denom;
  const halfWidth =
    (z * Math.sqrt((pHat * (1.0 - pHat)) / n + z2 / (4.0 * n * n))) / denom;

  const lower95 = k === 0 ? 0.0 : Math.max(0.0, center - halfWidth);
  const upper95 = k === n ? 1.0 : Math.min(1.0, center + halfWidth);

  return {
    pointEstimate: pHat,
    lower95: Number(lower95.toFixed(8)),
    upper95: Number(upper95.toFixed(8)),
  };
}

export function validateAndNormalizeEmbedding(
  raw: Float32Array | readonly number[] | undefined,
  expectedDim: number,
  label: string,
): Float32Array {
  if (!raw) {
    throw new Error(`Missing embedding for ${label}`);
  }
  if (raw.length !== expectedDim) {
    throw new Error(
      `Dimension mismatch for ${label}: expected ${expectedDim}, got ${raw.length}`,
    );
  }

  const out = new Float32Array(expectedDim);
  let normSq = 0.0;
  for (let i = 0; i < expectedDim; i++) {
    const val = raw[i];
    if (!Number.isFinite(val)) {
      throw new Error(`Non-finite value at index ${i} in ${label}`);
    }
    out[i] = val;
    normSq += val * val;
  }

  if (normSq < 1e-12) {
    throw new Error(`Zero-norm degenerate vector in ${label}`);
  }

  const invNorm = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < expectedDim; i++) {
    out[i] *= invNorm;
  }
  return out;
}

export function computeExactCosine(a: Float32Array, b: Float32Array): number {
  if (a.length !== b.length || a.length === 0) {
    throw new Error(
      `Incompatible vector dimensions in cosine: ${a.length} vs ${b.length}`,
    );
  }
  let dot = 0.0;
  let normA = 0.0;
  let normB = 0.0;
  for (let i = 0; i < a.length; i++) {
    const va = a[i];
    const vb = b[i];
    if (!Number.isFinite(va) || !Number.isFinite(vb)) {
      throw new Error(`Non-finite vector component at index ${i}`);
    }
    dot += va * vb;
    normA += va * va;
    normB += vb * vb;
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  if (denom < 1e-12 || !Number.isFinite(denom)) {
    throw new Error('Degenerate norm during cosine computation');
  }
  const cos = dot / denom;
  if (!Number.isFinite(cos)) {
    throw new Error('Non-finite cosine similarity score');
  }
  return Math.max(-1.0, Math.min(1.0, cos));
}

export function verifyPartitionDisjointness(
  samples: readonly BiometricSampleRecord[],
): void {
  if (samples.length === 0) {
    throw new Error('Calibration dataset is empty (0 samples provided).');
  }

  const subjectToPartition = new Map<string, DatasetPartition>();
  const sessionToPartition = new Map<string, DatasetPartition>();
  const sessionToSubject = new Map<string, string>();
  const seenSampleIds = new Set<string>();

  for (const s of samples) {
    if (!s.sampleId || !s.subjectId || !s.sessionId) {
      throw new Error(
        'Sample record has empty sampleId, subjectId, or sessionId.',
      );
    }
    if (seenSampleIds.has(s.sampleId)) {
      throw new Error(`Duplicate sampleId detected: ${s.sampleId}`);
    }
    seenSampleIds.add(s.sampleId);

    const existingSubjPart = subjectToPartition.get(s.subjectId);
    if (existingSubjPart && existingSubjPart !== s.partition) {
      throw new Error(
        `Subject leakage detected: subjectId '${s.subjectId}' appears in both ${existingSubjPart} and ${s.partition}.`,
      );
    }
    subjectToPartition.set(s.subjectId, s.partition);

    const existingSessPart = sessionToPartition.get(s.sessionId);
    if (existingSessPart && existingSessPart !== s.partition) {
      throw new Error(
        `Session leakage detected: sessionId '${s.sessionId}' appears in both ${existingSessPart} and ${s.partition}.`,
      );
    }
    sessionToPartition.set(s.sessionId, s.partition);

    const existingSessSubj = sessionToSubject.get(s.sessionId);
    if (existingSessSubj && existingSessSubj !== s.subjectId) {
      throw new Error(
        `Contradictory session ownership: sessionId '${s.sessionId}' linked to both '${existingSessSubj}' and '${s.subjectId}'.`,
      );
    }
    sessionToSubject.set(s.sessionId, s.subjectId);
  }
}

export function fitCalibratedLogisticFusion(
  calibrationPairs: readonly RawPairFeatures[],
): CalibratedFusionParameters {
  const genuines = calibrationPairs.filter((p) => p.isGenuine);
  const impostors = calibrationPairs.filter((p) => !p.isGenuine);

  if (genuines.length < 2 || impostors.length < 2) {
    throw new Error(
      `Insufficient CALIBRATION pairs to fit fusion model: genuine=${genuines.length}, impostor=${impostors.length}`,
    );
  }

  let b0 = -2.0;
  let wSface = 6.0;
  let wFull = 1.5;
  let wPeri = 1.5;
  let wInter = 1.0;

  const learningRate = 0.15;
  const l2Reg = 0.01;
  const iterations = 250;

  const posWeight = 0.5 / genuines.length;
  const negWeight = 0.5 / impostors.length;

  for (let iter = 0; iter < iterations; iter++) {
    let gradB0 = 0.0;
    let gradWSface = 0.0;
    let gradWFull = 0.0;
    let gradWPeri = 0.0;
    let gradWInter = 0.0;

    for (const p of calibrationPairs) {
      const occ = Math.max(0.0, Math.min(1.0, p.maxOcclusion));
      const x1 = p.sfaceCos;
      const x2 = (1.0 - occ) * p.landmarkFullCos;
      const x3 = occ * p.landmarkPeriCos;
      const x4 = p.sfaceCos * p.landmarkPeriCos;

      const z = b0 + wSface * x1 + wFull * x2 + wPeri * x3 + wInter * x4;
      const pred = 1.0 / (1.0 + Math.exp(-Math.max(-30.0, Math.min(30.0, z))));
      const target = p.isGenuine ? 1.0 : 0.0;
      const sampleWeight = p.isGenuine ? posWeight : negWeight;
      const err = (pred - target) * sampleWeight;

      gradB0 += err;
      gradWSface += err * x1;
      gradWFull += err * x2;
      gradWPeri += err * x3;
      gradWInter += err * x4;
    }

    b0 -= learningRate * gradB0;
    wSface -= learningRate * (gradWSface + l2Reg * wSface);
    wFull -= learningRate * (gradWFull + l2Reg * wFull);
    wPeri -= learningRate * (gradWPeri + l2Reg * wPeri);
    wInter -= learningRate * (gradWInter + l2Reg * wInter);
  }

  return {
    intercept: Number(b0.toFixed(6)),
    weightSface: Number(wSface.toFixed(6)),
    weightLandmarkFull: Number(wFull.toFixed(6)),
    weightLandmarkPeri: Number(wPeri.toFixed(6)),
    weightQualityInteraction: Number(wInter.toFixed(6)),
    fittedOnGenuinePairs: genuines.length,
    fittedOnImpostorPairs: impostors.length,
  };
}

export function scoreCalibratedFusionPair(
  pair: RawPairFeatures,
  params: CalibratedFusionParameters,
): number {
  const occ = Math.max(0.0, Math.min(1.0, pair.maxOcclusion));
  const x1 = pair.sfaceCos;
  const x2 = (1.0 - occ) * pair.landmarkFullCos;
  const x3 = occ * pair.landmarkPeriCos;
  const x4 = pair.sfaceCos * pair.landmarkPeriCos;

  const z =
    params.intercept +
    params.weightSface * x1 +
    params.weightLandmarkFull * x2 +
    params.weightLandmarkPeri * x3 +
    params.weightQualityInteraction * x4;

  if (!Number.isFinite(z)) {
    throw new Error('Non-finite fusion logit score');
  }
  const prob = 1.0 / (1.0 + Math.exp(-Math.max(-30.0, Math.min(30.0, z))));
  return Number(prob.toFixed(8));
}

export function computeSubjectClusterBootstrapAtThreshold(
  trials: readonly PairTrial[],
  threshold: number,
  bootstrapIterations = 200,
  seed = 0x18a0f00d,
): {
  fmrBootstrap95: ConfidenceInterval95;
  fnmrBootstrap95: ConfidenceInterval95;
} {
  const genuineTrials = trials.filter((t) => t.isGenuine);
  const impostorTrials = trials.filter((t) => !t.isGenuine);

  if (genuineTrials.length === 0 || impostorTrials.length === 0) {
    throw new Error(
      'Cannot compute bootstrap on empty genuine or impostor trial list.',
    );
  }

  const falseMatchesBase = impostorTrials.filter(
    (t) => t.score >= threshold,
  ).length;
  const falseNonMatchesBase = genuineTrials.filter(
    (t) => t.score < threshold,
  ).length;

  const baseFmr = falseMatchesBase / impostorTrials.length;
  const baseFnmr = falseNonMatchesBase / genuineTrials.length;

  const subjects = Array.from(
    new Set(trials.flatMap((t) => [t.subjectA, t.subjectB])),
  ).sort();

  const rng = createDeterministicPrng(seed);
  const fmrSamples: number[] = [];
  const fnmrSamples: number[] = [];

  for (let b = 0; b < bootstrapIterations; b++) {
    const subjectWeights = new Map<string, number>();
    for (let i = 0; i < subjects.length; i++) {
      const pick = subjects[Math.floor(rng() * subjects.length)];
      subjectWeights.set(pick, (subjectWeights.get(pick) ?? 0) + 1);
    }

    let impWeightTotal = 0.0;
    let impWeightErr = 0.0;
    for (const t of impostorTrials) {
      const wA = subjectWeights.get(t.subjectA) ?? 0;
      const wB = subjectWeights.get(t.subjectB) ?? 0;
      const w = 0.5 * (wA + wB);
      if (w > 0) {
        impWeightTotal += w;
        if (t.score >= threshold) impWeightErr += w;
      }
    }

    let genWeightTotal = 0.0;
    let genWeightErr = 0.0;
    for (const t of genuineTrials) {
      const w = subjectWeights.get(t.subjectA) ?? 0;
      if (w > 0) {
        genWeightTotal += w;
        if (t.score < threshold) genWeightErr += w;
      }
    }

    fmrSamples.push(
      impWeightTotal > 0 ? impWeightErr / impWeightTotal : baseFmr,
    );
    fnmrSamples.push(
      genWeightTotal > 0 ? genWeightErr / genWeightTotal : baseFnmr,
    );
  }

  fmrSamples.sort((a, b) => a - b);
  fnmrSamples.sort((a, b) => a - b);

  const loIdx = Math.max(0, Math.floor(0.025 * (bootstrapIterations - 1)));
  const hiIdx = Math.min(
    bootstrapIterations - 1,
    Math.ceil(0.975 * (bootstrapIterations - 1)),
  );

  return {
    fmrBootstrap95: {
      pointEstimate: Number(baseFmr.toFixed(8)),
      lower95: Number(fmrSamples[loIdx].toFixed(8)),
      upper95: Number(fmrSamples[hiIdx].toFixed(8)),
    },
    fnmrBootstrap95: {
      pointEstimate: Number(baseFnmr.toFixed(8)),
      lower95: Number(fnmrSamples[loIdx].toFixed(8)),
      upper95: Number(fnmrSamples[hiIdx].toFixed(8)),
    },
  };
}

export function evaluateOperatingPoint(
  trials: readonly PairTrial[],
  threshold: number,
  bootstrapIterations = 200,
  seed = 0x18a0f00d,
): RocDetOperatingPoint {
  if (!Number.isFinite(threshold)) {
    throw new Error(`Invalid non-finite threshold: ${threshold}`);
  }

  const genuineTrials = trials.filter((t) => t.isGenuine);
  const impostorTrials = trials.filter((t) => !t.isGenuine);

  if (genuineTrials.length === 0 || impostorTrials.length === 0) {
    throw new Error(
      `Both genuine (${genuineTrials.length}) and impostor (${impostorTrials.length}) trials must be non-empty.`,
    );
  }

  let falseMatches = 0;
  for (const t of impostorTrials) {
    if (!Number.isFinite(t.score)) {
      throw new Error('Non-finite score encountered in impostor trials.');
    }
    if (t.score >= threshold) falseMatches++;
  }

  let falseNonMatches = 0;
  for (const t of genuineTrials) {
    if (!Number.isFinite(t.score)) {
      throw new Error('Non-finite score encountered in genuine trials.');
    }
    if (t.score < threshold) falseNonMatches++;
  }

  const fmr = falseMatches / impostorTrials.length;
  const fnmr = falseNonMatches / genuineTrials.length;

  const fmrWilson95 = computeWilsonScoreInterval95(
    falseMatches,
    impostorTrials.length,
  );
  const fnmrWilson95 = computeWilsonScoreInterval95(
    falseNonMatches,
    genuineTrials.length,
  );

  const boot = computeSubjectClusterBootstrapAtThreshold(
    trials,
    threshold,
    bootstrapIterations,
    seed,
  );

  return {
    threshold: Number(threshold.toFixed(6)),
    fmr: Number(fmr.toFixed(8)),
    fnmr: Number(fnmr.toFixed(8)),
    fmrWilson95,
    fnmrWilson95,
    fmrClusterBootstrap95: boot.fmrBootstrap95,
    fnmrClusterBootstrap95: boot.fnmrBootstrap95,
    falseMatches,
    falseNonMatches,
  };
}

function summarizeDistribution(
  scores: readonly number[],
): ScoreDistributionSummary {
  if (scores.length === 0) {
    throw new Error('Cannot summarize empty score distribution.');
  }
  const sorted = [...scores].sort((a, b) => a - b);
  const n = sorted.length;
  let sum = 0.0;
  for (const s of sorted) {
    if (!Number.isFinite(s)) {
      throw new Error('Non-finite score in distribution summary.');
    }
    sum += s;
  }
  const mean = sum / n;
  let varSum = 0.0;
  for (const s of sorted) {
    const d = s - mean;
    varSum += d * d;
  }
  const stdDev = n > 1 ? Math.sqrt(varSum / (n - 1)) : 0.0;

  const quantile = (q: number) => {
    const pos = q * (n - 1);
    const lo = Math.floor(pos);
    const hi = Math.ceil(pos);
    const frac = pos - lo;
    return sorted[lo] * (1.0 - frac) + sorted[hi] * frac;
  };

  return {
    count: n,
    mean: Number(mean.toFixed(6)),
    stdDev: Number(stdDev.toFixed(6)),
    min: Number(sorted[0].toFixed(6)),
    p05: Number(quantile(0.05).toFixed(6)),
    p50: Number(quantile(0.5).toFixed(6)),
    p95: Number(quantile(0.95).toFixed(6)),
    max: Number(sorted[n - 1].toFixed(6)),
  };
}

export function selectMonotonicThresholdsFromValidation(
  validationTrials: readonly PairTrial[],
  minScore: number,
  maxScore: number,
): SelectedThresholds {
  const steps = 80;
  const stepSize = (maxScore - minScore) / steps;
  const grid: Array<{ threshold: number; fmr: number; fnmr: number }> = [];

  const genuines = validationTrials.filter((t) => t.isGenuine);
  const impostors = validationTrials.filter((t) => !t.isGenuine);

  for (let i = 0; i <= steps; i++) {
    const tau = minScore + i * stepSize;
    const fm = impostors.filter((t) => t.score >= tau).length;
    const fnm = genuines.filter((t) => t.score < tau).length;
    grid.push({
      threshold: tau,
      fmr: fm / Math.max(1, impostors.length),
      fnmr: fnm / Math.max(1, genuines.length),
    });
  }

  let bestVerify = grid[Math.floor(steps * 0.45)].threshold;
  let minCost = Infinity;
  for (const pt of grid) {
    const cost = pt.fmr * 3.0 + pt.fnmr;
    if (cost < minCost) {
      minCost = cost;
      bestVerify = pt.threshold;
    }
  }

  let bestDup = Math.min(
    maxScore - stepSize,
    bestVerify + Math.max(0.08, stepSize * 4),
  );
  for (const pt of grid) {
    if (pt.threshold > bestVerify + 0.04 && pt.fmr <= 0.001) {
      bestDup = pt.threshold;
      break;
    }
  }

  let bestHard = Math.min(
    maxScore,
    bestDup + Math.max(0.08, stepSize * 4),
  );
  for (const pt of grid) {
    if (pt.threshold > bestDup + 0.04 && pt.fmr === 0) {
      bestHard = Math.min(maxScore, pt.threshold + stepSize * 2);
      break;
    }
  }

  if (bestDup <= bestVerify) {
    bestDup = Number((bestVerify + 0.05).toFixed(6));
  }
  if (bestHard <= bestDup) {
    bestHard = Number((bestDup + 0.05).toFixed(6));
  }

  const verify1to1 = Number(bestVerify.toFixed(6));
  const duplicateWarning = Number(bestDup.toFixed(6));
  const hardBlock = Number(bestHard.toFixed(6));

  return {
    verify1to1,
    duplicateWarning,
    hardBlock,
    monotonicValid:
      verify1to1 < duplicateWarning && duplicateWarning < hardBlock,
  };
}

export function runV18DualSubspaceCalibrationSuite(
  samples: readonly BiometricSampleRecord[],
  options?: {
    enableFusionTrack?: boolean;
    bootstrapIterations?: number;
    randomSeed?: number;
  },
): V18CalibrationSuiteReport {
  verifyPartitionDisjointness(samples);

  const enableFusion = options?.enableFusionTrack ?? true;
  const bootstrapIterations = options?.bootstrapIterations ?? 200;
  const seed = options?.randomSeed ?? 0x18a0f00d;

  const datasetContainsSyntheticVectors = samples.some(
    (s) => s.isSyntheticData,
  );

  const byPartition: Record<DatasetPartition, BiometricSampleRecord[]> = {
    CALIBRATION: [],
    VALIDATION: [],
    HELD_OUT_EVAL: [],
  };

  for (const s of samples) {
    byPartition[s.partition].push(s);
  }

  const partitionCounts: Record<
    DatasetPartition,
    { subjects: number; samples: number }
  > = {
    CALIBRATION: {
      subjects: new Set(byPartition.CALIBRATION.map((s) => s.subjectId)).size,
      samples: byPartition.CALIBRATION.length,
    },
    VALIDATION: {
      subjects: new Set(byPartition.VALIDATION.map((s) => s.subjectId)).size,
      samples: byPartition.VALIDATION.length,
    },
    HELD_OUT_EVAL: {
      subjects: new Set(byPartition.HELD_OUT_EVAL.map((s) => s.subjectId)).size,
      samples: byPartition.HELD_OUT_EVAL.length,
    },
  };

  const evalSamples = byPartition.HELD_OUT_EVAL;
  if (evalSamples.length < 2) {
    throw new Error('HELD_OUT_EVAL partition requires at least 2 samples.');
  }

  const trackA = evaluateSingleModalityTrack({
    trackId: 'TRACK_A_SFACE_BASELINE',
    evalSamples,
    valSamples: byPartition.VALIDATION,
    hasSynthetic: datasetContainsSyntheticVectors,
    defaultThresholds: CANONICAL_SFACE_THRESHOLDS,
    bootstrapIterations,
    seed,
    extractScore: (a, b) => {
      const vecA = validateAndNormalizeEmbedding(
        a.sfaceEmbedding128,
        SFACE_DIMENSION,
        `SFace(${a.sampleId})`,
      );
      const vecB = validateAndNormalizeEmbedding(
        b.sfaceEmbedding128,
        SFACE_DIMENSION,
        `SFace(${b.sampleId})`,
      );
      return computeExactCosine(vecA, vecB);
    },
    canRun: (s) => s.sfaceEmbedding128 !== undefined,
  });

  const trackB = evaluateSingleModalityTrack({
    trackId: 'TRACK_B_LANDMARK_V3_EXPERIMENTAL',
    evalSamples,
    valSamples: byPartition.VALIDATION,
    hasSynthetic: datasetContainsSyntheticVectors,
    defaultThresholds: null,
    bootstrapIterations,
    seed,
    extractScore: (a, b) => {
      const fullA = validateAndNormalizeEmbedding(
        a.landmarkFull512,
        LANDMARK_V3_FULL_DIMENSION,
        `LandmarkFull512(${a.sampleId})`,
      );
      const fullB = validateAndNormalizeEmbedding(
        b.landmarkFull512,
        LANDMARK_V3_FULL_DIMENSION,
        `LandmarkFull512(${b.sampleId})`,
      );
      const periA = validateAndNormalizeEmbedding(
        a.landmarkPeri256,
        LANDMARK_V3_PERI_DIMENSION,
        `LandmarkPeri256(${a.sampleId})`,
      );
      const periB = validateAndNormalizeEmbedding(
        b.landmarkPeri256,
        LANDMARK_V3_PERI_DIMENSION,
        `LandmarkPeri256(${b.sampleId})`,
      );

      const fullCos = computeExactCosine(fullA, fullB);
      const periCos = computeExactCosine(periA, periB);
      const maxOcc = Math.max(a.occlusionRatio ?? 0.0, b.occlusionRatio ?? 0.0);
      const periWeight = Math.min(0.65, Math.max(0.15, 0.65 * maxOcc));
      return (1.0 - periWeight) * fullCos + periWeight * periCos;
    },
    canRun: (s) =>
      s.landmarkFull512 !== undefined && s.landmarkPeri256 !== undefined,
    extraWarnings: [
      'EXPERIMENTAL_REPRESENTATION: Dense500LandmarkEngineV3 encodes 3D mesh craniometric ratios rather than learned deep appearance features. Do not use as standalone primary 1:N identity matcher.',
    ],
  });

  const trackC = evaluateCalibratedFusionTrack({
    enableFusion,
    calSamples: byPartition.CALIBRATION,
    valSamples: byPartition.VALIDATION,
    evalSamples,
    hasSynthetic: datasetContainsSyntheticVectors,
    bootstrapIterations,
    seed,
  });

  let overallValidationStatus: ValidationStatus = 'EMPIRICALLY_VALIDATED';
  if (datasetContainsSyntheticVectors) {
    overallValidationStatus =
      'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED';
  } else if (
    trackA.validationStatus === 'INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR'
  ) {
    overallValidationStatus = 'INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR';
  }

  return {
    schemaVersion: 'v18.1.0',
    productionBiometricCalibrationApproved:
      PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
    deploymentGateMode: DEPLOYMENT_GATE_MODE,
    datasetContainsSyntheticVectors,
    overallValidationStatus,
    partitionCounts,
    tracks: {
      trackA_SFace: trackA,
      trackB_LandmarkV3: trackB,
      trackC_DualFusion: trackC,
    },
  };
}

function evaluateSingleModalityTrack(params: {
  trackId: EvaluationTrackId;
  evalSamples: readonly BiometricSampleRecord[];
  valSamples: readonly BiometricSampleRecord[];
  hasSynthetic: boolean;
  defaultThresholds:
    | SelectedThresholds
    | { verify1to1: number; duplicateWarning: number; hardBlock: number }
    | null;
  bootstrapIterations: number;
  seed: number;
  extractScore: (a: BiometricSampleRecord, b: BiometricSampleRecord) => number;
  canRun: (s: BiometricSampleRecord) => boolean;
  extraWarnings?: readonly string[];
}): TrackEvaluationReport {
  const eligibleEval = params.evalSamples.filter(params.canRun);
  if (eligibleEval.length < 2) {
    return {
      trackId: params.trackId,
      enabled: false,
      disabledReason: `Insufficient samples with required modality embeddings in HELD_OUT_EVAL (${eligibleEval.length}).`,
      validationStatus: 'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED',
      warnings: ['Track disabled: missing required embeddings.'],
      subjectCount: 0,
      sampleCount: eligibleEval.length,
      genuineTrialCount: 0,
      impostorTrialCount: 0,
      genuineDistribution: null,
      impostorDistribution: null,
      eerEstimate: null,
      selectedThresholds: null,
      operatingPointsAtSelected: null,
      rocSweep: [],
    };
  }

  const evalTrials = buildPairTrials(eligibleEval, params.extractScore);
  const eligibleVal = params.valSamples.filter(params.canRun);

  let selectedThresholds: SelectedThresholds;
  if (params.defaultThresholds) {
    selectedThresholds = {
      ...params.defaultThresholds,
      monotonicValid:
        params.defaultThresholds.verify1to1 <
          params.defaultThresholds.duplicateWarning &&
        params.defaultThresholds.duplicateWarning <
          params.defaultThresholds.hardBlock,
    };
  } else if (eligibleVal.length >= 4) {
    const valTrials = buildPairTrials(eligibleVal, params.extractScore);
    selectedThresholds = selectMonotonicThresholdsFromValidation(
      valTrials,
      -0.2,
      0.98,
    );
  } else {
    selectedThresholds = selectMonotonicThresholdsFromValidation(
      evalTrials,
      -0.2,
      0.98,
    );
  }

  return finalizeTrackReport({
    trackId: params.trackId,
    evalSamples: eligibleEval,
    evalTrials,
    selectedThresholds,
    hasSynthetic: params.hasSynthetic,
    bootstrapIterations: params.bootstrapIterations,
    seed: params.seed,
    minSweep: -0.2,
    maxSweep: 0.98,
    extraWarnings: params.extraWarnings ?? [],
  });
}

function evaluateCalibratedFusionTrack(params: {
  enableFusion: boolean;
  calSamples: readonly BiometricSampleRecord[];
  valSamples: readonly BiometricSampleRecord[];
  evalSamples: readonly BiometricSampleRecord[];
  hasSynthetic: boolean;
  bootstrapIterations: number;
  seed: number;
}): TrackEvaluationReport {
  const hasBothModalities = (s: BiometricSampleRecord) =>
    s.sfaceEmbedding128 !== undefined &&
    s.landmarkFull512 !== undefined &&
    s.landmarkPeri256 !== undefined;

  if (!params.enableFusion) {
    return {
      trackId: 'TRACK_C_CALIBRATED_LLR_FUSION',
      enabled: false,
      disabledReason:
        'Dual-subspace fusion explicitly disabled via configuration.',
      validationStatus: 'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED',
      warnings: ['Fusion disabled by caller.'],
      subjectCount: 0,
      sampleCount: 0,
      genuineTrialCount: 0,
      impostorTrialCount: 0,
      genuineDistribution: null,
      impostorDistribution: null,
      eerEstimate: null,
      selectedThresholds: null,
      operatingPointsAtSelected: null,
      rocSweep: [],
    };
  }

  const calEligible = params.calSamples.filter(hasBothModalities);
  const valEligible = params.valSamples.filter(hasBothModalities);
  const evalEligible = params.evalSamples.filter(hasBothModalities);

  if (
    calEligible.length < 4 ||
    valEligible.length < 4 ||
    evalEligible.length < 4
  ) {
    return {
      trackId: 'TRACK_C_CALIBRATED_LLR_FUSION',
      enabled: false,
      disabledReason: `Dual-subspace fusion requires dual-modality samples across all 3 disjoint splits (got cal=${calEligible.length}, val=${valEligible.length}, eval=${evalEligible.length}).`,
      validationStatus: 'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED',
      warnings: [
        'Fusion unavailable: missing dual-modality calibration/validation splits.',
      ],
      subjectCount: 0,
      sampleCount: evalEligible.length,
      genuineTrialCount: 0,
      impostorTrialCount: 0,
      genuineDistribution: null,
      impostorDistribution: null,
      eerEstimate: null,
      selectedThresholds: null,
      operatingPointsAtSelected: null,
      rocSweep: [],
    };
  }

  const extractRawPair = (
    a: BiometricSampleRecord,
    b: BiometricSampleRecord,
  ): RawPairFeatures => {
    const sfaceA = validateAndNormalizeEmbedding(
      a.sfaceEmbedding128,
      SFACE_DIMENSION,
      `SFace(${a.sampleId})`,
    );
    const sfaceB = validateAndNormalizeEmbedding(
      b.sfaceEmbedding128,
      SFACE_DIMENSION,
      `SFace(${b.sampleId})`,
    );
    const fullA = validateAndNormalizeEmbedding(
      a.landmarkFull512,
      LANDMARK_V3_FULL_DIMENSION,
      `LandmarkFull(${a.sampleId})`,
    );
    const fullB = validateAndNormalizeEmbedding(
      b.landmarkFull512,
      LANDMARK_V3_FULL_DIMENSION,
      `LandmarkFull(${b.sampleId})`,
    );
    const periA = validateAndNormalizeEmbedding(
      a.landmarkPeri256,
      LANDMARK_V3_PERI_DIMENSION,
      `LandmarkPeri(${a.sampleId})`,
    );
    const periB = validateAndNormalizeEmbedding(
      b.landmarkPeri256,
      LANDMARK_V3_PERI_DIMENSION,
      `LandmarkPeri(${b.sampleId})`,
    );

    return {
      subjectA: a.subjectId,
      subjectB: b.subjectId,
      sessionA: a.sessionId,
      sessionB: b.sessionId,
      isGenuine: a.subjectId === b.subjectId,
      sfaceCos: computeExactCosine(sfaceA, sfaceB),
      landmarkFullCos: computeExactCosine(fullA, fullB),
      landmarkPeriCos: computeExactCosine(periA, periB),
      maxOcclusion: Math.max(a.occlusionRatio ?? 0.0, b.occlusionRatio ?? 0.0),
      minQuality: Math.min(
        a.isoQualityScore ?? 100.0,
        b.isoQualityScore ?? 100.0,
      ),
    };
  };

  const calPairs: RawPairFeatures[] = [];
  for (let i = 0; i < calEligible.length; i++) {
    for (let j = i + 1; j < calEligible.length; j++) {
      calPairs.push(extractRawPair(calEligible[i], calEligible[j]));
    }
  }
  const fusionParams = fitCalibratedLogisticFusion(calPairs);

  const valTrials = buildPairTrials(valEligible, (a, b) =>
    scoreCalibratedFusionPair(extractRawPair(a, b), fusionParams),
  );
  const selectedThresholds = selectMonotonicThresholdsFromValidation(
    valTrials,
    0.05,
    0.99,
  );

  const evalTrials = buildPairTrials(evalEligible, (a, b) =>
    scoreCalibratedFusionPair(extractRawPair(a, b), fusionParams),
  );

  const report = finalizeTrackReport({
    trackId: 'TRACK_C_CALIBRATED_LLR_FUSION',
    evalSamples: evalEligible,
    evalTrials,
    selectedThresholds,
    hasSynthetic: params.hasSynthetic,
    bootstrapIterations: params.bootstrapIterations,
    seed: params.seed,
    minSweep: 0.05,
    maxSweep: 0.99,
    extraWarnings: [],
  });

  return {
    ...report,
    fusionParameters: fusionParams,
  };
}

function buildPairTrials(
  samples: readonly BiometricSampleRecord[],
  scoreFn: (a: BiometricSampleRecord, b: BiometricSampleRecord) => number,
): PairTrial[] {
  const trials: PairTrial[] = [];
  for (let i = 0; i < samples.length; i++) {
    for (let j = i + 1; j < samples.length; j++) {
      const a = samples[i];
      const b = samples[j];
      const score = scoreFn(a, b);
      if (!Number.isFinite(score)) {
        throw new Error(
          `Non-finite score computed between ${a.sampleId} and ${b.sampleId}`,
        );
      }
      trials.push({
        sampleA: a.sampleId,
        sampleB: b.sampleId,
        subjectA: a.subjectId,
        subjectB: b.subjectId,
        sessionA: a.sessionId,
        sessionB: b.sessionId,
        isGenuine: a.subjectId === b.subjectId,
        score,
      });
    }
  }
  return trials;
}

function finalizeTrackReport(params: {
  trackId: EvaluationTrackId;
  evalSamples: readonly BiometricSampleRecord[];
  evalTrials: readonly PairTrial[];
  selectedThresholds: SelectedThresholds;
  hasSynthetic: boolean;
  bootstrapIterations: number;
  seed: number;
  minSweep: number;
  maxSweep: number;
  extraWarnings: readonly string[];
}): TrackEvaluationReport {
  const genuineScores = params.evalTrials
    .filter((t) => t.isGenuine)
    .map((t) => t.score);
  const impostorScores = params.evalTrials
    .filter((t) => !t.isGenuine)
    .map((t) => t.score);

  if (genuineScores.length === 0 || impostorScores.length === 0) {
    throw new Error(
      `Track ${params.trackId} requires at least 1 genuine and 1 impostor pair in HELD_OUT_EVAL.`,
    );
  }

  const warnings: string[] = [...params.extraWarnings];
  let validationStatus: ValidationStatus = 'EMPIRICALLY_VALIDATED';

  if (impostorScores.length < 3000 || genuineScores.length < 300) {
    warnings.push(
      `INSUFFICIENT_SAMPLE_SIZE: Held-out evaluation contains ${genuineScores.length} genuine and ${impostorScores.length} impostor trials. At least 3,000 impostor trials and 300 genuine trials across >= 100 subjects are required to bound 0.1% FMR at 95% confidence.`,
    );
    validationStatus = 'INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR';
  }

  if (params.hasSynthetic) {
    warnings.push(
      'SYNTHETIC_DATA_WARNING: Dataset contains synthetic vectors. Results validate software arithmetic only; population-level biometric accuracy is NOT VALIDATED.',
    );
    validationStatus = 'SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED';
  }

  const sweepSteps = 20;
  const step = (params.maxSweep - params.minSweep) / sweepSteps;
  const rocSweep: RocDetOperatingPoint[] = [];
  let bestEer = 1.0;
  let minDiff = Infinity;

  for (let s = 0; s <= sweepSteps; s++) {
    const tau = params.minSweep + s * step;
    const pt = evaluateOperatingPoint(
      params.evalTrials,
      tau,
      params.bootstrapIterations,
      params.seed + s,
    );
    rocSweep.push(pt);
    const diff = Math.abs(pt.fmr - pt.fnmr);
    if (diff < minDiff) {
      minDiff = diff;
      bestEer = 0.5 * (pt.fmr + pt.fnmr);
    }
  }

  const opVerify = evaluateOperatingPoint(
    params.evalTrials,
    params.selectedThresholds.verify1to1,
    params.bootstrapIterations,
    params.seed + 101,
  );
  const opDup = evaluateOperatingPoint(
    params.evalTrials,
    params.selectedThresholds.duplicateWarning,
    params.bootstrapIterations,
    params.seed + 102,
  );
  const opHard = evaluateOperatingPoint(
    params.evalTrials,
    params.selectedThresholds.hardBlock,
    params.bootstrapIterations,
    params.seed + 103,
  );

  const subjectCount = new Set(params.evalSamples.map((s) => s.subjectId)).size;

  return {
    trackId: params.trackId,
    enabled: true,
    validationStatus,
    warnings,
    subjectCount,
    sampleCount: params.evalSamples.length,
    genuineTrialCount: genuineScores.length,
    impostorTrialCount: impostorScores.length,
    genuineDistribution: summarizeDistribution(genuineScores),
    impostorDistribution: summarizeDistribution(impostorScores),
    eerEstimate: Number(bestEer.toFixed(6)),
    selectedThresholds: params.selectedThresholds,
    operatingPointsAtSelected: {
      verify1to1: opVerify,
      duplicateWarning: opDup,
      hardBlock: opHard,
    },
    rocSweep,
  };
}
