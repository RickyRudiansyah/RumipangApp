import 'package:flutter/material.dart';

/// Tema event yang bisa dipilih owner dari aplikasi.
///
/// Daftar ini **harus sama persis dengan web** (BACKEND-ADDITIONS.md §6).
/// Nilai `wire` yang tidak dikenal jatuh ke [normal] - aplikasi versi lama
/// tidak error saat web menambah preset baru, temanya saja yang tidak ikut
/// berubah sampai aplikasi diperbarui.
enum ThemePreset {
  normal('NORMAL', 'Normal', Color(0xFF7B3F00), Color(0xFF5D4037)),
  natal('NATAL', 'Natal', Color(0xFFC62828), Color(0xFF1B7F4B)),
  ramadan('RAMADAN', 'Ramadan', Color(0xFF00695C), Color(0xFFB8860B)),
  kemerdekaan('KEMERDEKAAN', 'Kemerdekaan', Color(0xFFC62828), Color(0xFF37474F)),
  imlek('IMLEK', 'Imlek', Color(0xFFB71C1C), Color(0xFFD4AF37));

  const ThemePreset(this.wire, this.label, this.seed, this.accent);

  /// Nilai yang dikirim/diterima server.
  final String wire;

  /// Nama yang dibaca owner di layar.
  final String label;

  /// Warna dasar `ColorScheme.fromSeed`.
  final Color seed;

  /// Warna kedua untuk aksen dekoratif.
  final Color accent;

  static ThemePreset parse(Object? v) {
    final raw = v?.toString().toUpperCase();
    return ThemePreset.values.firstWhere(
      (e) => e.wire == raw,
      orElse: () => ThemePreset.normal,
    );
  }

  IconData get icon => switch (this) {
        ThemePreset.normal => Icons.coffee,
        ThemePreset.natal => Icons.park,
        ThemePreset.ramadan => Icons.nightlight_round,
        ThemePreset.kemerdekaan => Icons.flag,
        ThemePreset.imlek => Icons.celebration,
      };

  String get description => switch (this) {
        ThemePreset.normal => 'Cokelat kopi, warna asli Rumipang',
        ThemePreset.natal => 'Merah dan hijau',
        ThemePreset.ramadan => 'Hijau tosca dan emas',
        ThemePreset.kemerdekaan => 'Merah putih',
        ThemePreset.imlek => 'Merah dan emas',
      };
}
