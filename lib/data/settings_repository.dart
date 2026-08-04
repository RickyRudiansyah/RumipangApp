import '../core/api_client.dart';
import '../shared/app_theme_preset.dart';

/// Pengaturan yang dipakai bersama aplikasi dan web.
class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  Future<ThemePreset> theme() async {
    final json = await _api.get('/api/settings/theme');
    if (json is! Map) return ThemePreset.normal;
    return ThemePreset.parse(json['preset']);
  }

  /// Menyimpan tema. Web membaca nilai yang sama, jadi satu penyimpanan
  /// mengubah tampilan di kedua tempat (BACKEND-ADDITIONS.md §6).
  Future<ThemePreset> setTheme(ThemePreset preset) async {
    final json = await _api.patch('/api/settings/theme', body: {
      'preset': preset.wire,
    });
    if (json is! Map) return preset;
    return ThemePreset.parse(json['preset']);
  }
}
