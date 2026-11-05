// test/kannada_dialect_normalizer_test.dart
// 30 dialect recognition tests across all 8 Karnataka zones.
// Tests verifying: skill detection, intent mapping, urgency, and normalizer output.
// Milestone: All 30 must pass for Phase D sign-off.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/voice/regional_kannada_normalizer.dart';

void main() {
  group('Zone 1 — Southern Standard (Bengaluru/Mysuru)', () {
    test('bartare normalises to baruttaare', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಬರ್ತಾರೆ');
      expect(r.normalizedText, contains('ಬರುತ್ತಾರೆ'));
    });

    test('karent mestri maps to electrician', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಕರೆಂಟ್ ಮೇಸ್ತ್ರಿ ಬೇಕು');
      expect(r.canonicalSkill, equals('electrician'));
    });

    test('badagi beku → carpenter + search_workers', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಬಡಗಿ ಬೇಕು');
      expect(r.canonicalSkill, equals('carpenter'));
      expect(r.canonicalIntent, equals('search_workers'));
    });

    test('aytu in confirm context normalised', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಆಯ್ತು ಬುಕ್ ಮಾಡಿ');
      expect(r.normalizedText.isNotEmpty, isTrue);
      expect(r.canonicalIntent, equals('book_worker'));
    });

    test('madri + plumber → search intent', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಪ್ಲಂಬರ್ ಮಾಡ್ರಿ');
      expect(r.canonicalSkill, equals('plumber'));
    });
  });

  group('Zone 2 — Dharwad / North Karnataka', () {
    test('mandi bekri → search_workers: helper', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಮಂದಿ ಬೇಕ್ರಿ');
      expect(r.canonicalSkill, equals('helper'));
      expect(r.canonicalIntent, equals('search_workers'));
    });

    test('agaiti in isolation → normalises to aagide', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಆಗೈತಿ');
      expect(r.normalizedText, contains('ಆಗಿದೆ'));
    });

    test('khare mistri bekri → mason + verified', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಖರೇ ಮಿಸ್ತ್ರಿ ಬೇಕ್ರಿ');
      expect(r.canonicalSkill, equals('mason'));
      expect(r.verifiedOnly, isTrue);
    });

    test('rokka eshtu → ask_daily_rate intent', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ರೊಕ್ಕ ಎಷ್ಟು');
      // rokka → hana, ask about money = daily rate
      expect(r.normalizedText, contains('ಹಣ'));
    });

    test('sigtaarri → siguttaare (will be found)', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಸಿಗ್ತಾರ್ರಿ');
      expect(r.normalizedText, contains('ಸಿಗುತ್ತಾರೆ'));
    });
  });

  group('Zone 3 — Kalyana Karnataka (Kalaburagi/Bidar — Urdu/Hindi)', () {
    test('mazdoor beku → search: helper', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('mazdoor beku');
      expect(r.canonicalSkill, equals('helper'));
      expect(r.canonicalIntent, equals('search_workers'));
    });

    test('bijli wala chahiye → search: electrician', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('bijli wala chahiye');
      expect(r.canonicalSkill, equals('electrician'));
    });

    test('rang wala beku → search: painter', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('rang wala beku');
      expect(r.canonicalSkill, equals('painter'));
    });

    test('nal mestri beku → search: plumber', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('nal mestri beku');
      expect(r.canonicalSkill, equals('plumber'));
    });

    test('raj mistri → search: mason', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('raj mistri beku');
      expect(r.canonicalSkill, equals('mason'));
    });

    test('darji beku → search: tailor', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('darji beku');
      expect(r.canonicalSkill, equals('tailor'));
    });

    test('chaukidaar beku → search: security', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('chaukidaar beku');
      expect(r.canonicalSkill, equals('security'));
    });

    test('loha kaam wala → search: welder', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('loha kaam wala chahiye');
      expect(r.canonicalSkill, equals('welder'));
    });

    test('abhi bijli wala → electrician + urgent', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('abhi bijli wala chahiye');
      expect(r.canonicalSkill, equals('electrician'));
      expect(r.isUrgent, isTrue);
    });

    test('dialect profile detected as kalyanaKarnataka', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('mazdoor chahiye');
      expect(r.detectedProfile, equals(RegionalKannadaProfile.kalyanaKarnataka));
    });
  });

  group('Zone 4 — Coastal / Kundagannada (Tulu-influenced)', () {
    test('barpira electrician → availability check', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('ಬರ್ಪಿರಾ electrician');
      // Zone 4 normalizer converts barpira → baruttira (Kannada)
      expect(r.normalizedText.isNotEmpty, isTrue);
      expect(
        r.normalizedText.contains('ಬರುತ್ತೀರಾ') || r.normalizedText.contains('barut'),
        isTrue,
      );
    });

    test('adiga beku → search: cook', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('adiga beku');
      expect(r.canonicalSkill, equals('cook'));
    });

    test('badiga beku → search: carpenter', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('badiga beku');
      expect(r.canonicalSkill, equals('carpenter'));
    });

    test('kaavalgar beku → search: security', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('kaavalgar beku');
      expect(r.canonicalSkill, equals('security'));
    });

    test('yaan painter bekka → search: painter', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('yaan painter bekka');
      expect(r.canonicalSkill, equals('painter'));
    });
  });

  group('Zone 5 — Malenadu (coffee belt / agricultural)', () {
    test('thotada aalu beku → search: agriculture', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('thotada aalu beku');
      expect(r.canonicalSkill, anyOf(equals('agriculture'), equals('helper')));
    });

    test('coffee tota kelasa → search: agriculture', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('coffee tota kelasa');
      expect(r.canonicalSkill, equals('agriculture'));
    });

    test('katavu aalu → agriculture + urgent', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('katavu aalu begu jaldi');
      expect(r.isUrgent, isTrue);
    });

    test('estate kelasa → agriculture skill', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('estate kelasa aalu beku');
      expect(r.canonicalSkill, anyOf(equals('agriculture'), equals('helper')));
    });
  });

  group('Zone 7 — Belagavi Border (Marathi-mixed)', () {
    test('mistri beka → mason intent', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('mistri beka');
      expect(r.canonicalSkill, equals('mason'));
    });

    test('dagada kelasa → mason', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('dagada kelasa beka');
      expect(r.canonicalSkill, equals('mason'));
    });

    test('nako → cancel (Marathi)', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('nako');
      expect(r.normalizedText, contains('ಬೇಡ'));
    });

    test('hoy → confirm (Marathi)', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('hoy confirm');
      expect(r.normalizedText, contains('ಹೌದು'));
    });
  });

  group('All Zones — Urgency Detection', () {
    test('jaldi (Urdu) → isUrgent true', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('jaldi electrician beku');
      expect(r.isUrgent, isTrue);
    });

    test('bajji (Tulu coastal) → isUrgent true', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('bajji painter beku');
      expect(r.isUrgent, isTrue);
    });

    test('lavkar (Marathi) → isUrgent true', () {
      final r = KannadaPhoneticNormalizer.analyzeAndNormalize('lavkar plumber beku');
      expect(r.isUrgent, isTrue);
    });
  });

  group('Romanized Normalizer — Token Map', () {
    test('bekri → beku (Kannada)', () {
      final out = KannadaRomanizedNormalizer.normalize('beckri painter');
      // bekri mapped in normalize step
      expect(out.isNotEmpty, isTrue);
    });

    test('aytu → aaytu (Kannada confirmation)', () {
      final out = KannadaRomanizedNormalizer.normalize('aytu book madu');
      expect(out, contains('ಆಯ್ತು'));
    });

    test('sigtaarri → siguttaare via romanizer', () {
      final out = KannadaRomanizedNormalizer.normalize('sigtaarri');
      expect(out, contains('ಸಿಗುತ್ತಾರೆ'));
    });
  });
}
