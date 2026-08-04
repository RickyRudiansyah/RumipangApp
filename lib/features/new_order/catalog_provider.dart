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

/// Menu yang boleh dipesan, dikelompokkan per kategori dan diurutkan
/// mengikuti `sort_order` kategori.
final menuByCategoryProvider = Provider<List<MapEntry<String, List<MenuItemModel>>>>((ref) {
  final items = ref.watch(menuProvider).value ?? const <MenuItemModel>[];

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
