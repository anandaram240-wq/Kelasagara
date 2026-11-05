// lib/screens/voice/kannada_voice_screen.dart
// Kelasagara Voice AI V70 — Siri-Style Conversational Assistant for Hirers

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/performance/frame_budget_isolate_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../models/voice_session_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/voice/voice_session_manager.dart';
import '../../widgets/voice/impeller_siri_orb.dart';

class KannadaVoiceScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  const KannadaVoiceScreen({super.key, this.onNavigate});

  @override
  State<KannadaVoiceScreen> createState() => _KannadaVoiceScreenState();
}

class _KannadaVoiceScreenState extends State<KannadaVoiceScreen> with TickerProviderStateMixin {
  late final VoiceSessionManager _sessionManager;
  late final AnimationController _pulseCtrl;
  late final AnimationController _waveCtrl;

  VoiceSessionState _state = VoiceSessionState.idle;
  String _transcript = '';
  String _response = '';
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _pendingConfirmation;
  bool _showDiagnostics = false;
  final ValueNotifier<double> _amplitudeNotifier = ValueNotifier<double>(0.0);

  SiriOrbState get _siriOrbState {
    switch (_state) {
      case VoiceSessionState.idle:
        return SiriOrbState.idle;
      case VoiceSessionState.listening:
      case VoiceSessionState.userSpeaking:
        return SiriOrbState.listening;
      case VoiceSessionState.transcribing:
      case VoiceSessionState.understanding:
        return SiriOrbState.thinking;
      case VoiceSessionState.speaking:
        return SiriOrbState.speaking;
      default:
        return SiriOrbState.idle;
    }
  }

  static const _quickChips = [
    'ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು',
    'Tomorrow morning painter ಬೇಕು',
    'Book a painter near me',
    '5 km ಒಳಗೆ plumber ಹುಡುಕು',
    'ನನ್ನ active bookings ತೋರಿಸಿ',
    'Find closest electrician',
  ];

  @override
  void initState() {
    super.initState();
    FrameBudgetGuardian.instance.attachToScheduler();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

    _pulseCtrl.addListener(() {
      if (_state == VoiceSessionState.listening || _state == VoiceSessionState.userSpeaking) {
        _amplitudeNotifier.value = 0.35 + (_pulseCtrl.value * 0.45);
      } else if (_state == VoiceSessionState.speaking) {
        _amplitudeNotifier.value = 0.50 + (_pulseCtrl.value * 0.35);
      } else {
        _amplitudeNotifier.value = 0.05 + (_pulseCtrl.value * 0.08);
      }
    });

    _sessionManager = VoiceSessionManager();
    _sessionManager.onStateChanged = (state) {
      if (mounted) setState(() => _state = state);
    };
    _sessionManager.onTranscriptUpdate = (transcript, isFinal) {
      if (mounted) setState(() => _transcript = transcript);
    };
    _sessionManager.onResponseUpdate = (res) {
      if (mounted) setState(() => _response = res);
    };
    _sessionManager.onCandidatesFound = (candidates) {
      if (mounted) setState(() => _candidates = candidates.map((c) => c.toMap()).toList());
    };
    _sessionManager.onConfirmationRequested = (details) {
      if (mounted) setState(() => _pendingConfirmation = details);
    };
    _sessionManager.onNavigate = (screen) {
      if (widget.onNavigate != null) {
        if (screen.contains('job')) {
          widget.onNavigate!(0);
        } else if (screen.contains('app')) {
          widget.onNavigate!(1);
        } else if (screen.contains('prof')) {
          widget.onNavigate!(3);
        }
      }
    };

    _sessionManager.initialize();
  }

  @override
  void dispose() {
    _amplitudeNotifier.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _sessionManager.dispose();
    super.dispose();
  }

