import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mqtt/state/mqtt_users_provider.dart';
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

class _PinScreenState extends ConsumerState<PinScreen>
    with SingleTickerProviderStateMixin {
  final _digits = <int>[];
  bool _checking = false;

  /// Shown only for failures that are NOT a wrong PIN. A mismatch is answered
  /// by the shake — telling a waiter "Neispravan PIN" when the real problem is
  /// that no staff list has arrived would send them hunting for a typo.
  String? _error;

  /// True while the rejection animation plays: the dots turn red and shake,
  /// then clear.
  bool _wrong = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  static const _maxLen = 8;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onDigit(int d) {
    // `_wrong` blocks input for the length of the shake — a digit typed during
    // it would be wiped by the clear that ends the animation.
    if (_checking || _wrong || _digits.length >= _maxLen) return;
    HapticFeedback.selectionClick();
    setState(() {
      _digits.add(d);
      _error = null;
    });
  }

  void _onDelete() {
    if (_checking || _wrong || _digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.removeLast());
  }

  Future<void> _onOk() async {
    if (_checking || _wrong) return;
    HapticFeedback.selectionClick();
    if (_digits.isEmpty) {
      setState(() => _error = 'Unesite PIN.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final pin = int.tryParse(_digits.join()) ?? -1;
    final user = await ref.read(authControllerProvider).loginWithPin(pin);
    if (!mounted) return;
    if (user == null) {
      // loginWithPin returns null for more than one reason. Without a staff
      // list EVERY pin fails, so say that instead of implying a typo.
      if (ref.read(mqttUsersProvider).isEmpty) {
        setState(() {
          _checking = false;
          _digits.clear();
          _error = 'Nema popisa korisnika. Spojite se na MQTT '
              '(Postavke uređaja).';
        });
      } else {
        await _rejectPin();
      }
    }
    // On success the router's auth redirect (refreshListenable on currentUser)
    // moves us to /mqtt-tables ("Odabir stola") automatically; navigating here
    // too would double-trigger the route change and crash the shell route.
  }

  /// The wrong-PIN answer: a haptic thump, the filled dots turn red and shake,
  /// then they clear. No text — the gesture is the message, and it needs no
  /// reading, which matters when the phone is being glanced at rather than read.
  Future<void> _rejectPin() async {
    setState(() {
      _checking = false;
      _wrong = true;
    });
    HapticFeedback.heavyImpact();
    await _shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _wrong = false;
      _digits.clear();
    });
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
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      // Damped oscillation: two full swings, decaying to zero
                      // so the dots settle instead of stopping mid-swing.
                      final t = _shake.value;
                      final dx =
                          math.sin(t * math.pi * 4) * 10 * (1 - t);
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: _PinDots(length: _digits.length, error: _wrong),
                  ),
                  // No reserved slot: the message is the exception now, so the
                  // gap only exists when there is something in it.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
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
  const _PinDots({required this.length, this.error = false});

  final int length;

  /// Paints the dots in the error colour while the rejection shake plays.
  final bool error;

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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: error ? scheme.error : scheme.primary,
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
