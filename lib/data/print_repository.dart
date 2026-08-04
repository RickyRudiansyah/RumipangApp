import '../core/api_client.dart';
import '../models/json.dart';
import '../models/print_job.dart';

class PrintRepository {
  const PrintRepository(this._api);

  final ApiClient _api;

  static List<PrintJob> _parseJobs(dynamic raw) {
    final map = asMap(raw);
    final jobs = map['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .map((e) => PrintJob.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Ambil job `PENDING` **sekaligus menguncinya** jadi `PRINTING`.
  /// Aman untuk banyak perangkat: satu job hanya bisa diklaim satu perangkat.
  Future<List<PrintJob>> claim({int limit = 3}) async => _parseJobs(
        await _api.get('/api/print/jobs', query: {'claim': 1, 'limit': limit}),
      );

  /// 50 job terakhir (semua status) untuk layar monitoring.
  /// **Tidak** mengunci apa pun.
  Future<List<PrintJob>> recent() async =>
      _parseJobs(await _api.get('/api/print/jobs'));

  /// WAJIB dipanggil setelah mencoba cetak. Tanpa ACK, job kembali ke
  /// `PENDING` setelah 2 menit dan struk yang sama tercetak dua kali.
  Future<void> ack(String jobId, {required bool printed, String? error}) =>
      _api.patch('/api/print/jobs/$jobId/ack', body: {
        'status': printed ? 'PRINTED' : 'FAILED',
        if (!printed && error != null) 'error': _trimError(error),
      });

  /// Cetak ulang (`kind = REPRINT`, boleh berkali-kali).
  Future<void> reprint({required String orderId, required String verifiedBy}) =>
      _api.post('/api/print/jobs', body: {
        'order_id': orderId,
        'verified_by': verifiedBy,
      });

  /// Kembalikan job `FAILED` ke antrian.
  Future<void> retry(String jobId) => _api.post('/api/print/jobs/$jobId/retry');

  /// Pesan error printer bisa panjang (stack trace plugin). Potong supaya
  /// kolom `last_error` tetap terbaca di dashboard.
  static String _trimError(String error) {
    final clean = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length <= 200 ? clean : '${clean.substring(0, 197)}...';
  }
}
