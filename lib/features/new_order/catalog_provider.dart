import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/catalog.dart';
import '../../models/order.dart';

final tablesProvider = FutureProvider<List<CafeTable>>(
  (ref) => ref.watch(catalogRepositoryProvider).tables(),
);

final menuProvider = FutureProvider<List<MenuItemModel>>(
  (ref) => ref.watch(catalogRepositoryProvider).menu(),
);

final menuVariationsProvider = FutureProvider<List<MenuVariation>>(
  (ref) => ref.watch(catalogRepositoryProvider).variations(),
);

final menuCategoriesProvider = FutureProvider<List<MenuCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

/// Variasi dikelompokkan per menu, lalu per jenis variasi
/// ("Ukuran" -> [Regular, Large], "Level Gula" -> [...]).
final variationsByMenuProvider =
    Provider<Map<String, Map<String, List<MenuVariation>>>>((ref) {
  final all = ref.watch(menuVariationsProvider).value ?? const <MenuVariation>[];
  final result = <String, Map<String, List<MenuVariation>>>{};
  for (final v in all) {
    result
        .putIfAbsent(v.menuItemId, () => {})
        .putIfAbsent(v.variationType, () => [])
        .add(v);
  }
  return result;
});

// ------------------------------------------------------- filter layar POS ---

/// Kata kunci pencarian menu di layar Order.
class PosQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final posQueryProvider = NotifierProvider<PosQueryNotifier, String>(PosQueryNotifier.new);

/// Kategori yang sedang disaring di layar Order. `null` = semua kategori.
class PosCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryName) => state = categoryName;
}

final posCategoryProvider =
    NotifierProvider<PosCategoryNotifier, String?>(PosCategoryNotifier.new);

/// Nama kategori yang benar-benar punya menu - dipakai deretan filter.
final posCategoryNamesProvider = Provider<List<String>>((ref) {
  final items = ref.watch(menuProvider).value ?? const <MenuItemModel>[];

  final sortOrder = <String, int>{};
  for (final item in items) {
    sortOrder[item.categoryName] = item.categorySort;
  }

  return sortOrder.keys.toList()
    ..sort((a, b) {
      final byOrder = (sortOrder[a] ?? 999).compareTo(sortOrder[b] ?? 999);
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });
});

/// Muat ulang seluruh katalog dari server.
///
/// Menu, variasi, kategori, dan meja diambil ulang bersamaan: menu baru yang
/// ditambahkan dari tab Menu (atau dari web) tidak akan muncul di POS sampai
/// ini dipanggil, karena `FutureProvider` menyimpan hasil pertamanya.
void refreshCatalog(WidgetRef ref) {
  ref.invalidate(menuProvider);
  ref.invalidate(menuVariationsProvider);
  ref.invalidate(menuCategoriesProvider);
  ref.invalidate(tablesProvider);
}

/// Menu yang boleh dipesan, dikelompokkan per kategori dan diurutkan
/// mengikuti `sort_order` kategori, setelah disaring kata kunci + kategori.
final menuByCategoryProvider = Provider<List<MapEntry<String, List<MenuItemModel>>>>((ref) {
  final all = ref.watch(menuProvider).value ?? const <MenuItemModel>[];
  final query = ref.watch(posQueryProvider).trim().toLowerCase();
  final category = ref.watch(posCategoryProvider);

  final items = all.where((item) {
    if (category != null && item.categoryName != category) return false;
    if (query.isEmpty) return true;
    return item.name.toLowerCase().contains(query) ||
        (item.description ?? '').toLowerCase().contains(query);
  });

  final buckets = <String, List<MenuItemModel>>{};
  final sortOrder = <String, int>{};
  for (final item in items) {
    buckets.putIfAbsent(item.categoryName, () => []).add(item);
    sortOrder[item.categoryName] = item.categorySort;
  }

  final entries = buckets.entries.toList()
    ..sort((a, b) {
      final byOrder = (sortOrder[a.key] ?? 999).compareTo(sortOrder[b.key] ?? 999);
      return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
    });

  for (final entry in entries) {
    entry.value.sort((a, b) => a.name.compareTo(b.name));
  }
  return entries;
});
