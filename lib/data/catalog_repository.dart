import '../core/api_client.dart';
import '../models/catalog.dart';
import '../models/order.dart';

class CatalogRepository {
  const CatalogRepository(this._api);

  final ApiClient _api;

  static List<T> _parse<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => build(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CafeTable>> tables() async {
    final list = _parse(await _api.get('/api/tables'), CafeTable.fromJson);
    return list.where((t) => t.isActive).toList()
      ..sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
  }

  Future<List<MenuItemModel>> menu() async =>
      _parse(await _api.get('/api/menu'), MenuItemModel.fromJson);

  /// Server mengirim **semua** variasi sekaligus; penyaringan per
  /// `menu_item_id` dilakukan di aplikasi (API-CONTRACT §5).
  Future<List<MenuVariation>> variations() async =>
      _parse(await _api.get('/api/menu/variations'), MenuVariation.fromJson);
}

/// Catatan aktivitas. Sengaja dibuat "tembak lalu lupa": kegagalan mencatat
/// log tidak boleh pernah menggagalkan aksi kasir.
class ActivityLogRepository {
  const ActivityLogRepository(this._api);

  final ApiClient _api;

  Future<void> log({
    required String actorEmail,
    required String actorRole,
    required String action,
    required String targetType,
    required String targetId,
    String? detail,
  }) async {
    try {
      await _api.post('/api/activity-logs', body: {
        'actor_email': actorEmail,
        'actor_role': actorRole,
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'detail': detail,
      });
    } catch (_) {
      // Diabaikan dengan sengaja.
    }
  }
}
