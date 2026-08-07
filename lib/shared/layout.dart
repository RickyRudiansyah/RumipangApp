import 'package:flutter/material.dart';

/// Ukuran layar yang dipakai untuk memilih tata letak.
///
/// Aplikasi ini lahir untuk tablet 10,4" landscape, lalu ditambah dukungan HP.
/// Ambangnya mengikuti Material 3 supaya tidak perlu ditebak per layar.
enum ScreenSize {
  /// HP potret. Satu kolom, navigasi di bawah.
  compact,

  /// HP landscape / tablet kecil potret. Dua kolom masih muat.
  medium,

  /// Tablet landscape - tata letak asli.
  expanded;

  bool get isCompact => this == ScreenSize.compact;
  bool get isExpanded => this == ScreenSize.expanded;

  /// Cukup lebar untuk menaruh dua panel bersebelahan.
  bool get canSplit => this != ScreenSize.compact;
}

extension ScreenSizeContext on BuildContext {
  ScreenSize get screen {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 600) return ScreenSize.compact;
    if (width < 1000) return ScreenSize.medium;
    return ScreenSize.expanded;
  }

  bool get isCompact => screen.isCompact;

  /// Lebar isi dialog yang tidak melampaui layar.
  ///
  /// `AlertDialog` di Flutter tidak mengecilkan `content` sendiri, jadi
  /// `SizedBox(width: 480)` akan terpotong di HP. Angka 40 itu margin kiri +
  /// kanan bawaan dialog.
  double dialogWidth([double preferred = 480]) {
    final available = MediaQuery.sizeOf(this).width - 80;
    return available < preferred ? available : preferred;
  }

  /// Jumlah kolom grid yang wajar untuk lebar sekarang.
  int gridColumns({int compact = 1, int medium = 2, int expanded = 3}) =>
      switch (screen) {
        ScreenSize.compact => compact,
        ScreenSize.medium => medium,
        ScreenSize.expanded => expanded,
      };
}

/// Lebar minimum sebelum tata letak master-detail layak dipakai.
///
/// **Jangan pakai [ScreenSize] untuk keputusan ini.** Tablet 10,4" dalam
/// potret masuk kategori `medium`, tapi setelah dipotong panel kiri 264px
/// sisanya hanya ±335px - tidak cukup untuk detail order, dan tombolnya
/// menghimpit teks sampai pecah satu huruf per baris.
///
/// Ukurlah lebar yang **benar-benar tersedia** lewat `LayoutBuilder`, bukan
/// lebar layar.
class SplitLayout {
  const SplitLayout._();

  /// Panel meja 264 + detail order yang masih terbaca.
  static const cashierBoard = 720.0;

  /// Grid menu + keranjang 400.
  static const posCart = 760.0;

  /// Teks penjelas + tombol aksi panjang dalam satu baris.
  static const textWithAction = 520.0;

  /// Baris riwayat: nomor + meja + tanggal + 2 chip + harga + 2 tombol.
  static const historyRow = 860.0;

  /// Judul + kolom cari + tombol muat ulang dalam satu baris.
  static const searchBar = 640.0;

  /// Panel printer 400 + daftar antrian cetak.
  static const printerPane = 760.0;
}
