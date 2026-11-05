// lib/core/sdui/sdui_components_registry.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sdui_engine.dart';

void registerKelasagaraSduiComponents() {
  final registry = SduiRegistry.instance;
  if (registry.isInitialized) return; // Idempotent guard

  // --- LAYOUT PRIMITIVE 1: Vertical Composite Stack ---
  registry.register('sdui_column', (context, node, store, onAction) {
    final double spacing = (node.props['spacing'] as num?)?.toDouble() ?? 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < node.children.length; i++) ...[
          registry.buildNode(context, node.children[i], store, onAction),
          if (i < node.children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  });

  // --- LAYOUT PRIMITIVE 2: Horizontal Worker Carousel ---
  registry.register('sdui_carousel', (context, node, store, onAction) {
    final double height = (node.props['height'] as num?)?.toDouble() ?? 192.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: node.children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, idx) => registry.buildNode(ctx, node.children[idx], store, onAction),
      ),
    );
  });

  // --- COMPONENT 1: Streaming Booking Card (with Optimistic Lock) ---
  registry.register('booking_card', (context, node, store, onAction) {
    return _SduiBookingCard(node: node, onAction: onAction);
  });

  // --- COMPONENT 2: Stateful Wage Negotiator (with Counter-Offer Marker) ---
  registry.register('wage_negotiator', (context, node, store, onAction) {
    return _SduiWageNegotiatorCard(node: node, onAction: onAction);
  });

  // --- COMPONENT 3: 120 FPS CustomPainter Live GPS Radar ---
  registry.register('live_radar', (context, node, store, onAction) {
    return _SduiLiveRadarCard(node: node, onAction: onAction);
  });

  registry.markInitialized();
}

// ============================================================================
// 1. BOOKING CARD WIDGET
// ============================================================================
class _SduiBookingCard extends StatefulWidget {
  final SduiNode node;
  final SduiActionCallback onAction;

  const _SduiBookingCard({required this.node, required this.onAction});

  @override
  State<_SduiBookingCard> createState() => _SduiBookingCardState();
}

class _SduiBookingCardState extends State<_SduiBookingCard> {
  bool _isBookingOptimistic = false;

