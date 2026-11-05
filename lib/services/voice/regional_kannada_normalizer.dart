/// Regional Kannada Speech Profiles — All 8 Karnataka Dialect Zones
/// Covers 30 districts, Urdu/Tulu/Marathi loanwords, phonetic contractions
/// Used for dialect-aware normalization in Kelasagara voice pipeline
///
/// Zone 1 — Southern Standard  (Bengaluru, Mysuru, Mandya)
/// Zone 2 — Dharwad / North    (Dharwad, Haveri, Gadag)
/// Zone 3 — Kalyana Karnataka  (Kalaburagi, Bidar, Raichur, Yadgir)
/// Zone 4 — Coastal            (Mangaluru, Udupi, Kundapura)
/// Zone 5 — Malenadu           (Hassan, Chikkamagaluru, Shivamogga)
/// Zone 6 — Havyaka            (Community: Havyaka Brahmins)
/// Zone 7 — Belagavi Border    (Belagavi, Vijayapura — Kannada+Marathi)
/// Zone 8 — Code-Mixed Urban   (Any city — English+Kannada+Hindi)
enum RegionalKannadaProfile {
  mysuruBengaluru,  // Zone 1
  northKarnataka,   // Zone 2 — Dharwad
  kalyanaKarnataka, // Zone 3 — Kalaburagi/Bidar
  coastal,          // Zone 4 — Kundagannada + Tulu-influenced
  malenadu,         // Zone 5 — Coffee belt
  havyaka,          // Zone 6 — Old Kannada preserving community
  belagaviBorder,   // Zone 7 — Marathi-mixed
  kodagu,           // Zone 5b — Kodava Takk influenced
  codeMixed,        // Zone 8 — English+Kannada urban
  romanized,        // Roman-script Kannada (any zone)
  standard,
  unknown,
}

/// Normalized result of an incoming voice query.
class NormalizedVoiceQuery {
  final String originalQuery;
  final String normalizedText;
  final String? canonicalSkill;
  final String canonicalIntent;
  final int? extractedRadiusMeters;
  final bool isUrgent;
  final bool verifiedOnly;
  final RegionalKannadaProfile detectedProfile;
  final List<String> dynamicKeyterms;
  final double confidence;

  const NormalizedVoiceQuery({
    required this.originalQuery,
    required this.normalizedText,
    this.canonicalSkill,
    required this.canonicalIntent,
    this.extractedRadiusMeters,
    this.isUrgent = false,
    this.verifiedOnly = false,
    this.detectedProfile = RegionalKannadaProfile.standard,
    this.dynamicKeyterms = const [],
    this.confidence = 1.0,
  });

  Map<String, dynamic> toMap() => {
        'originalQuery': originalQuery,
        'normalizedText': normalizedText,
        'canonicalSkill': canonicalSkill,
        'canonicalIntent': canonicalIntent,
        'extractedRadiusMeters': extractedRadiusMeters,
        'isUrgent': isUrgent,
        'verifiedOnly': verifiedOnly,
        'detectedProfile': detectedProfile.name,
        'dynamicKeyterms': dynamicKeyterms,
        'confidence': confidence,
      };
}

