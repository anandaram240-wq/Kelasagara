// lib/screens/voice/voice_command_center_screen.dart
// Production-Grade Realtime Voice Command Center Surface for Kelasagara
// Implements VOICE -> UNDERSTAND -> ACT -> SHOW -> SPEAK -> INTERRUPT -> CONTINUE

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/job_categories.dart';
import '../../core/constants/karnataka_locations.dart';
import '../../core/theme/app_colors.dart';
import '../../models/voice_session_state.dart';
import '../../services/voice/voice_session_manager.dart';
import '../../services/voice/voice_settings_service.dart';
import '../../services/voice/voice_tool_registry.dart';
import '../../services/voice/voice_intent_parser.dart';
import '../settings/voice_accessibility_settings_screen.dart';
import 'direct_booking_screen.dart';
import 'hirer_route_preview_screen.dart';

class VoiceCommandCenterScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  const VoiceCommandCenterScreen({super.key, this.onNavigate});

  @override
  State<VoiceCommandCenterScreen> createState() => _VoiceCommandCenterScreenState();
}

class _VoiceCommandCenterScreenState extends State<VoiceCommandCenterScreen> with TickerProviderStateMixin {
  late final VoiceSessionManager _sessionManager;
  late final AnimationController _pulseCtrl;
  late final AnimationController _rotateCtrl;
  late final AnimationController _waveCtrl;

  VoiceSessionState _state = VoiceSessionState.idle;
  String _transcript = '';
  String _response = '';
  List<WorkerCandidate> _candidates = [];
  List<Map<String, dynamic>> _applications = [];
  Map<String, dynamic>? _pendingConfirmation;
  VoiceLatencyMetrics _metrics = VoiceLatencyMetrics();
  bool _showDiagnostics = false;
  VoiceSearchCommand? _activeCommand;

  static const _quickChips = [
    'ನನ್ನ ಅರ್ಜಿಗಳು',
    'My Applications',
    'ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು',
    'Find electrician in Hassan',
    'ಮೈಸೂರಿನಲ್ಲಿ ಪ್ಲಂಬರ್ ಬೇಕು',
    'ನಂಬರ್ 1 ಎಷ್ಟು ದೂರ?',
    'ಚಾಟ್ ಮಾಡಿ',
    'My Bookings',
    'Open Settings',
    'What can you do?',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

    _sessionManager = VoiceSessionManager();
    _setupSessionCallbacks();
    _sessionManager.initialize();
  }

  void _setupSessionCallbacks() {
    _sessionManager.onStateChanged = (state) {
      if (mounted) setState(() => _state = state);
    };

    _sessionManager.onTranscriptUpdate = (transcript, isFinal) {
      if (mounted) setState(() => _transcript = transcript);
    };

    _sessionManager.onResponseUpdate = (res) {
      if (mounted) setState(() => _response = res);
    };

    _sessionManager.onCommandParsed = (cmd) {
      if (mounted) setState(() => _activeCommand = cmd);
    };

    _sessionManager.onCandidatesFound = (candidates) {
      if (mounted) {
        setState(() {
          _candidates = candidates;
          _applications = [];
        });
      }
    };

    _sessionManager.onApplicationsFound = (apps) {
      if (mounted) {
        setState(() {
          _applications = apps;
          _candidates = [];
        });
      }
    };

    _sessionManager.onConfirmationRequested = (details) {
      if (mounted) setState(() => _pendingConfirmation = details);
    };

    _sessionManager.onMetricsUpdated = (m) {
      if (mounted) setState(() => _metrics = m);
    };

    _sessionManager.onNavigate = (screen) {
      if (!mounted) return;
      // Voice settings → dedicated screen
      if (screen == 'settings' || screen == 'voiceSettings') {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const VoiceAccessibilitySettingsScreen()),
        );
        return;
      }
      if (widget.onNavigate == null) return;

      // Map screen names → bottom nav tab indices
      if (screen == 'home' ||
          screen.contains('job') ||
          screen.contains('dash')) {
        widget.onNavigate!(0); // Home / Jobs tab
      } else if (screen == 'bookings' ||
          screen.contains('book') ||
          screen.contains('applic')) {
        widget.onNavigate!(1); // Bookings / Applications tab
      } else if (screen == 'chat' || screen.startsWith('chat/')) {
        widget.onNavigate!(3); // Chat tab
      } else if (screen == 'profile' || screen.contains('prof')) {
        widget.onNavigate!(4); // Profile tab
      } else if (screen == 'back') {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    };

