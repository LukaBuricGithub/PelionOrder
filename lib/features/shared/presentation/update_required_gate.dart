import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/version_check_service.dart';

/// Wraps the app so the version check runs once after the first frame. When
/// the store has a newer build, a blocking overlay covers everything until
/// the waiter acts on it:
///
/// * **Android** — "Ažuriraj sada" opens the Play listing, "Kasnije" closes
///   the app (Google allows an app to terminate itself).
/// * **iOS** — only "Ažuriraj sada": Apple's guidelines forbid a programmatic
///   exit, so there is no second button. The app can still be swiped away.
///
/// A Stack overlay rather than `showDialog`, as in the ikasa app: a dialog is
/// an imperative route on GoRouter's Navigator, and the first `context.go(…)`
/// after launch clears it — the waiter would see the dialog flash and vanish.
/// Painted here, it sits above everything the router draws.
class UpdateRequiredGate extends StatefulWidget {
  const UpdateRequiredGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateRequiredGate> createState() => _UpdateRequiredGateState();
}

class _UpdateRequiredGateState extends State<UpdateRequiredGate>
    with WidgetsBindingObserver {
  VersionCheckResult? _blocking;

  /// One check at a time. NOT a "ran once" flag any more: the check used to
  /// run exactly once per process, so a phone that is only ever backgrounded
  /// and resumed — which is every waiter's phone, all shift — never looked
  /// again after the first frame. The service decides how often a real query
  /// goes out; this only stops two running at once.
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background: ask again. A version published during the
  /// shift is then picked up when the waiter next picks the phone up, instead
  /// of waiting for someone to kill and reopen the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _runCheck();
  }

  Future<void> _runCheck() async {
    if (_running || _blocking != null) return;
    _running = true;
    try {
      final result = await const VersionCheckService().check();
      if (!mounted) return;
      if (!result.updateAvailable || result.storeUrl == null) return;
      setState(() => _blocking = result);
    } finally {
      _running = false;
    }
  }

  String _message(VersionCheckResult r) {
    final text = StringBuffer(
      'Za nastavak rada potrebno je ažurirati aplikaciju na najnoviju '
      'verziju.',
    );
    if (r.installedVersion.isNotEmpty) {
      text.write('\n\nTrenutna verzija: ${r.installedVersion}');
    }
    if (r.latestVersion != null && r.latestVersion!.isNotEmpty) {
      text.write('\nNova verzija: ${r.latestVersion}');
    }
    return text.toString();
  }

  Future<void> _openStore(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    // The overlay deliberately stays: coming back from the store without
    // updating must not let the waiter through.
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _blocking;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (blocking != null)
          Positioned.fill(
            child: _BlockingOverlay(
              message: _message(blocking),
              storeUrl: blocking.storeUrl!,
              onOpenStore: _openStore,
            ),
          ),
      ],
    );
  }
}

class _BlockingOverlay extends StatelessWidget {
  const _BlockingOverlay({
    required this.message,
    required this.storeUrl,
    required this.onOpenStore,
  });

  final String message;
  final String storeUrl;
  final Future<void> Function(String) onOpenStore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Swallows the back gesture and every tap outside the card, so there is
    // no way around it.
    return PopScope(
      canPop: false,
      child: ColoredBox(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 8,
                // In dark mode the black shadow is invisible against the dark
                // scaffold, so a hairline outline draws the card's edge
                // instead; light mode keeps the shadow alone.
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isDark
                      ? BorderSide(color: theme.colorScheme.outlineVariant)
                      : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Dostupna je nova verzija',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(message, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 20),
                      // Full width, stacked: this is read and tapped
                      // one-handed while holding a phone, so both targets run
                      // the whole width of the card instead of sitting in a
                      // small right-aligned row.
                      FilledButton(
                        onPressed: () => onOpenStore(storeUrl),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Ažuriraj sada'),
                      ),
                      if (Platform.isAndroid) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => SystemNavigator.pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Kasnije'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
