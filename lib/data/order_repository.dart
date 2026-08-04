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

  /// Board dapur: hanya `QUEUED` & `PROCESSING`.
  Future<List<OrderModel>> kitchenBoard() async =>
      _parseList(await _api.get('/api/orders'));

  /// Arsip + dibatalkan.
  Future<List<OrderModel>> history() async =>
      _parseList(await _api.get('/api/orders/history'));

  /// **Satu-satunya** cara melunasi order tunai. Memicu pembuatan job cetak
  /// di server.
  Future<MarkPaidResult> markPaid(String orderId) async {
    final res = await _api.patch('/api/orders/$orderId/mark-paid');
    return MarkPaidResult(printQueued: asBool(asMap(res)['print_queued']));
  }

  Future<void> setStatus(
    String orderId,
    OrderStatus status, {
    int? estimatedMinutes,
  }) =>
      _api.patch('/api/orders/$orderId/status', body: {
        'status': status.wire,
        if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      });

  /// **Menambah** waktu dari ETA yang sedang berjalan, bukan menimpa dari
  /// sekarang (API-CONTRACT §3). Rentang yang diterima server: 1-1440 menit.
  Future<void> updateEta(String orderId, int minutes) =>
      _api.patch('/api/orders/$orderId/update-eta', body: {
        'estimated_minutes': minutes.clamp(1, 1440),
      });

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
