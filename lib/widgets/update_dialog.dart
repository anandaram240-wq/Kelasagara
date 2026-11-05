// lib/widgets/update_dialog.dart
// ================================================================
// KELASAGARA — In-App Update Dialog
//
// Shows when AppUpdateService detects a newer build.
// "Update Now"  → opens APK download URL in browser
// "Not Now"     → dismissed (hidden if forceUpdate=true)
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';

class UpdateDialog extends StatelessWidget {
  final AppVersionInfo versionInfo;

  const UpdateDialog({super.key, required this.versionInfo});

  /// Call this from home_shell initState to show dialog if update available.
  static Future<void> checkAndShow(BuildContext context) async {
    final info = await AppUpdateService.instance.checkForUpdate();
    if (info == null || !info.updateAvailable) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (_) => UpdateDialog(versionInfo: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !versionInfo.forceUpdate,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 28)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Update Available',
                    style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('v${versionInfo.latestVersion}',
                    style: GoogleFonts.sora(color: const Color(0xFF6366F1), fontSize: 13, fontWeight: FontWeight.w600)),
                ])),
              ]),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFF334155)),
              const SizedBox(height: 12),

              // Version info
              Row(children: [
                _chip('Current', 'v${versionInfo.currentVersion}', const Color(0xFF475569)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF64748B), size: 18),
                const SizedBox(width: 8),
                _chip('New', 'v${versionInfo.latestVersion}', const Color(0xFF10B981)),
              ]),

              const SizedBox(height: 14),

              // Release notes
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("What's new", style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(versionInfo.releaseNotes,
                    style: GoogleFonts.sora(color: Colors.white70, fontSize: 13)),
                ]),
              ),

              if (versionInfo.forceUpdate) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.warning_rounded, color: Color(0xFFFCA5A5), size: 16),
                    const SizedBox(width: 6),
                    Text('This update is required to continue.',
                      style: GoogleFonts.sora(color: const Color(0xFFFCA5A5), fontSize: 12)),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              // Buttons
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final url = Uri.parse(versionInfo.downloadUrl);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Update Now', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  ]),
                ),
              ),

              if (!versionInfo.forceUpdate) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Color(0xFF334155))),
                    child: Text('Not Now', style: GoogleFonts.sora(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(80))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.sora(color: color.withAlpha(180), fontSize: 9, fontWeight: FontWeight.w600)),
      Text(value, style: GoogleFonts.sora(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}
