import '../core/api_client.dart';
import '../models/staff_meal.dart';

class StaffMealRepository {
  const StaffMealRepository(this._api);

  final ApiClient _api;

  static List<T> _parse<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => build(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Daftar karyawan yang berhak mengambil jatah makan.
  Future<List<StaffMember>> staff() async =>
      _parse(await _api.get('/api/staff'), StaffMember.fromJson);

  /// Jatah makan pada satu tanggal. Tanpa argumen = hari ini.
  Future<List<StaffMeal>> onDate(DateTime date) async => _parse(
        await _api.get('/api/staff-meals', query: {'date': _ymd(date)}),
        StaffMeal.fromJson,
      );

  /// Rekap rentang, untuk menghitung total biaya jatah makan.
  Future<List<StaffMeal>> range(DateTime from, DateTime to) async => _parse(
        await _api.get('/api/staff-meals', query: {
          'from': _ymd(from),
          'to': _ymd(to),
        }),
        StaffMeal.fromJson,
      );

  /// Catat jatah makan hari ini.
  ///
  /// Server membalas **409** kalau karyawan itu sudah mengambil jatahnya hari
  /// ini; pesannya diteruskan apa adanya ke kasir lewat [ApiFailure].
  /// `meal_date` sengaja tidak dikirim - biar jam server yang menentukan
  /// "hari ini", bukan jam tablet yang bisa saja salah setel.
  Future<StaffMeal> record({
    required String staffId,
    String? menuItemId,
    String? note,
  }) async {
    final json = await _api.post('/api/staff-meals', body: {
      'staff_id': staffId,
      if (menuItemId != null) 'menu_item_id': menuItemId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return StaffMeal.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<void> remove(String id) => _api.delete('/api/staff-meals/$id');

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