// ── Kelasagara Kannada Domain Lexicon ────────────────────────────────────────
// Complete skill synonym dictionary — all 15 skills × all 8 dialect zones
class KelasagaraKannadaDomainLexicon {
  static const Map<String, List<String>> skillSynonyms = {
    // ── Painter ──────────────────────────────────────────────────────────────
    'painter': [
      // Standard + Zone 1 (Southern)
      'painter', 'painters', 'ಪೇಂಟರ್', 'ಪೇಂಟರ್ಗಳು', 'ಬಣ್ಣದ ಕೆಲಸ',
      'ಬಣ್ಣ ಹಚ್ಚೋರು', 'ಬಣ್ಣದ ಆಳು', 'ಬಣ್ಣದವ್ರು', 'paint', 'ಪೇಂಟ',
      'paint hachovru', 'painteru', 'paint madooru',
      // Zone 2 (Dharwad)
      'ಬಣ್ಣ ಹಚ್ಚೋರ್ರಿ', 'paint hachooru',
      // Zone 3 (Kalyana Karnataka — Urdu)
      'rang wala', 'rang waala', 'rangwala', 'rang karne wala',
      'colour wala', 'color wala',
      // Zone 4 (Coastal)
      'ಬಣ್ಣ ಹಚ್ಚೋರ್',
      // Zone 7 (Belagavi)
      'rang', 'painting wala',
    ],

    // ── Electrician ──────────────────────────────────────────────────────────
    'electrician': [
      // Standard + Zone 1
      'electrician', 'electricians', 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್', 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್ಗಳು',
      'ಕರೆಂಟ್ ಕೆಲಸ', 'ವೈರಿಂಗ್', 'ಕರೆಂಟ್ ಮ್ಯಾನ್', 'ಕರೆಂಟ್ ಮೇಸ್ತ್ರಿ',
      'current kelasa', 'electricianu', 'current', 'ವೈರ್ ಮ್ಯಾನ್',
      // Zone 2 (Dharwad)
      'karent mestri', 'karent kelasa',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'bijli wala', 'bijli waala', 'bijliwala', 'bijli', 'bejli wala',
      'current wala', 'karentu',
      // Zone 4 (Coastal)
      'ಕರೆಂಟ್ ಮ್ಯಾನ್',
      // Zone 7 (Belagavi — Marathi)
      'light wala', 'wiring wala',
    ],

    // ── Plumber ──────────────────────────────────────────────────────────────
    'plumber': [
      // Standard + Zone 1
      'plumber', 'plumbers', 'ಪ್ಲಂಬರ್', 'ಪ್ಲಂಬರ್ಗಳು', 'ಪೈಪ್ ಕೆಲಸ',
      'ನೀರ್ ಪೈಪ್', 'ನಲ್ಲಿ ರಿಪೇರಿ', 'plumberu', 'pipe kelasa',
      'pipe', 'ನಲ್ಲಿ', 'ನಲ್ಲಿ ಮ್ಯಾನ್', 'nalli man',
      // Zone 2 (Dharwad)
      'nal mestri', 'naL mestri', 'nal mistry',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'nal mestri', 'pipe wala', 'paani wala', 'plumbing wala',
      // Zone 4 (Coastal — Havyaka)
      'ಪೈಪ್ ಕೆಲಸ',
      // Havyaka (Zone 6): toti = water tap
      'toti', 'ತೊಟಿ',
      // Zone 7 (Belagavi)
      'pani mistri', 'pani mistry',
    ],

    // ── Carpenter ────────────────────────────────────────────────────────────
    'carpenter': [
      // Standard + Zone 1
      'carpenter', 'carpenters', 'ಕಾರ್ಪೆಂಟರ್', 'ಕಾರ್ಪೆಂಟರ್ಗಳು',
      'ಮರಗೆಲಸ', 'ಬಡಗಿ', 'furniture kelasa', 'marada kelasa', 'carpenteru',
      'ಮರದ ಕೆಲಸ ಮಾಡೋರು',
      // Zone 2 (Dharwad)
      'ಬಡಗ', 'badaga',
      // Zone 3 (Kalyana Karnataka — Hindi)
      'lakdi ka kaam', 'lakdi wala', 'carpenter mistri',
      // Zone 4 (Coastal — Tulu word)
      'badiga', 'ಬಡಿಗ',
      // Zone 7 (Belagavi)
      'saval mistri',
    ],

    // ── Mason ────────────────────────────────────────────────────────────────
    'mason': [
      // Standard + Zone 1
      'mason', 'masons', 'ಮೇಸ್ತ್ರಿ', 'ಮೇಸ್ತ್ರಿಗಳು', 'ಗಾರೆ ಕೆಲಸ',
      'ಕಟ್ಟಡ ಕೆಲಸ', 'ಸಿಮೆಂಟ್ ಕೆಲಸ', 'gaare kelasa', 'mestri',
      'ಕಟ್ಟಡ ಮ್ಯಾನ್', 'ಸಿಮೆಂಟ್ ಮ್ಯಾನ್',
      // Zone 2 (Dharwad) — "mistri" (different from ಮೇಸ್ತ್ರಿ)
      'mistri', 'ಮಿಸ್ತ್ರಿ',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'raj mistri', 'raj mistry', 'rajmistri', 'kal mistri',
      'cement wala', 'gaara mestri',
      // Zone 4 (Coastal)
      'ಕಟ್ಟೋರ್', 'ಗಾರೆ ಮೇಸ್ತ್ರಿ',
      // Zone 7 (Belagavi — Marathi)
      'dagada wala', 'dagadacha kaam', 'bandkam',
      // Post-normalizer form (Zone 7 normalizer converts dagada → ಕಲ್ಲು ಕೆಲಸ)
      'ಕಲ್ಲು ಕೆಲಸ', 'kalu kelasa', 'dagada kelasa',
    ],

    // ── Cleaner ──────────────────────────────────────────────────────────────
    'cleaner': [
      // Standard + Zone 1
      'cleaner', 'cleaners', 'ಕ್ಲೀನರ್', 'ಕ್ಲೀನರ್ಗಳು', 'ಮನೆ ಕೆಲಸ',
      'ಕಸ ಗುಡಿಸೋರು', 'ಸ್ವಚ್ಛತೆ', 'cleaneru', 'ಮನೆ ಕ್ಲೀನ್ ಮಾಡೋರು',
      'ಸ್ವಚ್ಛ ಮಾಡೋರು',
      // Zone 2 (Dharwad)
      'ಸಾರ್ಸೋರ್', 'saarsooru',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'safai wala', 'jhadu wala', 'safai', 'jhadu', 'safai kaami',
      'ghar saaf karne wala',
      // Zone 4 (Coastal)
      'ಸಾರಿಸೋರ್', 'sarisooru',
      // Zone 5 (Malenadu)
      'ಮನೆ ಕ್ಲೀನ್',
    ],

    // ── Driver ───────────────────────────────────────────────────────────────
    'driver': [
      // Standard + Zone 1
      'driver', 'drivers', 'ಡ್ರೈವರ್', 'ಡ್ರೈವರ್ಗಳು', 'ಕಾರು ಚಾಲಕ',
      'ಗಾಡಿ ಹೊಡಿಯೋರು', 'driveru', 'sarathi', 'ಕಾರ್ ಡ್ರೈವರ್',
      'ಗಾಡಿ ಚಾಲಕ', 'chaalakaaru',
      // Zone 2 (Dharwad)
      'ಡ್ರೈವರ್ ಬೇಕ್ರಿ', 'gaadi hodiyoru',
      // Zone 3 (Kalyana Karnataka — Hindi)
      'driver chahiye', 'gaadi driver', 'chalak', 'rikshaw driver',
      // Zone 4 (Coastal)
      'ಬಂಡಿ ಓಡಿಸೋ', 'bandi odisoru',
      // Zone 7 (Belagavi)
      'riksha driver', 'gaadi wala',
    ],

    // ── Cook ─────────────────────────────────────────────────────────────────
    'cook': [
      // Standard + Zone 1
      'cook', 'ಅಡುಗೆಯವರು', 'ಕೂಕ್', 'ಅಡಿಗೆ ಮಾಡೋರು', 'chef',
      'adugeya', 'adige', 'ಊಟ ಮಾಡೋರು', 'ಅಡಿಗೆ ಮ್ಯಾನ್',
      // Zone 2 (Dharwad)
      'ಅಡುಗೆ ಮ್ಯಾನ್',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'khaana banaane wala', 'khaana wala', 'bawarchi', 'khansama',
      // Zone 4 & 6 (Coastal + Havyaka — Tulu word)
      'adiga', 'ಅಡಿಗ',
      // Zone 7 (Belagavi)
      'swayapak', 'swayampak wala',
    ],

    // ── Helper ───────────────────────────────────────────────────────────────
    'helper': [
      // Standard + Zone 1
      'helper', 'ಸಹಾಯಕ', 'ಹೆಲ್ಪರ್', 'ಕೆಲಸದ ಆಳು', 'labourer', 'labor',
      'aLu beku', 'ಆಳು ಬೇಕು',
      // Zone 2 (Dharwad)
      'ಮಂದಿ', 'ಮಂದಿ ಬೇಕ್ರಿ', 'ಊರಿನ ಆಳು', 'aLu bekri',
      // Post-Zone2-normalizer form of ಮಂದಿ ಬೇಕ್ರಿ → used by skill matcher
      'ಕೆಲಸಗಾರರು ಬೇಕಾಗಿದ್ದಾರೆ',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi — MOST COMMON!)
      'mazdoor', 'ಮಜ್ದೂರ್', 'mazdur', 'mazadoor',
      'kaam wala', 'kaamwala', 'kaam waala',
      'beldar', 'ಬೇಲ್ದಾರ', 'beldar wala',
      'coolies', 'coolie', 'laborer',
      // Zone 5 (Malenadu — agriculture context)
      'ಆಳುಗಳು', 'alugalu', 'ಮಂದಿ ಬೇಕು',
      // Zone 7 (Belagavi — Marathi)
      'maanus beka', 'maanasa',
    ],

    // ── Gardener ─────────────────────────────────────────────────────────────
    'gardener': [
      // Standard + Zone 1 (ornamental garden, not farm)
      'gardener', 'ತೋಟಗಾರ', 'mali', 'ಮಾಲಿ', 'ಹೂದೋಟ',
      'ಹೂ ತೋಟ', 'ಗಾರ್ಡನ್ ಮ್ಯಾನ್',
      'ತೋಟ ನೋಡ್ಕೋಳೋರು', 'ಹೂದೋಟ ಮ್ಯಾನ್',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'baagban', 'baaghbaan', 'garden wala', 'maalee',
      // Zone 5 (Malenadu)
      'ತೋಟ ನೋಡ್ಕೊಳ್ಳೋರು',
    ],

