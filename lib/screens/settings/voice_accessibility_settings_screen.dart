// lib/screens/settings/voice_accessibility_settings_screen.dart
// Production Voice & Accessibility Configuration Screen for Kelasagara

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../services/voice/voice_settings_service.dart';
import '../voice/voice_command_center_screen.dart';

class VoiceAccessibilitySettingsScreen extends StatelessWidget {
  const VoiceAccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = VoiceSettingsService.instance;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        leading: Semantics(
          label: 'Back',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textHead, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voice & Accessibility',
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
            ),
            Text(
              'ಧ್ವನಿ ಮತ್ತು ಪ್ರವೇಶಿಸುವಿಕೆ ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
              style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── HERO BANNER: Open Voice Command Center ──────────────────
              _buildHeroLauncher(context, settings),

              const SizedBox(height: 24),

              // ── SECTION: Voice Command Center Master ────────────────────
              _buildSectionHeader('VOICE RECOGNITION / ಧ್ವನಿ ಗುರುತಿಸುವಿಕೆ'),
              _buildSettingCard(children: [
                SwitchListTile.adaptive(
                  value: settings.isEnabled,
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(
                    'Voice Command Center',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'Enable conversational voice control for search, booking, and navigation.\nಧ್ವನಿ ಮೂಲಕ ಹುಡುಕಾಟ ಮತ್ತು ನಿಯಂತ್ರಣ ಸಕ್ರಿಯಗೊಳಿಸಿ.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  onChanged: (val) => settings.setEnabled(val),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Recognition Language',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'ಭಾಷಾ ಆದ್ಯತೆ: ${settings.language.label}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  trailing: DropdownButton<VoiceLanguagePreference>(
                    value: settings.language,
                    underline: const SizedBox(),
                    items: VoiceLanguagePreference.values.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text(
                          p.label,
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) settings.setLanguage(val);
                    },
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // ── SECTION: Spoken Feedback (TTS) ──────────────────────────
              _buildSectionHeader('VOICE FEEDBACK / ಧ್ವನಿ ಪ್ರತಿಕ್ರಿಯೆ'),
              _buildSettingCard(children: [
                SwitchListTile.adaptive(
                  value: settings.voiceReplies,
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Spoken Audio Replies',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'Assistant speaks aloud responses and confirmations.\nಉತ್ತರಗಳನ್ನು ಧ್ವನಿಯಲ್ಲಿ ಮಾತನಾಡಿ ಹೇಳುವುದು.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  onChanged: (val) => settings.setVoiceReplies(val),
                ),
                if (settings.voiceReplies) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Speech Speed / ಮಾತಿನ ವೇಗ',
                              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPale,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${settings.speed.toStringAsFixed(1)}x',
                                style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                        Slider.adaptive(
                          value: settings.speed,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.divider,
                          onChanged: (val) => settings.setSpeed(val),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),

              const SizedBox(height: 24),

              // ── SECTION: Accessibility & Transparency ───────────────────
              _buildSectionHeader('ACCESSIBILITY & CONFIRMATION / ಪ್ರವೇಶಿಸುವಿಕೆ'),
              _buildSettingCard(children: [
                SwitchListTile.adaptive(
                  value: settings.showLiveTranscript,
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Real-Time Live Transcript',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'Stream spoken words on screen in real time as you speak.\nಮಾತನಾಡುತ್ತಿರುವಾಗಲೇ ಪರದೆಯ ಮೇಲೆ ಪದಗಳನ್ನು ಪ್ರದರ್ಶಿಸಿ.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  onChanged: (val) => settings.setShowTranscript(val),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                SwitchListTile.adaptive(
                  value: settings.hapticEnabled,
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Haptic Feedback',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'Vibrate on microphone activation and command completion.\nಮೈಕ್ ಪ್ರಾರಂಭವಾದಾಗ ಮತ್ತು ಪೂರ್ಣಗೊಂಡಾಗ ಕಂಪನ ನೀಡಿ.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  onChanged: (val) => settings.setHaptic(val),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                SwitchListTile.adaptive(
                  value: settings.requireBookingConfirmation,
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Require Booking Confirmation',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  subtitle: Text(
                    'Ask for explicit spoken or button confirmation before booking.\nಬುಕಿಂಗ್ ಮಾಡುವ ಮುನ್ನ ದೃಢೀಕರಣ ಕೇಳಿ.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                  onChanged: (val) => settings.setConfirmBooking(val),
                ),
              ]),

              const SizedBox(height: 24),

              // ── SECTION: Voice Command Cheat Sheet ──────────────────────
              _buildSectionHeader('EXAMPLE VOICE COMMANDS / ಉದಾಹರಣೆ ಆಜ್ಞೆಗಳು'),
              _buildCheatsheetCard(),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroLauncher(BuildContext context, VoiceSettingsService settings) {
    return Semantics(
      label: 'Launch Voice Command Center button',
      hint: 'Opens the full-screen voice assistant',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceCommandCenterScreen()),
            );
          },
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFFC8019)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🎙️', style: TextStyle(fontSize: 28)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice Command Center',
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ಧ್ವನಿ ನಿಯಂತ್ರಣ ಕೇಂದ್ರ ತೆರೆಯಿರಿ',
                        style: GoogleFonts.notoSansKannada(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to speak naturally in Kannada or English →',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textLight,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildCheatsheetCard() {
    final examples = [
      ('🔍 Search Workers', 'ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು', 'Find electrician within 5 km'),
      ('🎯 Context Queries', 'ನಂಬರ್ 2 ಎಷ್ಟು ದೂರದಲ್ಲಿದ್ದಾನೆ?', 'When is number 1 available?'),
      ('📅 Real Booking', 'ನಾಳೆ ಬೆಳಗ್ಗೆ 10 ಗಂಟೆಗೆ ಬುಕ್ ಮಾಡಿ', 'Book number 2 for tomorrow 9 AM'),
      ('🗺️ Navigation', 'ನಂಬರ್ 2 ಗೆ ರೂಟ್ ತೋರಿಸಿ', 'Navigate to painter number 1'),
      ('⚡ App Control', 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ / Go Home', 'Show my active bookings'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: examples.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    e.$1,
                    style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.$2,
                        style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.$3,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
