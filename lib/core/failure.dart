/// Bentuk error dari server selalu `{ "error": "pesan" }` (API-CONTRACT §7).
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 400 / 404 dan sejenisnya - aturan bisnis dilanggar.
/// Pesannya datang dari server dan **ditampilkan apa adanya** ke kasir.
class ApiFailure extends AppFailure {
  const ApiFailure(super.message, this.statusCode);

  final int statusCode;

  bool get isNotFound => statusCode == 404;

  /// 400 dari `mark-paid` saat order sudah lunas duluan (mis. hasil retry
  /// antrian lokal yang sebenarnya sudah berhasil di server).
  bool get isAlreadyPaid => statusCode == 400 && message.toLowerCase().contains('already paid');
}

/// Token tidak valid / kedaluwarsa dan `refreshSession()` juga gagal.
/// Penanganannya: lempar kasir ke layar login.
class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure([super.message = 'Sesi berakhir, silakan masuk lagi']);
}

/// Tidak bisa menghubungi server: jaringan putus, timeout, DNS gagal.
/// Berbeda dari [ApiFailure] - aksi ini **layak dicoba lagi** nanti.
class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Tidak dapat terhubung ke server']);
}

/// Kesalahan server (5xx).
class ServerFailure extends AppFailure {
  const ServerFailure(super.message, this.statusCode);

  final int statusCode;
}

/// Kegagalan di sisi printer (koneksi putus, kertas habis, tidak dipilih).
class PrinterFailure extends AppFailure {
  const PrinterFailure(super.message);
}
