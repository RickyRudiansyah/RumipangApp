import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/printer/print_queue.dart';
import '../features/printer/printer_provider.dart';
import '../models/enums.dart';
import 'theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: filled ? color : color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.white : color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      OrderStatus.queued => (AppTheme.queued, Icons.schedule),
      OrderStatus.processing => (AppTheme.warn, Icons.local_fire_department),
      OrderStatus.served => (AppTheme.paid, Icons.check_circle),
      OrderStatus.cancelled => (Colors.grey, Icons.cancel),
      OrderStatus.unknown => (Colors.grey, Icons.help_outline),
    };
    return StatusChip(label: status.label, color: color, icon: icon);
  }
}

/// Status uang. Sengaja **selalu mencolok** saat belum bayar - ini satu-satunya
/// penanda yang tidak boleh terlewat kasir.
class PaymentChip extends StatelessWidget {
  const PaymentChip(this.status, {super.key, this.method});

  final PaymentStatus status;
  final PaymentMethod? method;

  @override
  Widget build(BuildContext context) {
    final paid = status.isPaid;
    final label = method == null ? status.label : '${status.label} · ${method!.label}';
    return StatusChip(
      label: label,
      color: paid ? AppTheme.paid : AppTheme.unpaid,
      icon: paid ? Icons.payments : Icons.money_off,
      filled: !paid,
    );
  }
}

/// Indikator printer di kanan atas - wajib selalu terlihat supaya kasir tahu
/// tanpa membuka menu (SPEC §11).
class PrinterIndicator extends ConsumerWidget {
  const PrinterIndicator({super.key, this.onTap, this.compact = false});

  final VoidCallback? onTap;

  /// Di HP hanya ikon + jumlah antrian yang ditampilkan; teks statusnya
  /// dibuang karena tidak muat, bukan karena tidak penting.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final printer = ref.watch(printerControllerProvider);
    final queue = ref.watch(printQueueProvider);

    final ok = printer.isHealthy;
    final color = ok ? AppTheme.paid : AppTheme.unpaid;

    if (compact) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.print : Icons.print_disabled, size: 22, color: color),
              if (queue.pending > 0 || queue.failed > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '${queue.failed > 0 ? queue.failed : queue.pending}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: queue.failed > 0 ? AppTheme.unpaid : Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.print : Icons.print_disabled, size: 20, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  printer.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  queue.pending == 0 ? 'antrian kosong' : '${queue.pending} struk menunggu',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            if (queue.failed > 0) ...[
              const SizedBox(width: 10),
              StatusChip(
                label: '${queue.failed} gagal',
                color: AppTheme.unpaid,
                filled: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Banner "data mungkin usang" saat server tidak terjangkau (SPEC §9).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.updatedAt, this.pendingActions = 0});

  final DateTime? updatedAt;
  final int pendingActions;

  @override
  Widget build(BuildContext context) {
    final when = updatedAt == null ? '' : ' · terakhir diperbarui ${_ago(updatedAt!)}';
    return Material(
      color: AppTheme.warn.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: AppTheme.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline - data mungkin usang$when'
                '${pendingActions > 0 ? ' · $pendingActions verifikasi menunggu terkirim' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    return '${d.inHours} jam lalu';
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.black26),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.unpaid),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- dialog ----

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Lanjutkan',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.unpaid)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Pembatalan **wajib** disertai alasan (API-CONTRACT §3).
Future<String?> reasonDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Batalkan Order'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Alasan pembatalan',
              hintText: 'mis. Pelanggan membatalkan',
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.unpaid),
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(ctx, value);
          },
          child: const Text('Batalkan Order'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.unpaid : null,
        behavior: SnackBarBehavior.floating,
        width: 520,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}
