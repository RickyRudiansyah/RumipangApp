import 'json.dart';

/// Penjualan satu menu dalam rentang waktu.
///
/// Server hanya menghitung order **lunas dan tidak batal**
/// (BACKEND-ADDITIONS.md §3). Menu yang tidak pernah terjual tetap dikirim
/// dengan `qty_sold: 0` - justru itu yang ingin dilihat di daftar kurang laku.
class MenuSalesStat {
  const MenuSalesStat({
    required this.menuItemId,
    required this.menuItemName,
    required this.qtySold,
    required this.revenue,
    required this.cost,
  });

  factory MenuSalesStat.fromJson(Map<String, dynamic> json) => MenuSalesStat(
        menuItemId: asString(json['menu_item_id']),
        menuItemName: asString(json['menu_item_name'], 'Menu'),
        qtySold: asInt(json['qty_sold']),
        revenue: asInt(json['revenue']),
        cost: asInt(json['cost']),
      );

  final String menuItemId;
  final String menuItemName;
  final int qtySold;
  final int revenue;

  /// Total HPP dari snapshot saat penjualan, bukan HPP hari ini.
  final int cost;

  int get grossProfit => revenue - cost;

  bool get neverSold => qtySold == 0;

  /// `null` kalau HPP belum pernah diisi untuk menu ini - lebih jujur
  /// daripada menampilkan margin 100%.
  double? get marginPercent {
    if (revenue <= 0 || cost <= 0) return null;
    return grossProfit / revenue * 100;
  }
}

/// Hasil laporan satu rentang waktu.
class MenuSalesReport {
  const MenuSalesReport({
    required this.from,
    required this.to,
    required this.items,
  });

  factory MenuSalesReport.fromJson(Map<String, dynamic> json) => MenuSalesReport(
        from: asDateOr(json['from'], DateTime.now()),
        to: asDateOr(json['to'], DateTime.now()),
        items: asList(json['items'], MenuSalesStat.fromJson),
      );

  final DateTime from;
  final DateTime to;
  final List<MenuSalesStat> items;

  int get totalRevenue => items.fold(0, (sum, e) => sum + e.revenue);
  int get totalCost => items.fold(0, (sum, e) => sum + e.cost);
  int get totalProfit => totalRevenue - totalCost;
  int get totalQty => items.fold(0, (sum, e) => sum + e.qtySold);

  /// Terlaris lebih dulu. Menu tanpa penjualan ikut terbawa ke ekor daftar.
  List<MenuSalesStat> get bestSellers {
    final sorted = [...items]..sort((a, b) => b.qtySold.compareTo(a.qtySold));
    return sorted;
  }

  /// Paling sedikit terjual lebih dulu, termasuk yang belum pernah laku.
  List<MenuSalesStat> get worstSellers {
    final sorted = [...items]..sort((a, b) => a.qtySold.compareTo(b.qtySold));
    return sorted;
  }
}
