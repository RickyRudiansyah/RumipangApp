import '../core/api_client.dart';
import '../models/catalog.dart';

/// Perubahan katalog menu: tambah menu, ubah harga, ubah HPP.
///
/// Dipisahkan dari [CatalogRepository] yang hanya membaca.
///
/// **Endpoint di sini sudah ada di web** (`POST /api/menu`,
/// `PUT/DELETE /api/menu/[id]`, `PATCH /api/menu/[id]/sold-out`). Yang belum
/// ada hanya kolom `cost_price` pada payload dan responsnya
/// (BACKEND-ADDITIONS.md §2). Verb-nya sengaja mengikuti web - PUT untuk
/// update menu, bukan PATCH seperti endpoint order.
class MenuAdminRepository {
  const MenuAdminRepository(this._api);

  final ApiClient _api;

  Future<MenuItemModel> create({
    required String name,
    required int price,
    required int costPrice,
    String? categoryId,
    String? description,
    String? imageUrl,
  }) async {
    final json = await _api.post('/api/menu', body: {
      'name': name,
      'price': price,
      'cost_price': costPrice,
      if (categoryId != null) 'category_id': categoryId,
      if (description != null && description.isNotEmpty) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      'is_available': true,
    });
    return MenuItemModel.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// `PUT` = **ganti seluruh baris**, jadi setiap field yang boleh disunting
  /// harus ikut dikirim — termasuk yang tidak diubah.
  ///
  /// Menghilangkan `image_url` atau `category_id` di sini berarti server
  /// menimpanya dengan `null`: foto menu hilang hanya karena harganya diubah.
  /// Itu sebabnya parameternya wajib, bukan opsional — pemanggil dipaksa
  /// mengambilnya dari objek menu yang sedang disunting.
  ///
  /// `is_sold_out` **tidak** ikut; web punya endpoint sendiri ([toggleSoldOut]).
  Future<MenuItemModel> update(
    String id, {
    required String name,
    required int price,
    required int costPrice,
    required bool isAvailable,
    required String? categoryId,
    required String? description,
    required String? imageUrl,
  }) async {
    final json = await _api.put('/api/menu/$id', body: {
      'name': name,
      'price': price,
      'cost_price': costPrice,
      'is_available': isAvailable,
      'category_id': categoryId,
      'description': description ?? '',
      'image_url': imageUrl,
    });
    return MenuItemModel.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// Unggah foto menu ke `POST /api/upload` (endpoint web yang sudah ada,
  /// batas 5 MB) lalu kembalikan URL publiknya.
  ///
  /// URL-nya belum tersimpan di menu mana pun — pemanggil harus meneruskannya
  /// ke [create] atau [update].
  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) =>
      _api.uploadFile(
        path: '/api/upload',
        bytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      );

  /// Endpoint terpisah milik web. Dipisah karena "habis hari ini" adalah aksi
  /// harian kasir, bukan penyuntingan katalog oleh owner.
  Future<void> toggleSoldOut(String id, bool soldOut) =>
      _api.patch('/api/menu/$id/sold-out', body: {'is_sold_out': soldOut});

  /// Web menghapus baris sungguhan. `order_items` aman karena sudah menyimpan
  /// `menu_item_name` dan `menu_item_price` sebagai snapshot.
  Future<void> remove(String id) => _api.delete('/api/menu/$id');

  // ------------------------------------------------ topping & variasi ----

  /// Endpoint variasi **sudah ada semua di web** — tidak ada pekerjaan backend
  /// untuk fitur ini.
  ///
  /// `variationType` adalah nama grupnya ("Extra Topping", "Ukuran"), `label`
  /// nama opsinya ("Keju"), dan `extraPrice` tambahan harganya.
  Future<MenuVariation> createVariation({
    required String menuItemId,
    required String variationType,
    required String label,
    required int extraPrice,
  }) async {
    final json = await _api.post('/api/menu/variations', body: {
      'menu_item_id': menuItemId,
      'variation_type': variationType,
      'label': label,
      'extra_price': extraPrice,
    });
    return MenuVariation.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<MenuVariation> updateVariation(
    String id, {
    required String menuItemId,
    required String variationType,
    required String label,
    required int extraPrice,
  }) async {
    final json = await _api.put('/api/menu/variations/$id', body: {
      'menu_item_id': menuItemId,
      'variation_type': variationType,
      'label': label,
      'extra_price': extraPrice,
    });
    return MenuVariation.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<void> deleteVariation(String id) =>
      _api.delete('/api/menu/variations/$id');

  // ---------------------------------------------------------- kategori ----

  /// Tambah kategori baru (Minuman, Nasi, ...).
  ///
  /// `GET /api/menu/categories` sudah ada di web, tapi **POST-nya belum** —
  /// lihat BACKEND-ADDITIONS.md §2b.
  ///
  /// `sortOrder` menentukan urutan tampil di layar kasir maupun di web.
  Future<MenuCategory> createCategory({
    required String name,
    required int sortOrder,
  }) async {
    final json = await _api.post('/api/menu/categories', body: {
      'name': name,
      'sort_order': sortOrder,
    });
    return MenuCategory.fromJson(Map<String, dynamic>.from(json as Map));
  }
}
