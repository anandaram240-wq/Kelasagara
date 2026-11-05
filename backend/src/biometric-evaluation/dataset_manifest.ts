/**
 * backend/src/biometric-evaluation/dataset_manifest.ts
 *
 * Controlled evaluation dataset manifest conforming to:
 * - Privacy-preserving research protocols (DPDPA 2023, GDPR Art 9).
 * - Zero PII / Opaque research participant identifiers.
 * - Strict 3-way subject-level partitioning (Dev / Calibration / Holdout).
 * - Real-world capture conditions (Indoor, Outdoor, Low Light, Backlight, Glasses, Mobile sensors).
 */

export type DatasetPartition = 'DEVELOPMENT_A' | 'CALIBRATION_B' | 'HOLDOUT_C';

export type EvaluationDataSourceType =
  | 'REAL_CONSENTED_HUMAN_DATA'
  | 'SYNTHETIC_VECTOR_TEST'
  | 'MOCKED_PIPELINE_TEST'
  | 'BENCHMARK_FIXTURE'
  | 'PHYSICAL_ATTACK_PRESENTATION_TEST'
  | 'UNVERIFIED_SOURCE';

export type LightingCondition =
  | 'INDOOR_UNIFORM'
  | 'OUTDOOR_DIRECT_SUN'
  | 'LOW_ILLUMINATION_NIGHT'
  | 'BACKLIT_STRONG_WINDOW'
  | 'DIFFUSE_FLUORESCENT';

export type CameraProfile =
  | 'ENTRY_720P_FIXED'
  | 'MID_1080P_AUTOFOCUS'
  | 'FLAGSHIP_4K_SENSOR';

export interface ParticipantMetadata {
  readonly participantId: string; // Opaque ID (e.g. 'SUBJ-A-01', 'SUBJ-C-14')
  readonly partition: DatasetPartition;
  readonly consentDocumentId: string; // Hash of signed research consent
  readonly consentedDate: string; // ISO 8601 UTC
  readonly voluntaryDemographics?: {
    readonly selfReportedSex?: 'FEMALE' | 'MALE' | 'NON_BINARY' | 'UNDISCLOSED';
    readonly skinToneCategory?: 'MONK_1_3_LIGHT' | 'MONK_4_6_MEDIUM' | 'MONK_7_10_DARK';
    readonly wearsGlasses?: boolean;
    readonly wearsHeadCovering?: boolean;
  };
}

export interface CaptureSample {
  readonly sampleId: string;
  readonly participantId: string;
  readonly partition: DatasetPartition;
  readonly sessionIndex: number; // 0 = baseline enrollment, 1+ = verification sessions
  readonly frameIndex: number; // 0, 1, 2 in 3-frame burst
  readonly lighting: LightingCondition;
  readonly camera: CameraProfile;
  readonly resolution: { width: number; height: number };
  readonly timestamp: number;
  readonly hasGlasses: boolean;
  readonly hasMaskOrOcclusion: boolean;
  readonly syntheticVectorMock?: readonly number[]; // Used ONLY when executing pure-computational synthetic load tests
}

export interface DatasetManifest {
  readonly manifestVersion: string;
  readonly createdAt: string;
  readonly description: string;
  readonly dataSourceType: EvaluationDataSourceType;
  readonly isSyntheticFixture: boolean;
  readonly sourceCorpusAvailable: boolean;
  readonly participants: readonly ParticipantMetadata[];
  readonly samples: readonly CaptureSample[];
  readonly totalParticipants: number;
  readonly totalSamples: number;
}

export interface CorpusVerificationResult {
  readonly isCorpusAvailable: boolean;
  readonly verifiedFilesCount: number;
  readonly missingFilesCount: number;
  readonly totalExpectedFiles: number;
  readonly status: 'VERIFIED_EMPIRICAL' | 'UNAVAILABLE_MISSING_RAW_IMAGES';
  readonly provenanceClassification: EvaluationDataSourceType;
}

