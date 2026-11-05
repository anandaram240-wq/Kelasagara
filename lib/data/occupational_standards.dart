// lib/data/occupational_standards.dart
// KELASAGARA local occupational standards registry.
// Based on publicly available NQR/NSQF reference data.
// NOT a live government API.

class NosArea {
  final String id;
  final String title;
  final String titleKn;
  final List<String> keyTasks;
  const NosArea({required this.id, required this.title, required this.titleKn, required this.keyTasks});
}

class OccupationalStandardEntry {
  final String occupationId;
  final String occupationName;
  final String occupationNameKn;
  final String qualificationCode;
  final String qualificationTitle;
  final String authority;
  final int    nsqfLevel;
  final String sector;
  final List<NosArea> nosAreas;
  final bool   licenseRequired;
  final String? licenseAuthority;
  final String? licenseNote;
  final String sourceUrl;
  final String standardVersion;
  final String retrievedAt;
  final String lastReviewed;

  const OccupationalStandardEntry({
    required this.occupationId, required this.occupationName,
    required this.occupationNameKn, required this.qualificationCode,
    required this.qualificationTitle, required this.authority,
    required this.nsqfLevel, required this.sector,
    required this.nosAreas, required this.licenseRequired,
    this.licenseAuthority, this.licenseNote,
    required this.sourceUrl, required this.standardVersion,
    required this.retrievedAt, required this.lastReviewed,
  });
}

class OccupationalStandardsRegistry {
  OccupationalStandardsRegistry._();

