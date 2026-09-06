import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class PdfReportGenerator {
  static Future<void> generateAndShare({
    required String periodLabel,
    required int totalOrders,
    required double totalRevenue,
    required List<MapEntry<String, double>> topProducts,
    required Map<DateTime, double> dailyBreakdown,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Kirana Sales Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                periodLabel,
                style: const pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 20),

              // Summary stats
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _summaryBox('Total Orders', totalOrders.toString()),
                  _summaryBox(
                    'Est. Revenue',
                    'Rs. ${totalRevenue.toStringAsFixed(0)}',
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Daily breakdown table
              if (dailyBreakdown.isNotEmpty) ...[
                pw.Text(
                  'Daily Breakdown',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        _cell('Date', bold: true),
                        _cell('Revenue', bold: true),
                      ],
                    ),
                    ...dailyBreakdown.entries.map(
                      (e) => pw.TableRow(
                        children: [
                          _cell(DateFormat('EEE, MMM d, yyyy').format(e.key)),
                          _cell('Rs. ${e.value.toStringAsFixed(0)}'),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
              ],

              // Top products table
              pw.Text(
                'Top Products',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              if (topProducts.isEmpty)
                pw.Text('No sales data for this period.')
              else
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        _cell('Product', bold: true),
                        _cell('Units Sold', bold: true),
                      ],
                    ),
                    ...topProducts.map(
                      (e) => pw.TableRow(
                        children: [
                          _cell(e.key),
                          _cell(e.value.toStringAsFixed(0)),
                        ],
                      ),
                    ),
                  ],
                ),

              pw.SizedBox(height: 30),
              pw.Text(
                'Generated on ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          );
        },
      ),
    );

    // Opens Android's native share/print sheet - lets the user save, print, or share the PDF
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'kirana_sales_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _summaryBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
