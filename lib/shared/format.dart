import 'package:intl/intl.dart';

/// Format angka & waktu untuk layar kasir Indonesia.
class Fmt {
  const Fmt._();

  static final NumberFormat _rupiah = NumberFormat.decimalPattern('id_ID');
  static final DateFormat _clock = DateFormat('HH.mm', 'id_ID');
  static final DateFormat _dayClock = DateFormat('d MMM, HH.mm', 'id_ID');
  static final DateFormat _full = DateFormat('EEEE, d MMMM yyyy HH.mm', 'id_ID');

  /// 27000 -> "Rp 27.000"
  static String rupiah(int amount) => 'Rp ${_rupiah.format(amount)}';

  /// 27000 -> "27.000" (tanpa prefiks, untuk kolom angka yang sudah jelas)
  static String number(int amount) => _rupiah.format(amount);

  static String clock(DateTime time) => _clock.format(time);
  static String dayClock(DateTime time) => _dayClock.format(time);
  static String full(DateTime time) => _full.format(time);

  /// "baru saja", "3 mnt lalu", "2 jam lalu"
  static String ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  /// Hitung mundur ETA. Negatif berarti sudah lewat: "telat 4 mnt".
  static String countdown(Duration remaining) {
    if (remaining.isNegative) {
      final late = -remaining;
      if (late.inMinutes < 1) return 'telat <1 mnt';
      if (late.inMinutes < 60) return 'telat ${late.inMinutes} mnt';
      return 'telat ${late.inHours} jam';
    }
    if (remaining.inMinutes < 1) return '<1 mnt lagi';
    if (remaining.inMinutes < 60) return '${remaining.inMinutes} mnt lagi';
    return '${remaining.inHours} jam lagi';
  }
}
