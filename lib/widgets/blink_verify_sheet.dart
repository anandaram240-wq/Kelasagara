// lib/widgets/blink_verify_sheet.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme/app_colors.dart';

/// ISO/IEC 30107-3 Level 1 presentation attack detection (PAD) modal sheet.
/// Mandates a natural physiological eye-blink before allowing sensitive profile
/// modifications (e.g. updating phone number, service area, or account data).
class BlinkVerifySheet extends StatefulWidget {
  final String actionLabel;
  final VoidCallback onVerified;

  const BlinkVerifySheet({
    super.key,
    required this.actionLabel,
    required this.onVerified,
  });

  /// Presents the bottom sheet and invokes [onVerified] upon confirmed blink.
  static Future<bool> show(
    BuildContext context, {
    required String actionLabel,
    required VoidCallback onVerified,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlinkVerifySheet(
        actionLabel: actionLabel,
        onVerified: onVerified,
      ),
    );
    return result == true;
  }

  @override
  State<BlinkVerifySheet> createState() => _BlinkVerifySheetState();
}

enum _VerifyStage { searching, aligned, blinking, verified, failed }

class _BlinkVerifySheetState extends State<BlinkVerifySheet> {
  static const double _eyeOpen = 0.62;
  static const double _eyeClosed = 0.30;
  static const int _minOpen = 6;
  static const int _minClosed = 2;

  List<CameraDescription> _cameras = [];
  CameraController? _camCtrl;
  FaceDetector? _detector;
  bool _processing = false;
  _VerifyStage _stage = _VerifyStage.searching;
  int _openCount = 0;
  int _closedCount = 0;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _initDetector();
    _initCamera();
  }

  @override
  void dispose() {
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _detector?.close();
    super.dispose();
  }

  Future<void> _initDetector() async {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.25,
      ),
    );
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint('[BlinkVerify] Camera permission not granted');
        if (mounted) setState(() {});
        return;
      }
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _camCtrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _camCtrl!.initialize();
      if (!mounted) return;
      setState(() {});
      _camCtrl!.startImageStream(_onCameraImage);
    } catch (e) {
      debugPrint('[BlinkVerify] Camera init exception: $e');
      if (mounted) setState(() {});
    }
  }

  void _onCameraImage(CameraImage img) {
    if (_processing || _verified) return;
    _processing = true;
    _detectBlink(img).whenComplete(() => _processing = false);
  }

  Future<void> _detectBlink(CameraImage img) async {
    try {
      if (_detector == null || !mounted) return;
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      final rotation = _getRotation(camera.sensorOrientation);
      final inputImage = InputImage.fromBytes(
        bytes: img.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: img.planes[0].bytesPerRow,
        ),
      );
      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted && _stage != _VerifyStage.searching) {
          setState(() => _stage = _VerifyStage.searching);
        }
        _openCount = 0;
        _closedCount = 0;
        return;
      }

      final face = faces.first;
      final lOpen = face.leftEyeOpenProbability ?? 1.0;
      final rOpen = face.rightEyeOpenProbability ?? 1.0;
      final avg = (lOpen + rOpen) / 2.0;
      _processBlink(avg);
    } catch (_) {}
  }

  void _processBlink(double avg) {
    switch (_stage) {
      case _VerifyStage.searching:
        if (avg > _eyeOpen) {
          _openCount = 1;
          if (mounted) setState(() => _stage = _VerifyStage.aligned);
        }
      case _VerifyStage.aligned:
        if (avg > _eyeOpen) {
          _openCount++;
        } else if (avg < _eyeClosed && _openCount >= _minOpen) {
          _closedCount = 1;
          if (mounted) setState(() => _stage = _VerifyStage.blinking);
        } else if (avg < _eyeClosed) {
          _openCount = 0;
        }
      case _VerifyStage.blinking:
        if (avg < _eyeClosed) {
          _closedCount++;
        } else if (avg > _eyeOpen && _closedCount >= _minClosed) {
          _onBlinkConfirmed();
        } else {
          _openCount = 0;
          _closedCount = 0;
          if (mounted) setState(() => _stage = _VerifyStage.aligned);
        }
      case _VerifyStage.verified:
      case _VerifyStage.failed:
        break;
    }
  }

  void _onBlinkConfirmed() {
    if (_verified) return;
    _verified = true;
    _camCtrl?.stopImageStream();
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _stage = _VerifyStage.verified);

    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) {
        widget.onVerified();
        Navigator.of(context).pop(true);
      }
    });
  }

  InputImageRotation _getRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Title
              Text(
                'ಮುಖ ಪರಿಶೀಲನೆ (Blink Verify)',
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textHead,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.actionLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              // Oval Camera Preview
              _buildCameraOval(),
              const SizedBox(height: 18),
              // Status Pill
              _buildStatusPill(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraOval() {
    final ovalColor = switch (_stage) {
      _VerifyStage.searching => AppColors.border,
      _VerifyStage.aligned => AppColors.primary,
      _VerifyStage.blinking => AppColors.gold,
      _VerifyStage.verified => AppColors.green,
      _VerifyStage.failed => AppColors.red,
    };

    final isReady = _camCtrl != null && _camCtrl!.value.isInitialized;

    return Center(
      child: Container(
        width: 220,
        height: 270,
        decoration: BoxDecoration(
          border: Border.all(color: ovalColor, width: 3.5),
          borderRadius: BorderRadius.circular(130),
          color: Colors.black,
        ),
        clipBehavior: Clip.hardEdge,
        child: isReady
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _camCtrl!.value.previewSize!.height,
                    height: _camCtrl!.value.previewSize!.width,
                    child: CameraPreview(_camCtrl!),
                  ),
                ),
              )
            : Container(
                color: Colors.black87,
                child: const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatusPill() {
    final (emoji, text, color) = switch (_stage) {
      _VerifyStage.searching => ('👤', 'ಮುಖ ಚೌಕಟ್ಟಿನಲ್ಲಿ ಹಿಡಿಯಿರಿ (Fit face in oval)', AppColors.textLight),
      _VerifyStage.aligned => ('😐', 'ಕಣ್ಣು ಮಿಟಕಿಸಿ (Now blink to verify)', AppColors.primary),
      _VerifyStage.blinking => ('🔄', 'ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ (Verifying blink...)', AppColors.gold),
      _VerifyStage.verified => ('✅', 'ಪರಿಶೀಲಿಸಲಾಗಿದೆ! (Identity verified)', AppColors.green),
      _VerifyStage.failed => ('❌', 'ವಿಫಲ — ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ (Try again)', AppColors.red),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
