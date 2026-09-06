class CreditTransaction {
  final String id;
  final String phone;
  final double amount;
  final String type; // 'credit' (owed) or 'payment' (paid back)
  final String note;
  final DateTime? createdAt;

  CreditTransaction({
    required this.id,
    required this.phone,
    required this.amount,
    required this.type,
    required this.note,
    required this.createdAt,
  });

  factory CreditTransaction.fromMap(String id, Map<String, dynamic> data) {
    return CreditTransaction(
      id: id,
      phone: data['phone'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      type: data['type'] ?? 'credit',
      note: data['note'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
    );
  }
}
