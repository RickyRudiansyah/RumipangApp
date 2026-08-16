import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/enums.dart';
import '../../models/expense.dart';
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

/// Satu tanggal tertentu. Kalau diisi, ia **menimpa** [historyRangeProvider].
///
/// Warung tutup tengah malam, jadi begitu lewat pukul 00.00 rentang "Hari Ini"
/// langsung kosong dan omzet semalam terlempar ke kemarin - yang tanpa ini
/// tidak bisa dilihat sama sekali.
class HistoryDayNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  /// Selalu disimpan sebagai tengah malam, supaya perbandingannya bersih.
  void select(DateTime? day) => state =
      day == null ? null : DateTime(day.year, day.month, day.day);
}

final historyDayProvider =
    NotifierProvider<HistoryDayNotifier, DateTime?>(HistoryDayNotifier.new);

/// Saring rekap per metode bayar. `null` = semua.
///
/// Uang tunai ada di laci, uang QRIS ada di rekening - saat mencocokkan kas
/// akhir hari, keduanya dihitung terpisah dan angka gabungan justru menyesatkan.
class HistoryMethodNotifier extends Notifier<PaymentMethod?> {
  @override
  PaymentMethod? build() => null;

  void select(PaymentMethod? method) => state = method;
}

final historyMethodProvider =
    NotifierProvider<HistoryMethodNotifier, PaymentMethod?>(HistoryMethodNotifier.new);

final filteredHistoryProvider = Provider<List<OrderModel>>((ref) {
  final all = ref.watch(historyProvider).value ?? const <OrderModel>[];
  final query = ref.watch(historyQueryProvider).trim().toLowerCase();
  final day = ref.watch(historyDayProvider);
  final since = day ?? ref.watch(historyRangeProvider).since;
  // Tanggal tertentu punya batas atas; rentang "N hari terakhir" tidak.
  final until = day?.add(const Duration(days: 1));

  final method = ref.watch(historyMethodProvider);

  return all.where((o) {
    if (since != null && o.createdAt.isBefore(since)) return false;
    if (until != null && !o.createdAt.isBefore(until)) return false;
    if (method != null && o.paymentMethod != method) return false;
    if (query.isEmpty) return true;
    return o.orderNo.toLowerCase().contains(query) ||
        o.tableLabel.toLowerCase().contains(query) ||
        o.items.any((i) => i.menuItemName.toLowerCase().contains(query));
  }).toList();
});

/// Rentang tanggal yang sedang dilihat: `(dari, sampai)`, `sampai` eksklusif.
///
/// Satu sumber untuk omzet **dan** pengeluaran. Kalau keduanya menghitung
/// rentangnya sendiri-sendiri, cepat atau lambat salah satu bergeser dan angka
/// "bersih" jadi mengurangkan pengeluaran hari lain.
final historyRangeBoundsProvider = Provider<(DateTime?, DateTime?)>((ref) {
  final day = ref.watch(historyDayProvider);
  if (day != null) return (day, day.add(const Duration(days: 1)));
  return (ref.watch(historyRangeProvider).since, null);
});

/// Pengeluaran untuk rentang yang sedang dilihat.
class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() {
    final (from, to) = ref.watch(historyRangeBoundsProvider);
    return ref.read(expenseRepositoryProvider).list(from: from, to: to);
  }

  Future<void> refresh() async {
    final (from, to) = ref.read(historyRangeBoundsProvider);
    state = await AsyncValue.guard(
      () => ref.read(expenseRepositoryProvider).list(from: from, to: to),
    );
  }

  Future<void> add({required int amount, required String note}) async {
    // Dicatat pada tanggal yang sedang dilihat, bukan selalu hari ini - kalau
    // Vona sedang membuka tanggal kemarin untuk merekap, pengeluaran yang ia
    // masukkan jelas milik kemarin.
    final day = ref.read(historyDayProvider);
    await ref.read(expenseRepositoryProvider).create(
          amount: amount,
          note: note,
          spentAt: day == null
              ? null
              : DateTime(day.year, day.month, day.day, 12), // tengah hari: aman dari zona waktu
        );
    await refresh();
  }

  Future<void> remove(String id) async {
    await ref.read(expenseRepositoryProvider).remove(id);
    await refresh();
  }
}

final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

/// Total pengeluaran periode yang sedang dilihat.
final expenseTotalProvider = Provider<int>((ref) {
  final list = ref.watch(expensesProvider).value ?? const <Expense>[];
  return list.fold(0, (sum, e) => sum + e.amount);
});

/// Ringkasan uang untuk rentang yang sedang dilihat.
class HistorySummary {
  const HistorySummary({
    required this.orders,
    required this.omzet,
    required this.omzetCash,
    required this.omzetQris,
    required this.cancelled,
  });

  final int orders;

  /// **Hanya order lunas & tidak dibatalkan.** Menjumlahkan semua baris riwayat
  /// akan memasukkan order batal dan order tunai yang tidak jadi dibayar ke
  /// dalam omzet - angka yang lebih besar dari uang yang benar-benar diterima.
  final int omzet;

  /// Dipecah karena uangnya ada di dua tempat berbeda: tunai di laci, QRIS di
  /// rekening. Saat mencocokkan kas akhir hari, angka gabungan tidak menjawab
  /// pertanyaan "isi laci harusnya berapa".
  final int omzetCash;
  final int omzetQris;

  final int cancelled;
}

final historySummaryProvider = Provider<HistorySummary>((ref) {
  final orders = ref.watch(filteredHistoryProvider);
  var cash = 0;
  var qris = 0;
  var cancelled = 0;
  for (final o in orders) {
    if (o.status == OrderStatus.cancelled) {
      cancelled++;
      continue;
    }
    if (!o.paymentStatus.isPaid) continue;
    if (o.paymentMethod == PaymentMethod.qris) {
      qris += o.totalAmount;
    } else {
      cash += o.totalAmount;
    }
  }
  return HistorySummary(
    orders: orders.length,
    omzet: cash + qris,
    omzetCash: cash,
    omzetQris: qris,
    cancelled: cancelled,
  );
});
