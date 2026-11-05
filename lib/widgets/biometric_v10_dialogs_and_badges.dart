// FILE: lib/widgets/biometric_v10_dialogs_and_badges.dart

import 'package:flutter/material.dart';
import '../biometrics/biometric_v10_models_and_client.dart';

class DuplicateAccountDetectedDialog extends StatelessWidget {
  final MaskedDuplicateAccountDetails details;
  final VoidCallback onSignInToOriginalAccount;
  final VoidCallback? onRequestHumanReview;

  const DuplicateAccountDetectedDialog({
    super.key,
    required this.details,
    required this.onSignInToOriginalAccount,
    this.onRequestHumanReview,
  });

  static Future<void> show({
    required BuildContext context,
    required MaskedDuplicateAccountDetails details,
    required VoidCallback onSignInToOriginalAccount,
    VoidCallback? onRequestHumanReview,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DuplicateAccountDetectedDialog(
        details: details,
        onSignInToOriginalAccount: onSignInToOriginalAccount,
        onRequestHumanReview: onRequestHumanReview,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('duplicate_account_detected_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Duplicate Account Creation Detected',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your face is already registered with an existing Kelasagara account. '
              'Multiple accounts for the same individual are not permitted.',
              style: TextStyle(fontSize: 13.5, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  _detailRow('Status', 'Duplicate Detected / ನಕಲಿ ಖಾತೆ ಪತ್ತೆಯಾಗಿದೆ', keyName: 'dup_status'),
                  const Divider(height: 12),
                  _detailRow('Notice', 'No individual details disclosed / ಗೌಪ್ಯತೆ ಸಂರಕ್ಷಣೆ', keyName: 'dup_privacy_notice'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (onRequestHumanReview != null)
          TextButton(
            key: const Key('dup_request_review_btn'),
            onPressed: () {
              Navigator.of(context).pop();
              onRequestHumanReview!();
            },
            child: const Text('Request Biometric Review'),
          ),
        ElevatedButton.icon(
          key: const Key('dup_signin_existing_btn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onSignInToOriginalAccount();
          },
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Sign In to Existing Account'),
        ),
      ],
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    required String keyName,
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            key: Key(keyName),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlight ? Colors.red.shade800 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class LockedBiometricTokenCard extends StatelessWidget {
  final String faceId;
  final String biometricLockToken;
  final VoidCallback onVerify1To1Ekyc;
  final VoidCallback onStepUpReRegister;

  const LockedBiometricTokenCard({
    super.key,
    required this.faceId,
    required this.biometricLockToken,
    required this.onVerify1To1Ekyc,
    required this.onStepUpReRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('locked_biometric_token_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Colors.green, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Face ID Registered & Locked (No Re-Registration Required)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Linked Face ID: $faceId', key: const Key('locked_face_id_text')),
          Text(
            'Lock Token: $biometricLockToken',
            key: const Key('locked_token_text'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('btn_verify_1to1_ekyc'),
                  onPressed: onVerify1To1Ekyc,
                  icon: const Icon(Icons.face_retouching_natural, size: 18),
                  label: const Text('Verify 1:1 eKYC'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('btn_step_up_rotate_face'),
                onPressed: onStepUpReRegister,
                child: const Text('Authorized Face Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
