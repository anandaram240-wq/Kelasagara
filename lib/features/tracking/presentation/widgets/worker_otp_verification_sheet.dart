// lib/features/tracking/presentation/widgets/worker_otp_verification_sheet.dart
// Production-grade Arrival OTP verification bottom sheet for gig-workers (V21.0).
// Unlocks job initiation, verifies against secure backend orchestration service
// (with HMAC-SHA256 verifier, attempt rate-limiting, and TTL expiry),
// stops foreground tracking isolate, and enforces bilingual (Kannada + English) feedback.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../services/booking_service.dart';
import '../../services/worker_gmaps_telemetry_service.dart';

class WorkerOtpVerificationSheet extends StatefulWidget {
  final String bookingId;
  final String hirerName;
  final String jobTitle;
  final VoidCallback? onVerified;

  const WorkerOtpVerificationSheet({
    super.key,
    required this.bookingId,
    this.hirerName = 'Hirer',
    this.jobTitle = 'Service Job',
    this.onVerified,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String bookingId,
    String hirerName = 'Hirer',
    String jobTitle = 'Service Job',
    VoidCallback? onVerified,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => WorkerOtpVerificationSheet(
        bookingId: bookingId,
        hirerName: hirerName,
        jobTitle: jobTitle,
        onVerified: onVerified,
      ),
    );
  }

  @override
  State<WorkerOtpVerificationSheet> createState() =>
      _WorkerOtpVerificationSheetState();
}

