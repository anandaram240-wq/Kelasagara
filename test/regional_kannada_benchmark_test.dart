import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/voice/regional_kannada_normalizer.dart';

void main() {
  group('Kelasagara Regional Kannada & Dialect Normalizer Tests', () {
    test('Malenadu dialect normalization: coffee estate, rural terms', () {
      final query1 = 'ಬೆಳ್ಳಂಬೆಳಗ್ಗೆ ಕಾಫಿ ತೋಟಕ್ಕೆ ಆಳು ಬೇಕು';
      final res1 = KannadaPhoneticNormalizer.analyzeAndNormalize(query1);

      expect(res1.detectedProfile, RegionalKannadaProfile.malenadu);
      expect(res1.canonicalSkill, 'agriculture');
      expect(res1.canonicalIntent, 'search_workers');

      final query2 = 'ಜಲ್ದಿ ಪೇಂಟರ್ ಕಳಿಸಿ';
      final res2 = KannadaPhoneticNormalizer.analyzeAndNormalize(query2);
      expect(res2.isUrgent, isTrue);
      expect(res2.canonicalSkill, 'painter');
      expect(res2.canonicalIntent, 'book_worker');
    });

    test('North Karnataka dialect normalization: verbal suffixes and honorifics', () {
      final query1 = 'ಯಾವಾಗ ಬರ್ತಾರ್ರೀ ಪ್ಲಂಬರ್';
      final res1 = KannadaPhoneticNormalizer.analyzeAndNormalize(query1);
      expect(res1.detectedProfile, RegionalKannadaProfile.northKarnataka);
      expect(res1.canonicalSkill, 'plumber');
      expect(res1.canonicalIntent, 'track_worker');

      final query2 = 'ಕೆಲ್ಸಕ್ಕ ಪೇಂಟರ್ ಸಿಗ್ತಾರೇನ್ರಿ';
      final res2 = KannadaPhoneticNormalizer.analyzeAndNormalize(query2);
      expect(res2.canonicalSkill, 'painter');
      expect(res2.canonicalIntent, 'search_workers');

      final query3 = 'ಪೇಂಟರ್ ಬುಕ್ ಮಾಡ್ರಿ';
      final res3 = KannadaPhoneticNormalizer.analyzeAndNormalize(query3);
      expect(res3.canonicalSkill, 'painter');
      expect(res3.canonicalIntent, 'book_worker');
    });

    test('Coastal Karnataka normalization (Mangaluru/Udupi)', () {
      final query = 'ಬೇಗ ಬರೊಡು ಎಲೆಕ್ಟ್ರಿಷಿಯನ್';
      final res = KannadaPhoneticNormalizer.analyzeAndNormalize(query);
      expect(res.detectedProfile, RegionalKannadaProfile.coastal);
      expect(res.canonicalSkill, 'electrician');
      expect(res.isUrgent, isTrue);
    });

    test('Code-Mixed Kannada-English intent extraction', () {
      final query1 = 'Urgent painter ಬೇಕು 5 km ಒಳಗೆ';
      final res1 = KannadaPhoneticNormalizer.analyzeAndNormalize(query1);
      expect(res1.canonicalSkill, 'painter');
      expect(res1.extractedRadiusMeters, 5000);
      expect(res1.isUrgent, isTrue);

      final query2 = 'Verified plumber ಮಾತ್ರ ಬುಕ್ ಮಾಡು';
      final res2 = KannadaPhoneticNormalizer.analyzeAndNormalize(query2);
      expect(res2.canonicalSkill, 'plumber');
      expect(res2.verifiedOnly, isTrue);
      expect(res2.canonicalIntent, 'book_worker');
    });

    test('Romanized Kannada phonetic transliteration normalization', () {
      final query1 = 'nanna hatra painter beku';
      final res1 = KannadaPhoneticNormalizer.analyzeAndNormalize(query1);
      expect(res1.canonicalSkill, 'painter');
      expect(res1.canonicalIntent, 'search_workers');

      final query2 = 'bega plumber kalsi';
      final res2 = KannadaPhoneticNormalizer.analyzeAndNormalize(query2);
      expect(res2.canonicalSkill, 'plumber');
      expect(res2.isUrgent, isTrue);
      expect(res2.canonicalIntent, 'book_worker');
    });

    test('Non-blocking dialect principle: low dialect confidence never blocks intent', () {
      final query = 'ನನ್ನ ಹತ್ರ painter ಬೇಕು';
      final res = KannadaPhoneticNormalizer.analyzeAndNormalize(query);
      // Even if profile is standard or mixed, skill and intent must be accurately resolved
      expect(res.canonicalSkill, 'painter');
      expect(res.canonicalIntent, 'search_workers');
      expect(res.confidence, greaterThanOrEqualTo(0.85));
    });

    test('Dynamic keyterms generated for Sarvam Saaras v4 prompting', () {
      final query = 'ಕಾರ್ಪೆಂಟರ್ ಬುಕ್ ಮಾಡು';
      final res = KannadaPhoneticNormalizer.analyzeAndNormalize(query);
      expect(res.dynamicKeyterms, contains('carpenter'));
      expect(res.dynamicKeyterms, contains('Kelasagara'));
      expect(res.dynamicKeyterms.length, lessThanOrEqualTo(20));
    });
  });
}
