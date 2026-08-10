import 'json.dart';

/// Satu pengeluaran warung: belanja bahan, galon, gas, parkir, dan sejenisnya.
///
/// Dipakai rekap harian untuk menghitung uang **bersih** — omzet saja
/// melaporkan uang yang masuk, bukan yang benar-benar tersisa.
class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.note,
    required this.spentAt,
    this.category,
    this.createdBy,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: asString(json['id']),
        amount: asInt(json['amount']),
        note: asString(json['note']),
        spentAt: asDateOr(json['spent_at'], DateTime.now()),
        category: asStringOrNull(json['category']),
        createdBy: asStringOrNull(json['created_by']),
      );

  final String id;
  final int amount;
  final String note;

  /// Kapan uangnya keluar — bukan kapan barisnya dibuat. Kasir bisa mencatat
  /// mundur kalau lupa, dan rekap harus mengikuti tanggal belanjanya.
  final DateTime spentAt;

  final String? category;
  final String? createdBy;
}
