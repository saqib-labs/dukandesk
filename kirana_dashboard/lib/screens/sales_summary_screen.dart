import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';
import 'pdf_report_generator.dart';
import '../theme/app_colors.dart';

enum ReportPeriod { day, week, month, custom }

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  ReportPeriod _selectedPeriod = ReportPeriod.day;
  DateTimeRange? _customRange;

  DateTime _startOfPeriod(ReportPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case ReportPeriod.day:
        return DateTime(now.year, now.month, now.day);
      case ReportPeriod.week:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      case ReportPeriod.month:
        return DateTime(now.year, now.month, 1);
      case ReportPeriod.custom:
        return _customRange != null
            ? DateTime(
                _customRange!.start.year,
                _customRange!.start.month,
                _customRange!.start.day,
              )
            : DateTime(now.year, now.month, now.day);
    }
  }

  DateTime _endOfPeriod(ReportPeriod period) {
    final now = DateTime.now();
    if (period == ReportPeriod.custom && _customRange != null) {
      final end = _customRange!.end;
      return DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text('sales_summary_title'.tr()),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF',
              onPressed: () async {
                final data = await _calculateSales(_selectedPeriod);
                final periodLabel = switch (_selectedPeriod) {
                  ReportPeriod.day => 'Today\'s Report',
                  ReportPeriod.week => 'This Week\'s Report',
                  ReportPeriod.month => 'This Month\'s Report',
                  ReportPeriod.custom =>
                    _customRange != null
                        ? '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d, yyyy').format(_customRange!.end)}'
                        : 'Custom Report',
                };
                await PdfReportGenerator.generateAndShare(
                  periodLabel: periodLabel,
                  totalOrders: data.totalOrders,
                  totalRevenue: data.totalRevenue,
                  topProducts: data.topProducts,
                  dailyBreakdown: data.dailyBreakdown,
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<ReportPeriod>(
                segments: [
                  ButtonSegment(
                    value: ReportPeriod.day,
                    label: Text('today_label'.tr()),
                  ),
                  ButtonSegment(
                    value: ReportPeriod.week,
                    label: Text('week_label'.tr()),
                  ),
                  ButtonSegment(
                    value: ReportPeriod.month,
                    label: Text('month_label'.tr()),
                  ),
                ],
                selected: {
                  _selectedPeriod == ReportPeriod.custom
                      ? ReportPeriod.day
                      : _selectedPeriod,
                },
                onSelectionChanged: (selection) {
                  setState(() => _selectedPeriod = selection.first);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 2),
                    lastDate: now,
                    initialDateRange:
                        _customRange ??
                        DateTimeRange(
                          start: now.subtract(const Duration(days: 7)),
                          end: now,
                        ),
                  );
                  if (picked != null) {
                    setState(() {
                      _customRange = picked;
                      _selectedPeriod = ReportPeriod.custom;
                    });
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text(
                  _customRange != null && _selectedPeriod == ReportPeriod.custom
                      ? '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d, yyyy').format(_customRange!.end)}'
                      : 'custom_range'.tr(),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<_SalesData>(
                key: ValueKey(
                  '$_selectedPeriod-${_customRange?.start}-${_customRange?.end}',
                ),
                future: _calculateSales(_selectedPeriod),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final data = snapshot.data!;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              'orders_label'.tr(),
                              data.totalOrders.toString(),
                              Icons.receipt_long,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statCard(
                              'revenue_label'.tr(),
                              'Rs. ${data.totalRevenue.toStringAsFixed(0)}',
                              Icons.trending_up,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              'cost_of_goods_label'.tr(),
                              'Rs. ${data.totalCost.toStringAsFixed(0)}',
                              Icons.shopping_bag_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statCard(
                              'expenses_label'.tr(),
                              'Rs. ${data.totalExpenses.toStringAsFixed(0)}',
                              Icons.money_off,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _statCard(
                        data.totalProfit >= 0
                            ? 'net_profit_label'.tr()
                            : 'net_loss_label'.tr(),
                        'Rs. ${data.totalProfit.abs().toStringAsFixed(0)}',
                        data.totalProfit >= 0
                            ? Icons.savings_outlined
                            : Icons.trending_down,
                        isNegative: data.totalProfit < 0,
                        fullWidth: true,
                      ),
                      if (data.dailyBreakdown.length > 1) ...[
                        const SizedBox(height: 24),
                        Text(
                          'revenue_trend'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 220,
                          padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _buildBarChart(data.dailyBreakdown),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'daily_breakdown'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...data.dailyBreakdown.entries.map(
                          (entry) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormat('EEE, MMM d').format(entry.key),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Rs. ${entry.value.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Rs. ${(data.dailyProfit[entry.key] ?? 0).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'top_products'.tr(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (data.topProducts.isNotEmpty) ...[
                        Container(
                          height: 220,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _buildTopProductsPie(data.topProducts),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (data.topProducts.isEmpty)
                        Text(
                          'no_sales_data'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        )
                      else
                        ...data.topProducts.map(
                          (entry) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${entry.value.toStringAsFixed(0)} ${'units_sold'.tr()}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(Map<DateTime, double> dailyBreakdown) {
    final entries = dailyBreakdown.entries.toList();
    final maxY = entries.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 10 : maxY * 1.2,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length)
                  return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('d/M').format(entries[index].key),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: List.generate(entries.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: entries[i].value,
                color: AppColors.primary,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTopProductsPie(List<MapEntry<String, double>> topProducts) {
    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      AppColors.textSecondary,
    ];
    final total = topProducts.fold(0.0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: List.generate(topProducts.length, (i) {
                final percent = total == 0
                    ? 0
                    : (topProducts[i].value / total * 100);
                return PieChartSectionData(
                  value: topProducts[i].value,
                  color: colors[i % colors.length],
                  title: '${percent.toStringAsFixed(0)}%',
                  radius: 60,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(topProducts.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        topProducts[i].key,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon, {
    bool isNegative = false,
    bool fullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: isNegative ? AppColors.error : AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: fullWidth
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: fullWidth
            ? [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Icon(icon, color: Colors.white, size: 32),
              ]
            : [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
      ),
    );
  }

  Future<_SalesData> _calculateSales(ReportPeriod period) async {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final startDate = _startOfPeriod(period);
    final endDate = _endOfPeriod(period);

    final productsSnapshot = await FirebaseFirestore.instance
        .collection('products')
        .where('ownerId', isEqualTo: ownerId)
        .get();

    final priceMap = <String, double>{};
    final costMap = <String, double>{};
    for (final doc in productsSnapshot.docs) {
      final data = doc.data();
      priceMap[data['name']] = (data['price'] ?? 0).toDouble();
      costMap[data['name']] = (data['costPrice'] ?? 0).toDouble();
    }

    final ordersSnapshot = await FirebaseFirestore.instance
        .collection('orders')
        .where('ownerId', isEqualTo: ownerId)
        .where('status', isEqualTo: 'matched')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    final expensesSnapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('ownerId', isEqualTo: ownerId)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    double totalExpenses = 0;
    for (final doc in expensesSnapshot.docs) {
      totalExpenses += (doc.data()['amount'] ?? 0).toDouble();
    }

    double totalRevenue = 0;
    double totalCost = 0;
    final productCounts = <String, double>{};
    final dailyRevenue = <DateTime, double>{};
    final dailyProfit = <DateTime, double>{};

    for (final doc in ordersSnapshot.docs) {
      final orderData = doc.data();
      final items = (orderData['matchedItems'] as List<dynamic>?) ?? [];
      final createdAt = (orderData['createdAt'] as Timestamp?)?.toDate();

      double orderRevenue = 0;
      double orderCost = 0;

      for (final item in items) {
        final name = item['productName'] as String;
        final qty = (item['quantity'] ?? 0).toDouble();
        final itemRevenue = qty * (priceMap[name] ?? 0);
        final itemCost = qty * (costMap[name] ?? 0);

        productCounts[name] = (productCounts[name] ?? 0) + qty;
        totalRevenue += itemRevenue;
        totalCost += itemCost;
        orderRevenue += itemRevenue;
        orderCost += itemCost;
      }

      if (createdAt != null) {
        final dayKey = DateTime(createdAt.year, createdAt.month, createdAt.day);
        dailyRevenue[dayKey] = (dailyRevenue[dayKey] ?? 0) + orderRevenue;
        dailyProfit[dayKey] =
            (dailyProfit[dayKey] ?? 0) + (orderRevenue - orderCost);
      }
    }

    final sortedProducts = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sortedDaily = Map.fromEntries(
      dailyRevenue.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    return _SalesData(
      totalOrders: ordersSnapshot.docs.length,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      totalExpenses: totalExpenses,
      totalProfit: totalRevenue - totalCost - totalExpenses,
      topProducts: sortedProducts.take(5).toList(),
      dailyBreakdown: sortedDaily,
      dailyProfit: dailyProfit,
    );
  }
}

class _SalesData {
  final int totalOrders;
  final double totalRevenue;
  final double totalCost;
  final double totalExpenses;
  final double totalProfit;
  final List<MapEntry<String, double>> topProducts;
  final Map<DateTime, double> dailyBreakdown;
  final Map<DateTime, double> dailyProfit;

  _SalesData({
    required this.totalOrders,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalExpenses,
    required this.totalProfit,
    required this.topProducts,
    required this.dailyBreakdown,
    required this.dailyProfit,
  });
}