    // ── Mechanic ─────────────────────────────────────────────────────────────
    'mechanic': [
      // Standard + Zone 1
      'mechanic', 'mechanics', 'ಮೆಕ್ಯಾನಿಕ್', 'ಮೆಕ್ಯಾನಿಕ್ಗಳು',
      'ಗಾಡಿ ರಿಪೇರಿ', 'ಬೈಕ್ ಮೆಕ್ಯಾನಿಕ್', 'garage kelasa', 'mechanicu',
      'ಗಾಡಿ ಸರಿ',
      // Zone 3 (Kalyana Karnataka — Hindi)
      'gaadi thik karne wala', 'repair wala', 'motor mistri',
      // Zone 7 (Belagavi)
      'gaadi rikshaw mechanic',
    ],

    // ── Welder ───────────────────────────────────────────────────────────────
    'welder': [
      // Standard + all zones
      'welder', 'ವೆಲ್ಡರ್', 'welding', 'ವೆಲ್ಡಿಂಗ್', 'ಕಬ್ಬಿಣ ಕೆಲಸ',
      'iron work', 'fabrication',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi)
      'loha kaam', 'loha kaam wala', 'lohe ka kaam', 'welding wala',
      // Zone 7 (Belagavi)
      'lohaar', 'lona kaam',
    ],

    // ── Tailor ───────────────────────────────────────────────────────────────
    'tailor': [
      // Standard + all zones
      'tailor', 'ದರ್ಜಿ', 'darji', 'ಹೊಲಿಗೆ', 'ಟೈಲರ್', 'ಹೊಲಿಗೆ ಮ್ಯಾನ್',
      'stitching', 'silai',
      // Zone 3 (Kalyana Karnataka — Urdu)
      'kapada silai', 'darji wala', 'kapada wala', 'silai wala',
      // Zone 7 (Belagavi — Marathi)
      'shivnakar', 'shivnakari',
    ],

    // ── Security ─────────────────────────────────────────────────────────────
    'security': [
      // Standard + all zones
      'security', 'ಭದ್ರತಾ ಸಿಬ್ಬಂದಿ', 'ವಾಚ್‌ಮನ್', 'watchman',
      'guard', 'ಗಾರ್ಡ್', 'ಕಾವಲ್ಗಾರ', 'kaaval', 'kaavalgar',
      'security guard', 'night watchman', 'night guard',
      // Zone 3 (Kalyana Karnataka — Urdu/Hindi — VERY COMMON!)
      'chaukidaar', 'chaukidar', 'chowkidar', 'chowkidaar',
      'watchman chahiye',
      // Zone 4 (Coastal)
      'kaavalgaraa', 'ಕಾವಲ್ ಮ್ಯಾನ್',
      // Zone 7 (Belagavi — Marathi)
      'pahara wala', 'rakhwala',
    ],

    // ── Agriculture ──────────────────────────────────────────────────────────
    'agriculture': [
      // Standard + Zone 1
      'agriculture', 'farmer', 'ಕೃಷಿ ಕೆಲಸ', 'ತೋಟದ ಕೆಲಸ',
      'ಕಾಫಿ ತೋಟ', 'ಆಳುಗಳು', 'ಮಂದಿ', 'ಕಟಾವು', 'ಕಾಫಿ ಕೊಯ್ಯೋರು',
      'thotada kelasa', 'coffee estate', 'alugalu',
      // Zone 5 (Malenadu — CORE ZONE for agriculture)
      'aaLu beku', 'thotada aalu', 'ಆಳು ಬೇಕು',
      'katavu aalu', 'ಕಟಾವು ಆಳು', 'ಎಸ್ಟೇಟ್ ಕೆಲಸ', 'estate kelasa',
      'coffee tota', 'ಕಾಫಿ ತೋಟ', 'adike katavu', 'ಅಡಿಕೆ ಕಟಾವು',
      'ಬೆಳ್ಳಂಬೆಳಗ್ಗೆ ಕೆಲಸ',
      // Zone 3 (Kalyana Karnataka — Hindi/Urdu)
      'khet kaam', 'khetiwala', 'fasal katai', 'khet wala',
      // Zone 7 (Belagavi — Marathi)
      'shetkari', 'shetachi kaam',
      // Kodagu (Zone 5b)
      'ಎಸ್ಟೇಟ್ ಮ್ಯಾನ್', 'naad kelasa',
      // Direct English forms picked up from code-mix
      'estate', 'estate kelasa', 'estate worker',
    ],
  };

  // ── Search Verbs — All Zones ───────────────────────────────────────────────
  static const List<String> searchVerbs = [
    // Zone 1 — Standard
    'ಹುಡುಕು', 'ಬೇಕು', 'ಬೇಕಾಗಿದ್ದಾರೆ', 'ಸಿಕ್ತಾರಾ', 'ಆಳು ಬೇಕು',
    'find', 'need', 'search', 'torisi', 'ತೋರಿಸಿ', 'nodri', 'ನೋಡ್ರಿ',
    'beku', 'bekagiddare', 'bekagidare',
    // Zone 2 — Dharwad
    'ಬೇಕ್ರಿ', 'bekri', 'ಬೇಕಾಗ್ಯಾರ', 'bekaagbaar', 'ಸಿಗ್ತಾರ್ರಿ',
    'sigtaarri', 'ಮಂದಿ ಬೇಕ್ರಿ', 'ಸಿಗ್ತಾರೇನ್ರಿ',
    // Zone 3 — Kalyana Karnataka (Urdu/Hindi)
    'chahiye', 'chaaiye', 'bheji', 'bhejo', 'mangta',
    'bhejna', 'laana', 'bulana',
    // Zone 4 — Coastal (Kundagannada)
    'ಉಳ್ಳೇರ್', 'ulleer', 'bekka', 'iddwara',
    // Zone 7 — Belagavi
    'beka', 'pahije',
  ];

  // ── Booking Verbs — All Zones ─────────────────────────────────────────────
  static const List<String> bookingVerbs = [
    // Standard
    'ಬುಕ್ ಮಾಡು', 'ಬುಕ್ ಮಾಡಿ', 'ಬುಕ್ ಮಾಡ್ರಿ', 'ಬುಕ್', 'ಬುಕಿಂಗ್',
    'ಕಳಿಸಿ', 'ಕಳುಹಿಸಿ', 'ಕಳಿಸ್ರಿ', 'ಕರಿಸಿ', 'ಕರೀರಿ',
    'book', 'hire', 'confirm', 'kalsi', 'book madi', 'book madu',
    // Zone 2 — Dharwad
    'ಕಳ್ಸ್ರಿ', 'kaLsri', 'ಆಗೈತಿ', 'agaiti', 'ಆಯ್ತು', // aytu = confirm
    // Zone 3 — Kalyana Karnataka
    'bhej do', 'bhejo', 'confirm karo', 'haan', 'theek hai',
    'ठीक है', 'haa', 'hanji',
    // Zone 4 — Coastal
    'ಆಯ್ತು', 'okay da', 'barpodu',
    // Zone 7 — Belagavi
    'bara', 'beka confirm', 'hoy',
  ];

  // ── Cancel Verbs — All Zones ──────────────────────────────────────────────
  static const List<String> cancelVerbs = [
    // Standard
    'ಕ್ಯಾನ್ಸಲ್', 'ರದ್ದು', 'ಬೇಡ', 'cancel', 'raddhu', 'beda',
    // Zone 2 — Dharwad
    'ಬ್ಯಾಡ', 'byada', 'ಬ್ಯಾಡ್ರಿ',
    // Zone 3 — Kalyana Karnataka
    'nahi chahiye', 'rehne do', 'nahi', 'chod do',
    // Zone 7 — Belagavi
    'nako', 'jaau de',
  ];

  // ── Tracking Verbs — All Zones ────────────────────────────────────────────
  static const List<String> trackingVerbs = [
    // Standard
    'ಎಲ್ಲಿದ್ದಾನೆ', 'ಎಲ್ಲಿಗೆ ಬಂದ', 'ಎಲ್ಲಿದ್ದಾರ್ರಿ', 'track', 'where',
    'status', 'ಸ್ಥಿತಿ', 'ಎಲ್ಲಿದ್ದಾರೆ', 'elliddane', 'ಯಾವಾಗ',
    'ಯಾವಾಗ ಬರ್ತಾರೆ', 'ಯಾವಾಗ ಬರ್ತಾರ್ರೀ',
    // Zone 2 — Dharwad
    'yavag bartar', 'eddaare', 'ellidaare',
    // Zone 3 — Kalyana Karnataka
    'kahan hai', 'kab aayega', 'kab aate hai',
    // Zone 4 — Coastal (Kundagannada)
    'enna iddara', // "where are they"
  ];

  // ── Urgent Words — All Zones ──────────────────────────────────────────────
  static const List<String> urgentWords = [
    // Standard
    'ಅರ್ಜೆಂಟ್', 'ತುರ್ತು', 'ಜಲ್ದಿ', 'ಬೇಗ', 'ಈಗಲೇ',
    'urgent', 'emergency', 'jaldi', 'bega', 'fast', 'quick', 'igale',
    // Zone 2 — Dharwad
    'ಬೇಗ ಮಾಡ್ರಿ', 'jaldi madri',
    // Zone 3 — Kalyana Karnataka (Urdu/Hindi)
    'jaldi', 'abhi chahiye', 'abhi', 'kal mat karo', 'turant',
    // Zone 4 — Coastal (Tulu-influenced)
    'ಬಜ್ಜಿ', 'bajji',
    // Zone 7 — Belagavi (Marathi)
    'lagech', 'lavkar', 'lavkara',
  ];

  // ── Verified / Quality Words ──────────────────────────────────────────────
  static const List<String> verifiedWords = [
    'verified', 'ವೆರಿಫೈಡ್', 'ಖಚಿತ', 'ಪರಿಶೀಲಿಸಿದ',
    // Zone 2 — Dharwad
    'ಖರೇ', 'khare', 'kharena',
    'certified', 'trusted',
    // Zone 3 — Kalyana Karnataka
    'pakka', 'achi tarah', 'bharosa waala',
  ];

  // ── Radius Keywords ──────────────────────────────────────────────────────
  static const Map<String, int> radiusKeywords = {
    '1': 1000, '2': 2000, '3': 3000, '5': 5000, '10': 10000, '20': 20000,
    'ಒಂದು': 1000, 'ಎರಡು': 2000, 'ಮೂರು': 3000,
    'ಐದು': 5000, 'ಹತ್ತು': 10000, 'ಇಪ್ಪತ್ತು': 20000,
  };
}

