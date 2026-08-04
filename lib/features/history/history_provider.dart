import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/order.dart';

/// Riwayat: order yang sudah diarsipkan **atau** dibatalkan.
///
/// Sengaja tidak ikut disegarkan realtime - daftarnya panjang dan jarang
/// berubah saat kasir sedang melihatnya. Muat ulang manual saja (SPEC §2:
/// batasi riwayat yang dimuat sekaligus).
class HistoryNotifier extends AsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() =>
      ref.read(orderRepositoryProvider).history();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(orderRepositoryProvider).history(),
    );
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<OrderModel>>(HistoryNotifier.new);

/// Kata kunci pencarian riwayat (nomor order / nama meja / nama menu).
class HistoryQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final historyQueryProvider =
    NotifierProvider<HistoryQueryNotifier, String>(HistoryQueryNotifier.new);

final filteredHistoryProvider = Provider<List<OrderModel>>((ref) {
  final all = ref.watch(historyProvider).value ?? const <OrderModel>[];
  final query = ref.watch(historyQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return all;
  return all.where((o) {
    return o.orderNo.toLowerCase().contains(query) ||
        o.tableLabel.toLowerCase().contains(query) ||
        o.items.any((i) => i.menuItemName.toLowerCase().contains(query));
  }).toList();
});