  void _handleOrbTap() {
    if (_state == VoiceSessionState.speaking) {
      _sessionManager.interrupt();
    } else if (_state == VoiceSessionState.listening || _state == VoiceSessionState.userSpeaking) {
      _sessionManager.stopListening();
    } else {
      _sessionManager.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // ── Hirer-Only Access Guard ──────────────────────────────────────────
    if (!auth.isHirer) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('🔒', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text('Hirer-Only Feature',
                style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead)),
              const SizedBox(height: 8),
              Text('The Siri-style Voice Booking Assistant is exclusively designed for Hirers to search and book workers.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight)),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => widget.onNavigate?.call(0),
                child: const Text('Return to Dashboard'),
              ),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), AppColors.primary]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('VOICE AI V70', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Text('Siri-Style Assistant', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
        actions: [
          IconButton(
            icon: Icon(_showDiagnostics ? Icons.bug_report : Icons.bug_report_outlined, color: Colors.white70),
            onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          // ── Diagnostics Banner (if enabled) ──────────────────────────────
          if (_showDiagnostics)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('State: ${_state.name} (${_state.displayName})', style: GoogleFonts.robotoMono(color: AppColors.green, fontSize: 11)),
                Text('Candidate Count: ${_candidates.length}', style: GoogleFonts.robotoMono(color: Colors.white70, fontSize: 11)),
                Text('Pending Confirmation: ${_pendingConfirmation != null}', style: GoogleFonts.robotoMono(color: Colors.white70, fontSize: 11)),
              ]),
            ),

          // ── Scrollable Dialog & Candidates Area ──────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Quick Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _quickChips.map((chip) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(chip, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        backgroundColor: const Color(0xFF21262D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF30363D))),
                        onPressed: () {
                          setState(() => _transcript = chip);
                          BackgroundWorkerIsolate.instance.speculativeParseAndMatch(
                            utterance: chip,
                            userLat: 12.9716,
                            userLng: 77.5946,
                          ).then((res) {
                            if (mounted && _candidates.isEmpty) {
                              setState(() {
                                _candidates = res.rankedCandidates.map((c) => c.toMap()).toList();
                              });
                            }
                          });
                          _sessionManager.startListening();
                        },
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // User Transcript Bubble
                if (_transcript.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16, left: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
                        borderRadius: BorderRadius.circular(20).copyWith(bottomRight: Radius.zero),
                      ),
                      child: Text(_transcript,
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

                // Assistant Response Bubble
                if (_response.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16, right: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(20).copyWith(bottomLeft: Radius.zero),
                        border: Border.all(color: const Color(0xFF374151)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('Kelasagara Assistant', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primaryBorder)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_response,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                      ]),
                    ),
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

                // Candidate Cards Carousel
                if (_candidates.isNotEmpty) ...[
                  Text('Available Verified Candidates',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white70)),
                  const SizedBox(height: 10),
                  ..._candidates.map((c) => _buildCandidateCard(c)),
                ],

                // Pending Confirmation Card
                if (_pendingConfirmation != null)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF374151), Color(0xFF1F2937)]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Text('⚠️', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text('Confirm Booking', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                      ]),
                      const SizedBox(height: 8),
                      Text('Book candidate: ${_pendingConfirmation!['workerId']}?',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _sessionManager.executeConfirmedAction(),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Text('Confirm ✓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _sessionManager.cancelPendingAction(),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Text('Cancel ✕', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ]),
                    ]),
                  ).animate().scale(duration: 300.ms),
              ],
            ),
          ),

          // ── Siri-Style Floating Voice Orb ────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFF06090E)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
            child: Column(children: [
              Text(_state.kannadaDisplayName,
                style: GoogleFonts.notoSansKannada(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryBorder)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _handleOrbTap,
                child: Stack(alignment: Alignment.center, children: [
                  ImpellerSiriOrb(
                    size: 96,
                    state: _siriOrbState,
                    amplitudeListenable: _amplitudeNotifier,
                    onTap: _handleOrbTap,
                  ),
                  IgnorePointer(
                    child: Icon(
                      _state == VoiceSessionState.speaking
                          ? Icons.volume_up_rounded
                          : _state == VoiceSessionState.userSpeaking
                              ? Icons.graphic_eq_rounded
                              : Icons.mic_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Text(
                _state == VoiceSessionState.speaking
                    ? 'Tap orb to interrupt (Barge-In)'
                    : 'Tap to speak / ಮಾತನಾಡಲು ಒತ್ತಿ',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white38),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildCandidateCard(Map<String, dynamic> c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryPale,
            child: Text(c['name']?[0] ?? 'W', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'] ?? 'Worker', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('${c['skill']} • ${c['distanceDisplay']} away', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white60)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.greenPale, borderRadius: BorderRadius.circular(8)),
            child: Text('${c['rating']?.toStringAsFixed(1)} ★', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.green)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(c['selectionReason'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton(
            onPressed: () {
              _sessionManager.geminiProvider.processUtterance(prompt: 'Book ${c['name']}');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Book ${c['name']} ✓', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
