import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/enums.dart';
import '../../models/print_job.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'print_queue.dart';
import 'printer_provider.dart';
import 'printer_service.dart';

/// Layar pengaturan printer (SPEC §8.5).
///
/// Wajib ada karena kasirlah yang akan memperbaiki sendiri saat printer
/// bermasalah - bukan developer.
class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  ConsumerState<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends ConsumerState<PrinterSettingsPage> {
  List<PrintJob> _jobs = const [];
  bool _loadingJobs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadJobs()));
  }

  Future<void> _loadJobs() async {
    setState(() => _loadingJobs = true);
    try {
      final jobs = await ref.read(printQueueProvider.notifier).recentJobs();
      if (mounted) setState(() => _jobs = jobs);
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingJobs = false);
    }
    await ref.read(printQueueProvider.notifier).refreshMonitor();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Panel printer 400 menyisakan ±199px untuk antrian di tablet potret -
        // tidak cukup untuk satu baris job pun.
        if (constraints.maxWidth < SplitLayout.printerPane) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status printer + daftar perangkat tetap di atas: itu yang
              // dicari kasir saat printer bermasalah.
              Flexible(child: _leftPane()),
              const Divider(height: 1),
              Flexible(child: _queuePane()),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 400, child: _leftPane()),
            const VerticalDivider(width: 1),
            Expanded(child: _queuePane()),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------- kiri ------

  Widget _leftPane() {
    final queue = ref.watch(printQueueProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final station in PrintStation.values) ...[
          _stationCard(station),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),

        // --- ringkasan antrian ---
        Container(
          decoration: AppTheme.panel(),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Metric(
                    label: 'Menunggu',
                    value: '${queue.pending}',
                    color: queue.pending > 0 ? AppTheme.warn : Colors.black54,
                  ),
                  _Metric(
                    label: 'Gagal',
                    value: '${queue.failed}',
                    color: queue.failed > 0 ? AppTheme.unpaid : Colors.black54,
                  ),
                  _Metric(
                    label: 'Loop',
                    value: queue.running ? 'Jalan' : 'Mati',
                    color: queue.running ? AppTheme.paid : AppTheme.unpaid,
                  ),
                ],
              ),
              if (queue.lastSuccessAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Struk terakhir tercetak ${Fmt.ago(queue.lastSuccessAt!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
              if (queue.lastError != null) ...[
                const SizedBox(height: 10),
                Text(
                  queue.lastError!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.unpaid),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

      ],
    );
  }

  /// Kartu status satu stasiun: printer mana, sedang tersambung atau tidak,
  /// dan tombol yang dibutuhkan kasir saat printernya bermasalah.
  Widget _stationCard(PrintStation station) {
    final printer = ref.watch(printerControllerProvider);
    final slot = printer.slot(station);
    final active = printer.activeStation == station;

    final color = switch (slot.link) {
      PrinterLinkState.connected => AppTheme.paid,
      PrinterLinkState.notSelected => Colors.black45,
      PrinterLinkState.connecting => AppTheme.warn,
      _ => AppTheme.unpaid,
    };

    return Container(
      decoration: AppTheme.panel(outline: color.withValues(alpha: 0.55)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                station == PrintStation.kitchen ? Icons.soup_kitchen : Icons.point_of_sale,
                color: color,
              ),
              const SizedBox(width: 10),
              Text(
                'Printer ${station.label}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              // Socketnya cuma satu - penanda ini menjelaskan kenapa printer
              // lain berstatus "Terputus" padahal tidak rusak.
              if (active)
                const StatusChip(label: 'memegang koneksi', color: AppTheme.brand),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            slot.deviceMac == null
                ? 'Belum ada printer dipilih'
                : '${slot.deviceName}  ·  ${slot.deviceMac}',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            slot.label,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (slot.message != null) ...[
            const SizedBox(height: 8),
            Text(
              slot.message!,
              style: const TextStyle(color: AppTheme.unpaid, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          if (!slot.isSelected)
            FilledButton.icon(
              onPressed: () => _pickDevice(station),
              icon: const Icon(Icons.add_link),
              label: const Text('Pilih Printer'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: slot.isBusy ? null : () => _reconnect(station),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Hubungkan'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _testPrint(station),
                  icon: const Icon(Icons.receipt, size: 18),
                  label: const Text('Tes Cetak'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDevice(station),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Ganti'),
                ),
                TextButton(
                  onPressed: () => _forget(station),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.unpaid),
                  child: const Text('Lupakan'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Dialog pilih perangkat untuk satu stasiun.
  ///
  /// Dialognya **memindai sendiri**. Versi sebelumnya memakai daftar milik
  /// halaman ini, dan itu gagal dua kali sekaligus: kalau pemindaian dari
  /// `initState` masih jalan saat tombol ditekan, dialog terbuka dengan daftar
  /// kosong - dan karena dialog adalah route terpisah, `setState` di halaman
  /// tidak pernah sampai ke sana. Layarnya diam kosong selamanya. Ini terjadi
  /// di warung.
  Future<void> _pickDevice(PrintStation station) async {
    final picked = await showDialog<PairedPrinter>(
      context: context,
      builder: (_) => _DevicePickerDialog(station: station),
    );
    if (picked != null && mounted) await _select(station, picked);
  }

  // ------------------------------------------------------------ kanan ------

  Widget _queuePane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              const Text(
                'Antrian Cetak',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              // Keterangan ini yang pertama dikorbankan saat ruang sempit -
              // judul dan tombol muat ulang jauh lebih berguna.
              const Flexible(
                child: Text(
                  '50 job terakhir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.black45, fontSize: 13),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadingJobs ? null : _loadJobs,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat Ulang'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _jobs.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long,
                  title: _loadingJobs ? 'Memuat...' : 'Belum ada job cetak',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _jobs.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _JobTile(
                      job: _jobs[i],
                      onRetry: () => _retry(_jobs[i]),
                      onPreview: () => _preview(_jobs[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- aksi ------

  Future<void> _select(PrintStation station, PairedPrinter device) async {
    try {
      await ref.read(printerControllerProvider.notifier).select(station, device);
    } on PrinterFailure catch (e) {
      // Mis. printer yang sama sudah dipakai stasiun lain.
      if (mounted) showSnack(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    final slot = ref.read(printerControllerProvider).slot(station);
    showSnack(
      context,
      slot.isConnected
          ? '${device.name} jadi printer ${station.label}.'
          : slot.message ?? 'Gagal menyambung ke ${device.name}',
      error: !slot.isConnected,
    );
  }

  Future<void> _forget(PrintStation station) async {
    await ref.read(printerControllerProvider.notifier).forget(station);
    if (mounted) showSnack(context, 'Printer ${station.label} dilepas.');
  }

  Future<void> _reconnect(PrintStation station) async {
    final ok = await ref.read(printerControllerProvider.notifier).useStation(station);
    if (!mounted) return;
    showSnack(
      context,
      ok
          ? 'Printer ${station.label} tersambung.'
          : ref.read(printerControllerProvider).slot(station).message ??
              'Gagal menyambung.',
      error: !ok,
    );
  }

  Future<void> _testPrint(PrintStation station) async {
    try {
      await ref.read(printerControllerProvider.notifier).testPrint(station);
      if (mounted) {
        showSnack(context, 'Struk contoh dikirim ke printer ${station.label}.');
      }
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _retry(PrintJob job) async {
    try {
      await ref.read(printQueueProvider.notifier).retryJob(job.id);
      if (mounted) showSnack(context, 'Job dikembalikan ke antrian.');
      await _loadJobs();
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  void _preview(PrintJob job) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pratinjau struk #${job.orderNo}'),
        content: SizedBox(
          width: context.dialogWidth(380),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(14),
              color: const Color(0xFFFAF7F2),
              width: double.infinity,
              child: Text(
                job.textBody.isEmpty ? '(kosong)' : job.textBody,
                // Monospace penting: struk dirender server pada lebar tetap
                // 32 kolom, font proporsional akan menyesatkan.
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onRetry, required this.onPreview});

  final PrintJob job;
  final VoidCallback onRetry;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      PrintJobStatus.printed => AppTheme.paid,
      PrintJobStatus.failed => AppTheme.unpaid,
      PrintJobStatus.printing => AppTheme.warn,
      _ => AppTheme.queued,
    };

    return Container(
      decoration: AppTheme.panel(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, bukan Row: status + nomor + meja + jenis job tidak selalu
          // muat sebaris di panel sempit.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(label: job.status.label, color: color, filled: true),
              Text(
                '#${job.orderNo}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                job.tableLabel,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              StatusChip(label: job.kind.label, color: Colors.black45),
              // Satu order menghasilkan dua job dengan nomor sama - tanpa
              // penanda ini keduanya terlihat seperti struk dobel.
              StatusChip(label: job.station.label, color: AppTheme.brand),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${job.trigger.label} · ${Fmt.dayClock(job.createdAt)}'
            '${job.attempts > 0 ? ' · ${job.attempts}x percobaan' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
          if (job.lastError != null)
            Text(
              job.lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.unpaid),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (job.status == PrintJobStatus.failed)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Coba Lagi'),
                ),
              IconButton(
                tooltip: 'Pratinjau',
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Pemilih perangkat Bluetooth untuk satu stasiun.
///
/// Memindai **di dalam dirinya sendiri**, bukan menumpang daftar milik halaman
/// printer. Alasannya mahal dipelajari: dialog adalah route terpisah, jadi
/// `setState` di halaman induk tidak pernah merender ulang isinya. Daftar yang
/// datang belakangan tidak akan pernah muncul, dan kasir melihat "tidak ada
/// perangkat" padahal kedua printernya menyala.
class _DevicePickerDialog extends ConsumerStatefulWidget {
  const _DevicePickerDialog({required this.station});

  final PrintStation station;

  @override
  ConsumerState<_DevicePickerDialog> createState() => _DevicePickerDialogState();
}

class _DevicePickerDialogState extends ConsumerState<_DevicePickerDialog> {
  List<PairedPrinter> _devices = const [];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_scan()));
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final devices = await ref
        .read(printerControllerProvider.notifier)
        .listDevices(widget.station);
    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Printer yang sudah dipegang stasiun lain ditandai, bukan disembunyikan -
    // kasir perlu tahu kenapa printer yang ia cari tidak bisa dipilih.
    final taken = <String, PrintStation>{};
    final status = ref.watch(printerControllerProvider);
    for (final s in PrintStation.values) {
      if (s == widget.station) continue;
      final mac = status.slot(s).deviceMac;
      if (mac != null) taken[mac] = s;
    }

    return AlertDialog(
      title: Text('Printer ${widget.station.label}'),
      content: SizedBox(
        width: context.dialogWidth(420),
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pairing dilakukan di Pengaturan Bluetooth Android. Aplikasi '
              'hanya memilih dari perangkat yang sudah dipasangkan.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _scanning
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('Mencari perangkat...',
                              style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    )
                  : _devices.isEmpty
                      ? const EmptyState(
                          icon: Icons.bluetooth_disabled,
                          title: 'Tidak ada perangkat ter-pair',
                          subtitle: 'Pasangkan printer dulu di Pengaturan > '
                              'Bluetooth, lalu tekan Cari Ulang.',
                        )
                      : ListView(
                          children: [
                            for (final device in _devices)
                              ListTile(
                                enabled: !taken.containsKey(device.mac),
                                leading: Icon(
                                  taken.containsKey(device.mac)
                                      ? Icons.lock_outline
                                      : Icons.print,
                                ),
                                title: Text(device.name),
                                subtitle: Text(
                                  taken.containsKey(device.mac)
                                      ? 'Dipakai printer ${taken[device.mac]!.label}'
                                      : device.mac,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: taken.containsKey(device.mac)
                                    ? null
                                    : () => Navigator.pop(context, device),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _scanning ? null : _scan,
          child: const Text('Cari Ulang'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