export function verifySourceCorpusAvailability(
  manifest: DatasetManifest,
  _corpusBasePath?: string
): CorpusVerificationResult {
  // In Phase 20.6 Forensic Discovery, source raw images are not present on disk.
  // The system explicitly reports missing raw images and prevents synthetic fixtures
  // from masquerading as verified real-world human data.
  const total = manifest.totalSamples;
  return {
    isCorpusAvailable: false,
    verifiedFilesCount: 0,
    missingFilesCount: total,
    totalExpectedFiles: total,
    status: 'UNAVAILABLE_MISSING_RAW_IMAGES',
    provenanceClassification: manifest.dataSourceType,
  };
}

export function createCanonicalEvaluationManifest(): DatasetManifest {
  // Construct a scientifically structured 3-way partitioned evaluation dataset
  // Partition A (Development): 10 subjects, checked for pipeline mechanics
  // Partition B (Calibration): 15 subjects, used for threshold calibration exploration
  // Partition C (Holdout): 25 subjects, used strictly for independent evaluation
  const participants: ParticipantMetadata[] = [];
  const samples: CaptureSample[] = [];

  const partitions: { name: DatasetPartition; count: number; prefix: string }[] = [
    { name: 'DEVELOPMENT_A', count: 10, prefix: 'SUBJ-A' },
    { name: 'CALIBRATION_B', count: 15, prefix: 'SUBJ-B' },
    { name: 'HOLDOUT_C', count: 25, prefix: 'SUBJ-C' },
  ];

  let sampleSeq = 1;
  const lightings: LightingCondition[] = [
    'INDOOR_UNIFORM',
    'OUTDOOR_DIRECT_SUN',
    'LOW_ILLUMINATION_NIGHT',
    'BACKLIT_STRONG_WINDOW',
    'DIFFUSE_FLUORESCENT',
  ];
  const cameras: CameraProfile[] = ['ENTRY_720P_FIXED', 'MID_1080P_AUTOFOCUS', 'FLAGSHIP_4K_SENSOR'];

  for (const part of partitions) {
    for (let i = 1; i <= part.count; i++) {
      const pId = `${part.prefix}-${String(i).padStart(2, '0')}`;
      const wearsGlasses = i % 3 === 0;
      const headCover = i % 5 === 0;
      const sex = i % 2 === 0 ? 'FEMALE' : 'MALE';
      const skinTone =
        i % 3 === 0 ? 'MONK_7_10_DARK' : i % 3 === 1 ? 'MONK_4_6_MEDIUM' : 'MONK_1_3_LIGHT';

      participants.push({
        participantId: pId,
        partition: part.name,
        consentDocumentId: `CONSENT-HASH-${part.prefix}-${i}`,
        consentedDate: '2026-10-15T00:00:00Z',
        voluntaryDemographics: {
          selfReportedSex: sex,
          skinToneCategory: skinTone,
          wearsGlasses,
          wearsHeadCovering: headCover,
        },
      });

      // Generate 3 sessions per subject across distinct lighting and camera profiles
      for (let s = 0; s < 3; s++) {
        const light = lightings[(i + s) % lightings.length];
        const cam = cameras[(i + s) % cameras.length];
        for (let f = 0; f < 3; f++) {
          samples.push({
            sampleId: `SMP-${String(sampleSeq++).padStart(4, '0')}`,
            participantId: pId,
            partition: part.name,
            sessionIndex: s,
            frameIndex: f,
            lighting: light,
            camera: cam,
            resolution: cam === 'FLAGSHIP_4K_SENSOR' ? { width: 3840, height: 2160 } : { width: 1920, height: 1080 },
            timestamp: 1761900000000 + s * 86400000 + f * 100,
            hasGlasses: wearsGlasses,
            hasMaskOrOcclusion: false,
          });
        }
      }
    }
  }

  return {
    manifestVersion: '1.0.0-phase20.5',
    createdAt: '2026-10-31T23:15:00Z',
    description: 'Kelasagara Controlled Research Evaluation Corpus (50 Subjects, 450 Samples)',
    dataSourceType: 'BENCHMARK_FIXTURE',
    isSyntheticFixture: true,
    sourceCorpusAvailable: false,
    participants,
    samples,
    totalParticipants: participants.length,
    totalSamples: samples.length,
  };
}
