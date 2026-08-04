import 'dart:convert';

/// Menyusun byte ESC/POS dari `text_body` yang **sudah jadi** dari server.
///
/// Aplikasi tidak pernah menyusun tata letak struk sendiri (SPEC §8.3):
/// server sudah merender 32 kolom untuk kertas 58 mm. Tugas berkas ini hanya
/// membungkusnya dengan perintah reset + feed + potong, dan memastikan tiap
/// byte muat di code page printer.
class ReceiptBytes {
  const ReceiptBytes._();

  static const List<int> _reset = [0x1B, 0x40]; // ESC @
  static const List<int> _feed = [0x0A, 0x0A, 0x0A];
  static const List<int> _cut = [0x1D, 0x56, 0x00]; // GS V 0

  /// Struk siap kirim ke printer.
  static List<int> receipt(String textBody) => [
        ..._reset,
        ...encodeText(textBody),
        ..._feed,
        ..._cut,
      ];

  /// Struk contoh untuk tombol "Tes Cetak" - tidak menyentuh antrian server.
  static List<int> testPage({required String deviceName}) {
    final now = DateTime.now();
    final stamp = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}.'
        '${now.minute.toString().padLeft(2, '0')}';

    final body = StringBuffer()
      ..writeln(_center('RUMIPANG'))
      ..writeln('-' * 32)
      ..writeln(_center('TES CETAK'))
      ..writeln('')
      ..writeln(_pad('Printer', _cut32(deviceName, 22)))
      ..writeln(_pad('Waktu', stamp))
      ..writeln('-' * 32)
      ..writeln('Lebar kertas 32 kolom:')
      ..writeln('12345678901234567890123456789012')
      ..writeln('-' * 32)
      ..writeln(_center('Kalau baris di atas pas,'))
      ..writeln(_center('printer siap dipakai.'));

    return [..._reset, ...encodeText(body.toString()), ..._feed, ..._cut];
  }

  /// Ubah teks jadi byte yang aman untuk printer termal murah.
  ///
  /// Printer kelas Panda PRJ-R58D umumnya hanya mendukung code page 437/850.
  /// Karakter di luar itu dicetak kacau, jadi ditransliterasi dulu ke ASCII
  /// (SPEC §8.4).
  static List<int> encodeText(String text) => latin1.encode(toAscii(text));

  /// Transliterasi ke ASCII murni. Yang tidak punya padanan jadi `?` -
  /// lebih baik satu karakter salah daripada seluruh baris bergeser.
  static String toAscii(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
        buffer.writeCharCode(rune);
      } else if (rune >= 0x20 && rune <= 0x7E) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(_replacements[rune] ?? '?');
      }
    }
    return buffer.toString();
  }

  static const Map<int, String> _replacements = {
    // Huruf beraksen yang mungkin muncul di nama menu
    0x00C0: 'A', 0x00C1: 'A', 0x00C2: 'A', 0x00C3: 'A', 0x00C4: 'A', 0x00C5: 'A',
    0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
    0x00C8: 'E', 0x00C9: 'E', 0x00CA: 'E', 0x00CB: 'E',
    0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
    0x00CC: 'I', 0x00CD: 'I', 0x00CE: 'I', 0x00CF: 'I',
    0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
    0x00D2: 'O', 0x00D3: 'O', 0x00D4: 'O', 0x00D5: 'O', 0x00D6: 'O',
    0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o', 0x00F6: 'o',
    0x00D9: 'U', 0x00DA: 'U', 0x00DB: 'U', 0x00DC: 'U',
    0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
    0x00D1: 'N', 0x00F1: 'n',
    0x00C7: 'C', 0x00E7: 'c',

    // Tanda baca tipografis - sering ikut ter-copy dari dashboard owner
    0x2018: "'", 0x2019: "'", 0x201A: "'",
    0x201C: '"', 0x201D: '"', 0x201E: '"',
    0x2013: '-', 0x2014: '-', 0x2212: '-',
    0x2026: '...',
    0x00A0: ' ',
    0x00B0: 'deg',
    0x00D7: 'x',
    0x20A8: 'Rp', 0x20B9: 'Rp',
  };

  // --- pembantu tata letak, khusus halaman tes ---

  static const int _width = 32;

  static String _center(String text) {
    final clean = _cut32(text, _width);
    final pad = ((_width - clean.length) / 2).floor();
    return ' ' * (pad < 0 ? 0 : pad) + clean;
  }

  /// "Label              nilai" rata kiri-kanan dalam 32 kolom.
  static String _pad(String left, String right) {
    final l = _cut32(left, _width - 1);
    final r = _cut32(right, _width - l.length - 1);
    final gap = _width - l.length - r.length;
    return l + ' ' * (gap < 1 ? 1 : gap) + r;
  }

  static String _cut32(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