// ── Romanized Kannada → Canonical Token Normalizer ───────────────────────────
/// Replaces Roman-script Kannada tokens with their canonical Kannada equivalents.
/// Handles all zones' romanized forms.
class KannadaRomanizedNormalizer {
  static const Map<String, String> romanToKannadaTokenMap = {
    // Standard search/booking
    'beku': 'ಬೇಕು', 'bekri': 'ಬೇಕ್ರಿ', 'bekagide': 'ಬೇಕಾಗಿದೆ',
    'bekagiddare': 'ಬೇಕಾಗಿದ್ದಾರೆ', 'bekaagrari': 'ಬೇಕಾಗ್ಯಾರ',
    // People/worker
    'yaru': 'ಯಾರು', 'iddare': 'ಇದ್ದಾರೆ', 'iddaare': 'ಇದ್ದಾರೆ',
    'alugalu': 'ಆಳುಗಳು', 'alugal': 'ಆಳುಗಳು', 'mandi': 'ಮಂದಿ',
    // Location
    'hatra': 'ಹತ್ತಿರ', 'hatthira': 'ಹತ್ತಿರ', 'hatira': 'ಹತ್ತಿರ',
    'illi': 'ಇಲ್ಲಿ',
    // Work
    'kelasa': 'ಕೆಲಸ', 'kelsa': 'ಕೆಲಸ', 'thota': 'ತೋಟ',
    // Urgency
    'bega': 'ಬೇಗ', 'jaldi': 'ಜಲ್ದಿ', 'bajji': 'ಬೇಗ',
    // Money
    'rotta': 'ರೊಕ್ಕ', 'rokka': 'ರೊಕ್ಕ',
    // Verb endings
    'agaiti': 'ಆಗೈತಿ', 'aagaiti': 'ಆಗೈತಿ', 'agaitti': 'ಆಗೈತಿ',
    'bartare': 'ಬರುತ್ತಾರೆ', 'bartaare': 'ಬರುತ್ತಾರೆ',
    'barri': 'ಬನ್ನಿ', 'banri': 'ಬನ್ನಿ',
    'siktara': 'ಸಿಗುತ್ತಾರೆ', 'sigtare': 'ಸಿಗುತ್ತಾರೆ',
    'sigtaarri': 'ಸಿಗುತ್ತಾರೆ',
    'madi': 'ಮಾಡಿ', 'madu': 'ಮಾಡು', 'madri': 'ಮಾಡ್ರಿ',
    'nodi': 'ನೋಡಿ', 'nodri': 'ನೋಡ್ರಿ',
    'torisi': 'ತೋರಿಸಿ', 'kalsi': 'ಕಳಿಸಿ', 'kaLsri': 'ಕಳಿಸ್ರಿ',
    'elliddane': 'ಎಲ್ಲಿದ್ದಾನೆ',
    'namaskara': 'ನಮಸ್ಕಾರ', 'namaskaar': 'ನಮಸ್ಕಾರ',
    'aytu': 'ಆಯ್ತು', 'aitu': 'ಆಯ್ತು',
    // Coastal (Kundagannada)
    'barpira': 'ಬರ್ಪಿರಾ', 'barpodu': 'ಬರೊಡು', 'barpodu2': 'ಬರ್ಪೊಡು',
    'ulleer': 'ಉಳ್ಳೇರ್',
    // Selections
    'ondu': 'ಒಂದು', 'eradu': 'ಎರಡು', 'mooru': 'ಮೂರು',
    'naLku': 'ನಾಲ್ಕು', 'naaku': 'ನಾಲ್ಕು', 'aidu': 'ಐದು',
    // Confirm/cancel
    'hauda': 'ಹೌದು', 'beda': 'ಬೇಡ', 'byada': 'ಬೇಡ',
    'byaad': 'ಬೇಡ', 'raddhu': 'ರದ್ದು',
  };

  static String normalize(String input) {
    String text = input.trim();
    for (final entry in romanToKannadaTokenMap.entries) {
      final regExp = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      text = text.replaceAll(regExp, entry.value);
    }
    return text;
  }
}

