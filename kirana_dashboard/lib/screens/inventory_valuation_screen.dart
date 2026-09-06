import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../models/product.dart';
import '../theme/app_colors.dart';

class InventoryValuationScreen extends StatelessWidget {
  const InventoryValuationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final isRtl = context.locale.languageCode == 'ur';

    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('inventory_valuation_title'.tr())),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('products')
              .where('ownerId', isEqualTo: ownerId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final products = snapshot.data!.docs
                .map((doc) => Product.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                .toList();

            double totalCostValue = 0;
            double totalSaleValue = 0;

            for (final p in products) {
              totalCostValue += p.stockQty * p.costPrice;
              totalSaleValue += p.stockQty * p.price;
            }

            final totalPotentialProfit = totalSaleValue - totalCostValue;

            products.sort((a, b) => (b.stockQty * b.price).compareTo(a.stockQty * a.price));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard('total_stock_value'.tr(), totalCostValue, AppColors.textSecondary, Icons.inventory_2_outlined),
                const SizedBox(height: 10),
                _summaryCard('total_potential_revenue'.tr(), totalSaleValue, AppColors.primary, Icons.trending_up),
                const SizedBox(height: 10),
                _summaryCard(
                  'total_potential_profit'.tr(),
                  totalPotentialProfit,
                  totalPotentialProfit >= 0 ? AppColors.success : AppColors.error,
                  totalPotentialProfit >= 0 ? Icons.savings_outlined : Icons.trending_down,
                ),
                const SizedBox(height: 24),
                Text(
                  'per_product_breakdown'.tr(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 12),
                if (products.isEmpty)
                  Text('no_products'.tr(), style: const TextStyle(color: AppColors.textSecondary))
                else
                  ...products.map((p) {
                    final costWorth = p.stockQty * p.costPrice;
                    final saleWorth = p.stockQty * p.price;
                    final profit = saleWorth - costWorth;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ),
                              Text(
                                '${p.stockQty} ${p.unit}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _miniStat('stock_worth_cost'.tr(), costWorth, AppColors.textSecondary),
                              _miniStat('stock_worth_sale'.tr(), saleWorth, AppColors.primary),
                              _miniStat('potential_profit'.tr(), profit, profit >= 0 ? AppColors.success : AppColors.error),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryCard(String label, double value, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Rs. ${value.abs().toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Icon(icon, color: Colors.white, size: 30),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          'Rs. ${value.abs().toStringAsFixed(0)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}