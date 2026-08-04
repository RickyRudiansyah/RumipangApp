import 'enums.dart';
import 'json.dart';

class CafeTable {
  const CafeTable({
    required this.id,
    required this.tableNumber,
    required this.label,
    required this.isActive,
  });

  factory CafeTable.fromJson(Map<String, dynamic> json) => CafeTable(
        id: asString(json['id']),
        tableNumber: asInt(json['table_number']),
        label: asString(json['label'], 'Meja ?'),
        isActive: asBool(json['is_active'], true),
      );

  final String id;
  final int tableNumber;
  final String label;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'table_number': tableNumber,
        'label': label,
        'is_active': isActive,
      };
}

class OrderVariation {
  const OrderVariation({
    required this.variationType,
    required this.label,
    required this.extraPrice,
  });

  factory OrderVariation.fromJson(Map<String, dynamic> json) => OrderVariation(
        variationType: asString(json['variation_type']),
        label: asString(json['label']),
        extraPrice: asInt(json['extra_price']),
      );

  final String variationType;
  final String label;
  final int extraPrice;

  Map<String, dynamic> toJson() => {
        'variation_type': variationType,
        'label': label,
        'extra_price': extraPrice,
      };
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    required this.menuItemPrice,
    required this.quantity,
    required this.subtotal,
    required this.variations,
    this.notes,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: asString(json['id']),
        menuItemId: asString(json['menu_item_id']),
        menuItemName: asString(json['menu_item_name'], 'Item'),
        menuItemPrice: asInt(json['menu_item_price']),
        quantity: asInt(json['quantity'], 1),
        subtotal: asInt(json['subtotal']),
        variations: asList(json['variations'], OrderVariation.fromJson),
        notes: asStringOrNull(json['notes']),
      );

  final String id;
  final String menuItemId;
  final String menuItemName;
  final int menuItemPrice;
  final int quantity;
  final int subtotal;
  final List<OrderVariation> variations;
  final String? notes;

  /// "Es Kopi Susu (Large, Extra Manis)"
  String get displayName {
    if (variations.isEmpty) return menuItemName;
    return '$menuItemName (${variations.map((v) => v.label).join(', ')})';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'menu_item_price': menuItemPrice,
        'quantity': quantity,
        'subtotal': subtotal,
        'variations': variations.map((v) => v.toJson()).toList(),
        'notes': notes,
      };
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
    required this.isArchived,
    required this.createdAt,
    required this.items,
    this.tableId,
    this.table,
    this.notes,
    this.cancelReason,
    this.confirmedAt,
    this.estimatedReadyAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: asString(json['id']),
        status: OrderStatus.parse(json['status']),
        paymentMethod: PaymentMethod.parse(json['payment_method']),
        paymentStatus: PaymentStatus.parse(json['payment_status']),
        totalAmount: asInt(json['total_amount']),
        isArchived: asBool(json['is_archived']),
        createdAt: asDateOr(json['created_at'], DateTime.now()),
        items: asList(json['items'], OrderItem.fromJson),
        tableId: asStringOrNull(json['table_id']),
        table: json['table'] is Map ? CafeTable.fromJson(asMap(json['table'])) : null,
        notes: asStringOrNull(json['notes']),
        cancelReason: asStringOrNull(json['cancel_reason']),
        confirmedAt: asDate(json['confirmed_at']),
        estimatedReadyAt: asDate(json['estimated_ready_at']),
      );

  final String id;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int totalAmount;
  final bool isArchived;
  final DateTime createdAt;
  final List<OrderItem> items;
  final String? tableId;
  final CafeTable? table;
  final String? notes;
  final String? cancelReason;
  final DateTime? confirmedAt;
  final DateTime? estimatedReadyAt;

  /// 6 karakter terakhir UUID - sama dengan `order_no` di struk ("38766F").
  String get orderNo {
    final compact = id.replaceAll('-', '').toUpperCase();
    return compact.length <= 6 ? compact : compact.substring(compact.length - 6);
  }

  String get tableLabel => table?.label ?? 'Tanpa Meja';

  // --- Aturan tombol (API-CONTRACT §3). Disamakan persis dengan web. ---

  bool get canMarkPaid => paymentStatus == PaymentStatus.unpaid;
  bool get canCancel => status == OrderStatus.queued;
  bool get canStartProcessing => status == OrderStatus.queued;
  bool get canMarkServed => status == OrderStatus.processing;

  /// Syarat sebuah order boleh ikut diarsipkan.
  bool get isSettled => status == OrderStatus.served && paymentStatus.isPaid;

  /// ETA sudah lewat tapi belum diantar -> kartu dapur jadi merah.
  bool get isOverdue {
    final eta = estimatedReadyAt;
    if (eta == null || !status.isActive) return false;
    return DateTime.now().isAfter(eta);
  }

  Duration? get remainingEta {
    final eta = estimatedReadyAt;
    if (eta == null || !status.isActive) return null;
    return eta.difference(DateTime.now());
  }

  /// Dipakai cache offline. Bentuknya sengaja sama persis dengan respons
  /// server supaya bisa dibaca ulang oleh [OrderModel.fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.wire,
        'payment_method': paymentMethod.wire,
        'payment_status': paymentStatus.wire,
        'total_amount': totalAmount,
        'is_archived': isArchived,
        'created_at': createdAt.toUtc().toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'table_id': tableId,
        'table': table?.toJson(),
        'notes': notes,
        'cancel_reason': cancelReason,
        'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
        'estimated_ready_at': estimatedReadyAt?.toUtc().toIso8601String(),
      };
}