// ── Dialect-Aware Phonetic Normalizer ─────────────────────────────────────────
/// All 8 zones have dedicated normalizers.
/// Run ALL of them on every utterance (order matters — most specific first).
class KannadaPhoneticNormalizer {

  // ── Zone 1: Southern Standard (Bengaluru/Mysuru/Mandya) ───────────────────
  static String normalizeSouthernStandard(String text) {
    var out = text;
    // Verb contractions: colloquial → canonical
    out = out.replaceAll(RegExp(r'ಬರ್ತಾರೆ'), 'ಬರುತ್ತಾರೆ');
    out = out.replaceAll(RegExp(r'ಸಿಗ್ತಾರೆ'), 'ಸಿಗುತ್ತಾರೆ');
    out = out.replaceAll(RegExp(r'ಮಾಡ್ತೀನಿ'), 'ಮಾಡುತ್ತೇನೆ');
    out = out.replaceAll(RegExp(r'ಮಾಡ್ತಾರೆ'), 'ಮಾಡುತ್ತಾರೆ');
    // "ಆಯ್ತು" as confirmation
    out = out.replaceAll(RegExp(r'\bಆಯ್ತು\b'), 'ಆಗಿದೆ');
    // ಬರ್ಬೇಕು = urgent come request
    out = out.replaceAll(RegExp(r'ಬರ್ಬೇಕು'), 'ಬರಬೇಕು');
    out = out.replaceAll(RegExp(r'ಆಗ್ಬೇಕು'), 'ಆಗಬೇಕು');
    // Mandya rural
    out = out.replaceAll(RegExp(r'ಎಷ್ಟ್ ರೊಕ್ಕ'), 'ಎಷ್ಟು ಹಣ');
    return out;
  }

  // ── Zone 2: North Karnataka / Dharwad ─────────────────────────────────────
  static String normalizeNorthKarnataka(String text) {
    var out = text;
    // Verb endings
    out = out.replaceAll(RegExp(r'ಬರ್ತಾರ್ರ[ೀಿ]|ಬರ್ತಾರ್ರೀ|ಬರ್ತಾರೆನ್ರಿ'), 'ಬರುತ್ತಾರೆ');
    out = out.replaceAll(RegExp(r'ಸಿಗ್ತಾರ್ರ[ೀಿ]|ಸಿಗ್ತಾರ್ರೀ|ಸಿಗ್ತಾರೇನ್ರಿ|ಸಿಗ್ತಾರನ್ರಿ'), 'ಸಿಗುತ್ತಾರೆ');
    out = out.replaceAll(RegExp(r'ಆಗೈತ[ೀಿ]|ಆಗೈತಿ|ಆಗ್ಯಾದ|ಆಗಿಲ್ಲೇನ್ರ[ೀಿ]'), 'ಆಗಿದೆ');
    out = out.replaceAll(RegExp(r'ರೊಕ್ಕ|ರೊಕ್ಕಾ'), 'ಹಣ');
    out = out.replaceAll(RegExp(r'ಮಂದಿ ಬೇಕಾಗ್ಯಾರ|ಮಂದಿ ಬೇಕಾಗ್ಯಾರ್ರೀ|ಮಂದಿ ಬೇಕ್ರಿ'), 'ಕೆಲಸಗಾರರು ಬೇಕಾಗಿದ್ದಾರೆ');
    out = out.replaceAll(RegExp(r'ಮಂದಿ ಕಳ್ಸ್ರಿ|ಮಂದಿ ಕಳಿಸ್ರಿ'), 'ಕಾರ್ಮಿಕರನ್ನು ಕಳಿಸಿ');
    out = out.replaceAll(RegExp(r'ಖರೇನಾ|ಖರೇ ಹೇಳ್ರ[ೀಿ]'), 'ನಿಜವಾ');
    // Honorific command forms
    out = out.replaceAll(RegExp(r'\bಬರ್ರ[ೀಿ]\b|\bಬರ್ರಿ\b'), 'ಬನ್ನಿ');
    out = out.replaceAll(RegExp(r'\bನಡೀರ್ರ[ೀಿ]\b'), 'ನಡೆಯಿರಿ');
    out = out.replaceAll(RegExp(r'\bಬ್ಯಾಡ\b|\bಬ್ಯಾಡ್ರಿ\b'), 'ಬೇಡ');
    out = out.replaceAll(RegExp(r'\bಮಾಡ್ರ[ೀಿ]\b|\bಮಾಡ್ರಿ\b'), 'ಮಾಡಿ');
    out = out.replaceAll(RegExp(r'\bಹೋಗ್ರಿ\b'), 'ಹೋಗಿ');
    out = out.replaceAll(RegExp(r'\bನೋಡ್ರಿ\b'), 'ನೋಡಿ');
    // mistri → mestri mapping
    out = out.replaceAll(RegExp(r'\bಮಿಸ್ತ್ರಿ\b'), 'ಮೇಸ್ತ್ರಿ');
    out = out.replaceAll(RegExp(r'\bmistri\b', caseSensitive: false), 'mestri');
    // bekri → beku
    out = out.replaceAll(RegExp(r'\bಬೇಕ್ರಿ\b'), 'ಬೇಕು');
    out = out.replaceAll(RegExp(r'\bbekri\b', caseSensitive: false), 'ಬೇಕು');
    return out;
  }

