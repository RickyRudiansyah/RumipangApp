import 'json.dart';

/// Bahan baku yang stoknya dilacak manual.
///
/// **Stok tidak berkurang otomatis saat ada penjualan.** HPP di aplikasi ini
/// diisi manual per menu, tanpa resep, jadi sistem tidak tahu satu porsi
/// menghabiskan berapa gram bahan. Semua perubahan lewat pencatatan manual
/// (BACKEND-ADDITIONS.md §4).
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stockQty,
    required this.alertThreshold,
    required this.isActive,
    this.updatedAt,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        id: asString(json['id']),
        name: asString(json['name'], 'Bahan'),
        unit: asString(json['unit'], 'pcs'),
        stockQty: asDouble(json['stock_qty']),
        alertThreshold: asDouble(json['alert_threshold'], 20),
        isActive: asBool(json['is_active'], true),
        updatedAt: asDate(json['updated_at']),
      );

  final String id;
  final String name;

  /// 'kg', 'gram', 'liter', 'pcs', ...
  final String unit;

  final double stockQty;
  final double alertThreshold;
  final bool isActive;
  final DateTime? updatedAt;

  /// Sudah menyentuh atau melewati ambang - inilah yang menyalakan alert.
  bool get isLow => stockQty <= alertThreshold;

  /// Benar-benar habis. Dibedakan dari [isLow] supaya urutan prioritas jelas.
  bool get isEmpty => stockQty <= 0;

  /// "12,5 kg" - pecahan dibuang kalau bulat supaya "20 pcs" tidak jadi
  /// "20.0 pcs".
  String get stockLabel => '${_trim(stockQty)} $unit';
  String get thresholdLabel => '${_trim(alertThreshold)} $unit';

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }
}

/// Alasan perubahan stok. Dikirim apa adanya ke server.
enum StockReason {
  purchase('PURCHASE', 'Belanja masuk'),
  usage('USAGE', 'Dipakai produksi'),
  waste('WASTE', 'Rusak / terbuang'),
  correction('CORRECTION', 'Koreksi hitung');

  const StockReason(this.wire, this.label);

  final String wire;
  final String label;

  /// Belanja menambah stok; sisanya mengurangi. Dipakai untuk menentukan tanda
  /// `delta` supaya kasir tidak perlu mengetik angka negatif.
  bool get isIncoming => this == purchase || this == correction;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.ingredientId,
    required this.delta,
    required this.reason,
    required this.createdAt,
    this.note,
    this.actorEmail,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: asString(json['id']),
        ingredientId: asString(json['ingredient_id']),
        delta: asDouble(json['delta']),
        reason: StockReason.values.firstWhere(
          (e) => e.wire == asString(json['reason']).toUpperCase(),
          orElse: () => StockReason.correction,
        ),
        createdAt: asDateOr(json['created_at'], DateTime.now()),
        note: asStringOrNull(json['note']),
        actorEmail: asStringOrNull(json['actor_email']),
      );

  final String id;
  final String ingredientId;
  final double delta;
  final StockReason reason;
  final DateTime createdAt;
  final String? note;
  final String? actorEmail;
}

/// Tidak ada di json.dart karena stok satu-satunya yang butuh pecahan -
/// rupiah dan kuantitas order semuanya bilangan bulat.
double asDouble(Object? v, [double fallback = 0]) => switch (v) {
      final double d => d,
      final num n => n.toDouble(),
      final String s => double.tryParse(s.replaceAll(',', '.')) ?? fallback,
      _ => fallback,
    };
