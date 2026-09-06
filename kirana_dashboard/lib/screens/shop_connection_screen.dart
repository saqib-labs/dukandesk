import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

class ShopConnectionScreen extends StatefulWidget {
  const ShopConnectionScreen({super.key});

  @override
  State<ShopConnectionScreen> createState() => _ShopConnectionScreenState();
}

class _ShopConnectionScreenState extends State<ShopConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneNumberIdController = TextEditingController();
  final _accessTokenController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _displayPhoneController = TextEditingController();
  bool _isSaving = false;

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final phoneNumberId = _phoneNumberIdController.text.trim();

    try {
      await FirebaseFirestore.instance.collection('shopChannels').doc(phoneNumberId).set({
        'ownerId': ownerId,
        'shopName': _shopNameController.text.trim(),
        'whatsappToken': _accessTokenController.text.trim(),
        'displayPhoneNumber': _displayPhoneController.text.trim(),
        'connectedAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      await FirebaseFirestore.instance.collection('users').doc(ownerId).set(
        {'whatsappPhoneNumberId': phoneNumberId},
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp number connected successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('connect_whatsapp_title'.tr())),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('connect_whatsapp_help'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Text('connect_whatsapp_steps'.tr(), style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _shopNameController,
                  decoration: InputDecoration(labelText: 'shop_name_field'.tr(), prefixIcon: const Icon(Icons.storefront_outlined)),
                  validator: (v) => v == null || v.isEmpty ? 'field_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayPhoneController,
                  decoration: InputDecoration(labelText: 'whatsapp_number_field'.tr(), prefixIcon: const Icon(Icons.phone)),
                  validator: (v) => v == null || v.isEmpty ? 'field_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumberIdController,
                  decoration: InputDecoration(labelText: 'phone_number_id_field'.tr(), prefixIcon: const Icon(Icons.numbers)),
                  validator: (v) => v == null || v.isEmpty ? 'field_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accessTokenController,
                  decoration: InputDecoration(labelText: 'access_token_field'.tr(), prefixIcon: const Icon(Icons.key)),
                  maxLines: 3,
                  validator: (v) => v == null || v.isEmpty ? 'field_required'.tr() : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveConnection,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('connect_whatsapp_button'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}