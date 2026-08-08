import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';

/// Penyimpanan lokal ringan: pilihan printer, cache board, dan antrian aksi
/// yang belum sempat dikirim ke server.
///
/// Sesi login **tidak** disimpan di sini - `supabase_flutter` sudah memakai
/// penyimpanan aman bawaannya (SPEC §12).
class LocalStore {
  const LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // -------------------------------------------------------------- printer ---

  // Kunci lama dari zaman satu printer. Masih dibaca sekali saat migrasi
  // supaya kasir yang sudah memasangkan printernya tidak perlu memilih ulang.
  static const _kLegacyMac = 'printer.mac';
  static const _kLegacyName = 'printer.name';

  static String _macKey(PrintStation s) => 'printer.${s.wire}.mac';
  static String _nameKey(PrintStation s) => 'printer.${s.wire}.name';

  String? printerMac(PrintStation station) => _prefs.getString(_macKey(station));
  String? printerName(PrintStation station) => _prefs.getString(_nameKey(station));

  Future<void> savePrinter(
    PrintStation station, {
    required String mac,
    required String name,
  }) async {
    await _prefs.setString(_macKey(station), mac);
    await _prefs.setString(_nameKey(station), name);
  }

  Future<void> clearPrinter(PrintStation station) async {
    await _prefs.remove(_macKey(station));
    await _prefs.remove(_nameKey(station));
  }

  /// Pindahkan printer tunggal versi lama ke slot kasir.
  ///
  /// Dijalankan sekali saat aplikasi mulai. Tanpa ini, pembaruan aplikasi akan
  /// terasa seperti printernya "hilang" — dan kasir memasangkan ulang di pagi
  /// yang sibuk.
  Future<void> migrateLegacyPrinter() async {
    final mac = _prefs.getString(_kLegacyMac);
    if (mac == null) return;
    if (printerMac(PrintStation.cashier) == null) {
      await savePrinter(
        PrintStation.cashier,
        mac: mac,
        name: _prefs.getString(_kLegacyName) ?? 'Printer',
      );
    }
    await _prefs.remove(_kLegacyMac);
    await _prefs.remove(_kLegacyName);
  }

  // ---------------------------------------------------------------- cache ---

  static const _kBoardCache = 'cache.board.';
  static const _kBoardCacheAt = 'cache.board.at.';

  /// Simpan board terakhir supaya kasir tetap melihat sesuatu saat server
  /// tidak terjangkau (SPEC §9). Ini **hanya untuk dibaca** - aksi apa pun
  /// tetap harus lewat server.
  Future<void> cacheBoard(String key, List<Map<String, dynamic>> orders) async {
    await _prefs.setString('$_kBoardCache$key', jsonEncode(orders));
    await _prefs.setInt(
      '$_kBoardCacheAt$key',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<Map<String, dynamic>> readCachedBoard(String key) {
    final raw = _prefs.getString('$_kBoardCache$key');
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  DateTime? cachedBoardAt(String key) {
    final ms = _prefs.getInt('$_kBoardCacheAt$key');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ------------------------------------------------------- antrian tunda ---

  static const _kPending = 'pending.actions';

  List<Map<String, dynamic>> readPendingActions() {
    final raw = _prefs.getString(_kPending);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> writePendingActions(List<Map<String, dynamic>> actions) =>
      _prefs.setString(_kPending, jsonEncode(actions));
}
