import '../core/api_client.dart';
import '../models/catalog.dart';

/// Perubahan katalog menu: tambah menu, ubah harga, ubah HPP.
///
/// Dipisahkan dari [CatalogRepository] yang hanya membaca - yang ini menulis,
/// dan penulisannya butuh endpoint yang belum ada di backend
/// (BACKEND-ADDITIONS.md §2).
class MenuAdminRepository {
  const MenuAdminRepository(this._api);

  final ApiClient _api;

  Future<MenuItemModel> create({
    required String name,
    required int price,
    required int costPrice,
    String? categoryId,
    String? description,
  }) async {
    final json = await _api.post('/api/menu', body: {
      'name': name,
      'price': price,
      'cost_price': costPrice,
      if (categoryId != null) 'category_id': categoryId,
      if (description != null && description.isNotEmpty) 'description': description,
      'is_available': true,
    });
    return MenuItemModel.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// Partial update - kirim hanya field yang berubah supaya dua owner yang
  /// menyunting menu berbeda tidak saling menimpa field lain.
  Future<MenuItemModel> update(
    String id, {
    String? name,
    int? price,
    int? costPrice,
    bool? isAvailable,
    bool? isSoldOut,
    String? description,
  }) async {
    final json = await _api.patch('/api/menu/$id', body: {
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (costPrice != null) 'cost_price': costPrice,
      if (isAvailable != null) 'is_available': isAvailable,
      if (isSoldOut != null) 'is_sold_out': isSoldOut,
      if (description != null) 'description': description,
    });
    return MenuItemModel.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// Server disarankan melakukan soft delete supaya `order_items` lama tidak
  /// kehilangan referensi menu.
  Future<void> remove(String id) => _api.delete('/api/menu/$id');
}
