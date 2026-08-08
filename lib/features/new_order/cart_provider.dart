import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/order_repository.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../orders/orders_provider.dart';
import 'catalog_provider.dart';

/// Satu baris keranjang. Item yang sama dengan variasi berbeda dihitung
/// sebagai baris berbeda.
class CartLine {
  const CartLine({
    required this.item,
    required this.variations,
    required this.quantity,
    this.notes,
  });

  final MenuItemModel item;
  final List<MenuVariation> variations;
  final int quantity;
  final String? notes;

  /// Identitas baris: menu + kombinasi variasi.
  String get key {
    final labels = variations.map((v) => '${v.variationType}:${v.label}').toList()
      ..sort();
    return '${item.id}|${labels.join('|')}';
  }

  int get extraPerUnit => variations.fold(0, (sum, v) => sum + v.extraPrice);

  /// (harga + total extra_price) x qty - **harus** sama dengan rumus server,
  /// karena server tidak menghitung ulang (API-CONTRACT §3).
  int get subtotal => (item.price + extraPerUnit) * quantity;

  String get displayName => variations.isEmpty
      ? item.name
      : '${item.name} (${variations.map((v) => v.label).join(', ')})';

  CartLine copyWith({int? quantity, String? notes}) => CartLine(
        item: item,
        variations: variations,
        quantity: quantity ?? this.quantity,
        notes: notes ?? this.notes,
      );

  NewOrderLine toPayloadLine() => NewOrderLine(
        menuItemId: item.id,
        menuItemName: item.name,
        menuItemPrice: item.price,
        quantity: quantity,
        variations: variations
            .map((v) => OrderVariation(
                  variationType: v.variationType,
                  label: v.label,
                  extraPrice: v.extraPrice,
                ))
            .toList(),
        notes: notes,
      );
}

class CartState {
  const CartState({
    this.lines = const [],
    this.tableId,
    this.method = PaymentMethod.cash,
    this.paymentStatus = PaymentStatus.unpaid,
    this.notes,
  });

  final List<CartLine> lines;
  final String? tableId;
  final PaymentMethod method;
  final PaymentStatus paymentStatus;
  final String? notes;

  int get total => lines.fold(0, (sum, l) => sum + l.subtotal);
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  bool get isEmpty => lines.isEmpty;

  CartState copyWith({
    List<CartLine>? lines,
    String? tableId,
    PaymentMethod? method,
    PaymentStatus? paymentStatus,
    String? notes,
    bool clearTable = false,
  }) =>
      CartState(
        lines: lines ?? this.lines,
        tableId: clearTable ? null : (tableId ?? this.tableId),
        method: method ?? this.method,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        notes: notes ?? this.notes,
      );
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(MenuItemModel item, {List<MenuVariation> variations = const [], String? notes}) {
    final line = CartLine(item: item, variations: variations, quantity: 1, notes: notes);
    final existing = state.lines.indexWhere((l) => l.key == line.key && l.notes == notes);

    if (existing >= 0) {
      final updated = [...state.lines];
      updated[existing] =
          updated[existing].copyWith(quantity: updated[existing].quantity + 1);
      state = state.copyWith(lines: updated);
    } else {
      state = state.copyWith(lines: [...state.lines, line]);
    }
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      state = state.copyWith(lines: state.lines.where((l) => l.key != key).toList());
      return;
    }
    state = state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.key == key) line.copyWith(quantity: quantity) else line,
      ],
    );
  }

  void remove(String key) =>
      state = state.copyWith(lines: state.lines.where((l) => l.key != key).toList());

  void setTable(String? tableId) => state = tableId == null
      ? state.copyWith(clearTable: true)
      : state.copyWith(tableId: tableId);

  void setMethod(PaymentMethod method) {
    // QRIS di POS hanya dipakai untuk pembayaran yang SUDAH diterima -
    // aplikasi kasir tidak membuat transaksi Midtrans sendiri.
    state = state.copyWith(
      method: method,
      paymentStatus:
          method == PaymentMethod.qris ? PaymentStatus.paid : state.paymentStatus,
    );
  }

  void setPaid(bool paid) => state = state.copyWith(
        paymentStatus: paid ? PaymentStatus.paid : PaymentStatus.unpaid,
      );

  void setNotes(String? notes) => state = state.copyWith(notes: notes);

  void clear() => state = const CartState();

  /// Kirim ke `POST /api/orders`. Kalau `payment_status: PAID`, server
  /// otomatis mengantrikan struk.
  Future<OrderModel> submit() async {
    final payload = NewOrderPayload(
      tableId: state.tableId,
      paymentMethod: state.method,
      paymentStatus: state.paymentStatus,
      notes: state.notes,
      items: state.lines.map((l) => l.toPayloadLine()).toList(),
    );

    final order = await ref.read(orderRepositoryProvider).create(payload);
    clear();

    // Saringan menu ikut dibersihkan. Kalau tidak, sisa pencarian pelanggan
    // sebelumnya menempel ke pelanggan berikutnya - dan kasir yang sedang
    // buru-buru menyimpulkan menunya hilang, lalu menutup paksa aplikasi.
    ref.read(posQueryProvider.notifier).setQuery('');
    ref.read(posCategoryProvider.notifier).select(null);

    await ref.read(cashierBoardProvider.notifier).refresh();
    return order;
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
