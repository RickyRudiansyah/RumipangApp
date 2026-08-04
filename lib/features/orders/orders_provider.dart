import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../models/order.dart';
import 'pending_actions.dart';

/// Isi board + penanda apakah datanya masih segar.
class BoardData {
  const BoardData({
    required this.orders,
    required this.fromCache,
    this.updatedAt,
  });

  static const empty = BoardData(orders: [], fromCache: false);

  final List<OrderModel> orders;

  /// `true` = server tidak terjangkau, ini data terakhir dari cache lokal.
  /// UI wajib menampilkan banner "Offline - data mungkin usang" (SPEC §9).
  final bool fromCache;

  final DateTime? updatedAt;
}

/// Satu meja beserta order aktifnya.
class TableGroup {
  const TableGroup({required this.label, required this.tableId, required this.orders});

  final String label;
  final String? tableId;
  final List<OrderModel> orders;

  int get unpaidCount => orders.where((o) => !o.paymentStatus.isPaid).length;
  int get total => orders.fold(0, (sum, o) => sum + o.totalAmount);

  /// Tombol "Selesai" hanya boleh muncul kalau **semua** order di meja ini
  /// sudah `SERVED` **dan** `PAID` (API-CONTRACT §3).
  bool get canArchive => orders.isNotEmpty && orders.every((o) => o.isSettled);
}

/// Sumber tunggal untuk board kasir.
///
/// `GET /api/orders?mode=cashier` memuat seluruh order aktif yang belum
/// diarsipkan. Board dapur yang dulu diturunkan dari sini sudah dihapus -
/// order cukup masuk lalu dibayar, tanpa langkah proses manual.
class CashierBoardNotifier extends AsyncNotifier<BoardData> {
  static const _cacheKey = 'cashier';

  @override
  Future<BoardData> build() => _fetch();

  Future<BoardData> _fetch() async {
    final repo = ref.read(orderRepositoryProvider);
    final store = ref.read(localStoreProvider);

    try {
      final orders = await repo.cashierBoard();
      await store.cacheBoard(_cacheKey, orders.map((o) => o.toJson()).toList());
      return BoardData(orders: orders, fromCache: false, updatedAt: DateTime.now());
    } on NetworkFailure {
      final cached = store.readCachedBoard(_cacheKey);
      if (cached.isEmpty) rethrow;
      return BoardData(
        orders: cached.map(OrderModel.fromJson).toList(),
        fromCache: true,
        updatedAt: store.cachedBoardAt(_cacheKey),
      );
    }
  }

  /// Muat ulang tanpa mengedipkan spinner - dipakai realtime & polling.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  // ------------------------------------------------------------- aksi ------

  /// Verifikasi tunai. **Satu-satunya** cara melunasi order tunai, dan inilah
  /// yang memicu struk tercetak.
  ///
  /// Jangan pernah menandai lunas di UI sebelum ini mengembalikan sukses.
  Future<MarkPaidOutcome> markPaid(OrderModel order) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      final result = await repo.markPaid(order.id);
      await refresh();
      return result.printQueued
          ? MarkPaidOutcome.paidAndQueued
          : MarkPaidOutcome.paidButNotQueued;
    } on NetworkFailure {
      // Simpan ke antrian lokal, coba lagi otomatis. Order TETAP tampil
      // belum lunas sampai server mengonfirmasi.
      await ref.read(pendingActionsProvider.notifier).enqueueMarkPaid(order);
      return MarkPaidOutcome.queuedOffline;
    }
  }

  Future<void> cancel(OrderModel order, String reason) async {
    await ref.read(orderRepositoryProvider).cancel(order.id, reason);
    await refresh();
  }

  /// Arsipkan seluruh order di satu meja.
  Future<void> archiveGroup(TableGroup group) async {
    final repo = ref.read(orderRepositoryProvider);
    for (final order in group.orders) {
      await repo.archive(order.id);
    }
    await refresh();
  }
}

enum MarkPaidOutcome {
  /// Lunas dan struk sudah masuk antrian cetak.
  paidAndQueued,

  /// Lunas, tapi `print_queued: false` - tawarkan cetak ulang.
  paidButNotQueued,

  /// Jaringan mati. Order **belum** lunas; aksi menunggu di antrian lokal.
  queuedOffline,
}

final cashierBoardProvider =
    AsyncNotifierProvider<CashierBoardNotifier, BoardData>(CashierBoardNotifier.new);

/// Order dikelompokkan per meja, meja yang punya tagihan belum bayar didahulukan.
final tableGroupsProvider = Provider<List<TableGroup>>((ref) {
  final board = ref.watch(cashierBoardProvider).value ?? BoardData.empty;

  final buckets = <String, List<OrderModel>>{};
  for (final order in board.orders) {
    buckets.putIfAbsent(order.tableId ?? '_none', () => []).add(order);
  }

  final groups = buckets.entries.map((entry) {
    final orders = entry.value..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TableGroup(
      label: orders.first.tableLabel,
      tableId: entry.key == '_none' ? null : entry.key,
      orders: orders,
    );
  }).toList();

  groups.sort((a, b) {
    // Meja dengan tagihan belum bayar naik ke atas.
    if ((a.unpaidCount > 0) != (b.unpaidCount > 0)) return a.unpaidCount > 0 ? -1 : 1;
    return a.label.compareTo(b.label);
  });
  return groups;
});

/// Jumlah order yang belum dibayar - dipakai lencana di navigasi.
final unpaidCountProvider = Provider<int>((ref) {
  final board = ref.watch(cashierBoardProvider).value ?? BoardData.empty;
  return board.orders.where((o) => !o.paymentStatus.isPaid).length;
});
