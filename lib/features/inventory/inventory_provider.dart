import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/inventory.dart';

final ingredientsProvider = FutureProvider<List<Ingredient>>(
  (ref) => ref.watch(inventoryRepositoryProvider).ingredients(),
);

/// Jumlah bahan yang sudah menyentuh ambang. Dipakai badge di NavigationRail
/// supaya owner tahu tanpa membuka layarnya.
final lowStockCountProvider = Provider<int>((ref) {
  final items = ref.watch(ingredientsProvider).value ?? const <Ingredient>[];
  return items.where((e) => e.isLow).length;
});
