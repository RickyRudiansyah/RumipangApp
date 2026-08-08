import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/enums.dart';
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

/// Rentang waktu riwayat yang sedang dilihat.
enum HistoryRange {
  today('Hari Ini', 1),
  week('7 Hari', 7),
  month('30 Hari', 30),
  all('Semua', null);

  const HistoryRange(this.label, this.days);

  final String label;

  /// `null` = tanpa batas.
  final int? days;

  /// Batas bawah, dihitung dari **tengah malam waktu tablet** - bukan
  /// "24 jam terakhir". Warung berpikir dalam hari kalender: omzet "hari ini"
  /// harus berhenti di tengah malam, bukan menggeser terus setiap jam.
  DateTime? get since {
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: days! - 1));
  }
}

class HistoryRangeNotifier extends Notifier<HistoryRange> {
  @override
  HistoryRange build() => HistoryRange.today;

  void select(HistoryRange range) => state = range;
}

final historyRangeProvider =
    NotifierProvider<HistoryRangeNotifier, HistoryRange>(HistoryRangeNotifier.new);

final filteredHistoryProvider = Provider<List<OrderModel>>((ref) {
  final all = ref.watch(historyProvider).value ?? const <OrderModel>[];
  final query = ref.watch(historyQueryProvider).trim().toLowerCase();
  final since = ref.watch(historyRangeProvider).since;

  return all.where((o) {
    if (since != null && o.createdAt.isBefore(since)) return false;
    if (query.isEmpty) return true;
    return o.orderNo.toLowerCase().contains(query) ||
        o.tableLabel.toLowerCase().contains(query) ||
        o.items.any((i) => i.menuItemName.toLowerCase().contains(query));
  }).toList();
});

/// Ringkasan uang untuk rentang yang sedang dilihat.
class HistorySummary {
  const HistorySummary({
    required this.orders,
    required this.omzet,
    required this.cancelled,
  });

  final int orders;

  /// **Hanya order lunas & tidak dibatalkan.** Menjumlahkan semua baris riwayat
  /// akan memasukkan order batal dan order tunai yang tidak jadi dibayar ke
  /// dalam omzet - angka yang lebih besar dari uang yang benar-benar diterima.
  final int omzet;

  final int cancelled;
}

final historySummaryProvider = Provider<HistorySummary>((ref) {
  final orders = ref.watch(filteredHistoryProvider);
  var omzet = 0;
  var cancelled = 0;
  for (final o in orders) {
    if (o.status == OrderStatus.cancelled) {
      cancelled++;
      continue;
    }
    if (o.paymentStatus.isPaid) omzet += o.totalAmount;
  }
  return HistorySummary(
    orders: orders.length,
    omzet: omzet,
    cancelled: cancelled,
  );
});
