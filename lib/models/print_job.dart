import 'enums.dart';
import 'json.dart';

/// Satu antrian cetak dari server (PRINTER.md §4).
///
/// Aplikasi **tidak pernah** membuat struk sendiri - hanya mencetak apa yang
/// sudah ada di antrian. Server hanya membuat job untuk order yang LUNAS.
class PrintJob {
  const PrintJob({
    required this.id,
    required this.orderId,
    required this.kind,
    required this.station,
    required this.status,
    required this.trigger,
    required this.textBody,
    required this.attempts,
    required this.createdAt,
    this.payload,
    this.lastError,
    this.deviceId,
    this.claimedAt,
    this.printedAt,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) => PrintJob(
        id: asString(json['id']),
        orderId: asString(json['order_id']),
        kind: PrintJobKind.parse(json['kind']),
        station: PrintStation.parse(json['station']),
        status: PrintJobStatus.parse(json['status']),
        trigger: PrintTrigger.parse(json['trigger']),
        textBody: asString(json['text_body']),
        attempts: asInt(json['attempts']),
        createdAt: asDateOr(json['created_at'], DateTime.now()),
        payload: asMapOrNull(json['payload']),
        lastError: asStringOrNull(json['last_error']),
        deviceId: asStringOrNull(json['device_id']),
        claimedAt: asDate(json['claimed_at']),
        printedAt: asDate(json['printed_at']),
      );

  final String id;
  final String orderId;
  final PrintJobKind kind;

  /// Printer tujuan. Baris lama tanpa kolom ini terbaca sebagai `cashier`.
  final PrintStation station;

  final PrintJobStatus status;
  final PrintTrigger trigger;

  /// Teks siap kirim ke printer, sudah 32 kolom (kertas 58 mm).
  /// **Pakai ini** - jangan menyusun format struk sendiri (SPEC §8.3).
  final String textBody;

  /// Struk terstruktur, cadangan kalau nanti mau format kustom/logo.
  final Map<String, dynamic>? payload;

  final int attempts;
  final DateTime createdAt;
  final String? lastError;
  final String? deviceId;
  final DateTime? claimedAt;
  final DateTime? printedAt;

  String get orderNo => asString(payload?['order_no'], _orderNoFromId());
  String get tableLabel => asString(payload?['table_label'], '-');
  int get total => asInt(payload?['total']);

  String _orderNoFromId() {
    final compact = orderId.replaceAll('-', '').toUpperCase();
    return compact.length <= 6 ? compact : compact.substring(compact.length - 6);
  }
}
