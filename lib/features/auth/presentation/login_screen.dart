import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../master_data/state/heartbeat_provider.dart';
import '../../profiles/state/profiles_provider.dart';
import '../../shared/presentation/hero_background.dart';
import '../../theme/state/theme_mode_provider.dart';
import '../state/login_controller.dart';

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
    required this.onlineGreen,
    required this.offlineRed,
    required this.tileIcon,
  });

  final Color title;
  final Color subtitle;
  final Color label;
  final Color card;
  final Color cardBorder;
  final Color onlineGreen;
  final Color offlineRed;
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
        onlineGreen: Color(0xFF35C46A),
        offlineRed: Color(0xFFE06C6C),
        tileIcon: Color(0xFF6FA0E6),
      );
    }
    return const _LoginPalette(
      title: Color(0xFF16233C),
      subtitle: Color(0xFF5C6B85),
      label: Color(0xFF7688A5),
      card: Colors.white,
      cardBorder: Color(0xFFD7E0EF),
      onlineGreen: Color(0xFF2E9E57),
      offlineRed: Color(0xFFC0392B),
      tileIcon: Color(0xFF4A78B4),
    );
  }
}

/// The landing screen: a branded hero with the app name, live connection
/// status, the (single) server profile, and the primary actions — sign in,
/// update data, settings, exit.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(heartbeatProvider.notifier).start());
  }

  @override
  void dispose() {
    ref.read(heartbeatProvider.notifier).stop();
    super.dispose();
  }

  /// Pull-to-refresh: ping the server right now (refresh the Online/Offline
  /// state without waiting for the heartbeat) and re-run the data update, so a
  /// login that was showing "Offline" re-enables "Prijava" once we're back on.
  Future<void> _onRefresh() async {
    await ref.read(heartbeatProvider.notifier).pingNow();
    await ref.read(loginControllerProvider.notifier).updateData();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _LoginPalette.of(Theme.of(context).brightness);
    final online = ref.watch(heartbeatProvider);
    final login = ref.watch(loginControllerProvider);
    final profiles = ref.watch(profilesProvider);

    // When the profile changes (added / edited / deleted in Postavke uređaja),
    // re-check cached data so the Prijava gate stays correct.
    ref.listen(profilesProvider, (prev, next) {
      if (prev?.current?.id != next.current?.id ||
          prev?.entries.length != next.entries.length) {
        ref.read(loginControllerProvider.notifier).onProfilesChanged();
      }
    });

    final hasProfile = profiles.current != null;
    // A profile is required to sign in — the PIN is validated against users
    // downloaded for that profile. Without one there is no venue to belong to.
    final prijavaEnabled = hasProfile && login.hasUsers && !login.syncing;
    final updateEnabled = online && hasProfile && !login.syncing;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: HeroBackground()),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      children: [
                        SizedBox(height: constraints.maxHeight * 0.10),
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
                        const SizedBox(height: 20),
                        _OnlineBadge(online: online, palette: palette),
                        const SizedBox(height: 28),
                        _ProfileCard(
                          palette: palette,
                          name: profiles.current?.name,
                          onTap: () => context.push('/settings'),
                        ),
                        if (login.error != null) ...[
                          const SizedBox(height: 14),
                          _ErrorBanner(message: login.error!),
                        ],
                        const SizedBox(height: 20),
                        _GradientButton(
                          label: 'Prijava',
                          icon: Icons.arrow_forward,
                          enabled: prijavaEnabled,
                          onTap: () => context.push('/pin'),
                        ),
                        if (!hasProfile) ...[
                          const SizedBox(height: 14),
                          Text(
                            'Dodajte profil poslužitelja u Postavkama uređaja',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: palette.label, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: _ActionTile(
                                palette: palette,
                                icon: Icons.sync,
                                label: 'Ažuriraj podatke',
                                enabled: updateEnabled,
                                loading: login.syncing,
                                onTap: () => ref
                                    .read(loginControllerProvider.notifier)
                                    .updateData(),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _ActionTile(
                                palette: palette,
                                icon: Icons.settings,
                                label: 'Postavke uređaja',
                                enabled: true,
                                onTap: () => context.push('/settings'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
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

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online, required this.palette});
  final bool online;
  final _LoginPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = online ? palette.onlineGreen : palette.offlineRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.palette,
    required this.name,
    required this.onTap,
  });

  final _LoginPalette palette;
  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasProfile = name != null;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Podatci za prijavu',
                      style: TextStyle(color: palette.label, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasProfile
                          ? (name!.isEmpty ? '(bez naziva)' : name!)
                          : 'Nema profila',
                      style: TextStyle(
                        color: palette.title,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.label),
            ],
          ),
        ),
      ),
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.loading = false,
  });

  final _LoginPalette palette;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Keep full opacity while loading so the spinner reads clearly, even though
    // the tile is non-tappable during the update.
    final dim = !enabled && !loading;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: (enabled && !loading) ? onTap : null,
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: palette.tileIcon,
                        ),
                      )
                    : Icon(icon, color: palette.tileIcon, size: 26),
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
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
