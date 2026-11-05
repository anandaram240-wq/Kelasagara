// ================================================================
// KELASAGARA — Occupation Taxonomy
// Extended job categories with risk level and standard reference
// for the Competency Trust Infrastructure
// ================================================================

class JobCategory {
  final String id;
  final String label;
  final String labelKn;
  final String emoji;
  final String color;
  // ── Trust Infrastructure additions ──────────────────────────
  final String riskLevel;       // 'low' | 'medium' | 'high' | 'critical'
  final int safetyThreshold;    // Minimum safety score /5 to pass assessment
  final String standardRef;     // Internal Kelasagara standard reference
  final String assessmentVersion;

  const JobCategory({
    required this.id,
    required this.label,
    required this.labelKn,
    required this.emoji,
    required this.color,
    this.riskLevel = 'low',
    this.safetyThreshold = 3,
    this.standardRef = '',
    this.assessmentVersion = 'V1.0',
  });
}

// ── Canonical Occupation Taxonomy ──────────────────────────────────
// These IDs are the single source of truth for skillId across:
//   workerSkills/{uid_skillId}
//   skillAssessments/{assessmentId}.skillId
//   assessmentEvidence/{evidenceId}.skillId
//   verifiedWorkRecords/{recordId}.skillId
//   jobs/{jobId}.requiredSkillId
// ──────────────────────────────────────────────────────────────────

const List<JobCategory> kJobCategories = [
  JobCategory(
    id: 'plumber', label: 'Plumber', labelKn: 'ಪ್ಲಂಬರ್',
    emoji: '🔧', color: '#3B82F6',
    riskLevel: 'medium', safetyThreshold: 4,
    standardRef: 'KG-PLB-001', assessmentVersion: 'PLUMBER-V1.0',
  ),
  JobCategory(
    id: 'electrician', label: 'Electrician', labelKn: 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
    emoji: '⚡', color: '#F59E0B',
    riskLevel: 'critical', safetyThreshold: 5,
    standardRef: 'KG-ELEC-001', assessmentVersion: 'ELECTRICIAN-V1.0',
  ),
  JobCategory(
    id: 'mason', label: 'Mason', labelKn: 'ಕಟ್ಟಡ ಕಾರ್ಮಿಕ',
    emoji: '🧱', color: '#8B5CF6',
    riskLevel: 'high', safetyThreshold: 4,
    standardRef: 'KG-MASON-001', assessmentVersion: 'MASON-V1.0',
  ),
  JobCategory(
    id: 'carpenter', label: 'Carpenter', labelKn: 'ಮರಗೆಲಸ',
    emoji: '🪚', color: '#10B981',
    riskLevel: 'medium', safetyThreshold: 4,
    standardRef: 'KG-CARP-001', assessmentVersion: 'CARPENTER-V1.0',
  ),
  JobCategory(
    id: 'painter', label: 'Painter', labelKn: 'ಬಣ್ಣ ಮಾಡು',
    emoji: '🎨', color: '#EC4899',
    riskLevel: 'medium', safetyThreshold: 4,
    standardRef: 'KG-PAINT-001', assessmentVersion: 'PAINTER-V1.0',
  ),
  JobCategory(
    id: 'driver', label: 'Driver', labelKn: 'ಚಾಲಕ',
    emoji: '🚗', color: '#06B6D4',
    riskLevel: 'medium', safetyThreshold: 5,
    standardRef: 'KG-DRV-001', assessmentVersion: 'DRIVER-V1.0',
  ),
  JobCategory(
    id: 'cook', label: 'Cook', labelKn: 'ಅಡುಗೆ',
    emoji: '👨‍🍳', color: '#EF4444',
    riskLevel: 'low', safetyThreshold: 3,
    standardRef: 'KG-COOK-001', assessmentVersion: 'COOK-V1.0',
  ),
  JobCategory(
    id: 'cleaner', label: 'Cleaner', labelKn: 'ಸ್ವಚ್ಛತೆ',
    emoji: '🧹', color: '#84CC16',
    riskLevel: 'low', safetyThreshold: 3,
    standardRef: 'KG-CLN-001', assessmentVersion: 'CLEANER-V1.0',
  ),
  JobCategory(
    id: 'gardener', label: 'Gardener', labelKn: 'ತೋಟಗಾರ',
    emoji: '🌱', color: '#22C55E',
    riskLevel: 'low', safetyThreshold: 2,
    standardRef: 'KG-GARD-001', assessmentVersion: 'GARDENER-V1.0',
  ),
  JobCategory(
    id: 'security', label: 'Security', labelKn: 'ಕಾವಲು',
    emoji: '💂', color: '#6366F1',
    riskLevel: 'medium', safetyThreshold: 4,
    standardRef: 'KG-SEC-001', assessmentVersion: 'SECURITY-V1.0',
  ),
  JobCategory(
    id: 'tailor', label: 'Tailor', labelKn: 'ದರ್ಜಿ',
    emoji: '🧵', color: '#F97316',
    riskLevel: 'low', safetyThreshold: 2,
    standardRef: 'KG-TAIL-001', assessmentVersion: 'TAILOR-V1.0',
  ),
  JobCategory(
    id: 'welder', label: 'Welder', labelKn: 'ವೆಲ್ಡರ್',
    emoji: '🔩', color: '#64748B',
    riskLevel: 'high', safetyThreshold: 5,
    standardRef: 'KG-WELD-001', assessmentVersion: 'WELDER-V1.0',
  ),
  JobCategory(
    id: 'loader', label: 'Loader', labelKn: 'ಲೋಡಿಂಗ್',
    emoji: '📦', color: '#A78BFA',
    riskLevel: 'low', safetyThreshold: 3,
    standardRef: 'KG-LOAD-001', assessmentVersion: 'LOADER-V1.0',
  ),
  JobCategory(
    id: 'agriculture', label: 'Agriculture', labelKn: 'ಕೃಷಿ ಕೆಲಸ',
    emoji: '🌾', color: '#78716C',
    riskLevel: 'low', safetyThreshold: 2,
    standardRef: 'KG-AGR-001', assessmentVersion: 'AGRICULTURE-V1.0',
  ),
];

// ── Lookup helpers ─────────────────────────────────────────────────
JobCategory? kGetCategory(String id) {
  try {
    return kJobCategories.firstWhere((c) => c.id == id);
  } catch (_) {
    return null;
  }
}

/// Safety-critical occupations where no substitute for human review
const kHighRiskOccupations = {'electrician', 'welder', 'mason'};
const kMediumRiskOccupations = {'plumber', 'carpenter', 'painter', 'driver', 'security'};

bool kIsHighRisk(String skillId) => kHighRiskOccupations.contains(skillId);
