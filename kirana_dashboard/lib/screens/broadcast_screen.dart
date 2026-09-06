import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _messageController = TextEditingController();
  final Set<String> _selectedPhones = {};
  bool _selectAll = true;
  bool _isSending = false;

  Future<void> _sendBroadcast(List<String> allPhones) async {
    if (_messageController.text.trim().isEmpty) return;

    final targetPhones = _selectAll ? allPhones : _selectedPhones.toList();
    if (targetPhones.isEmpty) return;

    setState(() => _isSending = true);

    final ownerId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('broadcasts').add({
      'ownerId': ownerId,
      'message': _messageController.text.trim(),
      'targetPhones': targetPhones,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() => _isSending = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('broadcast_queued_title'.tr()),
          content: Text(
            '${'broadcast_queued_body'.tr()} ${targetPhones.length} ${'customers_shortly'.tr()}',
          ),
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
        appBar: AppBar(title: Text('broadcast_title'.tr())),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('customerNames')
              .where(
                'ownerId',
                isEqualTo: FirebaseAuth.instance.currentUser!.uid,
              )
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final customers = snapshot.data!.docs
                .map(
                  (doc) => {
                    'phone': doc.id,
                    'name': (doc.data() as Map<String, dynamic>)['name'] ?? '',
                  },
                )
                .toList();

            final allPhones = customers
                .map((c) => c['phone']!)
                .toList()
                .cast<String>();

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'message_label'.tr(),
                      hintText: 'message_hint'.tr(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'send_to_all'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      '${customers.length} ${'customers_total'.tr()}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    value: _selectAll,
                    activeThumbColor: AppColors.primary,
                    onChanged: (value) => setState(() => _selectAll = value),
                  ),
                  if (!_selectAll) ...[
                    const Divider(),
                    Text(
                      'select_customers'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          final displayName = c['name']!.isNotEmpty
                              ? c['name']!
                              : c['phone']!;
                          return CheckboxListTile(
                            title: Text(
                              displayName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              c['phone']!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _selectedPhones.contains(c['phone']),
                            activeColor: AppColors.primary,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedPhones.add(c['phone']!);
                                } else {
                                  _selectedPhones.remove(c['phone']);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ] else
                    const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSending
                          ? null
                          : () => _sendBroadcast(allPhones),
                      icon: const Icon(Icons.send),
                      label: _isSending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text('send_broadcast'.tr()),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
