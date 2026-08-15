class Wallet {
  final double balance;
  final List<WalletTransaction> transactions;

  const Wallet({required this.balance, this.transactions = const []});

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final list = json['transactions'];
    return Wallet(
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      transactions: list is List
          ? list
              .whereType<Map<String, dynamic>>()
              .map((t) => WalletTransaction.fromJson(t))
              .toList()
          : const [],
    );
  }
}

class WalletTransaction {
  final int id;
  final double amount;
  final double balanceAfter;
  final String type;
  final String description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0,
      type: json['type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isCredit => amount > 0;
}