  // ── Zone 3: Kalyana Karnataka (Kalaburagi/Bidar) — Urdu/Hindi terms ────────
  static String normalizeKalyanaKarnataka(String text) {
    var out = text;
    // ⚠️ Compound terms FIRST — must run before generic 'kaam wala' below
    out = out.replaceAll(RegExp(r'\bloha\s*kaam\s*wala\b', caseSensitive: false), 'welder');
    out = out.replaceAll(RegExp(r'\bloha\s*kaam\b', caseSensitive: false), 'welder');
    out = out.replaceAll(RegExp(r'\blona\s*kaam\b', caseSensitive: false), 'welder');
    out = out.replaceAll(RegExp(r'\blohaar\b', caseSensitive: false), 'welder');
    out = out.replaceAll(RegExp(r'\bkhet\s*kaam\b', caseSensitive: false), 'agriculture');
    // Generic 'kaam wala' → helper (AFTER compound terms)
    out = out.replaceAll(RegExp(r'\bkaam\s*wala\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bkaamwala\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bmazdoor\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bmazdur\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bmazadoor\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bbeldar\b', caseSensitive: false), 'helper');
    out = out.replaceAll(RegExp(r'\bbijli\s*wala\b', caseSensitive: false), 'electrician');
    out = out.replaceAll(RegExp(r'\bbijliwala\b', caseSensitive: false), 'electrician');
    out = out.replaceAll(RegExp(r'\bbejli\s*wala\b', caseSensitive: false), 'electrician');
    out = out.replaceAll(RegExp(r'\brang\s*wala\b', caseSensitive: false), 'painter');
    out = out.replaceAll(RegExp(r'\brangwala\b', caseSensitive: false), 'painter');
    out = out.replaceAll(RegExp(r'\brand?\s*karne\s*wala\b', caseSensitive: false), 'painter');
    out = out.replaceAll(RegExp(r'\bnal\s*mestri\b', caseSensitive: false), 'plumber');
    out = out.replaceAll(RegExp(r'\bnal\s*mistri\b', caseSensitive: false), 'plumber');
    out = out.replaceAll(RegExp(r'\bpani\s*mistri\b', caseSensitive: false), 'plumber');
    out = out.replaceAll(RegExp(r'\bpipe\s*wala\b', caseSensitive: false), 'plumber');
    out = out.replaceAll(RegExp(r'\braj\s*mistri\b', caseSensitive: false), 'mason');
    out = out.replaceAll(RegExp(r'\braj\s*mistry\b', caseSensitive: false), 'mason');
    out = out.replaceAll(RegExp(r'\bcement\s*wala\b', caseSensitive: false), 'mason');
    out = out.replaceAll(RegExp(r'\bdarji\b', caseSensitive: false), 'tailor');
    out = out.replaceAll(RegExp(r'\bsilai\s*wala\b', caseSensitive: false), 'tailor');
    out = out.replaceAll(RegExp(r'\bkapada\s*silai\b', caseSensitive: false), 'tailor');
    out = out.replaceAll(RegExp(r'\bchaukidaa?r\b', caseSensitive: false), 'security');
    out = out.replaceAll(RegExp(r'\bchowkidaa?r\b', caseSensitive: false), 'security');
    out = out.replaceAll(RegExp(r'\bpahara\s*wala\b', caseSensitive: false), 'security');
    // loha kaam, lona kaam, lohaar, khet kaam already handled at top of method
    out = out.replaceAll(RegExp(r'\bbaagban\b', caseSensitive: false), 'gardener');
    out = out.replaceAll(RegExp(r'\bbaaghbaan\b', caseSensitive: false), 'gardener');
    out = out.replaceAll(RegExp(r'\bbawarchi\b', caseSensitive: false), 'cook');
    out = out.replaceAll(RegExp(r'\bkhaana\s*banaane\b', caseSensitive: false), 'cook');
    // ── GENERAL TERMS ─────────────────────────────────────────────────────
    out = out.replaceAll(RegExp(r'\brokka\b'), 'ಹಣ');
    out = out.replaceAll(RegExp(r'\bhaajri\b', caseSensitive: false), 'ಹಾಜರಿ');
    out = out.replaceAll(RegExp(r'\bthekedar\b', caseSensitive: false), 'ಹೈರರ್');
    out = out.replaceAll(RegExp(r'\bmukadam\b', caseSensitive: false), 'ಮ್ಯಾನೇಜರ್');
    // ── VERB FORMS ────────────────────────────────────────────────────────
    out = out.replaceAll(RegExp(r'\bsigtaava\b'), 'ಸಿಗುತ್ತಾರೆ');
    out = out.replaceAll(RegExp(r'\bbekaagyada\b'), 'ಬೇಕಾಗಿದೆ');
    out = out.replaceAll(RegExp(r'\bchahiye\b', caseSensitive: false), 'ಬೇಕು');
    out = out.replaceAll(RegExp(r'\bchaaiye\b', caseSensitive: false), 'ಬೇಕು');
    // Confirm/cancel
    out = out.replaceAll(RegExp(r'\bhaan\b|\bhanji\b|\bhan\b', caseSensitive: false), 'ಹೌದು');
    out = out.replaceAll(RegExp(r'\bnahi\b|\bnaa\b', caseSensitive: false), 'ಬೇಡ');
    out = out.replaceAll(RegExp(r'\btheek\s*hai\b', caseSensitive: false), 'ಆಯ್ತು');
    out = out.replaceAll(RegExp(r'\babhi\b', caseSensitive: false), 'ಈಗಲೇ');
    return out;
  }

  // ── Zone 4: Coastal / Kundagannada ────────────────────────────────────────
  static String normalizeCoastal(String text) {
    var out = text;
    // Kundagannada verb forms
    out = out.replaceAll('ಬರ್ಪಿರಾ', 'ಬರುತ್ತೀರಾ');
    out = out.replaceAll('ಮಾಡ್ಪಿರಾ', 'ಮಾಡುತ್ತೀರಾ');
    out = out.replaceAll('ಬೇಗ ಬರೊಡು', 'ಬೇಗ ಬರಬೇಕು');
    out = out.replaceAll('ಬರ್ಪೊಡು', 'ಬರಬೇಕು');
    out = out.replaceAll('ಮಾಡ್ಪೊಡು', 'ಮಾಡಬೇಕು');
    out = out.replaceAll('ಬರೊಡು', 'ಬರಬೇಕು');
    out = out.replaceAll('ಉಳ್ಳೇರ್', 'ಇದ್ದಾರೆ');
    out = out.replaceAll(RegExp(r'\benna\b'), 'ಎಲ್ಲಿ'); // "where" in Kundagannada
    // Tulu-influenced terms → Kannada
    out = out.replaceAll(RegExp(r'\byaan\b'), 'ನಾನು');
    out = out.replaceAll(RegExp(r'\baanda\b'), 'ಅವರೆ');
    out = out.replaceAll(RegExp(r'\bincha\b'), 'ಹಾಗೆ');
    out = out.replaceAll(RegExp(r'\benda\b'), 'ಅಂತ');
    // Coastal skill terms → canonical
    out = out.replaceAll(RegExp(r'\badiga\b', caseSensitive: false), 'cook');
    out = out.replaceAll(RegExp(r'\bbadiga\b', caseSensitive: false), 'carpenter');
    out = out.replaceAll(RegExp(r'\bkaavalgar[ar]?\b', caseSensitive: false), 'security');
    // Urgency: bajji = fast
    out = out.replaceAll('ಬಜ್ಜಿ', 'ಬೇಗ');
    out = out.replaceAll(RegExp(r'\bbajji\b', caseSensitive: false), 'ಬೇಗ');
    return out;
  }

  // ── Zone 5: Malenadu (Hassan / Chikkamagaluru / Shivamogga) ───────────────
  static String normalizeMalenadu(String text) {
    var out = text;
    // Timing expressions
    out = out.replaceAll('ಬೆಳ್ಳಂಬೆಳಗ್ಗೆ', 'ಮುಂಜಾನೆ');
    out = out.replaceAll('ಮಳೇಲಿ', 'ಮಳೆಯಲ್ಲಿ');
    out = out.replaceAll('ಜಲ್ದಿ', 'ಬೇಗ');
    // Agricultural worker terms → canonical
    out = out.replaceAll('ಆಳು ಬೇಕು', 'ಕೆಲಸಗಾರರು ಬೇಕು');
    out = out.replaceAll('ಆಳುಗಳು ಬೇಕು', 'ಕೆಲಸಗಾರರು ಬೇಕು');
    out = out.replaceAll('ತೋಟದ ಆಳು', 'ತೋಟದ ಕೆಲಸಗಾರ');
    out = out.replaceAll('ಕಟಾವು ಆಳು', 'ಕೃಷಿ ಕಾರ್ಮಿಕ');
    out = out.replaceAll('ಎಸ್ಟೇಟ್ ಕೆಲಸ', 'thotada kelasa');
    out = out.replaceAll('ಅಡಿಕೆ ಕಟಾವು', 'ಕೃಷಿ ಕಟಾವು');
    // Coffee estate synonyms
    out = out.replaceAll(RegExp(r'\bcoffee\s*tota\b', caseSensitive: false), 'coffee estate');
    return out;
  }