class _WorkerOtpVerificationSheetState
    extends State<WorkerOtpVerificationSheet> {
  static const int _codeLength = 6;
  final List<TextEditingController> _controllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_codeLength, (_) => FocusNode());

  bool _isSubmitting = false;
  bool _isLocked = false;
  int? _knownGeneration;
  String? _errorMessage;
  StreamSubscription<DocumentSnapshot>? _bookingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isLocked) _focusNodes[0].requestFocus();
    });

    _bookingSub = FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final d = snap.data() as Map<String, dynamic>;
      final gen = (d['arrivalOtpGeneration'] as num?)?.toInt() ?? 1;
      final locked = d['arrivalOtpLocked'] == true ||
          ((d['arrivalOtpAttempts'] as num?)?.toInt() ?? 0) >= 5;

      if (_knownGeneration != null && gen > _knownGeneration!) {
        // Generation incremented by Hirer! Reset inputs and unlock
        for (final c in _controllers) {
          c.clear();
        }
        setState(() {
          _knownGeneration = gen;
          _isLocked = false;
          _errorMessage = null;
        });
        if (_focusNodes.isNotEmpty) _focusNodes[0].requestFocus();
      } else {
        _knownGeneration = gen;
        if (locked != _isLocked) {
          setState(() {
            _isLocked = locked;
            if (locked) {
              _errorMessage =
                  '5 ವಿಫಲ ಪ್ರಯತ್ನಗಳು. OTP ಲಾಕ್ ಆಗಿದೆ. ಮಾಲೀಕರಿಂದ ಹೊಸ OTP ಪಡೆಯಿರಿ (OTP locked: max attempts exceeded. Ask hirer for new OTP)';
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _bookingSub?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp =>
      _controllers.map((c) => c.text.trim()).join();

  Future<void> _verifyOtp() async {
    final entered = _enteredOtp;
    if (entered.length != _codeLength) {
      setState(() => _errorMessage = 'ದಯವಿಟ್ಟು 6-ಅಂಕಿಯ OTP ನಮೂದಿಸಿ (Enter 6-digit arrival code)');
      HapticFeedback.vibrate();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await BookingService.instance.verifyArrivalOtp(
        bookingId: widget.bookingId,
        enteredOtp: entered,
      );

      if (res.success) {
        // Stop background telemetry isolate since worker has safely arrived & verified
        try {
          await WorkerGmapsTelemetryService.instance.stopShadowTracking();
        } catch (_) {}

        HapticFeedback.mediumImpact();
        widget.onVerified?.call();

        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      final rawError = res.error;
      String localizedError = 'ಪರಿಶೀಲನೆ ವಿಫಲವಾಗಿದೆ (Verification failed)';

      if (rawError.contains('INVALID_OTP') || rawError.contains('INCORRECT_OTP')) {
        final remaining = res.remainingAttempts;
        localizedError = (remaining != null && remaining > 0)
            ? 'ತಪ್ಪಾದ ಕೋಡ್. ಉಳಿದ ಪ್ರಯತ್ನಗಳು: $remaining (Incorrect code. $remaining attempts left)'
            : 'ತಪ್ಪಾದ ಕೋಡ್. ಮಾಲೀಕರಿಂದ ಸರಿಯಾದ ಕೋಡ್ ಪಡೆಯಿರಿ (Incorrect code)';
      } else if (rawError.contains('OTP_LOCKED') || rawError.contains('TOO_MANY_ATTEMPTS') || rawError.contains('MAX_ATTEMPTS_EXCEEDED')) {
        _isLocked = true;
        localizedError = '5 ವಿಫಲ ಪ್ರಯತ್ನಗಳು. OTP ಲಾಕ್ ಆಗಿದೆ. ಮಾಲೀಕರಿಂದ ಹೊಸ OTP ಪಡೆಯಿರಿ (OTP locked: max attempts exceeded. Ask hirer for new OTP)';
      } else if (rawError.contains('OTP_EXPIRED')) {
        localizedError = 'ಆಗಮನದ ಕೋಡ್ ಅವಧಿ ಮೀರಿದೆ (Arrival code expired)';
      } else if (rawError.contains('MISSING_EXPIRY')) {
        localizedError = 'ಆಗಮನದ ಕೋಡ್ ಅವಧಿ ಸೆಟ್ ಆಗಿಲ್ಲ (Arrival code expiry missing)';
      } else if (rawError.contains('OTP_ALREADY_USED') || rawError.contains('ALREADY_VERIFIED')) {
        localizedError = 'ಆಗಮನದ ಕೋಡ್ ಈಗಾಗಲೇ ಬಳಸಲಾಗಿದೆ (Arrival code already used)';
      } else if (rawError.contains('UNAUTHORIZED_WORKER') || rawError.contains('UNAUTHORIZED')) {
        localizedError = 'ಅನಧಿಕೃತ ಕರೆ: ನಿಯೋಜಿತ ಕೆಲಸಗಾರ ಮಾತ್ರ ಪರಿಶೀಲಿಸಬಹುದು (Unauthorized: only assigned worker can redeem)';
      } else if (rawError.contains('BOOKING_NOT_ARRIVED') || rawError.contains('PREMATURE_VERIFICATION_NOT_ARRIVED')) {
        localizedError = 'ನೀವು ಇನ್ನೂ ಕೆಲಸದ ಸ್ಥಳಕ್ಕೆ ತಲುಪಿಲ್ಲ (Worker has not arrived within 75m gate)';
      } else if (rawError.contains('BOOKING_NOT_FOUND')) {
        localizedError = 'ಬುಕಿಂಗ್ ಕಂಡುಬಂದಿಲ್ಲ (Booking not found)';
      } else if (rawError.contains('NETWORK_ERROR') || rawError.toLowerCase().contains('network')) {
        localizedError = 'ನೆಟ್‌ವರ್ಕ್ ದೋಷ. ದಯವಿಟ್ಟು ಇಂಟರ್ನೆಟ್ ಪರಿಶೀಲಿಸಿ (Network error. Check connection and retry)';
      } else if (rawError.contains('SERVER_ERROR')) {
        localizedError = 'ಸರ್ವರ್ ದೋಷ. ದಯವಿಟ್ಟು ನಂತರ ಪ್ರಯತ್ನಿಸಿ (Server error. Please retry later)';
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = localizedError;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'ಸರ್ವರ್ ಸಂಪರ್ಕ ವಿಫಲವಾಗಿದೆ. ದಯವಿಟ್ಟು ಇಂಟರ್ನೆಟ್ ಪರಿಶೀಲಿಸಿ (Server unreachable. Check connection and retry)';
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header with Shield Badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF059669),
              size: 32,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'ಸ್ಥಳ ಪರಿಶೀಲನೆ • Arrival Verification',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'ಕೆಲಸ ಪ್ರಾರಂಭಿಸಲು ${widget.hirerName} ಅವರಿಂದ ಆಗಮನದ ಕೋಡ್ ಕೇಳಿ\nAsk ${widget.hirerName} for the arrival code to begin ${widget.jobTitle}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 6-Digit Responsive Input Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_codeLength, (index) {
              return Container(
                width: 44,
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  readOnly: _isLocked,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: GoogleFonts.sora(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF10B981),
                        width: 2,
                      ),
                    ),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      HapticFeedback.lightImpact();
                      if (index < _codeLength - 1) {
                        _focusNodes[index + 1].requestFocus();
                      } else {
                        _focusNodes[index].unfocus();
                        _verifyOtp();
                      }
                    } else if (index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // Error Message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFDC2626),
                ),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 8),

          // Verify Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _isLocked) ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLocked ? const Color(0xFF94A3B8) : const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isLocked
                          ? 'OTP ಲಾಕ್ ಆಗಿದೆ (OTP Locked)'
                          : 'ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿ • Verify & Start Job',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
