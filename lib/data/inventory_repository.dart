import '../core/api_client.dart';
import '../models/inventory.dart';

class InventoryRepository {
  const InventoryRepository(this._api);

  final ApiClient _api;

  Future<List<Ingredient>> ingredients() async {
    final raw = await _api.get('/api/ingredients');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.isActive)
        .toList()
      // Yang menipis naik ke atas - itu yang perlu ditindak hari ini.
      ..sort((a, b) {
        if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<Ingredient> create({
    required String name,
    required String unit,
    required double stockQty,
    required double alertThreshold,
  }) async {
    final json = await _api.post('/api/ingredients', body: {
      'name': name,
      'unit': unit,
      'stock_qty': stockQty,
      'alert_threshold': alertThreshold,
    });
    return Ingredient.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<Ingredient> update(
    String id, {
    String? name,
    String? unit,
    double? alertThreshold,
    bool? isActive,
  }) async {
    final json = await _api.patch('/api/ingredients/$id', body: {
      if (name != null) 'name': name,
      if (unit != null) 'unit': unit,
      if (alertThreshold != null) 'alert_threshold': alertThreshold,
      if (isActive != null) 'is_active': isActive,
    });
    return Ingredient.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// Perubahan stok **selalu** lewat sini, tidak pernah dengan menimpa
  /// `stock_qty` langsung. Dua orang yang menyesuaikan stok bersamaan dengan
  /// PATCH akan saling menghapus; dengan `delta` keduanya terakumulasi benar
  /// (BACKEND-ADDITIONS.md §4).
  Future<Ingredient> adjust(
    String id, {
    required double delta,
    required StockReason reason,
    String? note,
  }) async {
    final json = await _api.post('/api/ingredients/$id/movements', body: {
      'delta': delta,
      'reason': reason.wire,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return Ingredient.fromJson(Map<String, dynamic>.from(json as Map));
  }
}
