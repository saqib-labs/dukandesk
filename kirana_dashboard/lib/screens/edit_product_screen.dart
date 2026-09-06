import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../models/product.dart';
import '../theme/app_colors.dart';

class EditProductScreen extends StatefulWidget {
  final Product product;
  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _costPriceController;
  late TextEditingController _priceController;
  late String _selectedUnit;
  static const List<String> unitOptions = [
    'pcs',
    'kg',
    'g',
    'ltr',
    'dozen',
    'pack',
    'box',
  ];
  late TextEditingController _stockController;
  late TextEditingController _thresholdController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _costPriceController = TextEditingController(
      text: widget.product.costPrice.toString(),
    );
    _priceController = TextEditingController(
      text: widget.product.price.toString(),
    );
    _selectedUnit = unitOptions.contains(widget.product.unit)
        ? widget.product.unit
        : 'pcs';
    _stockController = TextEditingController(
      text: widget.product.stockQty.toString(),
    );
    _thresholdController = TextEditingController(
      text: widget.product.lowStockThreshold.toString(),
    );
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final newPrice = double.parse(_priceController.text);
    final priceChanged = newPrice != widget.product.price;

    await FirebaseFirestore.instance
        .collection('products')
        .doc(widget.product.id)
        .update({
          'name': _nameController.text.trim(),
          'costPrice': double.parse(_costPriceController.text),
          'price': newPrice,
          'unit': _selectedUnit,
          'stockQty': int.parse(_stockController.text),
          'lowStockThreshold': int.parse(_thresholdController.text),
        });

    if (priceChanged) {
      await FirebaseFirestore.instance.collection('auditLog').add({
        'ownerId': FirebaseAuth.instance.currentUser!.uid,
        'action': 'price_change',
        'productName': widget.product.name,
        'oldValue': widget.product.price,
        'newValue': newPrice,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    setState(() => _isSaving = false);

    if (mounted) Navigator.pop(context);
  }

  Future<Map<String, String>?> _pickCustomer() async {
    final ownerId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('customerNames')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    final allCustomers = snapshot.docs
        .map(
          (doc) => {
            'phone': doc.id,
            'name': (doc.data()['name'] ?? '') as String,
          },
        )
        .toList();

    String search = '';

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = search.isEmpty
                ? allCustomers
                : allCustomers
                      .where(
                        (c) =>
                            c['name']!.toLowerCase().contains(
                              search.toLowerCase(),
                            ) ||
                            c['phone']!.contains(search),
                      )
                      .toList();

            return AlertDialog(
              title: const Text('Select Customer'),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search customers...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => search = value),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.storefront,
                              color: AppColors.textSecondary,
                            ),
                            title: const Text('Walk-in (no customer)'),
                            onTap: () => Navigator.pop(context, {
                              'phone': 'walk-in',
                              'name': '',
                            }),
                          ),
                          const Divider(),
                          ...filtered.map(
                            (c) => ListTile(
                              leading: const Icon(
                                Icons.person,
                                color: AppColors.primary,
                              ),
                              title: Text(
                                c['name']!.isNotEmpty
                                    ? c['name']!
                                    : c['phone']!,
                              ),
                              subtitle: Text(c['phone']!),
                              onTap: () => Navigator.pop(context, c),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showQuickSaleDialog() async {
    final customer = await _pickCustomer();
    if (customer == null) return;

    final quickQtyController = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log Sale — ${widget.product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer['name']!.isNotEmpty
                  ? 'Customer: ${customer['name']}'
                  : customer['phone'] == 'walk-in'
                  ? 'Customer: Walk-in'
                  : 'Customer: ${customer['phone']}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quickQtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantity sold (${widget.product.unit})',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = double.tryParse(quickQtyController.text);
              if (qty != null && qty > 0) {
                Navigator.pop(context, qty);
              }
            },
            child: const Text('Log Sale'),
          ),
        ],
      ),
    );

    if (result != null) {
      final currentStock = double.parse(_stockController.text);
      final newStock = currentStock - result;

      if (newStock < 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Insufficient Stock'),
            content: Text(
              'Only $currentStock ${widget.product.unit} in stock, but you\'re logging $result. '
              'Stock will go negative (${newStock.toStringAsFixed(0)}). Continue anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Log Anyway'),
              ),
            ],
          ),
        );

        if (proceed != true) return;
      }

      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.product.id)
          .update({'stockQty': newStock});

      try {
        await FirebaseFirestore.instance.collection('orders').add({
          'customerNumber': customer['phone'],
          'rawMessage': 'Manual entry',
          'ownerId': FirebaseAuth.instance.currentUser!.uid,
          'matchedItems': [
            {
              'productName': widget.product.name,
              'quantity': result,
              'unit': widget.product.unit,
            },
          ],
          'notFoundItems': [],
          'status': 'matched',
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged: $result ${widget.product.unit} sold'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Order log failed: $e')));
        }
      }

      if (mounted) {
        setState(() {
          _stockController.text = newStock.toString();
        });
      }
    }
  }

  Future<void> _showRestockDialog() async {
    final qtyController = TextEditingController();
    final costController = TextEditingController(
      text: _costPriceController.text,
    );
    final supplierController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restock — ${widget.product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantity added (${widget.product.unit})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cost price per unit (Rs.)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: supplierController,
              decoration: const InputDecoration(
                labelText: 'Supplier name (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Stock'),
          ),
        ],
      ),
    );

    if (result == true) {
      final qty = double.tryParse(qtyController.text.trim());
      final cost = double.tryParse(costController.text.trim());
      if (qty == null || qty <= 0) return;

      final currentStock = double.parse(_stockController.text);
      final newStock = currentStock + qty;

      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.product.id)
          .update({'stockQty': newStock, if (cost != null) 'costPrice': cost});

      await FirebaseFirestore.instance.collection('restockLogs').add({
        'ownerId': FirebaseAuth.instance.currentUser!.uid,
        'productId': widget.product.id,
        'productName': widget.product.name,
        'quantity': qty,
        'unit': widget.product.unit,
        'costPrice': cost ?? 0,
        'supplier': supplierController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _stockController.text = newStock.toString();
          if (cost != null) _costPriceController.text = cost.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $qty ${widget.product.unit} to stock')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('edit_product_title'.tr())),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'product_name'.tr(),
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'enter_name'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _costPriceController,
                  decoration: InputDecoration(
                    labelText: 'cost_price'.tr(),
                    prefixIcon: const Icon(Icons.shopping_bag_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'enter_cost'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'selling_price'.tr(),
                    prefixIcon: const Icon(Icons.sell_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) => value == null || value.isEmpty
                      ? 'enter_price'.tr()
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedUnit,
                  decoration: InputDecoration(
                    labelText: 'unit_hint'.tr(),
                    prefixIcon: const Icon(Icons.straighten),
                  ),
                  items: unitOptions
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedUnit = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stockController,
                  decoration: InputDecoration(
                    labelText: 'current_stock'.tr(),
                    prefixIcon: const Icon(Icons.warehouse_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) => value == null || value.isEmpty
                      ? 'enter_stock'.tr()
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _thresholdController,
                  decoration: InputDecoration(
                    labelText: 'low_stock_threshold'.tr(),
                    prefixIcon: const Icon(Icons.warning_amber_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _updateProduct,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('update_product'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _showQuickSaleDialog,
                  icon: const Icon(Icons.point_of_sale),
                  label: Text('log_sale'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _showRestockDialog,
                  icon: const Icon(Icons.add_box_outlined),
                  label: Text('restock'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
