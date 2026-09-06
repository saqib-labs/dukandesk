class Product {
  final String id;
  final String name;
  final double price;
  final double costPrice;
  final String unit;
  final int stockQty;
  final int lowStockThreshold;
  final String ownerId;
  final String barcode;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.costPrice,
    required this.unit,
    required this.stockQty,
    required this.lowStockThreshold,
    required this.ownerId,
    this.barcode = '',
  });

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      name: data['name'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      costPrice: (data['costPrice'] ?? 0).toDouble(),
      unit: data['unit'] ?? 'pcs',
      stockQty: (data['stockQty'] ?? 0).toInt(),
      lowStockThreshold: (data['lowStockThreshold'] ?? 5).toInt(),
      ownerId: data['ownerId'] ?? '',
      barcode: data['barcode'] ?? '',
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'costPrice': costPrice,
      'unit': unit,
      'stockQty': stockQty,
      'lowStockThreshold': lowStockThreshold,
      'ownerId': ownerId,
    };
  }
}
