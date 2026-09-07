import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/state/theme_mode_provider.dart';

/// Right-side settings drawer (opened from the app-bar cog), holding the
/// light/dark theme switch — mirrors the ikasa app's settings drawer.
///
/// Lives here rather than on a screen because it is the app's only settings
/// surface once signed in, and it opens from "Odabir stola".
class SettingsDrawer extends ConsumerWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                'Postavke',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            _ThemeRow(
              mode: mode,
              onChanged: (m) =>
                  ref.read(themeModeProvider.notifier).setThemeMode(m),
            ),
          ],
        ),
      ),
    );
  }
}

/// Light/dark theme picker: a "Tema" label with a compact day/night pill
/// toggle on the right.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      child: Row(
        children: [
          Text('Tema', style: tt.bodyLarge),
          const Spacer(),
          _ThemePill(mode: mode, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A compact day/night toggle pill: [ ☀ | 🌙 ] — the active mode is filled.
class _ThemePill extends StatelessWidget {
  const _ThemePill({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = mode == ThemeMode.dark;

    Widget seg(IconData icon, bool selected, ThemeMode target, String tip) =>
        InkWell(
          onTap: () => onChanged(target),
          borderRadius: BorderRadius.circular(18),
          child: Tooltip(
            message: tip,
            child: Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(Icons.light_mode_outlined, !dark, ThemeMode.light, 'Svijetla'),
          seg(Icons.dark_mode_outlined, dark, ThemeMode.dark, 'Tamna'),
        ],
      ),
    );
  }
}
