import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/hero_background.dart';
import '../state/auth_controller.dart';

/// Numeric PIN keypad for signing in. The waiter enters their personal PIN and
/// confirms; on a match they are taken into the Cash Register. Mirrors the
/// reference client's `PinScreen`.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _digits = <int>[];
  bool _checking = false;
  String? _error;

  static const _maxLen = 8;

  void _onDigit(int d) {
    if (_checking || _digits.length >= _maxLen) return;
    setState(() {
      _digits.add(d);
      _error = null;
    });
  }

  void _onDelete() {
    if (_checking || _digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _onOk() async {
    if (_checking) return;
    if (_digits.isEmpty) {
      setState(() => _error = 'Unesite PIN.');
      return;
    }
    setState(() => _checking = true);
    final pin = int.tryParse(_digits.join()) ?? -1;
    final user = await ref.read(authControllerProvider).loginWithPin(pin);
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _checking = false;
        _digits.clear();
        _error = 'Neispravan PIN.';
      });
    }
    // On success the router's auth redirect (refreshListenable on currentUser)
    // moves us to /cash-register automatically; navigating here too would
    // double-trigger the route change and crash the shell route.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Prijava'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: HeroBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text('Unesite PIN', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 20),
                  _PinDots(length: _digits.length),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 22,
                    child: _error == null
                        ? null
                        : Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                  ),
                  const SizedBox(height: 12),
                  _Keypad(
                    onDigit: _onDigit,
                    onDelete: _onDelete,
                    onOk: _onOk,
                    busy: _checking,
                  ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length});

  final int length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fixed height keeps the layout stable; empty until the user types (no
    // placeholder dot). One filled dot appears per entered character.
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDelete,
    required this.onOk,
    required this.busy,
  });

  final void Function(int) onDigit;
  final VoidCallback onDelete;
  final VoidCallback onOk;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) {
      return AspectRatio(
        aspectRatio: 1.4,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: OutlinedButton(
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    Widget digit(int d) => key(
          Text('$d',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          () => onDigit(d),
        );

    return Column(
      children: [
        for (final row in [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Row(children: [for (final d in row) Expanded(child: digit(d))]),
        Row(
          children: [
            Expanded(
              child: key(const Icon(Icons.backspace_outlined), onDelete),
            ),
            Expanded(child: digit(0)),
            Expanded(
              child: key(
                busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 26),
                onOk,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
