import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../mqtt/state/mqtt_users_provider.dart';
import '../../shared/presentation/hero_background.dart';
import '../../theme/state/theme_mode_provider.dart';

/// Colours for the login hero, derived from the active theme brightness so the
/// screen matches the standard light theme (and adapts if dark is ever used).
/// Accents come from the app's blue seed.
class _LoginPalette {
  const _LoginPalette({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.card,
    required this.cardBorder,
    required this.tileIcon,
  });

  final Color title;
  final Color subtitle;
  final Color label;
  final Color card;
  final Color cardBorder;
  final Color tileIcon;

  // Button gradient — same on both themes (reads well on light and dark).
  static const gradient = [Color(0xFF4A78B4), Color(0xFF6FA0E6)];

  factory _LoginPalette.of(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const _LoginPalette(
        title: Colors.white,
        subtitle: Color(0xFFB6C6DE),
        label: Color(0xFF8BA0BF),
        card: Color(0xFF16233C),
        cardBorder: Color(0xFF2A3B58),
        tileIcon: Color(0xFF6FA0E6),
      );
    }
    return const _LoginPalette(
      title: Color(0xFF16233C),
      subtitle: Color(0xFF5C6B85),
      label: Color(0xFF7688A5),
      card: Colors.white,
      cardBorder: Color(0xFFD7E0EF),
      tileIcon: Color(0xFF4A78B4),
    );
  }
}

/// The landing screen: a branded hero with the app name and the two actions —
/// "Prijava" (enabled once the MQTT staff list has arrived) and "Postavke
/// uređaja".
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _LoginPalette.of(Theme.of(context).brightness);
    // Login authenticates against the MQTT staff list (podaci/korisnici).
    // Prijava is enabled once that list has arrived.
    final mqttUsers = ref.watch(mqttUsersProvider);
    final prijavaEnabled = mqttUsers.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: HeroBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      // Centre the block in the viewport. This works because the
                      // ConstrainedBox above forces the Column to at least the
                      // viewport height; when the content is taller (a short
                      // screen) the Column simply grows and the view scrolls
                      // instead.
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pelion Order',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.title,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 48),
                        _GradientButton(
                          label: 'Prijava',
                          icon: Icons.arrow_forward,
                          enabled: prijavaEnabled,
                          onTap: () => context.push('/pin'),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: _ActionTile(
                            palette: palette,
                            icon: Icons.settings,
                            label: 'Postavke uređaja',
                            onTap: () => context.push('/settings'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: _ThemeToggleButton(palette: palette),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sun/dark-mode toggle overlaid on the login hero (top-right), mirroring the
/// ikasa login screen. Flips + persists the app theme.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton({required this.palette});

  final _LoginPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return IconButton(
      tooltip: isDark ? 'Svijetla tema' : 'Tamna tema',
      icon: Icon(
        // Show the icon for the mode we would switch TO.
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: palette.title,
        size: 22,
      ),
      onPressed: () =>
          ref.read(themeModeProvider.notifier).toggleThemeMode(),
    );
  }
}

/// Full-width gradient primary button (FilledButton can't do gradients).
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(colors: _LoginPalette.gradient)
                : const LinearGradient(
                    colors: [Color(0xFFB9C4D6), Color(0xFFB9C4D6)],
                  ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF4A78B4).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable card tile with an icon over a label ("Postavke uređaja").
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final _LoginPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: palette.tileIcon, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.title,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
