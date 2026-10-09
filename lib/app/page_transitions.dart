import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// How a screen enters and leaves in this app — one definition, used by the
/// router and by the few screens that are pushed straight onto the Navigator
/// (Detalji narudžbe, Stol X from the table view).
///
/// **Android:** the arriving screen slides in from the right while the one
/// underneath slides a third of the way out to the left; plain reverse on the
/// way back.
///
/// Both halves matter. `animation` moves the arriving screen;
/// `secondaryAnimation` moves a screen when something is pushed OVER it — and a
/// page that ignores it stays frozen underneath. That was the "Izbornik →
/// Neposlane narudžbe" problem: Android's default (a 25 % slide and a
/// cross-fade over 450 ms) arriving above a screen that never moved, which
/// reads as floating rather than pushing.
///
/// **iOS:** the platform default, which is already this motion and also carries
/// the edge-swipe back. That gesture comes from `CupertinoPageTransitionsBuilder`
/// and is lost on a plain custom route, so an iPhone keeps `MaterialPage` /
/// `MaterialPageRoute` and nothing here applies.
const _trajanje = Duration(milliseconds: 280);
const _trajanjeNatrag = Duration(milliseconds: 260);

Widget _slide(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // Arriving (or leaving, on the pop): off-screen right → in place.
  final ulaz = Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
    CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
  );
  // Being covered: in place → a third of the way left, so the two screens move
  // together and the push has a direction. A third, not the full width: the
  // screen behind should look pushed aside, not thrown out.
  final izlaz = Tween(begin: Offset.zero, end: const Offset(-1 / 3, 0)).animate(
    CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
  );
  return SlideTransition(
    position: izlaz,
    child: SlideTransition(position: ulaz, child: child),
  );
}

/// A router page with the app's motion. `/login`, `/pin` and `/settings` keep
/// their own entrances: those are fades over a static login, and nothing is
/// ever pushed on top of them.
Page<void> appSlidePage(LocalKey key, Widget child) {
  if (Platform.isIOS) return MaterialPage<void>(key: key, child: child);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: _trajanje,
    reverseTransitionDuration: _trajanjeNatrag,
    transitionsBuilder: _slide,
    child: child,
  );
}

/// The same motion for a screen pushed straight onto the Navigator rather than
/// routed. [T] is what the screen returns when it pops.
Route<T> appSlideRoute<T>(WidgetBuilder builder) {
  if (Platform.isIOS) return MaterialPageRoute<T>(builder: builder);
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: _trajanje,
    reverseTransitionDuration: _trajanjeNatrag,
    transitionsBuilder: _slide,
  );
}
