import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../models/enums.dart';
import 'printer_service.dart';

final printerServiceProvider = Provider<PrinterService>((ref) => PrinterService());

/// Koneksi ke printer: pilih perangkat, sambung, tes cetak.
///
/// MAC printer disimpan lokal supaya kasir tidak perlu memilih ulang tiap pagi
/// (SPEC §8.5). Sejak ada printer dapur, disimpan **satu per stasiun**.
///
/// Socket SPP-nya tetap satu. Yang berubah bukan jumlah koneksi, melainkan
/// siapa yang sedang memegangnya - lihat [useStation].
class PrinterController extends Notifier<PrinterStatus> {
  PrinterService get _service => ref.read(printerServiceProvider);

  @override
  PrinterStatus build() {
    final store = ref.read(localStoreProvider);
    return PrinterStatus(
      slots: {
        for (final station in PrintStation.values)
          station: () {
            final mac = store.printerMac(station);
            return PrinterSlot(
              link: mac == null
                  ? PrinterLinkState.notSelected
                  : PrinterLinkState.disconnected,
              deviceMac: mac,
              deviceName: store.printerName(station),
            );
          }(),
      },
    );
  }

  void _setSlot(PrintStation station, PrinterSlot slot) {
    state = state.withSlot(station, slot);
  }

  // ------------------------------------------------------------- memilih ----

  Future<List<PairedPrinter>> listDevices(PrintStation station) async {
    if (!await _service.ensurePermissions()) {
      _setSlot(
        station,
        state.slot(station).copyWith(
              link: PrinterLinkState.permissionDenied,
              message: 'Izin Bluetooth ditolak. Buka Pengaturan > Aplikasi > '
                  'Rumipang Kasir > Izin, lalu aktifkan "Perangkat di sekitar".',
            ),
      );
      return const [];
    }
    if (!await _service.bluetoothEnabled) {
      _setSlot(
        station,
        state.slot(station).copyWith(
              link: PrinterLinkState.bluetoothOff,
              message: 'Bluetooth tablet sedang mati.',
            ),
      );
      return const [];
    }
    try {
      return await _service.pairedPrinters();
    } catch (e) {
      _setSlot(station, state.slot(station).copyWith(message: 'Gagal membaca daftar perangkat: $e'));
      return const [];
    }
  }

  Future<void> select(PrintStation station, PairedPrinter printer) async {
    // Satu printer fisik tidak boleh memegang dua stasiun: strukya akan keluar
    // dua kali di kertas yang sama, dan kasir mengira sistemnya rusak.
    for (final other in PrintStation.values) {
      if (other == station) continue;
      if (state.slot(other).deviceMac == printer.mac) {
        throw PrinterFailure(
          '${printer.name} sudah dipakai sebagai printer ${other.label}. '
          'Pilih printer lain, atau lepaskan dulu dari stasiun itu.',
        );
      }
    }

    await ref.read(localStoreProvider).savePrinter(
          station,
          mac: printer.mac,
          name: printer.name,
        );
    _setSlot(
      station,
      PrinterSlot(
        link: PrinterLinkState.disconnected,
        deviceMac: printer.mac,
        deviceName: printer.name,
      ),
    );
    await useStation(station);
  }

  Future<void> forget(PrintStation station) async {
    if (state.activeStation == station) {
      await _service.disconnect();
      state = state.copyWith(clearActive: true);
    }
    await ref.read(localStoreProvider).clearPrinter(station);
    _setSlot(station, PrinterSlot.empty);
  }

  // ---------------------------------------------------------- menyambung ----

  /// Jadikan [station] pemegang socket, sambungkan kalau perlu.
  ///
  /// Mengembalikan `true` kalau printer stasiun itu siap menerima byte.
  /// **Inilah satu-satunya pintu untuk berpindah printer** - jangan pernah
  /// memanggil `PrinterService.connect` langsung dari luar, karena status
  /// slot lain harus ikut diturunkan jadi `disconnected`.
  Future<bool> useStation(PrintStation station) async {
    final slot = state.slot(station);
    final mac = slot.deviceMac;
    if (mac == null) return false;

    // Sudah pegang socket dan socketnya masih hidup.
    if (state.activeStation == station &&
        _service.connectedMac == mac &&
        await _service.isConnected) {
      if (!slot.isConnected) {
        _setSlot(station, slot.copyWith(link: PrinterLinkState.connected, clearMessage: true));
      }
      return true;
    }

    _setSlot(station, slot.copyWith(link: PrinterLinkState.connecting, clearMessage: true));

    try {
      if (!await _service.ensurePermissions()) {
        _setSlot(
          station,
          state.slot(station).copyWith(
                link: PrinterLinkState.permissionDenied,
                message: 'Izin Bluetooth belum diberikan.',
              ),
        );
        return false;
      }
      if (!await _service.bluetoothEnabled) {
        _setSlot(
          station,
          state.slot(station).copyWith(
                link: PrinterLinkState.bluetoothOff,
                message: 'Nyalakan Bluetooth tablet.',
              ),
        );
        return false;
      }

      await _service.connect(mac);

      // Stasiun lain otomatis kehilangan socketnya - catat, supaya layar tidak
      // menampilkan dua printer "Terhubung" padahal cuma satu yang benar.
      var next = state;
      for (final other in PrintStation.values) {
        if (other == station) continue;
        final s = next.slot(other);
        if (s.isSelected && s.link == PrinterLinkState.connected) {
          next = next.withSlot(other, s.copyWith(link: PrinterLinkState.disconnected));
        }
      }
      next = next.withSlot(
        station,
        next.slot(station).copyWith(link: PrinterLinkState.connected, clearMessage: true),
      );
      state = next.copyWith(activeStation: station);
      return true;
    } on PrinterFailure catch (e) {
      _setSlot(
        station,
        state.slot(station).copyWith(link: PrinterLinkState.disconnected, message: e.message),
      );
      return false;
    } catch (e) {
      _setSlot(
        station,
        state.slot(station).copyWith(
              link: PrinterLinkState.disconnected,
              message: 'Gagal menyambung: $e',
            ),
      );
      return false;
    }
  }

  /// Sambungkan printer pertama yang tersedia - dipakai saat aplikasi mulai,
  /// supaya indikator tidak merah sampai struk pertama datang.
  Future<void> connect() async {
    final configured = state.configured;
    if (configured.isEmpty) return;
    await useStation(configured.first);
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    var next = state;
    for (final station in PrintStation.values) {
      final s = next.slot(station);
      if (s.isSelected) {
        next = next.withSlot(station, s.copyWith(link: PrinterLinkState.disconnected));
      }
    }
    state = next.copyWith(clearActive: true);
  }

  /// Dipakai saat aplikasi kembali ke depan: pastikan socketnya masih hidup.
  Future<bool> ensureReady() async {
    final active = state.activeStation;
    if (active != null) return useStation(active);
    final configured = state.configured;
    if (configured.isEmpty) return false;
    return useStation(configured.first);
  }

  /// Struk contoh - tidak menyentuh antrian server sama sekali.
  Future<void> testPrint(PrintStation station) async {
    if (!await useStation(station)) {
      throw PrinterFailure(state.slot(station).message ?? 'Printer tidak terhubung');
    }
    await _service.printTestPage(
      '${state.slot(station).deviceName ?? 'Printer'} (${station.label})',
    );
  }
}

final printerControllerProvider =
    NotifierProvider<PrinterController, PrinterStatus>(PrinterController.new);