  // ── Zone 6: Havyaka (Old Kannada preserving) ─────────────────────────────
  static String normalizeHavyaka(String text) {
    var out = text;
    // Archaic vocabulary → standard
    out = out.replaceAll(RegExp(r'\btoti\b|\bಟೊಟಿ\b|\bತೊಟಿ\b'), 'ನಲ್ಲಿ'); // tap/water = plumbing
    out = out.replaceAll(RegExp(r'\badiga\b', caseSensitive: false), 'cook');
    out = out.replaceAll(RegExp(r'\bbegane\b', caseSensitive: false), 'ಬೇಗ');
    out = out.replaceAll('ಗೃಹ ಕಾರ್ಯ', 'ಮನೆ ಕೆಲಸ');
    return out;
  }

  // ── Zone 7: Belagavi / Vijayapura (Kannada+Marathi) ──────────────────────
  static String normalizeBelagaviBorder(String text) {
    var out = text;
    // Marathi-origin construction terms → Kannada
    out = out.replaceAll(RegExp(r'\bdagada?\b', caseSensitive: false), 'ಕಲ್ಲು ಕೆಲಸ');
    out = out.replaceAll(RegExp(r'\bhware\b', caseSensitive: false), 'ಕೆಲಸ');
    out = out.replaceAll(RegExp(r'\bmistri\b', caseSensitive: false), 'ಮೇಸ್ತ್ರಿ');
    out = out.replaceAll(RegExp(r'\blohaar\b', caseSensitive: false), 'welder');
    // Phonetic vowel corrections (Marathi pattern)
    out = out.replaceAll(RegExp(r'\bmani\b'), 'ಮನೆ'); // mane→mani
    out = out.replaceAll(RegExp(r'\bhotela\b', caseSensitive: false), 'hotel');
    // Verb forms: beka → beku
    out = out.replaceAll(RegExp(r'\bbeka\b'), 'ಬೇಕು');
    out = out.replaceAll(RegExp(r'\bbara\b'), 'ಬನ್ನಿ');
    out = out.replaceAll(RegExp(r'\bmada\b'), 'ಮಾಡಿ');
    out = out.replaceAll(RegExp(r'\baagtada\b'), 'ಆಗ್ತದೆ');
    out = out.replaceAll(RegExp(r'\bhyaanga\s*mada\b', caseSensitive: false), 'ಹೇಗೆ ಮಾಡಿ');
    // Marathi confirm/cancel
    out = out.replaceAll(RegExp(r'\bhoy\b'), 'ಹೌದು');
    out = out.replaceAll(RegExp(r'\bnako\b'), 'ಬೇಡ');
    out = out.replaceAll(RegExp(r'\bpahije\b'), 'ಬೇಕು');
    // Urgency (Marathi)
    out = out.replaceAll(RegExp(r'\blavkar\b|\blagech\b|\blavkara\b', caseSensitive: false), 'ಬೇಗ');
    return out;
  }

  // ── Zone 5b: Kodagu ───────────────────────────────────────────────────────
  static String normalizeKodagu(String text) {
    var out = text;
    out = out.replaceAll(RegExp(r'\bnaad\b'), 'ಊರು');
    out = out.replaceAll(RegExp(r'\bokay-?da\b', caseSensitive: false), 'ಆಯ್ತು');
    out = out.replaceAll('ಎಸ್ಟೇಟ್ ಕೆಲಸ', 'thotada kelasa');
    out = out.replaceAll('ಅಡಿಕೆ ಕಟಾವು', 'ಕೃಷಿ ಕಟಾವು');
    return out;
  }

  /// Detect dialect profile from utterance content
  static RegionalKannadaProfile _detectProfile(String original) {
    final lower = original.toLowerCase();

    // Code-mixed: both scripts
    if (RegExp(r'[a-zA-Z]').hasMatch(original) &&
        RegExp(r'[\u0C80-\u0CFF]').hasMatch(original)) {
      return RegionalKannadaProfile.codeMixed;
    }

    // Romanized Kannada
    if (RegExp(r'^[a-zA-Z0-9\s.,!?-]+$').hasMatch(original)) {
      final isRomanKn = ['beku', 'hatra', 'yaru', 'kelasa', 'bekri',
        'mandi', 'agaiti', 'mestri', 'madri', 'bartare'].any(lower.contains);
      if (isRomanKn) return RegionalKannadaProfile.romanized;
    }

    // Zone 3 — Kalyana Karnataka (Urdu/Hindi loanwords)
    if (['mazdoor', 'bijli wala', 'rang wala', 'chaukidaar', 'chaukidar',
         'raj mistri', 'beldar', 'haajri', 'thekedar', 'rokka',
         'chahiye', 'haan', 'nahi', 'theek hai'].any(lower.contains)) {
      return RegionalKannadaProfile.kalyanaKarnataka;
    }

    // Zone 7 — Belagavi Border (Marathi)
    if (['dagada', 'pahije', 'nako', 'hoy', 'lavkar', 'lagech',
         'bandkam'].any(lower.contains)) {
      return RegionalKannadaProfile.belagaviBorder;
    }

    // Zone 4 — Coastal / Kundagannada
    if (original.contains('ಬರ್ಪಿರಾ') || original.contains('ಮಾಡ್ಪಿರಾ') ||
        original.contains('ಬರೊಡು') || original.contains('ಉಳ್ಳೇರ್') ||
        lower.contains('barpira') || lower.contains('adiga') ||
        lower.contains('badiga') || lower.contains('bajji')) {
      return RegionalKannadaProfile.coastal;
    }

    // Zone 6 — Havyaka
    if (lower.contains('toti') || original.contains('ತೊಟಿ') ||
        lower.contains('begane') || original.contains('ಗೃಹ ಕಾರ್ಯ')) {
      return RegionalKannadaProfile.havyaka;
    }

    // Zone 5b — Kodagu
    if (lower.contains('naad') || lower.contains('okay-da') ||
        original.contains('ಎಸ್ಟೇಟ್')) {
      return RegionalKannadaProfile.kodagu;
    }

    // Zone 5 — Malenadu
    if (original.contains('ಬೆಳ್ಳಂಬೆಳಗ್ಗೆ') || original.contains('ಆಳು ಬೇಕು') ||
        original.contains('ಕಾಫಿ ತೋಟ') || original.contains('ತೋಟದ ಕೆಲಸ') ||
        lower.contains('coffee tota') || lower.contains('katavu') ||
        lower.contains('estate kelasa')) {
      return RegionalKannadaProfile.malenadu;
    }

    // Zone 2 — North Karnataka / Dharwad
    if (original.contains('್ರೀ') || original.contains('ರೊಕ್ಕ') ||
        original.contains('ಆಗೈತಿ') || original.contains('ಬೇಕಾಗ್ಯಾರ') ||
        original.contains('ಸಿಗ್ತಾರ್ರ') || original.contains('ಮಿಸ್ತ್ರಿ') ||
        lower.contains('bekri') || lower.contains('mistri') ||
        lower.contains('agaiti') || lower.contains('rokka') ||
        original.contains('ಖರೇ') || lower.contains('mandi')) {
      return RegionalKannadaProfile.northKarnataka;
    }

    // Zone 1 — Southern Standard / Unknown
    return RegionalKannadaProfile.standard;
  }

