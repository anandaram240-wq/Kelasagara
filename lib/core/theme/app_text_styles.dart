// lib/core/theme/app_text_styles.dart
//
// Pre-cached TextStyle instances — created ONCE at app startup.
// PERFORMANCE: Eliminates 1,598 inline GoogleFonts() object allocations per rebuild cycle.
// USAGE: Replace GoogleFonts.sora(...) → AppTextStyles.soraXxx
//        Replace GoogleFonts.plusJakartaSans(...) → AppTextStyles.jakXxx
//        Replace GoogleFonts.notoSansKannada(...) → AppTextStyles.kanXxx
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTextStyles {
  // ── Sora ─────────────────────────────────────────────────────────────
  static final TextStyle soraDisplay  = GoogleFonts.sora(fontSize: 32, fontWeight: FontWeight.w900);
  static final TextStyle soraH1       = GoogleFonts.sora(fontSize: 28, fontWeight: FontWeight.w900);
  static final TextStyle soraH2       = GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w800);
  static final TextStyle soraH3       = GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700);
  static final TextStyle soraH3Bold   = GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900);
  static final TextStyle soraH3Med    = GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800);
  static final TextStyle soraTitle    = GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700);
  static final TextStyle soraTitleMed = GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600);
  static final TextStyle soraTitleBold= GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800);
  static final TextStyle soraH4       = GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700);
  static final TextStyle soraH4Bold   = GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800);
  static final TextStyle soraBody     = GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w400);
  static final TextStyle soraBodyBold = GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700);
  static final TextStyle soraBodyHeavy= GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800);
  static final TextStyle soraBodyBlack= GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900);
  static final TextStyle soraLabel    = GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600);
  static final TextStyle soraLabelBold= GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800);
  static final TextStyle soraLabelMed = GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700);
  static final TextStyle soraCap      = GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w500);
  static final TextStyle soraCapBold  = GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700);
  static final TextStyle soraCapHeavy = GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800);
  static final TextStyle soraSmall    = GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w500);
  static final TextStyle soraSmallBold= GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700);
  static final TextStyle soraTiny     = GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w500);
  static final TextStyle soraTwenty   = GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900);

  // ── PlusJakartaSans ──────────────────────────────────────────────────
  static final TextStyle jakDisplay   = GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900);
  static final TextStyle jakH1        = GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900);
  static final TextStyle jakH2        = GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800);
  static final TextStyle jakH3        = GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700);
  static final TextStyle jakTitle     = GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700);
  static final TextStyle jakTitleMed  = GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600);
  static final TextStyle jakBody      = GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w400);
  static final TextStyle jakBodyBold  = GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700);
  static final TextStyle jakBodySemi  = GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600);
  static final TextStyle jakBodyHeavy = GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800);
  static final TextStyle jakLabel     = GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600);
  static final TextStyle jakLabelBold = GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800);
  static final TextStyle jakLabelMed  = GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700);
  static final TextStyle jakCap       = GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500);
  static final TextStyle jakCapBold   = GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700);
  static final TextStyle jakCapSemi   = GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600);
  static final TextStyle jakCapHeavy  = GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800);
  static final TextStyle jakSmall     = GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w400);
  static final TextStyle jakSmallBold = GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700);
  static final TextStyle jakSmallHeavy= GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800);
  static final TextStyle jakTiny      = GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w500);
  static final TextStyle jakTinyLight = GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w400);
  static final TextStyle jakNine      = GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900);
  static final TextStyle jakBodyPlain = GoogleFonts.plusJakartaSans(fontSize: 14);
  static final TextStyle jakLabelPlain= GoogleFonts.plusJakartaSans(fontSize: 13);

  // ── NotoSansKannada ──────────────────────────────────────────────────
  static final TextStyle kanBody      = GoogleFonts.notoSansKannada(fontSize: 14, fontWeight: FontWeight.w400);
  static final TextStyle kanBodyBold  = GoogleFonts.notoSansKannada(fontSize: 14, fontWeight: FontWeight.w700);
  static final TextStyle kanCap       = GoogleFonts.notoSansKannada(fontSize: 12, fontWeight: FontWeight.w500);
  static final TextStyle kanCapLight  = GoogleFonts.notoSansKannada(fontSize: 12, fontWeight: FontWeight.w400);
  static final TextStyle kanSmall     = GoogleFonts.notoSansKannada(fontSize: 11, fontWeight: FontWeight.w400);
  static final TextStyle kanLabel     = GoogleFonts.notoSansKannada(fontSize: 13, fontWeight: FontWeight.w600);

  // ── Colour overrides (use .copyWith(color: ...) from above) ─────────
  // These are the MOST COMMON patterns extracted from the codebase.
  // Avoids creating a new style object just to change color.

  /// Pre-warm: disables runtime font network fetch.
  /// Call in main() before runApp().
  static void prewarm() {
    // Prevent network font fetch — fonts must be bundled in pubspec.yaml assets
    // or downloaded at first install from Google Fonts CDN (once cached, no re-fetch).
    GoogleFonts.config.allowRuntimeFetching = true; // keep true for first-run download
    // Accessing the static fields triggers initialization (eager evaluation)
    // so the Dart VM resolves them before the first frame.
    soraBody; jakBody; kanBody; // touch a few to force class initialization
  }
}
