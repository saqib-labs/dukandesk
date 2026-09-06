import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  bool _isExporting = false;
  String _statusText = '';

  Future<void> _exportData() async {
    setState(() {
      _isExporting = true;
      _statusText = 'Fetching products...';
    });

    final ownerId = FirebaseAuth.instance.currentUser!.uid;

    try {
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      setState(() => _statusText = 'Fetching orders...');
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      setState(() => _statusText = 'Fetching customers...');
      final customersSnapshot = await FirebaseFirestore.instance
          .collection('customerNames')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      setState(() => _statusText = 'Fetching expenses...');
      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      final backupData = {
        'exportedAt': DateTime.now().toIso8601String(),
        'ownerId': ownerId,
        'products': productsSnapshot.docs
            .map((d) => _sanitize(d.data(), d.id))
            .toList(),
        'orders': ordersSnapshot.docs
            .map((d) => _sanitize(d.data(), d.id))
            .toList(),
        'customers': customersSnapshot.docs
            .map((d) => _sanitize(d.data(), d.id))
            .toList(),
        'expenses': expensesSnapshot.docs
            .map((d) => _sanitize(d.data(), d.id))
            .toList(),
      };

      setState(() => _statusText = 'Writing file...');

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final dir = await getTemporaryDirectory();
      final fileName =
          'dukandesk_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);

      setState(() {
        _isExporting = false;
        _statusText = 'Export ready — opening share sheet...';
      });

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'DukanDesk data backup'),
      );
    } catch (e) {
      setState(() {
        _isExporting = false;
        _statusText = 'Export failed: $e';
      });
    }
  }

  Map<String, dynamic> _sanitize(Map<String, dynamic> data, String id) {
    final result = {'id': id, ...data};
    result.forEach((key, value) {
      result[key] = _sanitizeValue(value);
    });
    return result;
  }

  dynamic _sanitizeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is Map) {
      return value.map((k, v) => MapEntry(k, _sanitizeValue(v)));
    } else if (value is List) {
      return value.map((v) => _sanitizeValue(v)).toList();
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('data_backup_title'.tr())),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      'backup_info_title'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'backup_info_body'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportData,
                  icon: const Icon(Icons.download),
                  label: _isExporting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text('export_share_backup'.tr()),
                ),
              ),
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
