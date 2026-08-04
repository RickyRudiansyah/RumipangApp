import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  static const _kPrinterMac = 'printer.mac';
  static const _kPrinterName = 'printer.name';

  String? get printerMac => _prefs.getString(_kPrinterMac);
  String? get printerName => _prefs.getString(_kPrinterName);

  Future<void> savePrinter({required String mac, required String name}) async {
    await _prefs.setString(_kPrinterMac, mac);
    await _prefs.setString(_kPrinterName, name);
  }

  Future<void> clearPrinter() async {
    await _prefs.remove(_kPrinterMac);
    await _prefs.remove(_kPrinterName);
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
