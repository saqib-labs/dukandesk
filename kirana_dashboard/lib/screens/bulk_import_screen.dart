import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  List<List<dynamic>>? _parsedRows;
  String? _fileName;
  bool _isImporting = false;
  int _importedCount = 0;
  List<String> _errors = [];

  List<List<dynamic>> _parseCsv(String content) {
    final rows = <List<dynamic>>[];
    final lines = const LineSplitter().convert(content);

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final row = <String>[];
      final buffer = StringBuffer();
      var inQuotes = false;

      for (var i = 0; i < line.length; i++) {
        final char = line[i];
        if (char == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (char == ',' && !inQuotes) {
          row.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(char);
        }
      }

      row.add(buffer.toString().trim());
      rows.add(row);
    }

    return rows;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final bytes = result.files.single.bytes!;
      final content = utf8.decode(bytes);
      final rows = _parseCsv(content);

      setState(() {
        _parsedRows = rows;
        _fileName = result.files.single.name;
        _errors = [];
        _importedCount = 0;
      });
    }
  }

  Future<void> _importProducts() async {
    if (_parsedRows == null || _parsedRows!.length < 2) return;

    setState(() {
      _isImporting = true;
      _errors = [];
      _importedCount = 0;
    });

    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final header = _parsedRows![0]
        .map((e) => e.toString().trim().toLowerCase())
        .toList();

    final nameIdx = header.indexOf('name');
    final costPriceIdx = header.indexOf('costprice');
    final priceIdx = header.indexOf('price');
    final unitIdx = header.indexOf('unit');
    final stockIdx = header.indexOf('stockqty');
    final thresholdIdx = header.indexOf('lowstockthreshold');

    if (nameIdx == -1 ||
        priceIdx == -1 ||
        costPriceIdx == -1 ||
        stockIdx == -1) {
      setState(() {
        _isImporting = false;
        _errors = [
          'Missing required columns. Need: name, costPrice, price, stockQty (unit and lowStockThreshold optional).',
        ];
      });
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    final productsRef = FirebaseFirestore.instance.collection('products');
    int count = 0;
    List<String> rowErrors = [];

    for (int i = 1; i < _parsedRows!.length; i++) {
      final row = _parsedRows![i];
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty))
        continue;

      try {
        final name = row[nameIdx].toString().trim();
        final costPrice = double.parse(row[costPriceIdx].toString().trim());
        final price = double.parse(row[priceIdx].toString().trim());
        final unit = unitIdx != -1 && unitIdx < row.length
            ? row[unitIdx].toString().trim()
            : 'pcs';
        final stockQty = int.parse(row[stockIdx].toString().trim());
        final threshold = thresholdIdx != -1 && thresholdIdx < row.length
            ? int.tryParse(row[thresholdIdx].toString().trim()) ?? 5
            : 5;

        if (name.isEmpty) {
          rowErrors.add('Row ${i + 1}: name is empty, skipped');
          continue;
        }

        final docRef = productsRef.doc();
        batch.set(docRef, {
          'name': name,
          'costPrice': costPrice,
          'price': price,
          'unit': unit.isEmpty ? 'pcs' : unit,
          'stockQty': stockQty,
          'lowStockThreshold': threshold,
          'ownerId': ownerId,
        });
        count++;
      } catch (e) {
        rowErrors.add('Row ${i + 1}: invalid data, skipped ($e)');
      }
    }

    if (count > 0) {
      await batch.commit();
    }

    setState(() {
      _isImporting = false;
      _importedCount = count;
      _errors = rowErrors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('bulk_import_title'.tr())),
        body: Padding(
          padding: const EdgeInsets.all(16),
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
                    Text(
                      'csv_format_title'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'csv_format_body'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_fileName ?? 'choose_csv'.tr()),
              ),
              if (_parsedRows != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${_parsedRows!.length - 1} ${'rows_found'.tr()}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isImporting ? null : _importProducts,
                    child: _isImporting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text('import_products_button'.tr()),
                  ),
                ),
              ],
              if (_importedCount > 0) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${'import_success'.tr()} $_importedCount ${'products_imported'.tr()}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (_errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'some_rows_issues'.tr(),
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._errors.map(
                        (e) => Text(
                          '• $e',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
