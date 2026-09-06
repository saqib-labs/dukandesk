import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isSubmitting = false;

  static const String paymentNumber = '03474268095';
  static const String paymentMethod = 'JazzCash / Easypaisa';
  static const String monthlyPrice = 'Rs. 449';

  Future<void> _submitPaymentClaim() async {
    setState(() => _isSubmitting = true);

    final user = FirebaseAuth.instance.currentUser!;

    await FirebaseFirestore.instance.collection('upgradeRequests').add({
      'ownerId': user.uid,
      'ownerPhone': user.phoneNumber ?? 'unknown',
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });

    setState(() => _isSubmitting = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('request_sent_title'.tr()),
          content: Text('request_sent_body'.tr()),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text('ok'.tr()),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('upgrade_title'.tr())),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF083244)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          color: AppColors.accent,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'premium_plan'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$monthlyPrice ${'per_month'.tr()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FeatureRow(text: 'feature_unlimited_products'.tr()),
                    _FeatureRow(text: 'feature_unlimited_orders'.tr()),
                    _FeatureRow(text: 'feature_advanced_reports'.tr()),
                    _FeatureRow(text: 'feature_priority_support'.tr()),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'how_to_pay'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryContainer,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. ${'pay_step1'.tr()} $monthlyPrice ${'pay_via'.tr()} $paymentMethod:',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      paymentNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '2. ${'pay_step2'.tr()}',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '3. ${'pay_step3'.tr()}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitPaymentClaim,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('sent_payment_button'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