  @override
  Widget build(BuildContext context) {
    final props = widget.node.props;
    final String workerId = props['workerId'] as String? ?? '';
    final String name = props['name'] as String? ?? 'Verified Worker';
    final String skill = props['skill'] as String? ?? 'ಪೇಂಟರ್ • Painter';
    final double rating = (props['rating'] as num?)?.toDouble() ?? 4.8;
    final int jobsCompleted = (props['jobsCompleted'] as num?)?.toInt() ?? 42;
    final int wage = (props['wage'] as num?)?.toInt() ?? 650;
    final String wageUnit = props['wageUnit'] as String? ?? 'ದಿನಕ್ಕೆ';
    final double distance = (props['distance'] as num?)?.toDouble() ?? 1.2;
    final String status = props['status'] as String? ?? 'available';
    final bool isBooked = status == 'booked' || _isBookingOptimistic;

    return Container(
      width: 295,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBooked
              ? const Color(0xFF34D399).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF7C3AED),
                    child: Icon(Icons.engineering, color: Colors.white, size: 20),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF131C2E), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, color: Color(0xFF38BDF8), size: 13),
                      ],
                    ),
                    Text(
                      skill,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Play Voice Intro',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onAction(SduiActionEvent(
                    actionId: 'play_worker_intro_tts',
                    nodeId: widget.node.id,
                    payload: {'workerId': workerId},
                  ));
                },
                icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF38BDF8), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 15),
                  const SizedBox(width: 3),
                  Text(
                    '$rating ($jobsCompleted)',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '₹$wage/$wageUnit • ${distance.toStringAsFixed(1)} km',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              onPressed: isBooked
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      setState(() => _isBookingOptimistic = true);
                      widget.onAction(SduiActionEvent(
                        actionId: 'book_worker',
                        nodeId: widget.node.id,
                        payload: {'workerId': workerId, 'wage': wage},
                      ));
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: isBooked ? const Color(0xFF065F46) : const Color(0xFFF5820A),
                disabledBackgroundColor: const Color(0xFF065F46),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                isBooked ? '✓ ವಿನಂತಿ ಕಳುಹಿಸಲಾಗಿದೆ • Requested' : 'ಈಗ ಬುಕ್ ಮಾಡಿ • Book Now',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. STATEFUL WAGE NEGOTIATOR CARD
// ============================================================================
class _SduiWageNegotiatorCard extends StatefulWidget {
  final SduiNode node;
  final SduiActionCallback onAction;

  const _SduiWageNegotiatorCard({required this.node, required this.onAction});

  @override
  State<_SduiWageNegotiatorCard> createState() => _SduiWageNegotiatorCardState();
}

class _SduiWageNegotiatorCardState extends State<_SduiWageNegotiatorCard> {
  late double _currentWage;

  @override
  void initState() {
    super.initState();
    _currentWage = (widget.node.props['defaultWage'] as num?)?.toDouble() ?? 600.0;
  }

  @override
  void didUpdateWidget(covariant _SduiWageNegotiatorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverWage = (widget.node.props['defaultWage'] as num?)?.toDouble();
    final oldServerWage = (oldWidget.node.props['defaultWage'] as num?)?.toDouble();
    if (serverWage != null && serverWage != oldServerWage) {
      _currentWage = serverWage;
    }
  }

  void _stepWage(double delta, double min, double max) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentWage = (_currentWage + delta).clamp(min, max);
    });
    widget.onAction(SduiActionEvent(
      actionId: 'update_wage',
      nodeId: widget.node.id,
      payload: {'agreedWage': _currentWage.round()},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.node.props;
    final double minWage = (props['minWage'] as num?)?.toDouble() ?? 400.0;
    final double maxWage = (props['maxWage'] as num?)?.toDouble() ?? 1000.0;
    final int? counterOffer = (props['workerCounterOffer'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ಕೂಲಿ ಮೊತ್ತ ಮಾತುಕತೆ (Wage Negotiation)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (counterOffer != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Worker Ask: ₹$counterOffer',
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹${minWage.toInt()}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '₹${_currentWage.toStringAsFixed(0)} / ದಿನ',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text('₹${maxWage.toInt()}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          Slider.adaptive(
            value: _currentWage.clamp(minWage, maxWage),
            min: minWage,
            max: maxWage,
            divisions: ((maxWage - minWage) / 25).round().clamp(1, 100),
            activeColor: const Color(0xFF38BDF8),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() => _currentWage = val);
            },
            onChangeEnd: (val) {
              widget.onAction(SduiActionEvent(
                actionId: 'update_wage',
                nodeId: widget.node.id,
                payload: {'agreedWage': val.round()},
              ));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _QuickStepChip(label: '-₹50', onTap: () => _stepWage(-50, minWage, maxWage)),
              const SizedBox(width: 8),
              _QuickStepChip(label: '+₹50', onTap: () => _stepWage(50, minWage, maxWage)),
              const SizedBox(width: 8),
              if (counterOffer != null)
                _QuickStepChip(
                  label: 'Match ₹$counterOffer',
                  highlight: true,
                  onTap: () => _stepWage(counterOffer - _currentWage, minWage, maxWage),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickStepChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _QuickStepChip({required this.label, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: highlight
                ? const Color(0xFF38BDF8)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: highlight ? const Color(0xFF38BDF8) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. 120 FPS HARDWARE-ACCELERATED LIVE GPS RADAR CARD
// ============================================================================
class _SduiLiveRadarCard extends StatefulWidget {
  final SduiNode node;
  final SduiActionCallback onAction;

  const _SduiLiveRadarCard({required this.node, required this.onAction});

  @override
  State<_SduiLiveRadarCard> createState() => _SduiLiveRadarCardState();
}

class _SduiLiveRadarCardState extends State<_SduiLiveRadarCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.node.props;
    final double radiusKm = (props['radiusKm'] as num?)?.toDouble() ?? 3.0;
    final List<dynamic> rawWorkers = props['workers'] as List<dynamic>? ?? const [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Isolated RepaintBoundary so the 120Hz CustomPainter never repaints the text column
          RepaintBoundary(
            child: SizedBox(
              width: 96,
              height: 96,
              child: CustomPaint(
                painter: _RadarSweepPainter(
                  sweepAnimation: _sweepController,
                  workers: rawWorkers,
                  maxRadiusKm: radiusKm,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'ಸಮೀಪದ ಕೆಲಸಗಾರರ ಹುಡುಕಾಟ (Live Radar)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${rawWorkers.length} workers active within ${radiusKm.toStringAsFixed(1)} km',
                  style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onAction(SduiActionEvent(
                      actionId: 'expand_radar_radius',
                      nodeId: widget.node.id,
                      payload: {'newRadiusKm': radiusKm + 2.0},
                    ));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.radar, size: 14, color: Color(0xFF34D399)),
                  label: const Text('ವ್ಯಾಪ್ತಿ ಹೆಚ್ಚಿಸಿ (+2 km)', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final Animation<double> sweepAnimation;
  final List<dynamic> workers;
  final double maxRadiusKm;

  _RadarSweepPainter({
    required this.sweepAnimation,
    required this.workers,
    required this.maxRadiusKm,
  }) : super(repaint: sweepAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = const Color(0xFF34D399).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric distance rings
    canvas.drawCircle(center, radius * 0.35, ringPaint);
    canvas.drawCircle(center, radius * 0.70, ringPaint);
    canvas.drawCircle(center, radius, ringPaint);

    // Draw rotating sweep sector
    final sweepAngle = sweepAnimation.value * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          const Color(0xFF34D399).withValues(alpha: 0.0),
          const Color(0xFF34D399).withValues(alpha: 0.40),
        ],
        transform: GradientRotation(sweepAngle - math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, sweepPaint);

    // Plot nearby worker blips using polar coordinates (distanceKm, bearingDeg)
    final blipPaint = Paint()..color = const Color(0xFF34D399);
    for (final raw in workers) {
      if (raw is Map) {
        final double dist = ((raw['distanceKm'] as num?)?.toDouble() ?? 1.0).clamp(0.1, maxRadiusKm);
        final double angleDeg = (raw['bearingDeg'] as num?)?.toDouble() ?? 45.0;
        final double angleRad = angleDeg * (math.pi / 180.0);
        final double normalizedR = (dist / maxRadiusKm) * (radius * 0.88);

        final blipOffset = Offset(
          center.dx + normalizedR * math.cos(angleRad),
          center.dy + normalizedR * math.sin(angleRad),
        );
        canvas.drawCircle(blipOffset, 3.5, blipPaint);
      }
    }

    // Center user pin
    canvas.drawCircle(center, 4.0, Paint()..color = const Color(0xFF38BDF8));
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) =>
      oldDelegate.workers != workers || oldDelegate.maxRadiusKm != maxRadiusKm;
}
