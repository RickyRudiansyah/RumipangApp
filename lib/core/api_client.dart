import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'failure.dart';

/// Klien REST ke API Next.js.
///
/// Aturan pokok (SPEC §3): **setiap perubahan status order harus lewat sini**,
/// tidak boleh update tabel Supabase langsung - logika bisnisnya (mis. membuat
/// job cetak saat `mark-paid`) ada di server.
///
/// Token diambil ulang **tepat sebelum tiap request** (SPEC §5). Jangan pernah
/// menyimpan `accessToken` di field; `supabase_flutter` menyegarkannya di
/// belakang layar dan salinan lama akan basi.
class ApiClient {
  ApiClient({
    required SupabaseClient supabase,
    http.Client? httpClient,
    String baseUrl = Env.apiBaseUrl,
  })  : _supabase = supabase,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  final SupabaseClient _supabase;
  final http.Client _http;
  final String _baseUrl;

  /// Menjaga hanya ada satu refresh berjalan walau beberapa request kena 401
  /// bersamaan.
  Future<bool>? _refreshInFlight;

  void dispose() => _http.close();

  // ---------------------------------------------------------------- verbs ---

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query, retryOnFailure: true);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  /// Dipakai untuk endpoint web yang sudah ada dan memang PUT
  /// (`PUT /api/menu/[id]`). Endpoint order semuanya PATCH.
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) =>
      _send('DELETE', path, query: query);

  // --------------------------------------------------------------- engine ---

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool retryOnFailure = false,
  }) async {
    // GET aman diulang. POST/PATCH TIDAK pernah diulang otomatis di sini -
    // pengulangan aksi uang diurus PendingActionQueue yang tahu konteksnya.
    final int attempts = retryOnFailure ? 3 : 1;

    AppFailure? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
      }
      try {
        return await _once(method, path, query: query, body: body);
      } on ServerFailure catch (e) {
        lastError = e; // 5xx -> layak diulang
      } on NetworkFailure catch (e) {
        lastError = e;
      }
    }
    throw lastError!;
  }

  Future<dynamic> _once(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool isRetryAfterRefresh = false,
  }) async {
    final uri = _buildUri(path, query);

    http.Response response;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(await _headers(withBody: body != null));
      if (body != null) request.body = jsonEncode(body);

      final streamed = await _http.send(request).timeout(Env.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const NetworkFailure('Server tidak merespons (timeout)');
    } on SocketException {
      throw const NetworkFailure('Tidak ada koneksi internet');
    } on http.ClientException catch (e) {
      throw NetworkFailure('Gangguan jaringan: ${e.message}');
    } on HandshakeException {
      throw const NetworkFailure('Koneksi aman ke server gagal');
    }

    // 401 -> coba refresh SEKALI, lalu ulangi. Kalau tetap gagal, ke login.
    if (response.statusCode == 401 && !isRetryAfterRefresh) {
      final refreshed = await _refreshSessionOnce();
      if (refreshed) {
        return _once(method, path, query: query, body: body, isRetryAfterRefresh: true);
      }
      throw const SessionExpiredFailure();
    }
    if (response.statusCode == 401) {
      throw const SessionExpiredFailure();
    }

    return _decode(response);
  }

  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final uri = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        for (final entry in query.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );
  }

  Future<Map<String, String>> _headers({required bool withBody}) async {
    // Diambil ulang setiap request - lihat catatan di atas kelas.
    final token = _supabase.auth.currentSession?.accessToken;
    return {
      'Accept': 'application/json',
      if (withBody) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> _refreshSessionOnce() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    try {
      await _supabase.auth.refreshSession();
    } catch (_) {
      // Refresh token ikut kedaluwarsa / dicabut -> jatuh ke pemeriksaan
      // session di bawah, pemanggil akan melempar SessionExpiredFailure.
    }
    return _supabase.auth.currentSession != null;
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;
    final raw = response.body;

    dynamic decoded;
    if (raw.isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null; // HTML error page dari Vercel, dsb.
      }
    }

    if (status >= 200 && status < 300) return decoded;

    final message = (decoded is Map && decoded['error'] is String)
        ? decoded['error'] as String
        : _fallbackMessage(status);

    if (status >= 500) throw ServerFailure(message, status);
    throw ApiFailure(message, status);
  }

  String _fallbackMessage(int status) => switch (status) {
        400 => 'Permintaan ditolak server',
        403 => 'Tidak punya akses',
        // 404 tanpa body JSON hampir selalu berarti route-nya memang belum ada
        // di Next.js - bukan "barisnya tidak ketemu". Membedakan keduanya
        // menghemat waktu menebak saat backend belum lengkap.
        404 => 'Endpoint ini belum tersedia di server',
        429 => 'Terlalu banyak permintaan, coba sebentar lagi',
        _ => 'Kesalahan server ($status)',
      };

  // ------------------------------------------------------------- unggah ----

  /// Unggah berkas ke `POST /api/upload` (multipart), lalu kembalikan URL
  /// publiknya.
  ///
  /// Bentuk respons endpoint web belum terdokumentasi, jadi beberapa nama
  /// field yang lazim dicoba berurutan sebelum menyerah.
  Future<String> uploadFile({
    required String path,
    required List<int> bytes,
    required String filename,
    String field = 'file',
    String? contentType,
  }) async {
    final uri = _buildUri(path, null);

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _headers(withBody: false))
        ..files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType:
                contentType == null ? null : MediaType.parse(contentType),
          ),
        );
      final streamed = await _http.send(request).timeout(_uploadTimeout);
      return http.Response.fromStream(streamed);
    }

    http.Response response;
    try {
      response = await send();
      if (response.statusCode == 401) {
        if (!await _refreshSessionOnce()) throw const SessionExpiredFailure();
        response = await send();
      }
    } on TimeoutException {
      throw const NetworkFailure('Unggah foto terlalu lama, coba lagi');
    } on SocketException {
      throw const NetworkFailure('Tidak ada koneksi internet');
    } on http.ClientException catch (e) {
      throw NetworkFailure('Gangguan jaringan: ${e.message}');
    }

    final decoded = _decode(response);
    final url = _pickUrl(decoded);
    if (url == null) {
      throw const ApiFailure(
        'Server tidak mengembalikan URL foto yang bisa dibaca',
        200,
      );
    }
    return url;
  }

  /// Unggah foto bisa jauh lebih lama dari request JSON biasa.
  static const _uploadTimeout = Duration(seconds: 60);

  static String? _pickUrl(dynamic decoded) {
    if (decoded is String && decoded.startsWith('http')) return decoded;
    if (decoded is! Map) return null;
    for (final key in const ['url', 'image_url', 'publicUrl', 'public_url', 'path']) {
      final value = decoded[key];
      if (value is String && value.isNotEmpty) return value;
    }
    // Beberapa handler membungkus dalam { data: { ... } }.
    if (decoded['data'] is Map) return _pickUrl(decoded['data']);
    return null;
  }
}
