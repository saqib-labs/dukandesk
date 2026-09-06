import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../models/product.dart';
import '../theme/app_colors.dart';
import '../theme/app_background.dart';
import 'add_product_screen.dart';
import 'edit_product_screen.dart';
import 'order_history_screen.dart';
import 'sales_summary_screen.dart';
import 'upgrade_screen.dart';
import 'admin_approvals_screen.dart';
import 'customers_screen.dart';
import 'bulk_import_screen.dart';
import 'low_stock_screen.dart';
import 'restock_history_screen.dart';
import 'expenses_screen.dart';
import 'broadcast_screen.dart';
import 'profile_screen.dart';
import 'data_backup_screen.dart';
import 'audit_log_screen.dart';
import 'shop_connection_screen.dart';
import 'login_screen.dart';
import 'inventory_valuation_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void dispose() {
    _searchController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Scan Product Barcode'),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 320,
            height: 320,
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                if (capture.barcodes.isEmpty) return;

                final code = capture.barcodes.first.rawValue;
                if (code == null || code.trim().isEmpty) return;

                _searchController.text = code.trim();
                setState(() => _searchQuery = code.trim().toLowerCase());
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('ownerId', isEqualTo: ownerId)
                .snapshots(),
            builder: (context, productSnapshot) {
              final count = productSnapshot.data?.docs.length ?? 0;

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(ownerId)
                    .snapshots(),
                builder: (context, userSnapshot) {
                  final userData =
                      userSnapshot.data?.data() as Map<String, dynamic>?;
                  final isPremium =
                      (userData?['isPremium'] == true) || ownerId == kAdminUid;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('My Products'),
                      Text(
                        isPremium
                            ? 'Premium — Unlimited'
                            : '$count / 10 products (Free Plan)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          actions: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .snapshots(),
              builder: (context, userSnapshot) {
                final userData =
                    userSnapshot.data?.data() as Map<String, dynamic>?;
                final isPremium = (userData?['isPremium'] == true);
                final isAdmin = ownerId == kAdminUid;

                if (isAdmin) {
                  return IconButton(
                    icon: const Icon(Icons.verified_user, color: Colors.amber),
                    tooltip: 'Manage Requests',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminApprovalsScreen(),
                        ),
                      );
                    },
                  );
                }

                if (isPremium) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.star, color: Colors.amber),
                  );
                }

                return IconButton(
                  icon: const Icon(Icons.star, color: Colors.amber),
                  tooltip: 'Upgrade to Premium',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UpgradeScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'logout'.tr(),
              onPressed: _handleLogout,
            ),
          ],
        ),
        drawer: _buildMenuDrawer(context, ownerId),
        body: AppBackground(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'search_products'.tr(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Scan barcode',
                          onPressed: _scanBarcode,
                        ),
                      ],
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
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

                    var docs = snapshot.data!.docs;

                    if (_searchQuery.isNotEmpty) {
                      docs = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name =
                            data['name']?.toString().toLowerCase() ?? '';
                        final barcode =
                            data['barcode']?.toString().toLowerCase() ?? '';
                        return name.contains(_searchQuery) ||
                            barcode.contains(_searchQuery);
                      }).toList();
                    }

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? '${'no_products_match'.tr()} "${_searchController.text}"'
                              : 'no_products'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final product = Product.fromMap(
                          docs[index].id,
                          docs[index].data() as Map<String, dynamic>,
                        );
                        final isLowStock =
                            product.stockQty <= product.lowStockThreshold;

                        return Dismissible(
                          key: Key(product.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('delete_product'.tr()),
                                content: Text(
                                  '${'delete'.tr()} "${product.name}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text('cancel'.tr()),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(
                                      'confirm_delete'.tr(),
                                      style: TextStyle(color: AppColors.error),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (direction) {
                            FirebaseFirestore.instance
                                .collection('auditLog')
                                .add({
                                  'ownerId': ownerId,
                                  'action': 'product_deleted',
                                  'productName': product.name,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                            FirebaseFirestore.instance
                                .collection('products')
                                .doc(product.id)
                                .delete();
                          },
                          child: Container(
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
                              title: Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '${product.stockQty} ${product.unit} ${'in_stock'.tr()}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              trailing: Text(
                                'Rs. ${product.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isLowStock
                                    ? AppColors.error.withOpacity(0.1)
                                    : AppColors.primaryContainer,
                                child: Icon(
                                  isLowStock
                                      ? Icons.warning_amber_rounded
                                      : Icons.inventory_2_outlined,
                                  color: isLowStock
                                      ? AppColors.error
                                      : AppColors.primary,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EditProductScreen(product: product),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddProductScreen()),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildMenuDrawer(BuildContext context, String ownerId) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final photoBase64 = data?['photoBase64'] as String?;
                final shopName = data?['shopName'] as String?;

                return InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    color: AppColors.primary,
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white24,
                          backgroundImage: photoBase64 != null
                              ? MemoryImage(base64Decode(photoBase64))
                              : null,
                          child: photoBase64 == null
                              ? const Icon(
                                  Icons.storefront,
                                  color: Colors.white,
                                  size: 26,
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          shopName?.isNotEmpty == true
                              ? shopName!
                              : 'DukanDesk',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'view_profile'.tr(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            _drawerItem(
              context,
              icon: Icons.link,
              label: 'connect_whatsapp_menu'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShopConnectionScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.people_outline,
              label: 'customers'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomersScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.bar_chart,
              label: 'sales_summary'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SalesSummaryScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.receipt_long,
              label: 'order_history'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OrderHistoryScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.inventory_outlined,
              label: 'low_stock'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LowStockScreen()),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.assessment_outlined,
              label: 'inventory_valuation_title'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InventoryValuationScreen(),
                ),
              ),
            ),

            _drawerItem(
              context,
              icon: Icons.local_shipping_outlined,
              label: 'restock_history'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RestockHistoryScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.money_off,
              label: 'expenses'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ExpensesScreen()),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.campaign_outlined,
              label: 'broadcast_message'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BroadcastScreen(),
                ),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.history,
              label: 'audit_log_menu'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AuditLogScreen()),
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.backup_outlined,
              label: 'data_backup_menu'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DataBackupScreen(),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.language, color: AppColors.primary),
              title: Text(
                'language'.tr(),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              trailing: DropdownButton<Locale>(
                value: context.locale,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: Locale('en'), child: Text('English')),
                  DropdownMenuItem(value: Locale('ur'), child: Text('اردو')),
                ],
                onChanged: (locale) {
                  if (locale != null) context.setLocale(locale);
                },
              ),
            ),
            const Divider(),
            _drawerItem(
              context,
              icon: Icons.upload_file,
              label: 'bulk_import'.tr(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BulkImportScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.primary),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      onLongPress: onLongPress == null
          ? null
          : () {
              Navigator.pop(context);
              onLongPress();
            },
    );
  }
}