  static const List<OccupationalStandardEntry> standards = [
    OccupationalStandardEntry(
      occupationId: 'painter', occupationName: 'Painter',
      occupationNameKn: 'ಬಣ್ಣ ಹಚ್ಚುವ ಕಾರ್ಮಿಕ',
      qualificationCode: 'CON/Q1303',
      qualificationTitle: 'Construction Painter and Decorator',
      authority: 'NSDC/NCVT', nsqfLevel: 4, sector: 'Construction',
      nosAreas: [
        NosArea(id: 'painter_nos_1', title: 'Surface Inspection and Preparation',
          titleKn: 'ಮೇಲ್ಮೈ ಪರೀಕ್ಷೆ ಮತ್ತು ತಯಾರಿ',
          keyTasks: ['Inspect surfaces for defects and moisture', 'Remove old paint and contamination', 'Fill cracks with filler', 'Sand surfaces to required finish']),
        NosArea(id: 'painter_nos_2', title: 'Paint and Coating Preparation',
          titleKn: 'ಬಣ್ಣ ಮತ್ತು ಲೇಪ ತಯಾರಿ',
          keyTasks: ['Read paint specifications', 'Mix paints to correct consistency', 'Select primer, undercoat, topcoat', 'Prepare surface protection']),
        NosArea(id: 'painter_nos_3', title: 'Paint Application',
          titleKn: 'ಬಣ್ಣ ಅನ್ವಯ',
          keyTasks: ['Apply primer and undercoat', 'Use brush, roller, spray gun', 'Apply topcoat for uniform finish', 'Maintain wet edge']),
        NosArea(id: 'painter_nos_4', title: 'Fault Identification and Correction',
          titleKn: 'ದೋಷ ಗುರುತಿಸುವಿಕೆ',
          keyTasks: ['Identify runs, sags, blistering, peeling', 'Determine cause of defects', 'Correct defects without full rework']),
        NosArea(id: 'painter_nos_5', title: 'Safety and Cleanup',
          titleKn: 'ಸುರಕ್ಷತೆ ಮತ್ತು ಸ್ವಚ್ಛತೆ',
          keyTasks: ['Use PPE: gloves, mask, goggles', 'Handle and dispose paint safely', 'Clean tools and work area', 'Height safety on ladders']),
      ],
      licenseRequired: false,
      sourceUrl: 'https://nqr.gov.in/qualification/CON-Q1303',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
    OccupationalStandardEntry(
      occupationId: 'plumber', occupationName: 'Plumber',
      occupationNameKn: 'ಪ್ಲಂಬರ್',
      qualificationCode: 'CON/Q0602', qualificationTitle: 'Plumber (General)',
      authority: 'NSDC/NCVT', nsqfLevel: 4, sector: 'Construction',
      nosAreas: [
        NosArea(id: 'plumber_nos_1', title: 'Safe Work Preparation',
          titleKn: 'ಸುರಕ್ಷಿತ ಕಾರ್ಯ ತಯಾರಿ',
          keyTasks: ['Read plumbing drawings', 'Identify pipe types and fittings', 'Select appropriate tools', 'Follow safety procedures']),
        NosArea(id: 'plumber_nos_2', title: 'Pipe Cutting, Joining and Installation',
          titleKn: 'ಪೈಪ್ ಕತ್ತರಿಸುವಿಕೆ ಮತ್ತು ಸ್ಥಾಪನೆ',
          keyTasks: ['Measure and cut pipes accurately', 'Join pipes using soldering, threading', 'Install pipes with correct fall and support', 'Prevent leaks']),
        NosArea(id: 'plumber_nos_3', title: 'Water Supply Systems',
          titleKn: 'ನೀರು ಸರಬರಾಜು ವ್ಯವಸ್ಥೆ',
          keyTasks: ['Install cold and hot water systems', 'Connect tanks and pumps', 'Install sanitary fixtures', 'Pressure test installations']),
        NosArea(id: 'plumber_nos_4', title: 'Fault Diagnosis',
          titleKn: 'ದೋಷ ಗುರುತಿಸುವಿಕೆ',
          keyTasks: ['Diagnose leaks and blockages', 'Replace washers, valves, seals', 'Maintain water heaters']),
      ],
      licenseRequired: false,
      licenseNote: 'Gas plumbing may require state authority license',
      sourceUrl: 'https://nqr.gov.in/qualification/CON-Q0602',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
    OccupationalStandardEntry(
      occupationId: 'electrician', occupationName: 'Electrician',
      occupationNameKn: 'ವಿದ್ಯುತ್ ತಜ್ಞ',
      qualificationCode: 'ELE/Q7101', qualificationTitle: 'Electrician (General)',
      authority: 'DGT/NSDC', nsqfLevel: 5, sector: 'Electronics and Hardware',
      nosAreas: [
        NosArea(id: 'elec_nos_1', title: 'Electrical Safety',
          titleKn: 'ವಿದ್ಯುತ್ ಸುರಕ್ಷತೆ',
          keyTasks: ['Isolation and lockout procedures', 'Use of PPE for electrical work', 'Identify live and dead circuits', 'First aid for electrical injury']),
        NosArea(id: 'elec_nos_2', title: 'Wiring Installation',
          titleKn: 'ತಂತಿ ಅಳವಡಿಕೆ',
          keyTasks: ['Read electrical drawings', 'Install conduit and cable trays', 'Pull and connect cables', 'Install switches, sockets, boards']),
        NosArea(id: 'elec_nos_3', title: 'Testing and Commissioning',
          titleKn: 'ಪರೀಕ್ಷೆ ಮತ್ತು ಆರಂಭ',
          keyTasks: ['Test continuity and insulation resistance', 'Check polarity and earthing', 'Commission and document installations']),
      ],
      licenseRequired: true,
      licenseAuthority: 'Electrical Inspectorate, Government of Karnataka',
      licenseNote: 'Wireman/Contractor license required under Karnataka Electricity Act',
      sourceUrl: 'https://nqr.gov.in/qualification/ELE-Q7101',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
    OccupationalStandardEntry(
      occupationId: 'carpenter', occupationName: 'Carpenter',
      occupationNameKn: 'ಬಡಗಿ',
      qualificationCode: 'CON/Q0303', qualificationTitle: 'Shuttering Carpenter',
      authority: 'NSDC', nsqfLevel: 4, sector: 'Construction',
      nosAreas: [
        NosArea(id: 'carp_nos_1', title: 'Material Preparation',
          titleKn: 'ವಸ್ತು ತಯಾರಿ',
          keyTasks: ['Identify and select timber materials', 'Measure, mark and cut accurately', 'Use hand and power tools safely']),
        NosArea(id: 'carp_nos_2', title: 'Joinery and Assembly',
          titleKn: 'ಜೋಡಣೆ',
          keyTasks: ['Construct mortise/tenon, dovetail joints', 'Assemble frames, doors, windows', 'Use adhesives and fixings correctly']),
        NosArea(id: 'carp_nos_3', title: 'Finishing',
          titleKn: 'ಮೆರುಗು',
          keyTasks: ['Sand and finish surfaces', 'Apply polish, varnish', 'Repair and patch defects']),
      ],
      licenseRequired: false,
      sourceUrl: 'https://nqr.gov.in/qualification/CON-Q0303',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
    OccupationalStandardEntry(
      occupationId: 'welder', occupationName: 'Welder',
      occupationNameKn: 'ವೆಲ್ಡರ್',
      qualificationCode: 'CSC/Q0303', qualificationTitle: 'Welder (SMAW)',
      authority: 'DGT', nsqfLevel: 4, sector: 'Capital Goods',
      nosAreas: [
        NosArea(id: 'weld_nos_1', title: 'Welding Safety',
          titleKn: 'ವೆಲ್ಡಿಂಗ್ ಸುರಕ್ಷತೆ',
          keyTasks: ['Use PPE: mask, gloves, apron', 'Handle gas cylinders safely', 'Fire prevention and control', 'Ventilation requirements']),
        NosArea(id: 'weld_nos_2', title: 'Joint Preparation and Welding',
          titleKn: 'ಜೋಡಣೆ ಮತ್ತು ವೆಲ್ಡಿಂಗ್',
          keyTasks: ['Clean and prepare joint surfaces', 'Set welding machine parameters', 'Perform SMAW butt, fillet, lap joints', 'Control distortion']),
        NosArea(id: 'weld_nos_3', title: 'Weld Quality',
          titleKn: 'ವೆಲ್ಡ್ ಗುಣಮಟ್ಟ',
          keyTasks: ['Visually inspect weld for defects', 'Identify porosity, cracks, undercut', 'Correct minor defects']),
      ],
      licenseRequired: false,
      licenseNote: 'Pressure vessel welding requires certified welder qualification',
      sourceUrl: 'https://nqr.gov.in/qualification/CSC-Q0303',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
    OccupationalStandardEntry(
      occupationId: 'mason', occupationName: 'Mason',
      occupationNameKn: 'ರಾಜಗಾರ',
      qualificationCode: 'CON/Q0103', qualificationTitle: 'Mason (General)',
      authority: 'NSDC', nsqfLevel: 4, sector: 'Construction',
      nosAreas: [
        NosArea(id: 'mason_nos_1', title: 'Material Preparation',
          titleKn: 'ವಸ್ತು ತಯಾರಿ',
          keyTasks: ['Mix concrete and mortar to specification', 'Identify and select bricks and blocks', 'Read construction drawings']),
        NosArea(id: 'mason_nos_2', title: 'Brickwork and Blockwork',
          titleKn: 'ಇಟ್ಟಿಗೆ ಕೆಲಸ',
          keyTasks: ['Lay bricks/blocks to line and level', 'Construct walls, piers, corners', 'Build openings for doors and windows', 'Point and finish joints']),
        NosArea(id: 'mason_nos_3', title: 'Plastering and Finishing',
          titleKn: 'ಗಾರೆ ಕೆಲಸ',
          keyTasks: ['Apply scratch coat and finishing coat', 'Float and trowel to smooth finish', 'Apply textured finishes']),
        NosArea(id: 'mason_nos_4', title: 'Safety',
          titleKn: 'ಸುರಕ್ಷತೆ',
          keyTasks: ['Use PPE: helmet, gloves, boots', 'Safe handling of heavy materials', 'Scaffold safety']),
      ],
      licenseRequired: false,
      sourceUrl: 'https://nqr.gov.in/qualification/CON-Q0103',
      standardVersion: 'v1.0', retrievedAt: '2025-01-01', lastReviewed: '2025-01-01',
    ),
  ];

  static OccupationalStandardEntry? findById(String id) {
    try { return standards.firstWhere((s) => s.occupationId == id); }
    catch (_) { return null; }
  }

  static List<NosArea> getNosAreas(String id) => findById(id)?.nosAreas ?? const [];
  static bool licenseRequired(String id) => findById(id)?.licenseRequired ?? false;
  static String? licenseAuthority(String id) => findById(id)?.licenseAuthority;
  static int getNsqfLevel(String id) => findById(id)?.nsqfLevel ?? 4;
}
