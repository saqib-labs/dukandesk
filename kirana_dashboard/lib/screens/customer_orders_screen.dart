import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../models/order.dart';
import '../models/credit_transaction.dart';
import '../theme/app_colors.dart';

class CustomerOrdersScreen extends StatefulWidget {
  final String phone;
  final String initialName;

  const CustomerOrdersScreen({
    super.key,
    required this.phone,
    required this.initialName,
  });

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final ownerId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('customerNames')
        .doc(widget.phone)
        .set({
          'ownerId': ownerId,
          'phone': widget.phone,
          'name': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'save'.tr()}: $name')));
    }
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _nameController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('customer_name_dialog'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'customer_name_label'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _nameController.text = result);
      await _saveName();
    }
  }

  Future<void> _addCreditTransaction(String type) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          type == 'credit'
              ? 'add_credit_title'.tr()
              : 'record_payment_title'.tr(),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: 'amount_label'.tr()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(labelText: 'note_optional'.tr()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );

    if (result == true) {
      final amount = double.tryParse(amountController.text.trim());
      if (amount == null || amount <= 0) return;

      final ownerId = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('creditTransactions').add({
        'ownerId': ownerId,
        'phone': widget.phone,
        'amount': amount,
        'type': type,
        'note': noteController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              type == 'credit' ? 'credit_added'.tr() : 'payment_recorded'.tr(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _nameController.text.isNotEmpty
                ? _nameController.text
                : widget.phone,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'rename_customer'.tr(),
              onPressed: _showRenameDialog,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'orders_tab'.tr()),
              Tab(text: 'credit_tab'.tr()),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.primaryContainer,
              child: Row(
                children: [
                  const Icon(Icons.phone, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    widget.phone,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('loyaltyPoints')
                        .doc(widget.phone)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final points = snapshot.data?.exists == true
                          ? (snapshot.data!.data()
                                    as Map<String, dynamic>)['points'] ??
                                0
                          : 0;
                      return Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$points pts',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildOrdersTab(), _buildCreditTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTab() {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('ownerId', isEqualTo: ownerId)
          .where('customerNumber', isEqualTo: widget.phone)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'no_orders_from_customer'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final order = ShopOrder.fromMap(
              docs[index].id,
              docs[index].data() as Map<String, dynamic>,
            );

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statusBadge(order.status),
                      Text(
                        order.createdAt != null
                            ? DateFormat(
                                'MMM d, h:mm a',
                              ).format(order.createdAt!)
                            : '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (order.matchedItems.isNotEmpty)
                    ...order.matchedItems.map(
                      (item) => Text(
                        '• ${item.quantity.toStringAsFixed(0)} ${item.unit} ${item.productName}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  if (order.notFoundItems.isNotEmpty)
                    Text(
                      '${'not_found_label'.tr()}: ${order.notFoundItems.join(', ')}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCreditTab() {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('creditTransactions')
          .where('ownerId', isEqualTo: ownerId)
          .where('phone', isEqualTo: widget.phone)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data!.docs
            .map(
              (doc) => CreditTransaction.fromMap(
                doc.id,
                doc.data() as Map<String, dynamic>,
              ),
            )
            .toList();

        double balance = 0;
        for (final t in transactions) {
          balance += t.type == 'credit' ? t.amount : -t.amount;
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: balance > 0
                    ? AppColors.warning.withOpacity(0.12)
                    : AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'outstanding_balance'.tr(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Rs. ${balance.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: balance > 0
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton.filled(
                        onPressed: () => _addCreditTransaction('credit'),
                        icon: const Icon(Icons.add),
                        tooltip: 'add_credit_tooltip'.tr(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => _addCreditTransaction('payment'),
                        icon: const Icon(Icons.check),
                        tooltip: 'record_payment_tooltip'.tr(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: transactions.isEmpty
                  ? Center(
                      child: Text(
                        'no_credit_history'.tr(),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final t = transactions[index];
                        final isCredit = t.type == 'credit';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCredit
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: isCredit
                                    ? AppColors.warning
                                    : AppColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCredit
                                          ? 'credit_given'.tr()
                                          : 'payment_received'.tr(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (t.note.isNotEmpty)
                                      Text(
                                        t.note,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    Text(
                                      t.createdAt != null
                                          ? DateFormat(
                                              'MMM d, h:mm a',
                                            ).format(t.createdAt!)
                                          : '',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Rs. ${t.amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit
                                      ? AppColors.warning
                                      : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    switch (status) {
      case 'matched':
        color = AppColors.success;
        break;
      case 'unmatched':
        color = AppColors.warning;
        break;
      case 'cancelled':
        color = AppColors.error;
        break;
      default:
        color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
