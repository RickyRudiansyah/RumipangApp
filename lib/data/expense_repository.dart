import '../core/api_client.dart';
import '../models/expense.dart';
import '../models/json.dart';

class ExpenseRepository {
  const ExpenseRepository(this._api);

  final ApiClient _api;

  static List<Expense> _parse(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Pengeluaran dalam satu rentang. Batas harinya ditentukan **di sini**,
  /// dari jam tablet — sama dengan omzet, supaya keduanya selalu bicara tentang
  /// hari yang sama. Tengah malam UTC jatuh pukul 07.00 pagi WIB, tepat di
  /// tengah hari kerja.
  Future<List<Expense>> list({DateTime? from, DateTime? to}) async =>
      _parse(await _api.get('/api/expenses', query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      }));

  Future<Expense> create({
    required int amount,
    required String note,
    DateTime? spentAt,
  }) async {
    final res = await _api.post('/api/expenses', body: {
      'amount': amount,
      'note': note,
      if (spentAt != null) 'spent_at': spentAt.toUtc().toIso8601String(),
    });
    return Expense.fromJson(asMap(res));
  }

  Future<void> remove(String id) => _api.delete('/api/expenses/$id');
}
