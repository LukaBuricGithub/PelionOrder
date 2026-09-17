import 'package:flutter/services.dart';

/// Who wants the Android navigation bar hidden right now.
///
/// Several screens hide it (Odabir stola, Stol X), and they sit on top of each
/// other: if each simply switched the bar on when it closed, leaving Stol X
/// would bring it back on Odabir stola too. So screens take and release a
/// request instead, and the bar is hidden while any request is held — unless
/// a screen on top (the order details) asks to show it for a while.
///
/// Hidden means the immersive mode Stol X always used: the status bar stays,
/// the navigation bar is gone until the user swipes it in.
class SystemBars {
  SystemBars._();

  static int _hideRequests = 0;
  static int _showRequests = 0;

  /// A screen that wants the navigation bar hidden — call from `initState`.
  static void hideNavigation() {
    _hideRequests++;
    _apply();
  }

  /// The matching release — call from `dispose`.
  static void releaseNavigation() {
    if (_hideRequests > 0) _hideRequests--;
    _apply();
  }

  /// A screen that needs the navigation bar even though one below hides it.
  static void showNavigation() {
    _showRequests++;
    _apply();
  }

  /// The matching release for [showNavigation].
  static void releaseShowNavigation() {
    if (_showRequests > 0) _showRequests--;
    _apply();
  }

  static void _apply() {
    if (_hideRequests > 0 && _showRequests == 0) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}
