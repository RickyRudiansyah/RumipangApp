/// Siklus DAPUR. **Terpisah total** dari [PaymentStatus] (API-CONTRACT §2).
/// Order bisa `SERVED` tapi masih `UNPAID`.
enum OrderStatus {
  queued('QUEUED', 'Antri'),
  processing('PROCESSING', 'Diproses'),
  served('SERVED', 'Diantar'),
  cancelled('CANCELLED', 'Batal'),

  /// Nilai yang tidak dikenal aplikasi (server menambah status baru).
  /// Ditampilkan apa adanya, tidak pernah ditebak jadi status lain.
  unknown('', '?');

  const OrderStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OrderStatus parse(Object? v) {
    final raw = v?.toString().toUpperCase();
    return OrderStatus.values.firstWhere(
      (e) => e.wire == raw && e != OrderStatus.unknown,
      orElse: () => OrderStatus.unknown,
    );
  }

  bool get isActive => this == queued || this == processing;
}

/// Siklus UANG. Jangan pernah diturunkan dari [OrderStatus].
enum PaymentStatus {
  paid('PAID', 'Lunas'),

  /// Default saat nilainya hilang/aneh. Salah tampil "belum bayar" jauh lebih
  /// aman daripada salah tampil "lunas".
  unpaid('UNPAID', 'Belum Bayar');

  const PaymentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static PaymentStatus parse(Object? v) =>
      v?.toString().toUpperCase() == 'PAID' ? paid : unpaid;

  bool get isPaid => this == paid;
}

enum PaymentMethod {
  cash('CASH', 'Tunai'),
  qris('QRIS', 'QRIS');

  const PaymentMethod(this.wire, this.label);

  final String wire;
  final String label;

  static PaymentMethod parse(Object? v) =>
      v?.toString().toUpperCase() == 'QRIS' ? qris : cash;
}

enum PrintJobStatus {
  pending('PENDING', 'Menunggu'),
  printing('PRINTING', 'Mencetak'),
  printed('PRINTED', 'Tercetak'),
  failed('FAILED', 'Gagal'),
  unknown('', '?');

  const PrintJobStatus(this.wire, this.label);

  final String wire;
  final String label;

  static PrintJobStatus parse(Object? v) {
    final raw = v?.toString().toUpperCase();
    return PrintJobStatus.values.firstWhere(
      (e) => e.wire == raw && e != PrintJobStatus.unknown,
      orElse: () => PrintJobStatus.unknown,
    );
  }
}

enum PrintJobKind {
  receipt('RECEIPT', 'Struk'),
  reprint('REPRINT', 'Cetak Ulang');

  const PrintJobKind(this.wire, this.label);

  final String wire;
  final String label;

  static PrintJobKind parse(Object? v) =>
      v?.toString().toUpperCase() == 'REPRINT' ? reprint : receipt;
}

/// Asal-usul job cetak (PRINTER.md §1).
enum PrintTrigger {
  qrisSettled('QRIS_SETTLED', 'QRIS lunas'),
  cashVerified('CASH_VERIFIED', 'Tunai diverifikasi'),
  cashierPaidOrder('CASHIER_PAID_ORDER', 'Order kasir'),
  staffReprint('STAFF_REPRINT', 'Cetak ulang'),
  unknown('', '-');

  const PrintTrigger(this.wire, this.label);

  final String wire;
  final String label;

  static PrintTrigger parse(Object? v) {
    final raw = v?.toString().toUpperCase();
    return PrintTrigger.values.firstWhere(
      (e) => e.wire == raw && e != PrintTrigger.unknown,
      orElse: () => PrintTrigger.unknown,
    );
  }
}
