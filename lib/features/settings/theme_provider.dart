import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/app_theme_preset.dart';
import '../auth/staff_provider.dart';

class ThemeNotifier extends AsyncNotifier<ThemePreset> {
  @override
  Future<ThemePreset> build() async {
    // Tema hanya relevan setelah login; sebelum itu tidak ada token untuk
    // memanggil API.
    if (!ref.watch(isSignedInProvider)) return ThemePreset.normal;

    try {
      return await ref.watch(settingsRepositoryProvider).theme();
    } catch (_) {
      // Tema tidak boleh pernah memblokir aplikasi. Server mati atau endpoint
      // belum ada -> pakai warna asli dan lanjut bekerja.
      return ThemePreset.normal;
    }
  }

  /// Optimistic update disengaja di sini.
  ///
  /// Aturan "jangan optimistic update" di README hanya berlaku untuk uang -
  /// salah menampilkan tema selama dua detik tidak merugikan siapa pun,
  /// sedangkan menunggu server membuat pemilihan warna terasa patah.
  Future<void> select(ThemePreset preset) async {
    final previous = state.value ?? ThemePreset.normal;
    state = AsyncValue.data(preset);
    try {
      final saved = await ref.read(settingsRepositoryProvider).setTheme(preset);
      state = AsyncValue.data(saved);
    } catch (_) {
      state = AsyncValue.data(previous);
      rethrow;
    }
  }
}

final themeProvider =
    AsyncNotifierProvider<ThemeNotifier, ThemePreset>(ThemeNotifier.new);

/// Tema yang sedang berlaku. Selalu punya nilai - tidak pernah loading.
final activeThemeProvider = Provider<ThemePreset>(
  (ref) => ref.watch(themeProvider).value ?? ThemePreset.normal,
);
