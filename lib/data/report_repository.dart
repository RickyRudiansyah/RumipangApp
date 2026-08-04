import '../core/api_client.dart';
import '../models/report.dart';

class ReportRepository {
  const ReportRepository(this._api);

  final ApiClient _api;

  /// Penjualan per menu dalam rentang waktu.
  ///
  /// Rentangnya dikirim sebagai UTC ISO-8601 karena itu yang dipakai kolom
  /// `created_at` di database; konversi ke WIB terjadi saat ditampilkan.
  Future<MenuSalesReport> menuSales({
    required DateTime from,
    required DateTime to,
  }) async {
    final json = await _api.get('/api/reports/menu-sales', query: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    return MenuSalesReport.fromJson(Map<String, dynamic>.from(json as Map));
  }
}
