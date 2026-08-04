import 'json.dart';

class MenuCategory {
  const MenuCategory({required this.id, required this.name, required this.sortOrder});

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        id: asString(json['id']),
        name: asString(json['name'], 'Lainnya'),
        sortOrder: asInt(json['sort_order'], 999),
      );

  final String id;
  final String name;
  final int sortOrder;
}

class MenuItemModel {
  const MenuItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.costPrice,
    required this.isAvailable,
    required this.isSoldOut,
    this.categoryId,
    this.category,
    this.description,
    this.imageUrl,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) => MenuItemModel(
        id: asString(json['id']),
        name: asString(json['name'], 'Menu'),
        price: asInt(json['price']),
        costPrice: asInt(json['cost_price']),
        isAvailable: asBool(json['is_available'], true),
        isSoldOut: asBool(json['is_sold_out']),
        categoryId: asStringOrNull(json['category_id']),
        category:
            json['category'] is Map ? MenuCategory.fromJson(asMap(json['category'])) : null,
        description: asStringOrNull(json['description']),
        imageUrl: asStringOrNull(json['image_url']),
      );

  final String id;
  final String name;
  final int price;

  /// HPP per porsi, diisi manual owner. 0 berarti **belum diisi**, bukan
  /// "modalnya gratis" - margin sengaja tidak ditampilkan untuk kasus ini.
  final int costPrice;

  final bool isAvailable;
  final bool isSoldOut;
  final String? categoryId;
  final MenuCategory? category;
  final String? description;
  final String? imageUrl;

  /// Boleh dimasukkan keranjang order manual.
  bool get isOrderable => isAvailable && !isSoldOut;

  String get categoryName => category?.name ?? 'Lainnya';
  int get categorySort => category?.sortOrder ?? 999;

  // ------------------------------------------------------------------ HPP ---

  bool get hasCost => costPrice > 0;

  /// Laba kotor per porsi.
  int get margin => price - costPrice;

  /// Persentase margin terhadap harga jual. `null` kalau HPP belum diisi -
  /// menampilkan "100%" untuk menu tanpa HPP itu menyesatkan.
  double? get marginPercent {
    if (!hasCost || price <= 0) return null;
    return margin / price * 100;
  }

  /// Jual di bawah modal. Ditandai merah, tapi tidak diblokir - bisa saja
  /// memang disengaja untuk menu promo.
  bool get isLossMaking => hasCost && margin < 0;
}

class MenuVariation {
  const MenuVariation({
    required this.id,
    required this.menuItemId,
    required this.variationType,
    required this.label,
    required this.extraPrice,
  });

  factory MenuVariation.fromJson(Map<String, dynamic> json) => MenuVariation(
        id: asString(json['id']),
        menuItemId: asString(json['menu_item_id']),
        variationType: asString(json['variation_type']),
        label: asString(json['label']),
        extraPrice: asInt(json['extra_price']),
      );

  final String id;
  final String menuItemId;
  final String variationType;
  final String label;
  final int extraPrice;
}
