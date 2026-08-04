import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/app_theme_preset.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'theme_provider.dart';

/// Pemilih tema event. Perubahan di sini **ikut mengubah web**, karena
/// keduanya membaca `app_settings.theme` yang sama.
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeThemeProvider);
    final async = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tema Event',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Berlaku untuk aplikasi kasir dan website sekaligus.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.6,
              children: [
                for (final preset in ThemePreset.values)
                  _PresetCard(
                    preset: preset,
                    selected: preset == active,
                    busy: async.isLoading,
                    onTap: () => _select(context, ref, preset),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Warna status (hijau lunas, merah belum bayar) sengaja tidak '
                  'ikut berubah supaya tetap mudah dibedakan di tema apa pun.',
                  style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.55)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, ThemePreset preset) async {
    try {
      await ref.read(themeProvider.notifier).select(preset);
      if (context.mounted) {
        showSnack(context, 'Tema ${preset.label} dipakai di aplikasi dan web');
      }
    } catch (error) {
      if (context.mounted) {
        showSnack(
          context,
          'Gagal menyimpan tema: ${error.toString().replaceFirst('Exception: ', '')}',
          error: true,
        );
      }
    }
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.panel(
          outline: selected ? preset.seed : null,
          background: selected ? preset.seed.withValues(alpha: 0.06) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preset.seed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(preset.icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 18,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preset.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, color: preset.seed, size: 22),
              ],
            ),
            const Spacer(),
            Text(
              preset.label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              preset.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
