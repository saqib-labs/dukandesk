import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'upgrade_screen.dart';
import 'barcode_scanner_screen.dart';
import '../theme/app_colors.dart';
import 'admin_approvals_screen.dart'; // for kAdminUid

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _priceController = TextEditingController();
  String _selectedUnit = 'pcs';
  static const List<String> unitOptions = [
    'pcs',
    'kg',
    'g',
    'ltr',
    'dozen',
    'pack',
    'box',
  ];
  final _stockController = TextEditingController();
  final _thresholdController = TextEditingController(text: '5');
  final _barcodeController = TextEditingController();

  bool _isSaving = false;

  static const int freeProductLimit = 10;

  // ---------------------------------------------------------
  // BARCODE SCANNER
  // ---------------------------------------------------------

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _barcodeController.text = result.trim();
      });
    }
  }

  // ---------------------------------------------------------
  // SHOW DUPLICATE MESSAGE
  // ---------------------------------------------------------

  Future<void> _showDuplicateDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // SAVE PRODUCT
  // ---------------------------------------------------------

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        setState(() {
          _isSaving = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Please login first.')));
        }

        return;
      }

      final ownerId = currentUser.uid;

      // -------------------------------------------------------
      // GET AND NORMALIZE INPUT VALUES
      // -------------------------------------------------------

      final productName = _nameController.text.trim();
      final productNameLower = productName.toLowerCase();

      final barcode = _barcodeController.text.trim();

      // -------------------------------------------------------
      // GET EXISTING PRODUCTS FOR THIS OWNER
      // -------------------------------------------------------

      final existingProducts = await FirebaseFirestore.instance
          .collection('products')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      // -------------------------------------------------------
      // CHECK DUPLICATES
      // -------------------------------------------------------

      for (final doc in existingProducts.docs) {
        final data = doc.data();

        final existingName = (data['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        final existingBarcode = (data['barcode'] ?? '').toString().trim();

        // -----------------------------------------------------
        // DUPLICATE PRODUCT NAME
        // -----------------------------------------------------

        if (existingName == productNameLower) {
          await _showDuplicateDialog(
            title: 'Duplicate Product',
            message: 'A product with the name "$productName" already exists.',
          );

          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }

          return;
        }

        // -----------------------------------------------------
        // DUPLICATE BARCODE
        // -----------------------------------------------------
        //
        // Barcode is optional.
        // If barcode is empty, we do not check for duplicates.
        //

        if (barcode.isNotEmpty && existingBarcode == barcode) {
          await _showDuplicateDialog(
            title: 'Duplicate Barcode',
            message:
                'The barcode "$barcode" is already assigned to another product.',
          );

          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }

          return;
        }
      }

      // -------------------------------------------------------
      // GET USER DATA
      // -------------------------------------------------------

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .get();

      final userData = userDoc.data();

      final isPremium =
          (userDoc.exists && userData?['isPremium'] == true) ||
          ownerId == kAdminUid;

      // -------------------------------------------------------
      // FREE PLAN PRODUCT LIMIT
      // -------------------------------------------------------

      if (!isPremium) {
        if (existingProducts.docs.length >= freeProductLimit) {
          if (mounted) {
            setState(() {
              _isSaving = false;
            });

            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('free_limit_title'.tr()),
                content: Text('free_limit_body'.tr()),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('not_now'.tr()),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UpgradeScreen(),
                        ),
                      );
                    },
                    child: Text('upgrade'.tr()),
                  ),
                ],
              ),
            );
          }

          return;
        }
      }

      // -------------------------------------------------------
      // PARSE NUMERIC VALUES
      // -------------------------------------------------------

      final costPrice = double.tryParse(_costPriceController.text.trim());

      final sellingPrice = double.tryParse(_priceController.text.trim());

      final stockQty = int.tryParse(_stockController.text.trim());

      final lowStockThreshold = int.tryParse(_thresholdController.text.trim());

      if (costPrice == null ||
          sellingPrice == null ||
          stockQty == null ||
          lowStockThreshold == null) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enter valid numbers in the price and stock fields.',
              ),
            ),
          );
        }

        return;
      }

      // -------------------------------------------------------
      // ADD PRODUCT TO FIRESTORE
      // -------------------------------------------------------

      await FirebaseFirestore.instance.collection('products').add({
        'name': productName,
        'costPrice': costPrice,
        'price': sellingPrice,
        'unit': _selectedUnit,
        'stockQty': stockQty,
        'lowStockThreshold': lowStockThreshold,
        'ownerId': ownerId,
        'barcode': barcode,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // -------------------------------------------------------
      // SUCCESS
      // -------------------------------------------------------

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product added successfully.')),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      // -------------------------------------------------------
      // ERROR HANDLING
      // -------------------------------------------------------

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save product: $e')));
      }
    }
  }

  // ---------------------------------------------------------
  // DISPOSE CONTROLLERS
  // ---------------------------------------------------------

  @override
  void dispose() {
    _nameController.dispose();
    _costPriceController.dispose();
    _priceController.dispose();

    _stockController.dispose();
    _thresholdController.dispose();
    _barcodeController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------
  // BUILD UI
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isRtl = context.locale.languageCode == 'ur';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('add_product_title'.tr())),

        body: Padding(
          padding: const EdgeInsets.all(16.0),

          child: Form(
            key: _formKey,

            child: ListView(
              children: [
                // -------------------------------------------------
                // PRODUCT NAME
                // -------------------------------------------------
                TextFormField(
                  controller: _nameController,

                  decoration: InputDecoration(
                    labelText: 'product_name'.tr(),
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'enter_name'.tr();
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------
                // BARCODE + SCANNER
                // -------------------------------------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _barcodeController,

                        decoration: const InputDecoration(
                          labelText: 'Barcode (optional)',
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    Container(
                      height: 56,
                      width: 56,

                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: IconButton(
                        onPressed: _isSaving ? null : _scanBarcode,

                        icon: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------
                // COST PRICE
                // -------------------------------------------------
                TextFormField(
                  controller: _costPriceController,

                  decoration: InputDecoration(
                    labelText: 'cost_price'.tr(),
                    prefixIcon: const Icon(Icons.shopping_bag_outlined),
                  ),

                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'enter_cost'.tr();
                    }

                    if (double.tryParse(value.trim()) == null) {
                      return 'Enter a valid cost price';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------
                // SELLING PRICE
                // -------------------------------------------------
                TextFormField(
                  controller: _priceController,

                  decoration: InputDecoration(
                    labelText: 'selling_price'.tr(),
                    prefixIcon: const Icon(Icons.sell_outlined),
                  ),

                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'enter_price'.tr();
                    }

                    if (double.tryParse(value.trim()) == null) {
                      return 'Enter a valid selling price';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------
                // UNIT
                // -------------------------------------------------
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

                // -------------------------------------------------
                // CURRENT STOCK
                // -------------------------------------------------
                TextFormField(
                  controller: _stockController,

                  decoration: InputDecoration(
                    labelText: 'current_stock'.tr(),
                    prefixIcon: const Icon(Icons.warehouse_outlined),
                  ),

                  keyboardType: TextInputType.number,

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'enter_stock'.tr();
                    }

                    if (int.tryParse(value.trim()) == null) {
                      return 'Enter a valid stock quantity';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------
                // LOW STOCK THRESHOLD
                // -------------------------------------------------
                TextFormField(
                  controller: _thresholdController,

                  decoration: InputDecoration(
                    labelText: 'low_stock_threshold'.tr(),
                    prefixIcon: const Icon(Icons.warning_amber_outlined),
                  ),

                  keyboardType: TextInputType.number,

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter low stock threshold';
                    }

                    if (int.tryParse(value.trim()) == null) {
                      return 'Enter a valid threshold';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // -------------------------------------------------
                // SAVE BUTTON
                // -------------------------------------------------
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveProduct,

                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text('save_product'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