  /// Main normalization pipeline — runs ALL dialect normalizers in sequence.
  /// Order: specific (Zone 3, 7) → medium (Zone 2, 4) → general (Zone 5, 6) → standard
  static NormalizedVoiceQuery analyzeAndNormalize(String rawQuery) {
    final original = rawQuery.trim();
    if (original.isEmpty) {
      return const NormalizedVoiceQuery(
        originalQuery: '', normalizedText: '', canonicalIntent: 'unknown', confidence: 0.0,
      );
    }

    // Step 1: Detect profile
    final profile = _detectProfile(original);

    // Step 2: Romanized normalization (all zones use Latin script sometimes)
    var text = KannadaRomanizedNormalizer.normalize(original);

    // Step 3: Zone-specific normalizations (order matters — most specific first)
    text = normalizeKalyanaKarnataka(text);    // Zone 3: Urdu loanwords (most unique)
    text = normalizeBelagaviBorder(text);       // Zone 7: Marathi terms
    text = normalizeCoastal(text);              // Zone 4: Tulu terms
    text = normalizeHavyaka(text);              // Zone 6: Old Kannada terms
    text = normalizeKodagu(text);               // Zone 5b: Kodava terms
    text = normalizeMalenadu(text);             // Zone 5: Coffee belt
    text = normalizeNorthKarnataka(text);       // Zone 2: Dharwad verb forms
    text = normalizeSouthernStandard(text);     // Zone 1: Southern contractions

    final lowerText = text.toLowerCase();

    // Step 4: Extract canonical skill
    String? matchedSkill;
    outer:
    for (final entry in KelasagaraKannadaDomainLexicon.skillSynonyms.entries) {
      for (final synonym in entry.value) {
        if (lowerText.contains(synonym.toLowerCase())) {
          matchedSkill = entry.key;
          break outer;
        }
      }
    }

    // Step 5: Extract canonical intent
    String intent = 'general_query';
    if (KelasagaraKannadaDomainLexicon.bookingVerbs
        .any((v) => lowerText.contains(v.toLowerCase()))) {
      intent = 'book_worker';
    } else if (KelasagaraKannadaDomainLexicon.cancelVerbs
        .any((v) => lowerText.contains(v.toLowerCase()))) {
      intent = 'cancel_booking';
    } else if (KelasagaraKannadaDomainLexicon.trackingVerbs
        .any((v) => lowerText.contains(v.toLowerCase()))) {
      intent = 'track_worker';
    } else if (matchedSkill != null ||
        KelasagaraKannadaDomainLexicon.searchVerbs
            .any((v) => lowerText.contains(v.toLowerCase()))) {
      intent = 'search_workers';
    } else if (lowerText.contains('settings') || lowerText.contains('ಸೆಟ್ಟಿಂಗ್ಸ್')) {
      intent = 'navigate_screen';
    }

    // Step 6: Urgency
    final isUrgent = KelasagaraKannadaDomainLexicon.urgentWords
        .any((w) => lowerText.contains(w.toLowerCase()));

    // Step 7: Verification filter
    final verifiedOnly = KelasagaraKannadaDomainLexicon.verifiedWords
        .any((w) => lowerText.contains(w.toLowerCase()));

    // Step 8: Radius hint
    int? extractedRadius;
    for (final entry in KelasagaraKannadaDomainLexicon.radiusKeywords.entries) {
      if (lowerText.contains('${entry.key} km') ||
          lowerText.contains('${entry.key} ಕಿಲೋಮೀಟರ್') ||
          lowerText.contains('${entry.key} ಕಿಮೀ') ||
          lowerText.contains('${entry.key} kilometer')) {
        extractedRadius = entry.value;
        break;
      }
    }

    // Step 9: Dynamic keyterms for Sarvam ASR hint
    final dynamicKeyterms = <String>{};
    if (matchedSkill != null) {
      dynamicKeyterms.add(matchedSkill);
      final synonyms = KelasagaraKannadaDomainLexicon.skillSynonyms[matchedSkill];
      if (synonyms != null) dynamicKeyterms.addAll(synonyms.take(4));
    }
    // Add dialect-specific keyterms for Sarvam hint
    dynamicKeyterms.addAll(_dialectKeyterms(profile));
    dynamicKeyterms.addAll(['Kelasagara', 'ಕೆಲಸಗಾರ', 'booking', 'ಬುಕ್', 'verified']);

    return NormalizedVoiceQuery(
      originalQuery: original,
      normalizedText: text,
      canonicalSkill: matchedSkill,
      canonicalIntent: intent,
      extractedRadiusMeters: extractedRadius,
      isUrgent: isUrgent,
      verifiedOnly: verifiedOnly,
      detectedProfile: profile,
      dynamicKeyterms: dynamicKeyterms.toList(),
      confidence: matchedSkill != null ? 0.95 : 0.85,
    );
  }

  /// Public accessor for dialect-specific Sarvam keyterms (used by DistrictDialectMapper)
  static List<String> dialectKeytermsPublic(RegionalKannadaProfile profile) =>
      _dialectKeyterms(profile);

  /// Returns top Sarvam ASR keyterms for each dialect zone
  static List<String> _dialectKeyterms(RegionalKannadaProfile profile) {
    switch (profile) {
      case RegionalKannadaProfile.kalyanaKarnataka:
        return ['mazdoor', 'thekedar', 'haajri', 'bijli wala', 'rang wala',
                'mistri', 'beldar', 'chaukidaar', 'darji', 'loha kaam'];
      case RegionalKannadaProfile.coastal:
        return ['barpira', 'barpodu', 'kaavalgar', 'adiga', 'badiga',
                'Kundagannada', 'ulleer', 'bajji'];
      case RegionalKannadaProfile.northKarnataka:
        return ['bekri', 'mandi', 'rokka', 'khare', 'agaiti',
                'mistri', 'madri', 'barri', 'nodri', 'sigtaarri'];
      case RegionalKannadaProfile.belagaviBorder:
        return ['mistri', 'dagada', 'beka', 'pahije', 'nako', 'hoy',
                'lavkar', 'bandkam'];
      case RegionalKannadaProfile.malenadu:
        return ['aaLu beku', 'thotada aalu', 'katavu', 'coffee tota',
                'estate kelasa', 'jaldi'];
      case RegionalKannadaProfile.havyaka:
        return ['toti', 'adiga', 'begane', 'gruha kaarya'];
      case RegionalKannadaProfile.kodagu:
        return ['naad', 'estate', 'adike', 'katavu'];
      default:
        return ['ಕೆಲಸಗಾರ', 'ಮೇಸ್ತ್ರಿ', 'ಬೇಕು', 'ಹತ್ತಿರ'];
    }
  }
}
