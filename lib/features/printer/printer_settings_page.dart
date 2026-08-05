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
  List<PairedPrinter> _devices = const [];
  List<PrintJob> _jobs = const [];
  bool _scanning = false;
  bool _loadingJobs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scan());
      unawaited(_loadJobs());
    });
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final devices = await ref.read(printerControllerProvider.notifier).listDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    }
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 400, child: _leftPane()),
        const VerticalDivider(width: 1),
        Expanded(child: _queuePane()),
      ],
    );
  }

  // ------------------------------------------------------------- kiri ------

  Widget _leftPane() {
    final printer = ref.watch(printerControllerProvider);
    final queue = ref.watch(printQueueProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: AppTheme.panel(
            outline: printer.isConnected ? AppTheme.paid : AppTheme.unpaid,
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    printer.isConnected ? Icons.print : Icons.print_disabled,
                    color: printer.isConnected ? AppTheme.paid : AppTheme.unpaid,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    printer.label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: printer.isConnected ? AppTheme.paid : AppTheme.unpaid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                printer.deviceName == null
                    ? 'Belum ada printer dipilih'
                    : '${printer.deviceName}  ·  ${printer.deviceMac}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              if (printer.message != null) ...[
                const SizedBox(height: 10),
                Text(
                  printer.message!,
                  style: const TextStyle(color: AppTheme.unpaid, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: printer.isBusy ? null : _reconnect,
                      icon: const Icon(Icons.link),
                      label: const Text('Hubungkan Ulang'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: printer.deviceMac == null ? null : _testPrint,
                      icon: const Icon(Icons.receipt),
                      label: const Text('Tes Cetak'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

        // --- daftar perangkat ter-pair ---
        Row(
          children: [
            const Text(
              'PERANGKAT TER-PAIR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: Colors.black45,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_scanning ? 'Mencari...' : 'Muat Ulang'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Pairing dilakukan di Pengaturan Bluetooth Android. Aplikasi hanya '
          'memilih dari perangkat yang sudah dipasangkan.',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 10),

        if (_devices.isEmpty && !_scanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Tidak ada perangkat ter-pair yang terbaca.',
              style: TextStyle(color: Colors.black45),
            ),
          ),
        ..._devices.map((device) {
          final active = device.mac == printer.deviceMac;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: AppTheme.panel(
                outline: active ? AppTheme.brand : null,
                background: active ? AppTheme.brand.withValues(alpha: 0.06) : null,
              ),
              child: ListTile(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(
                  active ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: active ? AppTheme.brand : Colors.black38,
                ),
                title: Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(device.mac, style: const TextStyle(fontSize: 12)),
                trailing: active
                    ? TextButton(onPressed: _forget, child: const Text('Lupakan'))
                    : null,
                onTap: active ? null : () => _select(device),
              ),
            ),
          );
        }),
      ],
    );
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
              const Text(
                '50 job terakhir',
                style: TextStyle(color: Colors.black45, fontSize: 13),
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

  Future<void> _select(PairedPrinter device) async {
    await ref.read(printerControllerProvider.notifier).select(device);
    if (!mounted) return;
    final status = ref.read(printerControllerProvider);
    showSnack(
      context,
      status.isConnected
          ? 'Tersambung ke ${device.name}'
          : status.message ?? 'Gagal menyambung ke ${device.name}',
      error: !status.isConnected,
    );
  }

  Future<void> _forget() async {
    await ref.read(printerControllerProvider.notifier).forget();
    if (mounted) showSnack(context, 'Printer dilepas dari aplikasi.');
  }

  Future<void> _reconnect() async {
    final ok = await ref.read(printerControllerProvider.notifier).connect();
    if (!mounted) return;
    showSnack(
      context,
      ok
          ? 'Printer tersambung.'
          : ref.read(printerControllerProvider).message ?? 'Gagal menyambung.',
      error: !ok,
    );
  }

  Future<void> _testPrint() async {
    try {
      await ref.read(printerControllerProvider.notifier).testPrint();
      if (mounted) showSnack(context, 'Struk contoh dikirim ke printer.');
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
      child: Row(
        children: [
          StatusChip(label: job.status.label, color: color, filled: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#${job.orderNo}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      job.tableLabel,
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(label: job.kind.label, color: Colors.black45),
                  ],
                ),
                const SizedBox(height: 2),
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
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pratinjau',
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined),
          ),
          if (job.status == PrintJobStatus.failed)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Coba Lagi'),
            ),
        ],
      ),
    );
  }
}
