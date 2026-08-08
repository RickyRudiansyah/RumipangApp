import '../core/api_client.dart';
import '../models/enums.dart';
import '../models/json.dart';
import '../models/order.dart';

/// Hasil `PATCH /api/orders/{id}/mark-paid`.
class MarkPaidResult {
  const MarkPaidResult({required this.printQueued});

  /// `false` berarti order **tetap lunas** tapi struk gagal diantrikan.
  /// Jangan gagalkan transaksinya - tampilkan peringatan + tawarkan cetak ulang
  /// (API-CONTRACT §3).
  final bool printQueued;
}

class OrderRepository {
  const OrderRepository(this._api);

  final ApiClient _api;

  static List<OrderModel> _parseList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    // Beberapa endpoint bisa membungkus dalam { orders: [...] }.
    if (raw is Map && raw['orders'] is List) return _parseList(raw['orders']);
    return const [];
  }

  /// Board kasir: order aktif non-arsip & non-cancel, **termasuk `SERVED` yang
  /// belum diarsipkan** supaya tagihan belum dibayar tidak hilang dari layar.
  Future<List<OrderModel>> cashierBoard() async =>
      _parseList(await _api.get('/api/orders', query: {'mode': 'cashier'}));

  /// Arsip + dibatalkan.
  Future<List<OrderModel>> history() async =>
      _parseList(await _api.get('/api/orders/history'));

  /// Order QRIS yang sudah lunas sejak [since] - hanya untuk dilihat.
  ///
  /// QRIS diarsipkan server begitu pembayarannya settle, jadi ia tidak pernah
  /// muncul di board kasir. Warung tetap perlu memantaunya; inilah daftarnya.
  /// Batas harinya dihitung dari jam tablet (WIB), bukan UTC.
  Future<List<OrderModel>> qrisPaid({required DateTime since}) async =>
      _parseList(await _api.get('/api/orders', query: {
        'mode': 'qris-paid',
        'from': since.toUtc().toIso8601String(),
      }));

  /// Sapu pembayaran QRIS yang tertinggal, kembalikan jumlah yang diselamatkan.
  ///
  /// Order QRIS hanya lahir dari `settleIntent()` di server, dan pemicunya
  /// (tab checkout pelanggan + webhook) sama-sama rapuh. Kalau keduanya gagal,
  /// pelanggan sudah membayar tapi ordernya tidak pernah ada - pernah terjadi,
  /// dua order senilai Rp 107.000 hilang begitu saja. Tablet ini satu-satunya
  /// perangkat yang menyala sepanjang hari, jadi ia yang jadi jaring
  /// pengamannya.
  Future<int> reconcilePayments() async {
    final res = asMap(await _api.post('/api/payments/reconcile'));
    return asInt(res['recovered']);
  }

  /// Hapus riwayat. Tanpa rentang berarti **seluruh** riwayat.
  ///
  /// [from] inklusif, [to] eksklusif, dan keduanya dikirim setelah dikonversi
  /// ke UTC. Batas "hari" ditentukan pemanggil dari jam tablet (WIB), bukan
  /// oleh server: tengah malam UTC jatuh pukul 07.00 pagi di warung, tepat di
  /// tengah hari kerja.
  Future<int> deleteHistory({DateTime? from, DateTime? to}) async {
    final res = await _api.delete('/api/orders/history', query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    return asInt(asMap(res)['deleted']);
  }

  /// **Satu-satunya** cara melunasi order tunai. Memicu pembuatan job cetak
  /// di server.
  Future<MarkPaidResult> markPaid(String orderId) async {
    final res = await _api.patch('/api/orders/$orderId/mark-paid');
    return MarkPaidResult(printQueued: asBool(asMap(res)['print_queued']));
  }

  // Catatan: `setStatus` dan `updateEta` sengaja dihapus. Alur dapur (ETA,
  // "mulai proses", "sudah diantar") tidak lagi ada di aplikasi - order cukup
  // masuk lalu dibayar. Endpointnya boleh tetap hidup di server untuk web;
  // aplikasi hanya berhenti memanggilnya (BACKEND-ADDITIONS.md §7).

  Future<void> cancel(String orderId, String reason) =>
      _api.patch('/api/orders/$orderId/cancel', body: {'reason': reason});

  Future<void> archive(String orderId) => _api.patch('/api/orders/$orderId/archive');

  /// Order manual (POS).
  ///
  /// `total_amount` dan `subtotal` dihitung klien - server tidak memverifikasi
  /// ulang, jadi perhitungan di [NewOrderPayload] harus benar.
  Future<OrderModel> create(NewOrderPayload payload) async {
    final res = await _api.post('/api/orders', body: payload.toJson());
    return OrderModel.fromJson(asMap(res));
  }
}

class NewOrderLine {
  const NewOrderLine({
    required this.menuItemId,
    required this.menuItemName,
    required this.menuItemPrice,
    required this.quantity,
    required this.variations,
    this.notes,
  });

  final String menuItemId;
  final String menuItemName;
  final int menuItemPrice;
  final int quantity;
  final List<OrderVariation> variations;
  final String? notes;

  int get extraPerUnit =>
      variations.fold(0, (sum, v) => sum + v.extraPrice);

  /// (harga + total extra_price) x qty
  int get subtotal => (menuItemPrice + extraPerUnit) * quantity;

  Map<String, dynamic> toJson() => {
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'menu_item_price': menuItemPrice,
        'quantity': quantity,
        'variations': variations.map((v) => v.toJson()).toList(),
        'subtotal': subtotal,
        'notes': notes,
      };
}

class NewOrderPayload {
  const NewOrderPayload({
    required this.paymentMethod,
    required this.paymentStatus,
    required this.items,
    this.tableId,
    this.notes,
  });

  final String? tableId;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final List<NewOrderLine> items;
  final String? notes;

  int get totalAmount => items.fold(0, (sum, line) => sum + line.subtotal);

  Map<String, dynamic> toJson() => {
        'table_id': tableId,
        'payment_method': paymentMethod.wire,
        'payment_status': paymentStatus.wire,
        'total_amount': totalAmount,
        'notes': notes ?? 'Order manual',
        'items': items.map((e) => e.toJson()).toList(),
      };
}
