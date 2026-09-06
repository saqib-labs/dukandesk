class OrderItem {
  final String productName;
  final double quantity;
  final String unit;

  OrderItem({
    required this.productName,
    required this.quantity,
    required this.unit,
  });

  factory OrderItem.fromMap(Map<String, dynamic> data) {
    return OrderItem(
      productName: data['productName'] ?? '',
      quantity: (data['quantity'] ?? 0).toDouble(),
      unit: data['unit'] ?? 'pcs',
    );
  }
}

class ShopOrder {
  final String id;
  final String customerNumber;
  final String rawMessage;
  final List<OrderItem> matchedItems;
  final List<String> notFoundItems;
  final String status;
  final DateTime? createdAt;

  ShopOrder({
    required this.id,
    required this.customerNumber,
    required this.rawMessage,
    required this.matchedItems,
    required this.notFoundItems,
    required this.status,
    required this.createdAt,
  });

  factory ShopOrder.fromMap(String id, Map<String, dynamic> data) {
    final itemsList = (data['matchedItems'] as List<dynamic>?) ?? [];
    final notFoundList = (data['notFoundItems'] as List<dynamic>?) ?? [];

    return ShopOrder(
      id: id,
      customerNumber: data['customerNumber'] ?? '',
      rawMessage: data['rawMessage'] ?? '',
      matchedItems: itemsList
          .map((item) => OrderItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      notFoundItems: notFoundList.map((e) => e.toString()).toList(),
      status: data['status'] ?? 'unknown',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
    );
  }
}