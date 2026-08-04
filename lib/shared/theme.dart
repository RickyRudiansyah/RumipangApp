import 'package:flutter/material.dart';

import 'app_theme_preset.dart';

/// Tema untuk tablet 10,4" landscape yang dipakai berjam-jam di ruangan terang.
///
/// Prinsipnya: kontras tinggi, target sentuh besar, tanpa animasi berat -
/// chipset Unisoc T618 lebih cepat kehabisan napas untuk efek dekoratif
/// daripada untuk daftar biasa (SPEC §2).
class AppTheme {
  const AppTheme._();

  static const Color brand = Color(0xFF7B3F00); // cokelat kopi

  // Warna semantik. **Tidak ikut berubah saat tema event diganti** - merah
  // harus selalu berarti "belum bayar". Tema Natal yang membuat semuanya
  // merah akan membuat penanda belum-bayar hilang di antara dekorasi.
  static const Color paid = Color(0xFF1B7F4B);
  static const Color unpaid = Color(0xFFC62828);
  static const Color warn = Color(0xFFE07A00);
  static const Color queued = Color(0xFF3F6BC4);

  static const Color border = Color(0xFFE2DCD4);

  /// Kartu standar. Dipakai menggantikan `Card` bertema supaya tampilannya
  /// sama di semua versi Flutter.
  static BoxDecoration panel({Color? background, Color? outline}) => BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: outline ?? border),
      );

  /// [preset] datang dari `app_settings.theme` di server, supaya aplikasi dan
  /// web berganti tema bersamaan (BACKEND-ADDITIONS.md §6).
  static ThemeData build([ThemePreset preset = ThemePreset.normal]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F4F1),
      visualDensity: VisualDensity.comfortable,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF231A12),
        ),
      ),

      // Catatan: `cardTheme` sengaja tidak diisi. Tipenya pernah berganti
      // (CardTheme -> CardThemeData) antar rilis Flutter, jadi kartu di sini
      // memakai [panel] supaya proyek tidak terikat satu versi SDK.

      // Tombol besar: kasir menekan sambil berdiri, sering dengan tangan basah.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),

      dividerTheme: const DividerThemeData(space: 1, thickness: 1),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(fontSize: 12),
      ),
    );
  }
}