    _sessionManager.onNavigateToWorker = (worker) {
      if (!mounted) return;
      _launchNavigation(worker);
    };

    _sessionManager.onOpenBookingForm = (worker) {
      if (!mounted) return;
      _navigateToBookingForm(worker);
    };

    _sessionManager.onDirectAction = (action, args) {
      if (action == 'SHOW_APPLICATIONS' || action == 'SHOW_APPLICANTS' || action == 'NAV_BOOKINGS') {
        widget.onNavigate?.call(1);
      } else if (action == 'NAV_JOBS' || action == 'NAV_HOME') {
        widget.onNavigate?.call(0);
      } else if (action == 'NAV_PROFILE') {
        widget.onNavigate?.call(3);
      }
    };
  }

  void _navigateToBookingForm(WorkerCandidate worker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DirectBookingScreen(worker: worker),
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _waveCtrl.dispose();
    _sessionManager.dispose();
    super.dispose();
  }

  void _handleOrbTap() {
    if (_state == VoiceSessionState.speaking) {
      // Natural instant barge-in
      _sessionManager.interrupt();
    } else if (_state == VoiceSessionState.listening || _state == VoiceSessionState.userSpeaking) {
      _sessionManager.stopListening();
    } else {
      if (mounted) setState(() => _response = '');
      _sessionManager.startListening();
    }
  }

  void _launchNavigation(WorkerCandidate worker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HirerRoutePreviewScreen(worker: worker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = VoiceSettingsService.instance;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: Semantics(
          label: 'Back button',
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
              'Voice Command Center',
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
            ),
            Text(
              'ಧ್ವನಿ ನಿಯಂತ್ರಣ ಕೇಂದ್ರ',
              style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight),
            ),
          ],
        ),
        actions: [
          // Diagnostics toggle
          IconButton(
            icon: Icon(
              _showDiagnostics ? Icons.analytics : Icons.analytics_outlined,
              color: _showDiagnostics ? AppColors.primary : AppColors.textLight,
            ),
            tooltip: 'Latency Diagnostics',
            onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
          ),
          // Settings shortcut
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.textHead),
            tooltip: 'Voice Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceAccessibilitySettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP: Interactive Orb Surface ─────────────────────────────
            _buildOrbSurface(),

            // ── MIDDLE: Scrollable Content (Transcript + Cards + Prompts) 
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Confirmation banner if pending consequential action
                  if (_pendingConfirmation != null) ...[
                    _buildPendingConfirmationCard(),
                    const SizedBox(height: 16),
                  ],

                  // Streaming Transcript & Response
                  if (settings.showLiveTranscript && (_transcript.isNotEmpty || _response.isNotEmpty)) ...[
                    _buildTranscriptSection(),
                    const SizedBox(height: 16),
                  ],

                  // Active Search Filter Chips (Trade, District, Radius, Specialization)
                  _buildSearchEntityFilterChips(),

                  // Candidate Cards (Live Firestore + Valhalla/OSRM Road Distance)
                  if (_candidates.isNotEmpty) ...[
                    _buildCandidatesHeader(),
                    ..._candidates.asMap().entries.map((entry) {
                      return RepaintBoundary(
                        child: _buildWorkerCandidateCard(entry.key + 1, entry.value),
                      );
                    }),
                    if (_sessionManager.hasMoreCandidates)
                      _buildLoadMoreButton(),
                    const SizedBox(height: 16),
                  ],

                  // Work / Application Cards (Live Firestore Application Records)
                  if (_applications.isNotEmpty) ...[
                    _buildApplicationsHeader(),
                    ..._applications.asMap().entries.map((entry) {
                      return RepaintBoundary(
                        child: _buildApplicationCard(entry.key + 1, entry.value),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // Diagnostics Overlay (Collapsible)
                  if (_showDiagnostics) ...[
                    _buildDiagnosticsCard(),
                    const SizedBox(height: 16),
                  ],

                  // Quick Suggestion Chips
                  _buildQuickSuggestions(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ORB SURFACE WIDGET ───────────────────────────────────────────────────
  Widget _buildOrbSurface() {
    final (stateColor, stateLabelKn, stateLabelEn) = _getStateInfo(_state);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Semantics(
            label: 'Voice Assistant Orb. Current state: $stateLabelEn. Tap to ${_state == VoiceSessionState.speaking ? "interrupt" : _state == VoiceSessionState.listening ? "stop" : "start speaking"}.',
            button: true,
            child: GestureDetector(
              onTap: _handleOrbTap,
              child: SizedBox(
                width: 130,
                height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Pulsing Wave
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, _) {
                        final scale = 1.0 + (_pulseCtrl.value * 0.18);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: stateColor.withValues(alpha: 0.12 * (1.0 - _pulseCtrl.value * 0.5)),
                            ),
                          ),
                        );
                      },
                    ),

                    // Rotating Glow Ring
                    AnimatedBuilder(
                      animation: _rotateCtrl,
                      builder: (context, _) {
                        return Transform.rotate(
                          angle: _rotateCtrl.value * 2 * math.pi,
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  stateColor.withValues(alpha: 0.1),
                                  stateColor.withValues(alpha: 0.6),
                                  stateColor,
                                  stateColor.withValues(alpha: 0.1),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Core Gradient Orb
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white,
                            stateColor.withValues(alpha: 0.9),
                            stateColor,
                          ],
                          stops: const [0.0, 0.7, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: stateColor.withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _getOrbIcon(_state),
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // State Status Label
          Text(
            stateLabelKn,
            style: GoogleFonts.notoSansKannada(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: stateColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stateLabelEn,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  // ── TRANSCRIPT & RESPONSE DISPLAY ────────────────────────────────────────
  Widget _buildTranscriptSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_transcript.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mic, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'YOU SAID / ನೀವು ಹೇಳಿದ್ದು:',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _transcript,
              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textHead),
            ),
          ],
          if (_transcript.isNotEmpty && _response.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.divider),
            ),
          if (_response.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.volume_up, size: 16, color: AppColors.violet),
                const SizedBox(width: 6),
                Text(
                  'ASSISTANT / ಸಹಾಯಕ:',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _response,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textBody),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  // ── SEARCH ENTITY FILTER CHIPS ──────────────────────────────────────────
  Widget _buildSearchEntityFilterChips() {
    final cmd = _activeCommand;
    final chips = <Widget>[];

    final currentTrade = (cmd?.trade != null && !cmd!.trade!.isGenericWorker)
        ? cmd.trade!.canonicalName
        : null;
    final currentDistrict = (cmd?.geography.district != null && cmd!.geography.district!.isNotEmpty)
        ? cmd.geography.district!
        : null;
    final currentRadius = cmd?.geography.radiusKm ?? 10.0;

    // 1. Trade / Category Chip
    if (currentTrade != null) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.work_outline, size: 14, color: AppColors.primary),
          label: Text(currentTrade, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.primaryPale,
          side: const BorderSide(color: AppColors.primaryBorder),
          onPressed: () => _showTradeSelector(currentDistrict, currentRadius),
          onDeleted: () {
            setState(() => _activeCommand = null);
            _sessionManager.processTextUtterance('any worker');
          },
        ),
      );
    } else {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.add, size: 14, color: AppColors.primary),
          label: Text('All Trades / ಎಲ್ಲಾ', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          onPressed: () => _showTradeSelector(currentDistrict, currentRadius),
        ),
      );
    }

    // 2. Geography / District Chip
    if (currentDistrict != null) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.location_city, size: 14, color: AppColors.primary),
          label: Text('$currentDistrict District', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.primaryBorder),
          onPressed: () => _showDistrictSelector(currentTrade, currentRadius),
          onDeleted: () {
            _sessionManager.processTextUtterance('${currentTrade ?? "workers"} near me');
          },
        ),
      );
    } else {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.my_location, size: 14, color: AppColors.primary),
          label: Text('Near Me / ಜಿಪಿಎಸ್', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          onPressed: () => _showDistrictSelector(currentTrade, currentRadius),
        ),
      );
    }

    // 3. Radius / Distance Chip
    chips.add(
      ActionChip(
        avatar: const Icon(Icons.radar, size: 14, color: AppColors.primary),
        label: Text('${currentRadius.round()} km', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        onPressed: () => _showRadiusSelector(currentTrade, currentDistrict),
      ),
    );

    // 4. Specialization chip if active
    if (cmd?.trade?.specializationMode == 'all') {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.tune, size: 14, color: AppColors.textMed),
          label: Text('All types', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          onPressed: () => _showTradeSelector(currentDistrict, currentRadius),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list_rounded, size: 14, color: AppColors.textLight),
              const SizedBox(width: 4),
              Text(
                'SEARCH FILTERS / ಹುಡುಕಾಟ ಫಿಲ್ಟರ್‌ಗಳು:',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: chips,
          ),
        ],
      ),
    );
  }

  void _showTradeSelector(String? currentDistrict, double currentRadius) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.work_outline, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Select Trade / ಕಸುಬು ಆಯ್ಕೆಮಾಡಿ',
                        style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.people_outline, color: AppColors.primary),
                        title: Text('All Trades / ಯಾವುದೇ ಕೆಲಸ', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                        subtitle: Text('Show all verified workers', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
                        onTap: () {
                          Navigator.pop(ctx);
                          final loc = currentDistrict != null ? 'in $currentDistrict district' : 'near me';
                          _sessionManager.processTextUtterance('any worker $loc');
                        },
                      ),
                      ...kJobCategories.map((cat) => ListTile(
                            leading: Text(cat.emoji, style: const TextStyle(fontSize: 22)),
                            title: Text(cat.label, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700)),
                            subtitle: Text(cat.labelKn, style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight)),
                            onTap: () {
                              Navigator.pop(ctx);
                              final loc = currentDistrict != null ? 'in $currentDistrict district' : 'near me';
                              _sessionManager.processTextUtterance('${cat.label} $loc');
                            },
                          )),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDistrictSelector(String? currentTrade, double currentRadius) {
    final districts = KarnatakaLocation.allDistricts;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = districts
                .where((d) => d.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.location_city, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Select Karnataka District / ಜಿಲ್ಲೆ ಆಯ್ಕೆಮಾಡಿ',
                            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search district (e.g. Shivamogga, Hassan)...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val);
                        },
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.my_location, color: AppColors.primary),
                            title: Text('Near Me (GPS) / ನನ್ನ ಹತ್ತಿರ', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                            subtitle: Text('Search using live GPS location', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _sessionManager.processTextUtterance('${currentTrade ?? "workers"} near me');
                            },
                          ),
                          ...filtered.map((d) => ListTile(
                                leading: const Icon(Icons.place_outlined, color: AppColors.primaryFire),
                                title: Text(d, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${KarnatakaLocation.taluksForDistrict(d).length} Taluks',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _sessionManager.processTextUtterance('${currentTrade ?? "workers"} in $d district');
                                },
                              )),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRadiusSelector(String? currentTrade, String? currentDistrict) {
    const distances = [5, 10, 20, 50];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search Radius / ಹುಡುಕಾಟದ ವ್ಯಾಪ್ತಿ',
                style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
              ),
              const SizedBox(height: 12),
              ...distances.map((dist) => ListTile(
                    leading: const Icon(Icons.radar, color: AppColors.primary),
                    title: Text('$dist km / $dist ಕಿ.ಮೀ', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700)),
                    onTap: () {
                      Navigator.pop(ctx);
                      final trade = currentTrade ?? 'workers';
                      _sessionManager.processTextUtterance('$trade within $dist km');
                    },
                  )),
            ],
          ),
        );
      },
    );
  }

  // ── CANDIDATES SECTION ───────────────────────────────────────────────────
  Widget _buildCandidatesHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'AVAILABLE WORKERS (${_candidates.length})',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textLight,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            'ಕಾರ್ಮಿಕರು',
            style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCandidateCard(int index, WorkerCandidate worker) {
    final freshnessColor = switch (worker.locationFreshness) {
      'LIVE'   => AppColors.green,
      'RECENT' => Colors.blue,
      'STALE'  => AppColors.gold,
      _        => Colors.grey,
    };

    final freshnessLabel = switch (worker.locationFreshness) {
      'LIVE'   => 'Live GPS',
      'RECENT' => 'Recent GPS',
      'STALE'  => 'Stale GPS',
      _        => 'Approx',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Index Circle (1, 2, 3...)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primaryPale,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Name & Skill
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            worker.name,
                            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.greenPale,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '✓ Verified',
                            style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.green),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${worker.skill} • ⭐ ${worker.rating.toStringAsFixed(1)} (${worker.completedJobs} jobs)',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),

              // Road Distance & Duration Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      worker.distanceDisplay,
                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ),
                  if (worker.roadDurationDisplay != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '🚗 ${worker.roadDurationDisplay}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMed),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Freshness & Selection Reason Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: freshnessColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: freshnessColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(
                      freshnessLabel,
                      style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: freshnessColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  worker.selectionReason,
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Action Buttons: Navigate / Book
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.navigation_outlined, size: 14, color: AppColors.primary),
                  label: Text('Navigate / ರೂಟ್', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _launchNavigation(worker),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 14, color: Colors.white),
                  label: Text('Book / ಬುಕ್', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                  ),
                  onPressed: () => _navigateToBookingForm(worker),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    final isLoading = _sessionManager.isLoadingMore;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: isLoading
              ? null
              : () async {
                  await _sessionManager.loadMoreCandidates();
                  if (mounted) setState(() {});
                },
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.primary),
          label: Text(
            isLoading ? 'Loading more workers...' : 'Load More Workers / ಇನ್ನಷ್ಟು ಕಾರ್ಮಿಕರು',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: const BorderSide(color: AppColors.primaryBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: AppColors.surface,
          ),
        ),
      ),
    );
  }

  // ── APPLICATIONS SECTION ─────────────────────────────────────────────────
  Widget _buildApplicationsHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'MY JOB APPLICATIONS (${_applications.length})',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textLight,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            'ಕೆಲಸದ ಅರ್ಜಿಗಳು',
            style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(int index, Map<String, dynamic> app) {
    final status = (app['status'] as String? ?? 'pending').toLowerCase();
    final jobTitle = app['jobTitle'] as String? ?? 'Job Application';
    final hirerName = app['hirerName'] as String? ?? 'Hirer';
    final pay = app['pay']?.toString() ?? '';

    final (statusColor, statusBg, statusLabel, statusIcon) = switch (status) {
      'accepted'   => (AppColors.green, AppColors.greenPale, 'Accepted ✓', Icons.check_circle_outline),
      'rejected'   => (AppColors.red, AppColors.redPale, 'Not Selected', Icons.cancel_outlined),
      'shortlisted'=> (AppColors.violet, AppColors.violetPale, 'Shortlisted', Icons.star_border),
      _            => (AppColors.gold, AppColors.primaryPale, 'Applied / Pending', Icons.schedule),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Index Circle
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primaryPale,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Job Title & Hirer
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jobTitle,
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Employer: $hirerName ${pay.isNotEmpty ? "• ₹$pay" : ""}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Action row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 14, color: AppColors.primary),
                  label: Text(
                    'Open in Applications / ವಿವರಗಳು',
                    style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    // Switch to Applications tab (index 1)
                    widget.onNavigate?.call(1);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  // ── PENDING CONFIRMATION BANNER ──────────────────────────────────────────
  Widget _buildPendingConfirmationCard() {
    final details = _pendingConfirmation!;
    final workerName = details['workerName'] ?? details['workerId'] ?? 'Worker';
    final date = details['date'] ?? 'Tomorrow';
    final time = details['time'] ?? '10:00 AM';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm Booking / ಬುಕಿಂಗ್ ದೃಢೀಕರಣ',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Book $workerName for $date at $time?',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _sessionManager.cancelPendingBooking();
                    setState(() => _pendingConfirmation = null);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Cancel (ರದ್ದು)', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _sessionManager.executeConfirmedBooking();
                    setState(() => _pendingConfirmation = null);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text('Confirm (ಖಚಿತ)', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack);
  }

  // ── QUICK SUGGESTIONS ────────────────────────────────────────────────────
  Widget _buildQuickSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'QUICK PROMPTS / ಉದಾಹರಣೆಗಳು',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textLight,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickChips.map((chip) {
            return ActionChip(
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
              label: Text(
                chip,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBody,
                ),
              ),
              onPressed: () {
                if (mounted) setState(() => _response = '');
                _sessionManager.startListening();
                // Simulate feeding query directly to test path
                _sessionManager.onTranscriptUpdate?.call(chip, true);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── LATENCY DIAGNOSTICS CARD ─────────────────────────────────────────────
  Widget _buildDiagnosticsCard() {
    final m = _metrics;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ FORENSIC LATENCY DIAGNOSTICS',
                style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.cyanAccent),
              ),
              Text(
                '${m.totalLatencyMs} ms total',
                style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ),
          const Divider(height: 16, color: Colors.white24),
          _diagRow('Speech-to-Partial (t1 - t0):', '${m.speechToPartialMs} ms'),
          _diagRow('Final-to-Intent (t3 - t2):', '${m.finalToIntentMs} ms'),
          _diagRow('Tool Execution (t5 - t4):', '${m.toolExecutionMs} ms'),
          _diagRow('Result-to-Audio (t6 - t5):', '${m.resultToAudioMs} ms'),
          _diagRow('Active Candidates:', '${_candidates.length}'),
          _diagRow('Speculative Coordinator:', 'Armed & Active'),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white70)),
          Text(value, style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  // ── STATE INFO HELPER ────────────────────────────────────────────────────
  (Color, String, String) _getStateInfo(VoiceSessionState state) {
    return switch (state) {
      VoiceSessionState.idle => (
        AppColors.primary,
        'ಸ್ಪರ್ಶಿಸಿ ಮತ್ತು ಮಾತನಾಡಿ',
        'Tap orb to speak',
      ),
      VoiceSessionState.listening => (
        Colors.orangeAccent,
        'ಆಲಿಸಲಾಗುತ್ತಿದೆ...',
        'Listening...',
      ),
      VoiceSessionState.userSpeaking => (
        Colors.deepOrange,
        'ನೀವು ಮಾತನಾಡುತ್ತಿದ್ದೀರಿ...',
        'Hearing you...',
      ),
      VoiceSessionState.transcribing => (
        Colors.amber,
        'ಪರಿವರ್ತಿಸಲಾಗುತ್ತಿದೆ...',
        'Transcribing speech...',
      ),
      VoiceSessionState.understanding => (
        AppColors.violet,
        'ಅರ್ಥಮಾಡಿಕೊಳ್ಳಲಾಗುತ್ತಿದೆ...',
        'Understanding intent...',
      ),
      VoiceSessionState.toolRequested ||
      VoiceSessionState.toolValidating ||
      VoiceSessionState.executing => (
        Colors.indigoAccent,
        'ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
        'Executing search...',
      ),
      VoiceSessionState.waitingConfirmation => (
        AppColors.gold,
        'ದೃಢೀಕರಣಕ್ಕಾಗಿ ಕಾಯಲಾಗುತ್ತಿದೆ...',
        'Waiting confirmation...',
      ),
      VoiceSessionState.responding ||
      VoiceSessionState.speaking => (
        AppColors.green,
        'ಉತ್ತರಿಸಲಾಗುತ್ತಿದೆ (ಸ್ಪರ್ಶಿಸಿ ನಿಲ್ಲಿಸಿ)',
        'Speaking (tap to interrupt)',
      ),
      VoiceSessionState.interrupted => (
        Colors.teal,
        'ತಡೆಹಿಡಿಯಲಾಗಿದೆ...',
        'Interrupted, listening...',
      ),
      VoiceSessionState.cancelled => (
        Colors.grey,
        'ರದ್ದುಗೊಳಿಸಲಾಗಿದೆ',
        'Cancelled',
      ),
      VoiceSessionState.error => (
        AppColors.red,
        'ದೋಷ ಸಂಭವಿಸಿದೆ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ',
        'Error occurred. Tap to retry',
      ),
      VoiceSessionState.retrying => (
        Colors.orange,
        'ಮರುಪ್ರಯತ್ನಿಸಲಾಗುತ್ತಿದೆ...',
        'Retrying...',
      ),
      VoiceSessionState.closed => (
        Colors.grey,
        'ಮುಚ್ಚಲಾಗಿದೆ',
        'Session closed',
      ),
    };
  }

  IconData _getOrbIcon(VoiceSessionState state) {
    return switch (state) {
      VoiceSessionState.idle => Icons.mic,
      VoiceSessionState.listening => Icons.graphic_eq,
      VoiceSessionState.userSpeaking => Icons.record_voice_over,
      VoiceSessionState.transcribing => Icons.text_fields,
      VoiceSessionState.understanding => Icons.psychology,
      VoiceSessionState.toolRequested ||
      VoiceSessionState.toolValidating ||
      VoiceSessionState.executing => Icons.search,
      VoiceSessionState.waitingConfirmation => Icons.question_mark,
      VoiceSessionState.responding ||
      VoiceSessionState.speaking => Icons.volume_up,
      VoiceSessionState.interrupted => Icons.pause,
      VoiceSessionState.cancelled => Icons.close,
      VoiceSessionState.error => Icons.error_outline,
      VoiceSessionState.retrying => Icons.refresh,
      VoiceSessionState.closed => Icons.power_settings_new,
    };
  }
}
