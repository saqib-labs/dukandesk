import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  Future<void> _showOrderActions(BuildContext context, ShopOrder order) async {
    if (order.status == 'cancelled') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Order Cancelled'),
          content: const Text('This order has already been cancelled.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order Options'),
        content: const Text(
          'Cancelling will restore any deducted stock for this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (order.status == 'matched')
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text(
                'Cancel Order',
                style: TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
    );

    if (action == 'cancel') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Cancellation'),
          content: const Text(
            'This will mark the order as cancelled and restore stock for its items. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await _cancelOrder(order);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Order cancelled and stock restored'),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
          }
        }
      }
    }
  }

  Future<void> _cancelOrder(ShopOrder order) async {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final productsSnapshot = await FirebaseFirestore.instance
        .collection('products')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    final productByName = {
      for (final doc in productsSnapshot.docs)
        (doc.data()['name'] as String): doc.id,
    };

    for (final item in order.matchedItems) {
      final productId = productByName[item.productName];
      if (productId != null) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .update({'stockQty': FieldValue.increment(item.quantity)});
      }
    }

    await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
      'status': 'cancelled',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order History')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('ownerId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .orderBy('createdAt', descending: true)
            .limit(50)
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
            return const Center(
              child: Text(
                'No orders yet.',
                style: TextStyle(color: AppColors.textSecondary),
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

              return InkWell(
                onTap: () => _showOrderActions(context, order),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
                          Text(
                            order.customerNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          _statusBadge(order.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (order.matchedItems.isNotEmpty)
                        ...order.matchedItems.map(
                          (item) => Text(
                            '• ${item.quantity.toStringAsFixed(0)} ${item.unit} ${item.productName}',
                            style: TextStyle(
                              fontSize: 14,
                              color: order.status == 'cancelled'
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                              decoration: order.status == 'cancelled'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      if (order.notFoundItems.isNotEmpty)
                        Text(
                          'Not found: ${order.notFoundItems.join(', ')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.error,
                          ),
                        ),
                      const SizedBox(height: 6),
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
                ),
              );
            },
          );
        },
      ),
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
