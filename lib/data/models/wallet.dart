/// The viewer's coin wallet: current balance plus recent transaction history.
class Wallet {
  /// Current balance, in coins (decimal; negative balances are not expected).
  final double balance;
  /// Recent transactions, newest first as returned by the server; empty when
  /// the payload omits them.
  final List<WalletTransaction> transactions;

  /// Creates a wallet; see [fromJson] for payload defaults.
  const Wallet({required this.balance, this.transactions = const []});

  /// Deserializes from the server's wallet payload, tolerating a missing
  /// transaction list.
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

/// One wallet ledger entry: money in (credit) or money out (debit), with the
/// balance snapshot right after it happened.
class WalletTransaction {
  /// Server-assigned transaction id; 0 when the payload omits it.
  final int id;
  /// Amount moved, in coins; positive for credits (see [isCredit]), negative
  /// for debits.
  final double amount;
  /// Balance immediately after the transaction, in coins.
  final double balanceAfter;
  /// Machine-readable reason for the movement (server-defined).
  final String type;
  /// Human-readable description of the transaction.
  final String description;
  /// When the transaction happened (localized timestamp).
  final DateTime createdAt;

  /// Creates a transaction; see [fromJson] for payload defaults.
  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  /// Deserializes from the server's transaction payload; unparseable dates
  /// fall back to the Unix epoch.
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

  /// True when this transaction added coins ([amount] > 0).
  bool get isCredit => amount > 0;
}
