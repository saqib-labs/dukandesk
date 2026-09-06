import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'customer_orders_screen.dart';
import '../theme/app_colors.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomerSummary {
  final String phone;
  String name;
  int orderCount;
  DateTime? lastOrderAt;

  _CustomerSummary({
    required this.phone,
    required this.name,
    required this.orderCount,
    required this.lastOrderAt,
  });
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('add_customer_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'customer_name_label'.tr(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'customer_phone_label'.tr(),
                helperText: 'customer_phone_hint'.tr(),
              ),
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
      final name = nameController.text.trim();
      final phone = phoneController.text.trim().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (name.isEmpty || phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('name_phone_required'.tr())));
        }
        return;
      }

      final ownerId = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection('customerNames')
          .doc(phone)
          .set({
            'ownerId': ownerId,
            'phone': phone,
            'name': name,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'added_customer'.tr()}: $name')),
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
        appBar: AppBar(title: Text('customers_title'.tr())),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'search_customers'.tr(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('customerNames')
                    .where(
                      'ownerId',
                      isEqualTo: FirebaseAuth.instance.currentUser!.uid,
                    )
                    .snapshots(),
                builder: (context, nameSnapshot) {
                  final nameMap = <String, String>{};
                  if (nameSnapshot.hasData) {
                    for (final doc in nameSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      nameMap[doc.id] = data['name'] ?? '';
                    }
                  }

                  final ownerId = FirebaseAuth.instance.currentUser!.uid;
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('orders')
                        .where('ownerId', isEqualTo: ownerId)
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, orderSnapshot) {
                      if (orderSnapshot.hasError) {
                        return Center(
                          child: Text('Error: ${orderSnapshot.error}'),
                        );
                      }
                      if (!orderSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final grouped = <String, _CustomerSummary>{};

                      for (final entry in nameMap.entries) {
                        grouped[entry.key] = _CustomerSummary(
                          phone: entry.key,
                          name: entry.value,
                          orderCount: 0,
                          lastOrderAt: null,
                        );
                      }

                      for (final doc in orderSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final phone = data['customerNumber'] as String?;
                        if (phone == null || phone == 'walk-in') continue;

                        final createdAt = (data['createdAt'] as Timestamp?)
                            ?.toDate();

                        if (grouped.containsKey(phone)) {
                          grouped[phone]!.orderCount++;
                          grouped[phone]!.lastOrderAt ??= createdAt;
                        } else {
                          grouped[phone] = _CustomerSummary(
                            phone: phone,
                            name: nameMap[phone] ?? '',
                            orderCount: 1,
                            lastOrderAt: createdAt,
                          );
                        }
                      }

                      var customers = grouped.values.toList();

                      if (_searchQuery.isNotEmpty) {
                        customers = customers.where((c) {
                          final nameMatch = c.name.toLowerCase().contains(
                            _searchQuery,
                          );
                          final phoneMatch = c.phone.contains(_searchQuery);
                          return nameMatch || phoneMatch;
                        }).toList();
                      }

                      customers.sort((a, b) {
                        if (a.lastOrderAt == null && b.lastOrderAt == null)
                          return 0;
                        if (a.lastOrderAt == null) return 1;
                        if (b.lastOrderAt == null) return -1;
                        return b.lastOrderAt!.compareTo(a.lastOrderAt!);
                      });

                      if (customers.isEmpty) {
                        return Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? '${'no_customers_match'.tr()} "${_searchController.text}"'
                                : 'no_customers_yet'.tr(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          final customer = customers[index];
                          final displayName = customer.name.isNotEmpty
                              ? customer.name
                              : 'unnamed'.tr();
                          final orderWord = customer.orderCount == 1
                              ? 'order_count'.tr()
                              : 'orders_count_plural'.tr();

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
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
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryContainer,
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: customer.name.isEmpty
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  fontStyle: customer.name.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${customer.phone} • ${customer.orderCount} $orderWord'
                                '${customer.lastOrderAt != null ? ' • ${'last_order'.tr()} ${DateFormat('MMM d').format(customer.lastOrderAt!)}' : ''}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerOrdersScreen(
                                      phone: customer.phone,
                                      initialName: customer.name,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddCustomerDialog,
          child: const Icon(Icons.person_add),
        ),
      ),
    );
  }
}
